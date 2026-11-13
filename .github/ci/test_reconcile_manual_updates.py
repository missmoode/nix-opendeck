"""Security and state-transition tests for manual updater issue reconciliation."""

import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import reconcile_manual_updates as manual
from package_updates import previous_failed_packages


def issue_body(labels):
    encoded = base64.urlsafe_b64encode(json.dumps(sorted(labels)).encode()).decode()
    return (
        "<!-- nix-opendeck-package-update-failures:012345 -->\n"
        f"<!-- nix-opendeck-failed-packages:{encoded} -->\n"
        "## Outstanding package update failures\n\n"
        "The automated updater could not validate the following updates.\n\n"
        + "".join(f"- {label}: updater failed (diagnostic text)\n" for label in sorted(labels))
        + "\n### Diagnostic excerpts\n\nOriginal logs must remain intact.\n"
    )


class VersionTests(unittest.TestCase):
    def test_normalized_numeric_versions(self):
        self.assertTrue(manual.advanced("1.3.0", "2.0.0"))
        self.assertTrue(manual.advanced("1.3", "1.3.1"))
        for old, new in [
            ("1.3", "1.3.0"),
            ("1.3.0", "1.3"),
            ("1.3.0", "1.2.9"),
            ("1.3.0", "1.3.0"),
            ("v1.3.0", "2.0.0"),
            ("1.3.0-rc1", "2.0.0"),
            ("1.3.0", None),
        ]:
            with self.subTest(old=old, new=new):
                self.assertFalse(manual.advanced(old, new))

    def test_paths_reject_traversal(self):
        for label in ("../../etc/passwd", "foo/../../bar", "owner/name/extra"):
            with self.subTest(label=label), self.assertRaises(ValueError):
                manual.package_path(label)
        self.assertEqual(
            manual.package_path("opendeck-core"), "src/packages/opendeck/default.nix"
        )
        self.assertEqual(
            manual.package_path("wortkrieg/onairclock"),
            "src/packages/plugins/wortkrieg/onairclock/default.nix",
        )

    def test_pr_intent_must_be_exact_issue_and_package(self):
        msg = "fix: packaging\n\nResolves-Update-Failure: #99 wortkrieg/onairclock\n"
        self.assertEqual(
            manual.acknowledged_labels(msg, "99"), {"wortkrieg/onairclock"}
        )
        self.assertEqual(manual.acknowledged_labels(msg, "98"), set())
        self.assertEqual(
            manual.acknowledged_labels(
                "Resolves-Update-Failure: #99 ../../etc", "99"
            ),
            set(),
        )
        self.assertEqual(manual.acknowledged_labels("Fixes #99", "99"), set())

    def test_partial_issue_state_preserves_history(self):
        body = issue_body({"wortkrieg/onairclock", "tonyheadband/steam"})
        update = manual.remaining_issue_body(
            body, {"tonyheadband/steam"}, {"wortkrieg/onairclock"}
        )
        self.assertEqual(previous_failed_packages(update), {"tonyheadband/steam"})
        self.assertNotIn("- wortkrieg/onairclock: updater failed", update)
        self.assertIn("- tonyheadband/steam: updater failed", update)
        self.assertIn("Original logs must remain intact.", update)
        self.assertIn("explicitly acknowledged", update)

    def test_invalid_tracking_layout_fails_closed(self):
        body = issue_body({"a/b", "c/d"})
        with self.assertRaisesRegex(ValueError, "disagrees"):
            manual.remaining_issue_body(
                body.replace("- a/b: updater failed (diagnostic text)\n", ""),
                {"c/d"}, {"a/b"}
            )
        with self.assertRaisesRegex(ValueError, "layout"):
            manual.remaining_issue_body(
                body.replace("## Outstanding package update failures", "different"),
                {"c/d"}, {"a/b"}
            )


class RealGitTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        previous = os.getcwd()
        os.chdir(self.tmp.name)
        self.addCleanup(os.chdir, previous)
        for args in (
            ("init", "-q", "-b", "main"),
            ("config", "user.email", "test@example.invalid"),
            ("config", "user.name", "Test"),
            ("config", "commit.gpgsign", "false"),
        ):
            self.git(*args)
        self.write("src/packages/plugins/wortkrieg/onairclock/default.nix", 'version = "1.3.0";\n')
        self.write("src/packages/plugins/other/package/default.nix", 'version = "0.1.0";\n')
        self.commit("base")
        self.before = self.git("rev-parse", "HEAD")

    def git(self, *args):
        return subprocess.run(
            ["git", *args], check=True, capture_output=True, text=True
        ).stdout.strip()

    def write(self, path, content):
        f = Path(path)
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(content)

    def commit(self, subject):
        self.git("add", "-A")
        self.git("commit", "-qm", subject)

    def test_changed_version_only_one_tracked_label(self):
        self.write("src/packages/plugins/wortkrieg/onairclock/default.nix", 'version = "2.0.0";\n')
        self.write("src/packages/plugins/other/package/default.nix", 'version = "0.1.0";\n# patch only\n')
        self.commit("manual repair")
        changed = manual.updated_packages(
            {"wortkrieg/onairclock", "other/package"}, self.before, self.git("rev-parse", "HEAD")
        )
        self.assertEqual(changed, {"wortkrieg/onairclock": ("1.3.0", "2.0.0")})

    def test_removed_package_not_marked_resolved(self):
        Path("src/packages/plugins/wortkrieg/onairclock/default.nix").unlink()
        self.commit("remove")
        self.assertEqual(
            manual.updated_packages(
                {"wortkrieg/onairclock"}, self.before, self.git("rev-parse", "HEAD")
            ),
            {},
        )


