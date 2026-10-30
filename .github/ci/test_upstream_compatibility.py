"""Tests for automatic patched-package discovery, routing, and reporting."""

import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

MODULE = Path(__file__).with_name("upstream_compatibility.py")
spec = importlib.util.spec_from_file_location("upstream_compatibility", MODULE)
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)

CORE = "opendeck-core"
DESKTOP = "openactionplugins/desktopentry"
EXTRA = "openactionplugins/example"
COUNTER = "openactionplugins/counter"
STARTER = "nekename/starterpack"


class DiscoveryAndRoutingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.old_cwd = Path.cwd()
        os.chdir(self.temp.name)
        self.addCleanup(os.chdir, self.old_cwd)
        self.add_package(CORE, patched=True, owner="nekename", repo="OpenDeck")
        self.add_package(DESKTOP, patched=True, owner="OpenActionPlugins", repo="desktopentry")
        self.staged = [self.path(CORE), self.path(DESKTOP)]
        self.state = Path("state.json")
        self.targets = Path("targets.json")
        self.set_accepted(CORE, DESKTOP)

    def path(self, label):
        return audit.package_dir(label) + "default.nix"

    def add_package(self, label, *, patched=False, owner="example", repo="example", tag='v${finalAttrs.version}'):
        path = Path(self.path(label))
        path.parent.mkdir(parents=True, exist_ok=True)
        patches = '\npatches = [ ./patches/example.patch ];\n' if patched else ''
        path.write_text(f'''version = "2.0.0";
src = fetchFromGitHub {{
    owner = "{owner}";
    repo = "{repo}";
    tag = "{tag}";
}};{patches}''')
        if patched:
            patch_path = path.parent / "patches/example.patch"
            patch_path.parent.mkdir(exist_ok=True)
            patch_path.write_text("fixture patch")
        return path

    def update_version(self, label, new="2.1.0"):
        path = Path(self.path(label))
        path.write_text(path.read_text().replace('version = "2.0.0"', f'version = "{new}"', 1))

    def set_accepted(self, *names):
        self.state.write_text(json.dumps({"ready": True, "accepted": list(names)}))

    def select_with_old_versions(self, old="2.0.0"):
        def fake_git(*args, **kwargs):
            if args[0] == "show":
                return f'version = "{old}";\n'
            if args[:3] == ("diff", "--cached", "--name-only"):
                return "\n".join(self.staged) + "\n"
            raise AssertionError(args)
        with patch.object(audit, "git", side_effect=fake_git):
            return audit.select("fixture-sha", self.state, self.targets)

    def routes(self):
        return json.loads(self.targets.read_text())

    def test_only_changed_patched_package_is_audited(self):
        self.update_version(DESKTOP)
        self.assertEqual(self.select_with_old_versions(), 1)
        self.assertEqual(self.routes()["auditTargets"], [
            {"package": DESKTOP, "from": "2.0.0", "to": "2.1.0"}
        ])

    def test_no_version_changes_even_if_accepted(self):
        self.assertEqual(self.select_with_old_versions(), 0)
        self.assertEqual(self.routes()["auditTargets"], [])

    def test_both_versions_change(self):
        self.update_version(CORE)
        self.update_version(DESKTOP)
        self.assertEqual(self.select_with_old_versions(), 2)

    def test_only_accepted_packages(self):
        self.set_accepted(CORE)
        self.staged = [self.path(CORE)]
        self.update_version(CORE)
        self.update_version(DESKTOP)
        self.assertEqual(self.select_with_old_versions(), 1)
        self.assertEqual(self.routes()["auditTargets"][0]["package"], CORE)

    def test_routes_only_changed_review_package_files(self):
        self.add_package(COUNTER)
        self.staged.append(self.path(COUNTER))
        self.set_accepted(CORE, DESKTOP, COUNTER)
        self.update_version(DESKTOP)
        self.assertEqual(self.select_with_old_versions(), 1)
        self.assertEqual(self.routes()["reviewPaths"], [self.path(DESKTOP)])
        self.assertEqual(set(self.routes()["autoPaths"]), set(self.staged) - {self.path(DESKTOP)})

    def test_new_patched_plugin_is_discovered_without_registration(self):
        self.add_package(EXTRA, patched=True, owner="TestOrg", repo="ExamplePlugin", tag='${finalAttrs.version}')
        self.staged.append(self.path(EXTRA))
        self.set_accepted(CORE, DESKTOP, EXTRA)
        self.update_version(EXTRA)
        self.assertEqual(self.select_with_old_versions(), 1)
        self.assertEqual(self.routes()["reviewPackages"], [EXTRA])
        spec = audit.package_spec(EXTRA)
        self.assertEqual(audit.source_spec(spec), {"upstream": "TestOrg/ExamplePlugin", "tag_prefix": ""})

    def test_unpatched_version_bump_is_not_reviewed(self):
        self.add_package(COUNTER)
        self.update_version(COUNTER)
        self.staged.append(self.path(COUNTER))
        self.set_accepted(CORE, DESKTOP, COUNTER)
        self.assertEqual(self.select_with_old_versions(), 0)
        self.assertIn(self.path(COUNTER), self.routes()["autoPaths"])

    def test_patch_file_not_referenced_does_not_trigger_review(self):
        self.add_package(COUNTER)
        directory = Path(audit.package_dir(COUNTER)) / "patches"
        directory.mkdir()
        (directory / "abandoned.patch").write_text("old")
        self.staged.append(self.path(COUNTER))
        self.set_accepted(CORE, DESKTOP, COUNTER)
        self.update_version(COUNTER)
        self.assertEqual(self.select_with_old_versions(), 0)

    def test_postpatch_and_nested_patch_references_are_discovered(self):
        path = Path(self.path(EXTRA))
        self.add_package(EXTRA)
        (path.parent / "patches/tauri").mkdir(parents=True)
        (path.parent / "patches/tauri/fix.patch").write_text("patch")
        path.write_text(path.read_text() + "\npostPatch = ''${./patches/tauri/fix.patch}'';\n")
        self.staged.append(self.path(EXTRA))
        self.set_accepted(CORE, DESKTOP, EXTRA)
        self.update_version(EXTRA)
        self.assertEqual(self.select_with_old_versions(), 1)
        self.assertEqual(len(audit.patch_files(audit.package_spec(EXTRA))), 1)

    def test_root_level_diff_is_also_discovered(self):
        path = self.add_package(EXTRA)
        (path.parent / "fix.diff").write_text("patch")
        path.write_text(path.read_text() + "\npatches = [ ./fix.diff ];\n")
        self.staged.append(self.path(EXTRA))
        self.set_accepted(CORE, DESKTOP, EXTRA)
        self.update_version(EXTRA)
        self.assertEqual(self.select_with_old_versions(), 1)
        self.assertEqual(len(audit.patch_files(audit.package_spec(EXTRA))), 1)

    def test_nonliteral_fetched_patch_is_reviewed_but_cannot_pass_audit(self):
        path = self.add_package(EXTRA)
        path.write_text(path.read_text() + '\npatches = [ (fetchpatch { url = "https://example.com/fix.patch"; hash = "sha256-abc"; }) ];\n')
        self.staged.append(self.path(EXTRA))
        self.set_accepted(CORE, DESKTOP, EXTRA)
        self.update_version(EXTRA)
        self.assertEqual(self.select_with_old_versions(), 1)
        self.assertIn(EXTRA, self.routes()["reviewPackages"])
        audit.review(self.targets, "report.md")
        report = Path("report.md").read_text()
        self.assertIn("**Review unavailable:**", report)
        self.assertIn("cannot be read from local patch files", report)

    def test_core_and_starterpack_remain_together(self):
        self.add_package(STARTER)
        self.set_accepted(CORE, STARTER)
        self.update_version(CORE)
        self.staged = [self.path(CORE), self.path(STARTER)]
        self.select_with_old_versions()
        self.assertIn(self.path(STARTER), self.routes()["reviewPaths"])
        self.assertIn(STARTER, self.routes()["reviewPackages"])
        self.assertNotIn(self.path(STARTER), self.routes()["autoPaths"])
        self.assertEqual(len(self.routes()["auditTargets"]), 1)

    def test_routes_reject_outside_src(self):
        self.staged.append(".github/workflows/update-packages.yml")
        with self.assertRaisesRegex(ValueError, "outside src"):
            self.select_with_old_versions()

    def test_bodies_are_isolated(self):
        self.update_version(DESKTOP)
        self.select_with_old_versions()
        audit.pr_bodies(self.targets, "auto.md", "review.md")
        self.assertIn("Auto-merge eligible", Path("auto.md").read_text())
        self.assertIn("manual review required", Path("review.md").read_text())
        self.assertIn(DESKTOP, Path("review.md").read_text())
        self.assertIn("non-draft PR", Path("review.md").read_text())
        self.assertNotIn("run checks", Path("review.md").read_text())
        self.assertNotIn(DESKTOP, Path("auto.md").read_text())

    def test_unattributed_shared_file_fails_closed(self):
        self.staged.append("src/lib/plugins/mkRustOpenDeckPlugin.nix")
        with self.assertRaisesRegex(ValueError, "Cannot attribute"):
            self.select_with_old_versions()

    def test_missing_accepted_package_file_fails_closed(self):
        self.staged = [self.path(CORE)]
        with self.assertRaisesRegex(ValueError, "Accepted package has no staged changes"):
            self.select_with_old_versions()

    def test_missing_referenced_patch_fails_closed(self):
        (Path(self.path(CORE)).parent / "patches/example.patch").unlink()
        self.update_version(CORE)
        with self.assertRaisesRegex(ValueError, "Referenced downstream patch is missing"):
            self.select_with_old_versions()

    def test_unready_state_fails_closed(self):
        self.state.write_text(json.dumps({"ready": False, "accepted": [CORE]}))
        with self.assertRaisesRegex(ValueError, "not finalized"):
            self.select_with_old_versions()

    def test_unknown_source_does_not_become_an_ai_pass(self):
        self.update_version(DESKTOP)
        self.select_with_old_versions()
        p = Path(self.path(DESKTOP))
        p.write_text(p.read_text().replace("fetchFromGitHub", "fetchurl"))
        audit.review(self.targets, "report.md")
        self.assertIn("**Review unavailable:**", Path("report.md").read_text())
        self.assertIn("Cannot identify one fetchFromGitHub source", Path("report.md").read_text())

    def test_review_error_does_not_hide_other_package(self):
        Path("targets.json").write_text(json.dumps({"auditTargets": [
            {"package": label, "from": "2.0.0", "to": "2.1.0"} for label in (CORE, DESKTOP)
        ]}))
        with patch.object(audit, "source_diff", side_effect=RuntimeError("upstream fetch failed")):
            audit.review("targets.json", "report.md")
        report = Path("report.md").read_text()
        self.assertEqual(report.count("**Review unavailable:**"), 2)
        self.assertIn(audit.MARKER, report)

    def test_unsupported_tag_format_does_not_get_guessed(self):
        self.add_package(EXTRA, patched=True, tag='release-${finalAttrs.version}')
        with self.assertRaisesRegex(ValueError, "Cannot identify supported version tags"):
            audit.source_spec(audit.package_spec(EXTRA))

    def test_missing_key_is_not_a_pass(self):
        with patch.dict(os.environ, {"GEMINI_API_KEY": ""}):
            with self.assertRaisesRegex(RuntimeError, "not configured"):
                audit.ask_gemini("hello")

    def test_bad_model_completion_is_not_a_pass(self):
        class FakeResponse:
            def __enter__(self): return self
            def __exit__(self, *_): return None
        response = FakeResponse()
        with patch.dict(os.environ, {"GEMINI_API_KEY": "test-secret"}):
            with patch.object(audit, "urlopen", return_value=response):
                with patch.object(audit.json, "load", return_value={
                    "candidates": [{"finishReason": "MAX_TOKENS", "content": {"parts": [{"text": "partial"}]}}]
                }):
                    with self.assertRaisesRegex(RuntimeError, "without a complete review"):
                        audit.ask_gemini("hello")


    def test_missing_model_finish_reason_is_not_a_pass(self):
        class FakeResponse:
            def __enter__(self): return self
            def __exit__(self, *_): return None
        with patch.dict(os.environ, {"GEMINI_API_KEY": "test-secret"}):
            with patch.object(audit, "urlopen", return_value=FakeResponse()):
                with patch.object(audit.json, "load", return_value={
                    "candidates": [{"content": {"parts": [{"text": "unconfirmed"}]}}]
                }):
                    with self.assertRaisesRegex(RuntimeError, "without a complete review"):
                        audit.ask_gemini("hello")

    def test_confirmed_model_finish_reason_is_accepted(self):
        class FakeResponse:
            def __enter__(self): return self
            def __exit__(self, *_): return None
        with patch.dict(os.environ, {"GEMINI_API_KEY": "test-secret"}):
            with patch.object(audit, "urlopen", return_value=FakeResponse()):
                with patch.object(audit.json, "load", return_value={
                    "candidates": [{"finishReason": "STOP", "content": {"parts": [{"text": "review"}]}}]
                }):
                    self.assertEqual(audit.ask_gemini("hello"), "review")


class WorkflowWiringTests(unittest.TestCase):
    def test_no_update_skips_all_count_dependent_failure_checks(self):
        # When `finalize` reports ready=false, audit-select is skipped and
        # outputs are empty, not "0". Check the real workflow gate.
        workflow = MODULE.parent.parent / "workflows/update-packages.yml"
        content = workflow.read_text()
        gate = content.split("      - name: Fail after reporting all errors", 1)[1]
        self.assertEqual(gate.count("steps.audit-select.outcome == 'success' &&"), 3)
        for count in ("auto_count", "review_count"):
            self.assertRegex(
                gate,
                rf"steps\.audit-select\.outcome == 'success' &&\s+"
                rf"steps\.audit-select\.outputs\.{count} != '0'",
            )

    def test_existing_maintainers_variable_is_used_for_assignees(self):
        content = (MODULE.parent.parent / "workflows/update-packages.yml").read_text()
        self.assertIn("assignees: ${{ vars.UPDATE_MAINTAINERS }}", content)
        self.assertIn("UPDATE_MAINTAINERS: ${{ vars.UPDATE_MAINTAINERS }}", content)
        self.assertNotIn("UPSTREAM_AUDIT_ASSIGNEE", content)



if __name__ == "__main__":
    unittest.main()
