"""Regression checks for the package-updater's repository mutation boundary.

These tests use a temporary Git checkout and a simulated nix-update command;
no Nix installation or network access is required.
"""

import contextlib
import io
import json
import os
from pathlib import Path
from types import SimpleNamespace
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import package_updates


class UpdateScopeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "checkout"
        self.root.mkdir()
        self.previous_dir = Path.cwd()
        os.chdir(self.root)
        self.addCleanup(os.chdir, self.previous_dir)

        self.write("src/plugin/default.nix", 'version = "1.0";\n')
        self.write("flake.lock", '{"nodes": {}}\n')
        self.write(".github/workflows/cache.yml", "name: cache\n")
        self.write("README.md", "# Example\n")
        for args in [
            ("init", "-q"),
            ("config", "user.name", "CI Test"),
            ("config", "user.email", "test@example.invalid"),
            ("config", "commit.gpgsign", "false"),
            ("add", "-A"),
            ("commit", "-qm", "initial"),
        ]:
            subprocess.run(["git", *args], check=True, capture_output=True)

        self.plan = Path(self.temp.name) / "plan.json"
        self.plan.write_text(
            json.dumps(
                {
                    "packages": [
                        {
                            "id": "plugin-test",
                            "label": "test/plugin",
                            "system": "x86_64-linux",
                            "attr": "packages.x86_64-linux.test",
                        }
                    ],
                    "updaters": [{"system": "x86_64-linux", "runner": "ubuntu-24.04"}],
                }
            )
        )
        self.out = Path(self.temp.name) / "output"

    def write(self, relative, content):
        file = self.root / relative
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(content)

    def simulate_update(self, changes, exit_code=0):
        actual_run = package_updates.run

        def intercept(*argv, **kwargs):
            if argv[0] == "nix-update":
                for filename, contents in changes.items():
                    self.write(filename, contents)
                return subprocess.CompletedProcess(argv, exit_code)
            return actual_run(*argv, **kwargs)

        args = type(
            "Args",
            (),
            {
                "plan": str(self.plan),
                "system": "x86_64-linux",
                "output": str(self.out),
            },
        )()
        with patch.object(package_updates, "run", side_effect=intercept):
            with contextlib.redirect_stdout(io.StringIO()):
                package_updates.update(args)
        records = json.loads((self.out / "results.json").read_text())
        status = subprocess.run(
            ["git", "status", "--porcelain"], capture_output=True, text=True, check=True
        ).stdout
        # The updater must leave the Git checkout clean after every attempt.
        self.assertEqual(status.strip(), "")
        return records[0]

    def test_source_change_produces_a_patch(self):
        record = self.simulate_update({"src/plugin/default.nix": 'version = "1.1";\n'})
        self.assertEqual(record["status"], "changed")
        patch_path = self.out / "patches" / "plugin-test.patch"
        self.assertTrue(patch_path.is_file())
        self.assertEqual(
            record["sha256"],
            package_updates.hashlib.sha256(patch_path.read_bytes()).hexdigest(),
        )

    def test_workflow_change_is_rejected(self):
        record = self.simulate_update(
            {".github/workflows/cache.yml": "name: changed\n"}
        )
        self.assertEqual(record["status"], "failed")
        self.assertIn("outside src/", record["error"])
        self.assertFalse((self.out / "patches" / "plugin-test.patch").exists())

    def test_flake_lock_change_is_rejected(self):
        record = self.simulate_update({"flake.lock": '{"nodes": {"changed": true}}\n'})
        self.assertEqual(record["status"], "failed")
        self.assertIn("outside src/", record["error"])

    def test_updater_failure_is_reported(self):
        record = self.simulate_update({}, exit_code=1)
        self.assertEqual(record["status"], "failed")
        self.assertIn("nix-update exited", record["error"])