class TrustedTreeTests(unittest.TestCase):
    def setUp(self):
        self.repo = "example/repo"
        self.bot = "nixopendeck-ci[bot]"
        self.head = "c" * 40
        self.sha = "d" * 40
        self.tree = "e" * 40
        self.pr = {"number": 42, "head": {"sha": self.head}}
        self.contexts = sorted(manual.WORKFLOWS)

    def fixture(self, *, status_state="success", status_bot=None, run_head=None,
                run_title=None, run_path=None, tree=None, disagree=False,
                run_conclusion="success", bad_url=False):
        statuses = []
        for i, context in enumerate(self.contexts, 1):
            statuses.append({
                "context": context,
                "state": status_state,
                "creator": {"login": status_bot or self.bot},
                "target_url": ("https://evil.invalid/actions/runs/1" if bad_url
                               else f"https://github.com/{self.repo}/actions/runs/{i}"),
            })
        path_to_run = {}
        for i, context in enumerate(self.contexts, 1):
            path, kind = manual.WORKFLOWS[context]
            path_to_run[f"repos/{self.repo}/actions/runs/{i}"] = {
                "event": "pull_request",
                "status": "completed",
                "conclusion": run_conclusion,
                "head_sha": run_head or self.head,
                "repository": {"full_name": self.repo},
                "path": (run_path or path) + "@refs/heads/main",
                "display_title": run_title or f"{kind} PR #42 merge {self.sha}",
            }
        merged = {"tree": {"sha": tree or self.tree}}

        def resolve(endpoint):
            if endpoint == f"repos/{self.repo}/commits/{self.head}/status":
                return {"statuses": statuses}
            if endpoint == f"repos/{self.repo}/git/commits/{self.sha}":
                return {"tree": {"sha": "f" * 40 if disagree and resolve.calls > 1 else self.tree}}
            if endpoint in path_to_run:
                return path_to_run[endpoint]
            raise AssertionError(f"unexpected API call {endpoint}")

        resolve.calls = 0
        def tracking(endpoint):
            if endpoint == f"repos/{self.repo}/git/commits/{self.sha}":
                resolve.calls += 1
            return resolve(endpoint)
        return tracking

    def assert_refused(self, **kwargs):
        with patch.object(manual, "api", side_effect=self.fixture(**kwargs)):
            self.assertIsNone(manual.certified_tree(self.repo, self.pr, self.bot))

    def test_exact_synthetic_merge_tree_is_retrievable(self):
        with patch.object(manual, "api", side_effect=self.fixture()):
            self.assertEqual(manual.certified_tree(self.repo, self.pr, self.bot), self.tree)

    def test_stale_or_failing_status_rejected(self):
        self.assert_refused(status_state="failure")
        self.assert_refused(status_bot="another-app[bot]")

    def test_wrong_run_url_or_path_rejected(self):
        self.assert_refused(bad_url=True)
        self.assert_refused(run_path=".github/workflows/fake.yml")

    def test_run_not_for_head_or_pr_rejected(self):
        self.assert_refused(run_head="f" * 40)
        self.assert_refused(run_title=f"Checks PR #43 merge {self.sha}")
        self.assert_refused(run_conclusion="failure")

    def test_mismatched_runs_rejected(self):
        self.assert_refused(disagree=True)

    def test_latest_status_wins_over_older_success(self):
        latest = manual.latest_statuses([
            {"context": "tests", "state": "failure"},
            {"context": "tests", "state": "success"},
        ])
        self.assertEqual(latest["tests"]["state"], "failure")


class MergeAssociationTests(unittest.TestCase):
    def setUp(self):
        self.before, self.after, self.head = "a" * 40, "b" * 40, "c" * 40
        self.pr = {
            "number": 42,
            "merged_at": "2026-11-13T20:00:00Z",
            "merge_commit_sha": self.after,
            "base": {"ref": "main", "repo": {"full_name": "example/repo"}},
            "head": {"sha": self.head},
        }

    def verify(self, *, prs=None, parent=None):
        with (
            patch.object(manual, "execute", side_effect=[self.after, parent or self.before]),
            patch.object(manual, "api", return_value=[self.pr] if prs is None else prs),
        ):
            return manual.matching_merged_pr("example/repo", self.before, self.after, "main")

    def test_single_merged_pr(self):
        self.assertEqual(self.verify(), self.pr)

    def test_ambiguous_pr_or_direct_push_rejected(self):
        self.assertIsNone(self.verify(prs=[]))
        self.assertIsNone(self.verify(prs=[self.pr, self.pr]))
        self.assertIsNone(self.verify(parent="d" * 40))
        invalid = dict(self.pr, merge_commit_sha="f" * 40)
        self.assertIsNone(self.verify(prs=[invalid]))


