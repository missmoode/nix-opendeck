"""Safety invariants for reusing previous PR matrix-job success."""

import importlib.util
import os
from unittest.mock import MagicMock, patch
from pathlib import Path
from tempfile import TemporaryDirectory
import subprocess
import unittest

spec = importlib.util.spec_from_file_location(
    "pr_verification_reuse", Path(__file__).with_name("pr_verification_reuse.py")
)
reuse = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reuse)

REPO = "missmoode/nix-opendeck"
HEAD = "a" * 40
MERGE = "b" * 40
CURRENT_RUN = 900


def plugin(
    *,
    attr="legacyPackages.x86_64-linux.opendeck-plugins.a.foo",
    store="/nix/store/old-foo",
):
    return {
        "kind": "plugin",
        "system": "x86_64-linux",
        "runner": "ubuntu-24.04",
        "attr": attr,
        "label": "a/foo",
        "storePath": store,
    }


def run(*, run_id=800, pr=91, conclusion="failure", head=HEAD, merge=MERGE):
    return {
        "id": run_id,
        "event": "pull_request",
        "status": "completed",
        "conclusion": conclusion,
        "repository": {"full_name": REPO},
        "display_title": f"Package verification PR #{pr} merge {merge}",
        "head_sha": head,
        "pull_requests": [{"number": pr}],
    }


def job(*, conclusion="success", label="a/foo"):
    return {
        "name": f"Rebuild: x86_64-linux / {label}",
        "conclusion": conclusion,
        "html_url": "https://github.com/missmoode/nix-opendeck/actions/runs/800/job/44",
    }


def pick(changed=None, runs=None, jobs=None, catalogue=None):
    changed = [plugin()] if changed is None else changed
    runs = [run()] if runs is None else runs
    jobs = [job()] if jobs is None else jobs
    catalogue = (
        {item["attr"]: item for item in changed} if catalogue is None else catalogue
    )
    return reuse.select_reused(
        changed,
        runs,
        repo=REPO,
        pr_number=91,
        current_run_id=CURRENT_RUN,
        job_lookup=lambda _id: jobs,
        old_catalogue=lambda _run, _merge: catalogue,
    )


