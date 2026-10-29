"""Offline regression tests for selective failed-build analysis and request dedup."""

import hashlib
import json
import os
import contextlib
import io
import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import failure_audit as audit
import package_updates


class FailureAuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.old_cwd = Path.cwd()
        os.chdir(self.root)
        self.addCleanup(os.chdir, self.old_cwd)
        self.label = "opendeck-core"
        self.path = self.root / "src/packages/opendeck/default.nix"
        self.path.parent.mkdir(parents=True)
        self.path.write_text('''version = "2.14.2";
src = fetchFromGitHub {
  owner = "nekename";
  repo = "OpenDeck";
  tag = "v${finalAttrs.version}";
};
patches = [
  ./patches/0001-source.patch
];
''')
        self.patch = self.path.parent / "patches/0001-source.patch"
        self.patch.parent.mkdir()
        self.patch.write_text('''diff --git a/src-tauri/src/encoder_layouts.rs b/src-tauri/src/encoder_layouts.rs
--- a/src-tauri/src/encoder_layouts.rs
+++ b/src-tauri/src/encoder_layouts.rs
@@ -1,1 +1,1 @@
-let x = 1;
+let x = 2;
''')
        self.update_patch = b'''diff --git a/src/packages/opendeck/default.nix b/src/packages/opendeck/default.nix
--- a/src/packages/opendeck/default.nix
+++ b/src/packages/opendeck/default.nix
@@ -1 +1 @@
-version = "2.14.2";
+version = "2.15.0";
'''
        self.update_path = self.root / "updates/updates-x86_64-linux/patches/core.patch"
        self.update_path.parent.mkdir(parents=True)
        self.update_path.write_bytes(self.update_patch)
        self.record = {"id": "core", "label": self.label, "system": "x86_64-linux",
                       "status": "changed", "sha256": hashlib.sha256(self.update_patch).hexdigest()}
        self.target = {"id": "opendeck", "label": "opendeck", "system": "x86_64-linux",
                       "attr": "packages.x86_64-linux.opendeck", "patches": [self.record]}
        self.prepared_path = self.root / "prepared.json"
        self.build_path = self.root / "builds/build-opendeck-x86_64-linux/result.json"
        self.build_path.parent.mkdir(parents=True)
        self.prepared = {"updateResults": [self.record], "errors": [],
                         "opendeck": [self.target], "plugins": []}

    def select(self, excerpt, phase="nix-build"):
        self.prepared_path.write_text(json.dumps(self.prepared))
        self.build_path.write_text(json.dumps({
            "id": "opendeck", "label": "opendeck", "system": "x86_64-linux",
            "attr": "packages.x86_64-linux.opendeck", "phase": phase,
            "status": "failed", "error": "nix build exited with 1", "errorExcerpt": excerpt,
        }))
        return audit.select(self.prepared_path, self.root / "updates", self.root / "builds")

    def test_rejects_unrelated_build_error(self):
        self.assertEqual(self.select('error: network unavailable while fetching dependency'), [])

    def test_rejects_updater_or_non_native_failure(self):
        self.assertEqual(self.select('Hunk #1 FAILED', phase="apply-update-patch"), [])

    def test_rejects_source_hash_only_update(self):
        self.update_path.write_bytes(self.update_patch.replace(b'2.15.0', b'2.14.2'))
        self.prepared["updateResults"][0]["sha256"] = hashlib.sha256(self.update_path.read_bytes()).hexdigest()
        self.assertEqual(self.select('Hunk #1 FAILED'), [])

    def test_patch_application_selects_exactly_one_candidate(self):
        selected = self.select('patching file src-tauri/src/encoder_layouts.rs\nHunk #1 FAILED at 30')
        self.assertEqual(len(selected), 1)
        self.assertEqual(selected[0]["reason"], "patch application")

    def test_compiler_diagnostic_must_reference_patched_path(self):
        self.assertEqual(self.select('error[E0308]: mismatched types\n --> unrelated.rs:3:2'), [])
        self.assertEqual(self.select('src-tauri/src/encoder_layouts.rs\n'
                                     'error[E0308]: mismatched types\n --> unrelated.rs:3:2'), [])
        selected = self.select('error[E0308]: mismatched types\n --> src-tauri/src/encoder_layouts.rs:3:2')
        self.assertEqual(len(selected), 1)
        self.assertIn("compiler", selected[0]["reason"])

    def test_same_code_different_log_has_same_fingerprint(self):
        a = self.select('Hunk #1 FAILED at 30')[0]["fingerprint"]
        b = self.select('Hunk #2 FAILED at 40')[0]["fingerprint"]
        self.assertEqual(a, b)
        self.patch.write_text(self.patch.read_text() + '\n# changed downstream source patch\n')
        c = self.select('Hunk #2 FAILED at 40')[0]["fingerprint"]
        self.assertNotEqual(a, c)

    def test_combined_sources_skip_ambiguous_patch_failure(self):
        companion = {"id": "starter", "label": "nekename/starterpack", "sha256": "c" * 64}
        self.target["patches"].append(companion)
        self.assertEqual(self.select('Hunk #1 FAILED'), [])

    def test_new_issue_number_does_not_depend_on_search_indexing(self):
        with patch.dict(os.environ, {"ISSUE_NUMBER": "123"}):
            with patch.object(audit, "gh", side_effect=AssertionError("unexpected search")):
                self.assertEqual(audit.issue_number(), 123)

    def test_reserve_only_once_for_bot_authored_markers(self):
        candidates = self.select('Hunk #1 FAILED')
        path = self.root / "candidates.json"
        out = self.root / "reserved.json"
        path.write_text(json.dumps(candidates))
        previous = ""
        posts = []
        def fake_gh(*args):
            nonlocal previous
            if args[:2] == ("issue", "list"):
                return json.dumps([{"number": 12, "title": "Automated package update failures"}])
            if "--paginate" in args:
                return previous
            if "POST" in args:
                body = args[-1][5:]
                posts.append(body)
                previous = body
                return json.dumps({"id": 99})
            raise AssertionError(args)
        with patch.object(audit, "gh", side_effect=fake_gh), patch.dict(
            os.environ, {"GH_REPO": "example/nix-opendeck", "APP_BOT_LOGIN": "bot[bot]"}
        ):
            audit.reserve(path, out)
            self.assertEqual(len(json.loads(out.read_text())), 1)
            audit.reserve(path, out)
            self.assertEqual(json.loads(out.read_text()), [])
        self.assertEqual(len(posts), 1)