class FinalizationTests(unittest.TestCase):
    """Test package-level failures separately from untrusted/incomplete CI runs."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "checkout"
        self.root.mkdir()
        self.previous_dir = Path.cwd()
        os.chdir(self.root)
        self.addCleanup(os.chdir, self.previous_dir)
        source = self.root / "src" / "plugin" / "default.nix"
        source.parent.mkdir(parents=True)
        source.write_text('version = "1.0";\n')
        for args in [
            ("init", "-q"),
            ("config", "user.name", "CI Test"),
            ("config", "user.email", "test@example.invalid"),
            ("config", "commit.gpgsign", "false"),
            ("add", "-A"),
            ("commit", "-qm", "initial"),
        ]:
            subprocess.run(["git", *args], check=True, capture_output=True)

        self.output = Path(self.temp.name)
        self.updates = self.output / "updates"
        self.builds = self.output / "builds"
        self.plan = self.output / "plan.json"
        self.prepared = self.output / "prepared.json"
        self.report = self.output / "report.md"
        self.pr_report = self.output / "pr.md"
        self.state = self.output / "state.json"
        self.alpha = {
            "id": "alpha",
            "label": "test/alpha",
            "system": "x86_64-linux",
            "attr": "packages.x86_64-linux.alpha",
        }
        self.beta = {
            "id": "beta",
            "label": "test/beta",
            "system": "x86_64-linux",
            "attr": "packages.x86_64-linux.beta",
        }

    def changed(self, pkg, version="1.1"):
        source = self.root / "src/plugin/default.nix"
        source.write_text(f'version = "{version}";\n')
        subprocess.run(["git", "add", "-A"], check=True, capture_output=True)
        diff = subprocess.run(
            ["git", "diff", "--cached", "--binary"], check=True, capture_output=True
        ).stdout
        subprocess.run(
            ["git", "reset", "--hard", "HEAD"], check=True, capture_output=True
        )
        location = (
            self.updates / f"updates-{pkg['system']}" / "patches" / f"{pkg['id']}.patch"
        )
        location.parent.mkdir(parents=True, exist_ok=True)
        location.write_bytes(diff)
        return {
            **pkg,
            "status": "changed",
            "sha256": package_updates.hashlib.sha256(diff).hexdigest(),
        }

    def failed(self, pkg):
        return {**pkg, "status": "failed", "error": "upstream is unavailable"}

    def build(self, pkg, status="success", error="compilation failed"):
        location = self.builds / f"build-{pkg['id']}-{pkg['system']}" / "result.json"
        package_updates.save(
            location,
            {
                **{key: pkg[key] for key in ("id", "label", "system", "attr")},
                "status": status,
                **({"error": error} if status == "failed" else {}),
            },
        )

    def finalize(
        self,
        packages,
        results,
        targets=(),
        errors=(),
        base_unchanged=True,
        nix_fails=False,
    ):
        package_updates.save(self.plan, {"packages": packages})
        package_updates.save(
            self.prepared,
            {
                "updateResults": results,
                "errors": list(errors),
                "plugins": list(targets),
                "opendeck": [],
            },
        )
        args = SimpleNamespace(
            plan=str(self.plan),
            prepared=str(self.prepared),
            updates=str(self.updates),
            builds=str(self.builds),
            base_unchanged="true" if base_unchanged else "false",
            report=str(self.report),
            pr_report=str(self.pr_report),
            state=str(self.state),
        )
        actual_run = package_updates.run

        def intercept(*argv, **kwargs):
            if argv[:3] == ("nix", "flake", "check"):
                if nix_fails:
                    raise subprocess.CalledProcessError(1, argv)
                return subprocess.CompletedProcess(argv, 0)
            return actual_run(*argv, **kwargs)

        with patch.object(package_updates, "run", side_effect=intercept):
            with contextlib.redirect_stdout(io.StringIO()):
                package_updates.finalize(args)
        return package_updates.load(self.state)

    def test_partial_success_proposes_only_validated_changes_and_reports_failures(self):
        changed = self.changed(self.alpha)
        failed = self.failed(self.beta)
        self.build(self.alpha)
        state = self.finalize([self.alpha, self.beta], [changed, failed], [self.alpha])
        self.assertTrue(state["ready"])
        self.assertFalse(state["infrastructureFailure"])
        self.assertEqual(state["accepted"], ["test/alpha"])
        self.assertTrue(any("test/beta" in x for x in state["packageFailures"]))
        self.assertIn(
            'version = "1.1"', (self.root / "src/plugin/default.nix").read_text()
        )
        self.assertIn("test/alpha", self.pr_report.read_text())
        self.assertNotIn("test/beta", self.pr_report.read_text())

    def test_every_update_fails_without_proposing_changes(self):
        state = self.finalize(
            [self.alpha, self.beta], [self.failed(self.alpha), self.failed(self.beta)]
        )
        self.assertFalse(state["ready"])
        self.assertFalse(state["infrastructureFailure"])
        self.assertEqual(len(state["packageFailures"]), 2)
        self.assertEqual(state["accepted"], [])

    def test_failed_native_build_is_a_package_failure(self):
        changed = self.changed(self.alpha)
        self.build(self.alpha, status="failed")
        state = self.finalize([self.alpha], [changed], [self.alpha])
        self.assertFalse(state["ready"])
        self.assertFalse(state["infrastructureFailure"])
        self.assertIn("compilation failed", " ".join(state["packageFailures"]))

    def test_missing_build_report_blocks_all_changes(self):
        changed = self.changed(self.alpha)
        state = self.finalize([self.alpha], [changed], [self.alpha])
        self.assertFalse(state["ready"])
        self.assertTrue(state["infrastructureFailure"])
        self.assertIn(
            "Missing or invalid build report", " ".join(state["infrastructureErrors"])
        )
        self.assertIn(
            'version = "1.0"', (self.root / "src/plugin/default.nix").read_text()
        )

    def test_missing_updater_report_blocks_otherwise_valid_update(self):
        changed = self.changed(self.alpha)
        self.build(self.alpha)
        state = self.finalize(
            [self.alpha],
            [changed],
            [self.alpha],
            errors=["Missing updater report for aarch64-linux"],
        )
        self.assertFalse(state["ready"])
        self.assertTrue(state["infrastructureFailure"])
        self.assertIn(
            'version = "1.0"', (self.root / "src/plugin/default.nix").read_text()
        )

    def test_obsolete_base_blocks_otherwise_valid_update(self):
        changed = self.changed(self.alpha)
        self.build(self.alpha)
        state = self.finalize(
            [self.alpha], [changed], [self.alpha], base_unchanged=False
        )
        self.assertFalse(state["ready"])
        self.assertTrue(state["infrastructureFailure"])
        self.assertIn(
            'version = "1.0"', (self.root / "src/plugin/default.nix").read_text()
        )

    def test_failed_combined_flake_check_does_not_publish_changes(self):
        changed = self.changed(self.alpha)
        self.build(self.alpha)
        state = self.finalize([self.alpha], [changed], [self.alpha], nix_fails=True)
        self.assertFalse(state["ready"])
        self.assertTrue(state["infrastructureFailure"])
        self.assertIn(
            'version = "1.0"', (self.root / "src/plugin/default.nix").read_text()
        )

    def test_all_unchanged_allows_resolving_existing_failure_issue(self):
        unchanged = {**self.alpha, "status": "unchanged"}
        state = self.finalize([self.alpha], [unchanged])
        self.assertFalse(state["ready"])
        self.assertFalse(state["infrastructureFailure"])
        self.assertEqual(state["packageFailures"], [])
        self.assertEqual(state["failedPackages"], [])
        self.assertEqual(state["catalogPackages"], ["test/alpha"])


class IssueStatusTests(unittest.TestCase):
    @staticmethod
    def metadata(labels):
        payload = json.dumps(sorted(labels)).encode()
        encoded = package_updates.base64.urlsafe_b64encode(payload).decode()
        return f"<!-- nix-opendeck-failed-packages:{encoded} -->\n"

    def status(self, previous, *, failing, catalog, infrastructure=False):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            state = root / "state.json"
            old = root / "old.md"
            comment = root / "comment.md"
            package_updates.save(
                state,
                {
                    "infrastructureFailure": infrastructure,
                    "packageFailures": [f"{p}: updater failed" for p in failing],
                    "failedPackages": failing,
                    "catalogPackages": catalog,
                },
            )
            old.write_text(previous)
            package_updates.render_failure_status(state, old, comment)
            return comment.read_text()

    def test_only_changes_in_failure_set_get_a_comment(self):
        previous = self.metadata(["a", "b"])
        self.assertEqual(
            self.status(previous, failing=["a", "b"], catalog=["a", "b"]), ""
        )
        comment = self.status(previous, failing=["b", "c"], catalog=["a", "b", "c"])
        self.assertIn("Newly failing", comment)
        self.assertIn("No longer failing", comment)
        self.assertIn("`a`", comment)
        self.assertIn("`c`", comment)
        self.assertIn("Outstanding failures:** 2", comment)
        self.assertNotIn("will now be closed", comment)

    def test_unchanged_failure_does_not_comment_when_error_changes(self):
        previous = self.metadata(["a"])
        self.assertEqual(self.status(previous, failing=["a"], catalog=["a"]), "")

    def test_removed_package_is_not_reported_as_fixed(self):
        previous = self.metadata(["a", "b"])
        comment = self.status(previous, failing=["b"], catalog=["b"])
        self.assertIn("No longer in the updater catalogue", comment)
        self.assertIn("`a`", comment)
        self.assertNotIn("No longer failing in the latest run", comment)
        closing = self.status(previous, failing=[], catalog=[])
        self.assertIn("not verified as fixed", closing)
        self.assertIn("will now be closed", closing)
        self.assertNotIn("all failures have been resolved", closing)

    def test_completed_episode_has_closing_status(self):
        previous = self.metadata(["a"])
        comment = self.status(previous, failing=[], catalog=["a"])
        self.assertIn("No longer failing", comment)
        self.assertIn("As no outstanding tracked failures remain", comment)
        self.assertIn("Outstanding failures:** 0", comment)

    def test_prior_catalogue_removal_is_not_reclassified_as_resolved(self):
        initial = self.metadata(["a", "b"])
        partial = self.status(initial, failing=["b"], catalog=["b"])
        self.assertIn("No longer in the updater catalogue", partial)
        # The next issue body tracks only b. It should not matter that a's
        # removal happened in an earlier run when the issue eventually closes.
        closing = self.status(self.metadata(["b"]), failing=[], catalog=["b"])
        self.assertIn("As no outstanding tracked failures remain", closing)
        self.assertNotIn("all failures have been resolved", closing)

    def test_missing_metadata_fails_safe(self):
        with self.assertRaisesRegex(ValueError, "tracking metadata"):
            self.status("No valid bot tracking metadata", failing=[], catalog=[])

    def test_issue_metadata_is_hidden_and_preserves_labels(self):
        with tempfile.TemporaryDirectory() as temp:
            state = Path(temp) / "state.json"
            issue = Path(temp) / "issue.md"
            package_updates.save(
                state,
                {
                    "packageFailures": ["new/key: updater failed"],
                    "failedPackages": ["new/key"],
                    "failureDiagnostics": [],
                },
            )
            package_updates.render_failure_issue(state, issue)
            self.assertEqual(
                package_updates.previous_failed_packages(issue.read_text()),
                {"new/key"},
            )

    def test_incomplete_report_cannot_close(self):
        with self.assertRaises(ValueError):
            self.status("", failing=[], catalog=[], infrastructure=True)


if __name__ == "__main__":
    unittest.main()