class ReuseTests(unittest.TestCase):
    def test_public_actions_api_does_not_use_authorization_header(self):
        response = MagicMock()
        response.__enter__.return_value = response
        response.read.return_value = b'{"workflow_runs": []}'
        with patch.object(reuse, "urlopen", return_value=response) as call:
            self.assertEqual(
                reuse.github_api(REPO, "/actions/runs"), {"workflow_runs": []}
            )
            request = call.call_args.args[0]
            self.assertFalse(any(k.lower() == "authorization" for k in request.headers))

    def test_successful_job_in_otherwise_failed_run_is_reusable(self):
        result = pick()
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["storePath"], plugin()["storePath"])

    def test_prior_output_must_be_identical(self):
        old = plugin(store="/nix/store/different-foo")
        self.assertEqual(pick(catalogue={old["attr"]: old}), [])

    def test_failed_cancelled_or_ambiguous_jobs_are_not_proof(self):
        self.assertEqual(pick(jobs=[job(conclusion="failure")]), [])
        self.assertEqual(pick(jobs=[job(), job()]), [])
        self.assertEqual(pick(jobs=[]), [])

    def test_only_previous_completed_run_of_the_same_pr_counts(self):
        cases = [
            run(run_id=CURRENT_RUN),
            run(run_id=CURRENT_RUN + 1),
            run(pr=92),
            run(head="untrusted"),
            run(merge="untrusted"),
            {**run(), "event": "push"},
            {**run(), "repository": {"full_name": "fork/repo"}},
            {**run(), "conclusion": "cancelled"},
            {**run(), "status": "in_progress"},
            {**run(), "pull_requests": [{"number": 92}]},
        ]
        for candidate in cases:
            with self.subTest(candidate=candidate):
                self.assertEqual(pick(runs=[candidate]), [])

    def test_no_reuse_if_previous_policy_or_merge_is_unavailable(self):
        self.assertEqual(pick(catalogue=None, changed=[plugin()], runs=[]), [])
        self.assertEqual(
            reuse.select_reused(
                [plugin()],
                [run()],
                repo=REPO,
                pr_number=91,
                current_run_id=CURRENT_RUN,
                job_lookup=lambda _: [job()],
                old_catalogue=lambda *_: None,
            ),
            [],
        )

    def test_old_target_must_match_kind_system_attribute_and_label(self):
        current = plugin()
        for changed in (
            {**current, "kind": "core"},
            {**current, "system": "aarch64-linux"},
            {**current, "label": "new-name"},
        ):
            with self.subTest(changed=changed):
                self.assertEqual(
                    pick(changed=[changed], catalogue={current["attr"]: current}), []
                )

    def test_core_not_reused_even_if_all_other_fields_match(self):
        target = {**plugin(), "kind": "core"}
        self.assertEqual(pick(changed=[target], catalogue={target["attr"]: target}), [])

    def test_impure_historical_eval_does_not_receive_api_credentials(self):
        with patch.dict(
            os.environ,
            {
                "GH_TOKEN": "secret",
                "GITHUB_TOKEN": "other-secret",
                "ACTIONS_RUNTIME_TOKEN": "runtime-secret",
                "PATH": "/bin",
            },
            clear=True,
        ):
            env = reuse.nix_eval_environment("/trusted/targets.nix")
            self.assertEqual(env["PATH"], "/bin")
            self.assertEqual(env["TRUSTED_TARGETS"], "/trusted/targets.nix")
            for name in ("GH_TOKEN", "GITHUB_TOKEN", "ACTIONS_RUNTIME_TOKEN"):
                self.assertNotIn(name, env)

    def test_more_recent_verified_result_wins(self):
        recent = run(run_id=850, merge="c" * 40, head="d" * 40)
        old = run(run_id=800)
        selected = reuse.select_reused(
            [plugin()],
            [old, recent],
            repo=REPO,
            pr_number=91,
            current_run_id=CURRENT_RUN,
            job_lookup=lambda id: [
                {**job(), "html_url": f"https://example.org/job/{id}"}
            ],
            old_catalogue=lambda *_: {plugin()["attr"]: plugin()},
        )
        self.assertEqual(selected[0]["jobUrl"], "https://example.org/job/850")

    def test_missing_proof_is_a_rebuild_not_an_error(self):
        selected = reuse.select_reused(
            [plugin()],
            [run()],
            repo=REPO,
            pr_number=91,
            current_run_id=CURRENT_RUN,
            job_lookup=lambda _: (_ for _ in ()).throw(OSError("API unavailable")),
            old_catalogue=lambda *_: None,
        )
        self.assertEqual(selected, [])

    def test_policy_compares_git_modes_and_blobs_and_validates_merge_parent(self):
        with TemporaryDirectory() as temp:
            repo = Path(temp)

            def git(*args):
                return subprocess.check_output(
                    ["git", "-C", str(repo), *args], text=True
                ).strip()

            git("init", "-q")
            git("config", "user.email", "ci@example.invalid")
            git("config", "user.name", "CI")
            for path in reuse.POLICY:
                target = repo / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("trusted\n")
            git("add", ".")
            git("commit", "-qm", "base")
            base = git("rev-parse", "HEAD")
            git("switch", "-qc", "pr")
            (repo / "package.nix").write_text("a")
            git("add", "package.nix")
            git("commit", "-qm", "pr")
            head = git("rev-parse", "HEAD")
            git(
                "switch",
                "-q",
                "master" if git("branch", "--list", "master") else "main",
            )
            git("merge", "--no-ff", "--no-edit", "pr")
            merge = git("rev-parse", "HEAD")
            # The helper uses Git subprocesses relative to cwd.
            # git() helper's cwd is explicitly passed via monkeypatch here.
            real_git = reuse.git

            def in_repo(*args, cwd=None, timeout=30):
                return real_git(
                    *args, cwd=str(repo) if cwd is None else cwd, timeout=timeout
                )

            with patch.object(reuse, "git", side_effect=in_repo):
                self.assertTrue(reuse.trusted_revision(merge, base, head))
                self.assertFalse(reuse.trusted_revision(merge, base, "e" * 40))
                git("switch", "-qc", "untrusted-policy", base)
                (repo / reuse.POLICY[2]).write_text("modified\n")
                git("add", ".")
                git("commit", "-qm", "change policy")
                changed_head = git("rev-parse", "HEAD")
                git(
                    "switch",
                    "-q",
                    "master" if git("branch", "--list", "master") else "main",
                )
                git("merge", "--no-ff", "--no-edit", "untrusted-policy")
                self.assertFalse(
                    reuse.trusted_revision(git("rev-parse", "HEAD"), base, changed_head)
                )


if __name__ == "__main__":
    unittest.main()
