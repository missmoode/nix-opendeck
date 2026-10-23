"""Regression checks for the package-updater's repository mutation boundary.

These tests use a temporary Git checkout and a simulated nix-update command;
no Nix installation or network access is required.
"""

import contextlib
import io
import json
import os
from pathlib import Path
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
        self.write(".github/workflows/cache.yml", 'name: cache\n')
        self.write("README.md", '# Example\n')
        for args in [
            ("init", "-q"),
            ("config", "user.name", "CI Test"),
            ("config", "user.email", "test@example.invalid"),
            ("add", "-A"),
            ("commit", "-qm", "initial"),
        ]:
            subprocess.run(["git", *args], check=True, capture_output=True)

        self.plan = Path(self.temp.name) / "plan.json"
        self.plan.write_text(json.dumps({
            "packages": [{
                "id": "plugin-test", "label": "test/plugin",
                "system": "x86_64-linux", "attr": "packages.x86_64-linux.test",
            }],
            "updaters": [{"system": "x86_64-linux", "runner": "ubuntu-24.04"}],
        }))
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

        args = type("Args", (), {
            "plan": str(self.plan),
            "system": "x86_64-linux",
            "output": str(self.out),
        })()
        with patch.object(package_updates, "run", side_effect=intercept):
            with contextlib.redirect_stdout(io.StringIO()):
                package_updates.update(args)
        records = json.loads((self.out / "results.json").read_text())
        status = subprocess.run(["git", "status", "--porcelain"],
                                capture_output=True, text=True, check=True).stdout
        # The updater must leave the Git checkout clean after every attempt.
        self.assertEqual(status.strip(), "")
        return records[0]

    def test_source_change_produces_a_patch(self):
        record = self.simulate_update({"src/plugin/default.nix": 'version = "1.1";\n'})
        self.assertEqual(record["status"], "changed")
        patch_path = self.out / "patches" / "plugin-test.patch"
        self.assertTrue(patch_path.is_file())
        self.assertEqual(record["sha256"], package_updates.hashlib.sha256(patch_path.read_bytes()).hexdigest())

    def test_workflow_change_is_rejected(self):
        record = self.simulate_update({".github/workflows/cache.yml": 'name: changed\n'})
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


if __name__ == "__main__":
    unittest.main()
