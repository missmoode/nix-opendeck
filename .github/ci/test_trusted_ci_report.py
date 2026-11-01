"""Focused tests for the privileged reporter's trust boundary.

Included in the PR and updater Python test suites. These are mocked unit
tests, not a substitute for a live GitHub Actions integration test.
"""

import importlib.util
import json
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch
from urllib.error import URLError

spec = importlib.util.spec_from_file_location(
    "trusted_ci_report", Path(__file__).with_name("trusted_ci_report.py")
)
reporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reporter)

HEAD, MERGE, BASE = "a" * 40, "b" * 40, "c" * 40
REPO = "missmoode/nix-opendeck"


def fixture(kind="Checks"):
    path = next(path for path, (name, _, _) in reporter.WORKFLOWS.items() if name == kind)
    title = f"{kind} PR #39 merge {MERGE}"
    event = {"workflow_run": {
        "id": 42, "name": title, "display_title": title, "path": path,
        "event": "pull_request", "status": "completed", "conclusion": "success",
        "head_sha": HEAD, "repository": {"full_name": REPO},
        "pull_requests": [{"number": 39}], "html_url": "https://github.com/example/run/42",
    }}
    pr = {
        "state": "open", "merge_commit_sha": MERGE,
        "base": {"ref": "main", "sha": BASE, "repo": {"full_name": REPO}},
        "head": {"sha": HEAD, "ref": "feature", "repo": {"full_name": REPO}},
        "draft": False, "labels": [], "user": {"login": "contributor"},
    }
    return event, pr


class FakeAPI:
    repo = REPO

    def __init__(self, pr, kind="Checks"):
        self.pr = pr
        self.changed = set()
        self.newer = False
        self.recent = []
        self.jobs = [{"name": next(job for name, job, _ in reporter.WORKFLOWS.values() if name == kind),
                      "conclusion": "success"}]
        self.published = []
        self.fail_status = False
        self.annotations = []
        self.comments = []
        self.writes = []

    def request(self, path, **kwargs):
        if path.startswith("/pulls/"):
            return self.pr
        if path.startswith("/issues/"):
            self.writes.append((path, kwargs))
            return {"id": 123}
        raise AssertionError("Unexpected request: " + path)

    def pages(self, path, key=None):
        if path.startswith("/actions/workflows/"):
            if self.newer:
                yield {"id": 43, "display_title": f"Checks PR #39 merge {MERGE}"}
            yield from self.recent
        elif path.startswith("/actions/runs/"):
            yield from self.jobs
        elif path.startswith("/check-runs/"):
            yield from self.annotations
        elif path.startswith("/issues/"):
            yield from self.comments
        else:
            raise AssertionError("Unexpected pagination: " + path)

    def content_sha(self, path, ref):
        return "changed" if (path, ref) in self.changed else "trusted"

    def status(self, result):
        if self.fail_status:
            raise URLError("status publication failed")
        self.published.append((result["head"], result["context"], result["state"]))