class DiagnosticCaptureTests(unittest.TestCase):
    def test_failed_updater_retains_diagnostic_excerpt(self):
        with patch.object(package_updates, "logged_build", return_value=(1, "updater failed to fetch source")):
            result = package_updates.run("nix-update", "example", check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn("failed to fetch", result.errorExcerpt)

    def test_failed_build_streams_and_captures_bounded_excerpt(self):
        command = 'import sys; print("ok"); print("\\x1b[31mHunk #1 FAILED\\x1b[0m", file=sys.stderr); sys.exit(1)'
        with contextlib.redirect_stdout(io.StringIO()):
            code, excerpt = package_updates.logged_build(sys.executable, "-c", command)
        self.assertEqual(code, 1)
        self.assertIn("Hunk #1 FAILED", excerpt)
        self.assertNotIn("\x1b", excerpt)
        self.assertLessEqual(len(excerpt), 10000)

    def test_issue_always_includes_excerpt(self):
        with tempfile.TemporaryDirectory() as temp:
            state = Path(temp) / "state.json"
            output = Path(temp) / "issue.md"
            state.write_text(json.dumps({
                "packageFailures": ["opendeck: failed"],
                "failureDiagnostics": [{
                    "label": "opendeck", "system": "x86_64-linux", "phase": "nix-build",
                    "error": "nix build exited with 1", "excerpt": "Hunk #1 FAILED",
                }],
            }))
            package_updates.render_failure_issue(state, output)
            body = output.read_text()
            self.assertIn("Hunk #1 FAILED", body)
            self.assertIn("### Diagnostic excerpts", body)
            self.assertIn("nix-opendeck-package-update-failures", body)



if __name__ == "__main__":
    unittest.main()