class WriteBoundaryTests(RealGitTests):
    """Exercise the whole reconciliation command with mocked GitHub only."""

    def setUp(self):
        super().setUp()
        self.write(
            "src/packages/plugins/wortkrieg/onairclock/default.nix",
            'version = "2.0.0";\n',
        )
        self.commit("fix plugin\n\nResolves-Update-Failure: #99 wortkrieg/onairclock")
        self.after = self.git("rev-parse", "HEAD")
        self.tree = self.git("rev-parse", "HEAD^{tree}")
        self.bot = "nixopendeck-ci[bot]"
        self.pr = {
            "number": 42, "merged_at": "2026-11-13T20:00:00Z",
            "merge_commit_sha": self.after,
            "head": {"sha": "c" * 40},
            "base": {"ref": "main", "repo": {"full_name": "example/repo"}},
        }
        self.body = issue_body({"wortkrieg/onairclock", "other/package"})
        self.issue = {
            "state": "open", "title": manual.TITLE,
            "user": {"login": self.bot}, "body": self.body,
        }
        self.writes = []
        self.original_execute = manual.execute

    def run_reconciliation(self, *, tree=None, change_issue=False, remote=None,
                           pr=None, status_ok=True):
        env = {
            "GH_REPO": "example/repo", "BASE_BRANCH": "main",
            "APP_BOT_LOGIN": self.bot, "ISSUE_NUMBER": "99",
            "BEFORE_SHA": self.before, "AFTER_SHA": self.after,
            "GITHUB_RUN_ID": "1234", "GITHUB_SERVER_URL": "https://github.com",
        }
        calls = {"issues": 0}

        def endpoint(path):
            if path == "repos/example/repo/issues/99":
                calls["issues"] += 1
                if change_issue and calls["issues"] > 1:
                    return dict(self.issue, body=self.body + "edited\n")
                return self.issue
            if path == f"repos/example/repo/commits/{self.after}/pulls?per_page=100":
                return [pr or self.pr]
            if path == "repos/example/repo/git/ref/heads/main":
                return {"object": {"sha": remote or self.after}}
            raise AssertionError(f"unexpected endpoint {path}")

        def operation(*args):
            if args[0] == "gh":
                self.writes.append(args)
                if "--body-file" in args:
                    self.writes.append(Path(args[args.index("--body-file") + 1]).read_text())
                return ""
            return self.original_execute(*args)

        with (
            patch.dict(os.environ, env),
            patch.object(manual, "api", side_effect=endpoint),
            patch.object(manual, "execute", side_effect=operation),
            patch.object(manual, "certified_tree", return_value=(tree if tree is not None else self.tree) if status_ok else None),
        ):
            manual.main()

    def test_verified_repair_partially_updates_issue(self):
        self.run_reconciliation()
        self.assertEqual([w[2] for w in self.writes if isinstance(w, tuple)], ["comment", "edit"])
        final_body = self.writes[-1]
        self.assertEqual(previous_failed_packages(final_body), {"other/package"})
        self.assertIn("Original logs must remain intact.", final_body)

    def test_mismatched_merge_tree_cannot_close_or_comment(self):
        self.run_reconciliation(tree="f" * 40)
        self.assertEqual(self.writes, [])

    def test_unverified_status_cannot_close_or_comment(self):
        self.run_reconciliation(status_ok=False)
        self.assertEqual(self.writes, [])

    def test_newer_main_tip_does_not_write(self):
        self.run_reconciliation(remote="e" * 40)
        self.assertEqual(self.writes, [])

    def test_issue_concurrent_edit_rejects_without_comment(self):
        with self.assertRaisesRegex(ValueError, "changed during"):
            self.run_reconciliation(change_issue=True)
        self.assertEqual(self.writes, [])

    def test_unacknowledged_commit_does_not_write(self):
        # Existing merge has an acknowledgement only for #99; using another
        # issue number must not activate a different failure incident.
        original_execute = manual.execute
        with patch.object(manual, "acknowledged_labels", return_value=set()):
            self.run_reconciliation()
        self.assertEqual(self.writes, [])

    def test_all_resolved_closes_issue_after_comment(self):
        self.issue = dict(self.issue, body=issue_body({"wortkrieg/onairclock"}))
        self.run_reconciliation()
        self.assertEqual([w[2] for w in self.writes if isinstance(w, tuple)], ["comment", "close"])


if __name__ == "__main__":
    unittest.main()