class ReporterTests(unittest.TestCase):
    def setup_case(self, kind="Checks"):
        event, pr = fixture(kind)
        return event, pr, FakeAPI(pr, kind)

    def test_realistic_run_is_accepted(self):
        for kind in ("Checks", "Package verification"):
            with self.subTest(kind=kind):
                event, _, api = self.setup_case(kind)
                self.assertEqual(reporter.assess(event, api)["state"], "success")

    def test_modified_ci_policy_fails_closed(self):
        for kind in ("Checks", "Package verification"):
            event, _, api = self.setup_case(kind)
            paths = [event["workflow_run"]["path"], *reporter.REPORTER_PATHS]
            if kind == "Package verification":
                paths.append(".github/ci/targets.nix")
            for path in paths:
                with self.subTest(kind=kind, path=path):
                    api.changed = {(path, MERGE)}
                    self.assertEqual(reporter.assess(event, api)["state"], "failure")

    def test_stale_pr_revision_is_ignored(self):
        for field in ("head", "merge"):
            event, pr, api = self.setup_case()
            if field == "head":
                pr["head"]["sha"] = "d" * 40
            else:
                pr["merge_commit_sha"] = "d" * 40
            with self.subTest(field=field):
                self.assertIsNone(reporter.assess(event, api))

    def test_unrelated_or_misidentified_run_is_ignored(self):
        for change in ("path", "display_title", "association"):
            event, _, api = self.setup_case()
            if change == "path":
                event["workflow_run"]["path"] = ".github/workflows/other.yml"
            elif change == "display_title":
                event["workflow_run"]["display_title"] = "Unrelated"
            else:
                event["workflow_run"]["pull_requests"] = [{"number": 12}]
            with self.subTest(change=change):
                self.assertIsNone(reporter.assess(event, api))

    def test_superseded_or_cancelled_run_is_ignored(self):
        event, _, api = self.setup_case()
        api.newer = True
        self.assertIsNone(reporter.assess(event, api))
        api.newer = False
        event["workflow_run"]["conclusion"] = "cancelled"
        self.assertIsNone(reporter.assess(event, api))

    def test_cancelled_newer_run_does_not_hide_success(self):
        event, _, api = self.setup_case()
        api.recent = [{
            "id": 43, "display_title": f"Checks PR #39 merge {MERGE}",
            "status": "completed", "conclusion": "cancelled",
        }]
        self.assertEqual(reporter.assess(event, api)["state"], "success")

    def test_cancelled_run_reconsiders_earlier_completion(self):
        event, _, api = self.setup_case()
        event["workflow_run"]["id"] = 43
        event["workflow_run"]["conclusion"] = "cancelled"
        api.recent = [{
            "id": 42, "display_title": f"Checks PR #39 merge {MERGE}",
            "head_sha": HEAD, "status": "completed", "conclusion": "success",
            "html_url": "https://github.com/example/run/42",
        }]
        result = reporter.assess(event, api)
        self.assertEqual(result["state"], "success")
        self.assertEqual(result["url"], "https://github.com/example/run/42")

    def test_cancelled_run_does_not_recover_running_or_obsolete_results(self):
        event, _, api = self.setup_case()
        event["workflow_run"]["id"] = 43
        event["workflow_run"]["conclusion"] = "cancelled"
        prior = {
            "id": 42, "display_title": f"Checks PR #39 merge {MERGE}",
            "head_sha": HEAD, "status": "completed", "conclusion": "success",
            "html_url": "https://github.com/example/run/42",
        }
        api.recent = [{**prior, "status": "in_progress"}]
        self.assertIsNone(reporter.assess(event, api))
        api.recent = [{**prior, "head_sha": "d" * 40}]
        self.assertIsNone(reporter.assess(event, api))
        api.recent = [prior, {
            "id": 44, "display_title": f"Checks PR #39 merge {MERGE}",
            "status": "in_progress", "conclusion": None,
        }]
        self.assertIsNone(reporter.assess(event, api))

    def test_cancelled_new_commit_cannot_reuse_old_success(self):
        """A cancellation must never certify a different commit or merge tree."""
        for kind in ("Checks", "Package verification"):
            with self.subTest(kind=kind):
                event, pr, api = self.setup_case(kind)
                event["workflow_run"]["id"] = 43
                event["workflow_run"]["conclusion"] = "cancelled"
                # Run 42 passed, but for the previous PR head/merge revision.
                api.recent = [{
                    "id": 42, "display_title": event["workflow_run"]["display_title"],
                    "head_sha": "d" * 40, "status": "completed",
                    "conclusion": "success", "html_url": "https://github.com/example/run/42",
                }]
                self.assertIsNone(reporter.assess(event, api))
                # Even a valid prior run becomes obsolete after a new push.
                api.recent[0]["head_sha"] = HEAD
                pr["head"]["sha"] = "d" * 40
                self.assertIsNone(reporter.assess(event, api))

    def test_newer_failed_run_is_authoritative_over_older_success(self):
        event, _, api = self.setup_case()
        api.recent = [{
            "id": 43, "display_title": f"Checks PR #39 merge {MERGE}",
            "head_sha": HEAD, "status": "completed", "conclusion": "failure",
        }]
        self.assertIsNone(reporter.assess(event, api))

    def test_both_verifications_require_current_non_draft_pr(self):
        for kind in ("Checks", "Package verification"):
            for draft in (True, None):
                with self.subTest(kind=kind, draft=draft):
                    event, pr, api = self.setup_case(kind)
                    pr["draft"] = draft
                    result = reporter.assess(event, api)
                    self.assertEqual(result["state"], "pending")
                    self.assertFalse(result["report_failure"])

    def test_labels_do_not_change_verification_eligibility(self):
        for kind in ("Checks", "Package verification"):
            event, pr, api = self.setup_case(kind)
            pr["labels"] = [{"name": "some unrelated label"}]
            self.assertEqual(reporter.assess(event, api)["state"], "success")

    def test_draft_transition_rechecks_current_readiness(self):
        for kind in ("Checks", "Package verification"):
            event, pr, api = self.setup_case(kind)
            pr["draft"] = True
            self.assertEqual(reporter.assess(event, api)["state"], "pending")
            pr["draft"] = False
            self.assertEqual(reporter.assess(event, api)["state"], "success")
            # A draft-skipped job cannot be certified after the PR becomes ready.
            api.jobs[0]["conclusion"] = "skipped"
            self.assertEqual(reporter.assess(event, api)["state"], "pending")

    def test_skipped_run_during_draft_to_ready_race_stays_pending(self):
        for kind in ("Checks", "Package verification"):
            with self.subTest(kind=kind):
                event, pr, api = self.setup_case(kind)
                # A successful run published an App status before drafting.
                api.status(reporter.assess(event, api))
                self.assertEqual(api.published[-1][2], "success")
                # Its successor was skipped while draft. The completion
                # reporter starts only after the PR is ready again.
                event["workflow_run"]["id"] = 43
                event["workflow_run"]["conclusion"] = "skipped"
                api.jobs[0]["conclusion"] = "skipped"
                pr["draft"] = False
                result = reporter.assess(event, api)
                self.assertEqual(result["state"], "pending")
                self.assertFalse(result["report_failure"])
                api.status(result)
                self.assertEqual(api.published[-1][2], "pending")
                # A subsequent real verification can resolve pending.
                event["workflow_run"]["id"] = 44
                event["workflow_run"]["conclusion"] = "success"
                api.jobs[0]["conclusion"] = "success"
                api.status(reporter.assess(event, api))
                self.assertEqual(api.published[-1][2], "success")

    def test_skipped_gate_does_not_hide_other_workflow_failures(self):
        for kind in ("Checks", "Package verification"):
            with self.subTest(kind=kind):
                event, _, api = self.setup_case(kind)
                api.jobs[0]["conclusion"] = "skipped"
                self.assertEqual(reporter.assess(event, api)["state"], "pending")
                event["workflow_run"]["conclusion"] = "failure"
                result = reporter.assess(event, api)
                self.assertEqual(result["state"], "failure")
                self.assertTrue(result["report_failure"])

    def test_skipped_run_does_not_hide_modified_ci_policy(self):
        for kind in ("Checks", "Package verification"):
            with self.subTest(kind=kind):
                event, _, api = self.setup_case(kind)
                event["workflow_run"]["conclusion"] = "skipped"
                api.jobs[0]["conclusion"] = "skipped"
                api.changed = {(event["workflow_run"]["path"], MERGE)}
                result = reporter.assess(event, api)
                self.assertEqual(result["state"], "failure")
                self.assertFalse(result["report_failure"])

    def test_required_job_must_pass_exactly_once(self):
        for conclusions in ([], ["failure"], ["success", "success"]):
            event, _, api = self.setup_case()
            job = api.jobs[0]["name"]
            api.jobs = [{"name": job, "conclusion": value} for value in conclusions]
            with self.subTest(conclusions=conclusions):
                self.assertEqual(reporter.assess(event, api)["state"], "failure")

    def test_workflow_failure_is_not_certified(self):
        event, _, api = self.setup_case()
        event["workflow_run"]["conclusion"] = "failure"
        self.assertEqual(reporter.assess(event, api)["state"], "failure")

    def test_publish_targets_head_only(self):
        event, _, api = self.setup_case()
        api.status(reporter.assess(event, api))
        self.assertEqual(api.published, [(HEAD, "nix-opendeck/tests", "success")])

    def test_notification_error_does_not_undo_status(self):
        event, _, api = self.setup_case("Package verification")
        with TemporaryDirectory() as directory:
            event_file = Path(directory) / "event.json"
            event_file.write_text(json.dumps(event), encoding="utf-8")
            env = {"GITHUB_EVENT_PATH": str(event_file), "GITHUB_REPOSITORY": REPO,
                   "GH_TOKEN": "read", "APP_TOKEN": "app"}
            with patch.dict(os.environ, env), \
                 patch.object(reporter, "GitHub", return_value=api), \
                 patch.object(reporter, "notify", side_effect=RuntimeError("comment failure")):
                reporter.main()
        self.assertEqual(api.published, [(HEAD, "nix-opendeck/package-verification", "success")])

    def test_removed_targets_comment(self):
        event, _, api = self.setup_case("Package verification")
        event["workflow_run"]["conclusion"] = "failure"
        api.jobs[0]["conclusion"] = "failure"
        api.jobs.append({"id": 177, "name": "Discover changed packages",
                         "conclusion": "failure"})
        api.annotations = [{"title": "Published package targets removed",
                            "annotation_level": "failure"}]
        result = reporter.assess(event, api)
        self.assertEqual(result["state"], "failure")
        self.assertEqual(result["discovery_check_id"], 177)
        with patch.dict(os.environ, {"APP_BOT_LOGIN": "test[bot]"}):
            reporter.notify(api, result)
        body = api.writes[-1][1]["payload"]["body"]
        self.assertIn("Published package targets were removed", body)
        self.assertIn("only if authorised", body)
        self.assertIn("bypass of required checks", body)

    def test_other_discovery_failure_does_not_claim_removal(self):
        event, _, api = self.setup_case("Package verification")
        event["workflow_run"]["conclusion"] = "failure"
        api.jobs[0]["conclusion"] = "failure"
        api.jobs.append({"id": 177, "name": "Discover changed packages",
                         "conclusion": "failure"})
        api.annotations = [{"title": "Nix evaluation failed",
                            "annotation_level": "failure"}]
        result = reporter.assess(event, api)
        with patch.dict(os.environ, {"APP_BOT_LOGIN": "test[bot]"}):
            reporter.notify(api, result)
        body = api.writes[-1][1]["payload"]["body"]
        self.assertIn("Package verification failed", body)
        self.assertNotIn("Published package targets were removed", body)
        self.assertNotIn("bypass", body)

    def test_status_publication_error_is_not_suppressed(self):
        event, _, api = self.setup_case()
        api.fail_status = True
        with TemporaryDirectory() as directory:
            event_file = Path(directory) / "event.json"
            event_file.write_text(json.dumps(event), encoding="utf-8")
            env = {"GITHUB_EVENT_PATH": str(event_file), "GITHUB_REPOSITORY": REPO,
                   "GH_TOKEN": "read", "APP_TOKEN": "app"}
            with patch.dict(os.environ, env), patch.object(reporter, "GitHub", return_value=api):
                with self.assertRaises(URLError):
                    reporter.main()


if __name__ == "__main__":
    unittest.main()
