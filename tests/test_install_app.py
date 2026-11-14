"""Filesystem regression tests for the standalone Bash installer (no Nix required)."""

import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "src/apps/install.sh"
PLUGIN_ID = "dev.example.test.sdPlugin"


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.output = self.root / "store-output"
        self.source = self.output / PLUGIN_ID
        self.source.mkdir(parents=True)
        (self.source / "manifest.json").write_text(
            json.dumps({"Name": "Example", "Version": "1.0.0", "Actions": []})
        )
        (self.source / "binary").write_text("new executable")
        (self.source / "binary").chmod(0o555)
        self.config = self.root / "config" / "opendeck"
        self.target = self.config / "plugins" / PLUGIN_ID
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self._program(
            "nix",
            """
          printf '%s\\n' "$FIXTURE_OUTPUT"
          printf '%s\\n' "$*" > "$FIXTURE_NIX_ARGS"
        """,
        )
        self._program(
            "nix-store",
            """
          root=''
          previous=''
          for arg in "$@"; do
            if [[ "$previous" == --add-root ]]; then root=$arg; fi
            previous=$arg
          done
          [[ "$*" == *'--indirect'* ]] || exit 7
          [[ "$root" == "$FIXTURE_DEST/.nix-opendeck-gc-root" ]] || exit 8
          [[ -d "$FIXTURE_DEST" ]] || exit 9
          if [[ ${FAIL_ROOT:-0} == 1 ]]; then exit 10; fi
          ln -s "$FIXTURE_OUTPUT" "$root"
        """,
        )
        self.env = os.environ.copy()
        self.env.update(
            {
                "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
                "HOME": str(self.root / "home"),
                "XDG_CONFIG_HOME": str(self.root / "config"),
                "FIXTURE_OUTPUT": str(self.output),
                "FIXTURE_NIX_ARGS": str(self.root / "nix-args"),
                "FIXTURE_DEST": str(self.target),
            }
        )

    def _program(self, name, body):
        file = self.bin / name
        file.write_text("#!/usr/bin/env bash\nset -euo pipefail\n" + body)
        file.chmod(0o755)

    def run_install(self, plugin="openactionplugins.mpris", ok=True):
        result = subprocess.run(
            [
                "bash",
                str(SCRIPT),
                "/nix/store/catalogue-source",
                "x86_64-linux",
                plugin,
            ],
            env=self.env,
            text=True,
            capture_output=True,
        )
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def test_installs_and_roots_in_final_directory(self):
        self.run_install()
        self.assertFalse(self.target.is_symlink())
        self.assertEqual((self.target / "binary").read_text(), "new executable")
        mode = (self.target / "binary").stat().st_mode
        self.assertTrue(mode & stat.S_IWUSR)
        self.assertTrue(mode & stat.S_IXUSR)
        self.assertEqual(
            (self.target / ".nix-opendeck-gc-root").readlink(), self.output
        )
        args = (self.root / "nix-args").read_text()
        self.assertIn(
            "/nix/store/catalogue-source#legacyPackages.x86_64-linux.opendeck-plugins.openactionplugins.mpris",
            args,
        )

    def test_external_installable_passes_through(self):
        ref = "github:missmoode/opendeck-umbriel-controls#default"
        self.run_install(ref)
        self.assertTrue((self.root / "nix-args").read_text().rstrip().endswith(ref))

    def test_replaces_ordinary_directory(self):
        self.target.mkdir(parents=True)
        (self.target / "old").write_text("old")
        self.run_install()
        self.assertFalse((self.target / "old").exists())
        self.assertTrue((self.target / "binary").exists())

    def test_managed_entry_is_refused_without_existing_plugin(self):
        self.config.mkdir(parents=True)
        (self.config / "externally-managed-plugins").write_text(PLUGIN_ID + "\n")
        result = self.run_install(ok=False)
        self.assertIn("externally managed", result.stderr)
        self.assertFalse(self.target.exists())

    def test_managed_entry_does_not_overwrite_existing_copy(self):
        self.target.mkdir(parents=True)
        (self.target / "old").write_text("preserve")
        self.config.mkdir(parents=True, exist_ok=True)
        (self.config / "externally-managed-plugins").write_text(PLUGIN_ID + "\n")
        result = self.run_install(ok=False)
        self.assertIn("externally managed", result.stderr)
        self.assertEqual((self.target / "old").read_text(), "preserve")

    def test_failed_copy_preserves_previous_copy(self):
        self.target.mkdir(parents=True)
        (self.target / "old").write_text("preserve")
        (self.source / "cycle").symlink_to(self.source, target_is_directory=True)
        self.run_install(ok=False)
        self.assertEqual((self.target / "old").read_text(), "preserve")

    def test_does_not_overwrite_existing_or_dangling_symlinks(self):
        for value in (self.output, self.root / "missing"):
            with self.subTest(value=value):
                self.target.parent.mkdir(parents=True, exist_ok=True)
                self.target.symlink_to(value)
                self.run_install(ok=False)
                self.assertEqual(self.target.readlink(), value)
                self.target.unlink()

    def test_refuses_symlink_ownership_file(self):
        self.config.mkdir(parents=True)
        (self.config / "externally-managed-plugins").symlink_to(self.root / "nowhere")
        self.run_install(ok=False)
        self.assertFalse(self.target.exists())

    def test_failed_root_restores_previous_copy(self):
        self.target.mkdir(parents=True)
        (self.target / "important").write_text("old data")
        self.env["FAIL_ROOT"] = "1"
        self.run_install(ok=False)
        self.assertEqual((self.target / "important").read_text(), "old data")
        self.assertFalse((self.target / "binary").exists())

    def test_failed_root_removes_fresh_copy(self):
        self.env["FAIL_ROOT"] = "1"
        self.run_install(ok=False)
        self.assertFalse(self.target.exists())

    def test_rejects_multiple_plugins(self):
        other = self.output / "other.sdPlugin"
        other.mkdir()
        (other / "manifest.json").write_text("{}")
        self.run_install(ok=False)
        self.assertFalse(self.target.exists())

    def test_rejects_invalid_manifest(self):
        (self.source / "manifest.json").write_text("not json")
        self.run_install(ok=False)
        self.assertFalse(self.target.exists())

    def test_copies_internal_symlinks(self):
        assets = self.output / "assets"
        assets.mkdir()
        (assets / "icon").write_text("svg")
        (self.source / "icons").symlink_to(assets, target_is_directory=True)
        self.run_install()
        self.assertFalse((self.target / "icons").is_symlink())
        self.assertEqual((self.target / "icons" / "icon").read_text(), "svg")

    def test_rejects_relative_xdg_config(self):
        self.env["XDG_CONFIG_HOME"] = "relative"
        self.run_install(ok=False)
        self.assertFalse(self.target.exists())

    def test_arbitrary_plugin_directory_suffix(self):
        self.source.rename(self.output / "legacy.streamDeckPlugin")
        self.env["FIXTURE_DEST"] = str(self.config / "plugins/legacy.streamDeckPlugin")
        self.run_install()
        self.assertTrue(
            (self.config / "plugins/legacy.streamDeckPlugin/binary").exists()
        )


if __name__ == "__main__":
    unittest.main()
