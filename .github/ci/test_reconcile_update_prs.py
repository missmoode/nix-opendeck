"""Tests for closing only fully incorporated bot source updates."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import reconcile_update_prs as cleanup


class SourceRedundancyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.previous = Path.cwd()
        os.chdir(self.tmp.name)
        self.addCleanup(os.chdir, self.previous)
        for argv in (("init", "-q"), ("config", "user.name", "Test"),
                     ("config", "user.email", "test@example.invalid")):
            self.git(*argv)
        self.write("src/plugin.nix", 'version = "1";\n')
        self.write("src/another.nix", 'version = "1";\n')
        self.write("src/patches/fix.patch", "old patch\n")
        self.write(".github/workflows/update-packages.yml", "old workflow\n")
        self.commit("original")
        self.git("branch", "automated/test")

    def git(self, *argv):
        return subprocess.run(["git", *argv], check=True,
                              capture_output=True, text=True).stdout.strip()

    def write(self, file, text):
        path = Path(file)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-qm", message)

    def propose(self, changes):
        self.git("switch", "-q", "automated/test")
        for path, body in changes.items():
            self.write(path, body)
        self.commit("proposed updater changes")
        self.git("switch", "-q", "master")

    def test_unmerged_update_is_preserved(self):
        self.propose({"src/plugin.nix": 'version = "2";\n'})
        self.assertFalse(cleanup.redundant_source_changes("master", "automated/test"))

    def test_combined_repair_on_main_makes_update_redundant(self):
        self.propose({"src/plugin.nix": 'version = "2";\n'})
        self.write("src/plugin.nix", 'version = "2";\n')
        self.write("src/patches/fix.patch", "new patch for v2\n")
        self.commit("merged version and patch repair")
        self.assertTrue(cleanup.redundant_source_changes("master", "automated/test"))

    def test_partially_integrated_update_stays_open(self):
        self.propose({"src/plugin.nix": 'version = "2";\n',
                      "src/another.nix": 'version = "2";\n'})
        self.write("src/plugin.nix", 'version = "2";\n')
        self.commit("merged first package only")
        self.assertFalse(cleanup.redundant_source_changes("master", "automated/test"))

    def test_modified_derivation_not_equivalent_is_preserved(self):
        self.propose({"src/plugin.nix": 'version = "2";\n'})
        self.write("src/plugin.nix", 'version = "2";\n# different repair edits\n')
        self.commit("different file content")
        self.assertFalse(cleanup.redundant_source_changes("master", "automated/test"))

    def test_non_source_edit_is_not_auto_closed(self):
        self.propose({".github/workflows/update-packages.yml": "changed workflow\n"})
        self.write(".github/workflows/update-packages.yml", "changed workflow\n")
        self.commit("same workflow on main")
        self.assertFalse(cleanup.redundant_source_changes("master", "automated/test"))


class MatchingPRTests(unittest.TestCase):
    @patch.object(cleanup, "execute")
    def test_bot_only_and_correct_head(self, execute):
        def entry(user, branch, number):
            return {"number": number, "state": "open", "user": {"login": user},
                    "head": {"ref": branch, "repo": {"full_name": "example/repo"}},
                    "base": {"ref": "main"}}
        import json
        execute.return_value = json.dumps([
            entry("person", "automated/package-updates", 1),
            entry("mybot[bot]", "automated/package-updates", 2),
        ])
        result = cleanup.matching_pr("example/repo", "main", "automated/package-updates", "mybot[bot]")
        self.assertEqual(result["number"], 2)


if __name__ == "__main__":
    unittest.main()
