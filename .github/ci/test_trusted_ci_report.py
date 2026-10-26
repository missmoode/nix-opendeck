"""Security regression tests for the trusted workflow_run reporter."""
import importlib.util
import os
from pathlib import Path
import unittest
from unittest.mock import patch

script = Path(__file__).with_name('trusted_ci_report.py')
spec = importlib.util.spec_from_file_location('trusted_ci_report', script)
reporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reporter)

HEAD = 'a' * 40
MERGE = 'b' * 40
BASE = 'c' * 40


def fixture(kind='Checks'):
    filename, job, _ = reporter.WORKFLOWS[kind]
    run = {
        'id': 10, 'name': f'{kind} PR #37 merge {MERGE}', 'event': 'pull_request',
        'path': filename, 'status': 'completed', 'conclusion': 'success',
        'head_sha': HEAD, 'repository': {'full_name': 'missmoode/nix-opendeck'},
        'display_title': f'{kind} PR #37 merge {MERGE}',
        'pull_requests': [{'number': 37}], 'html_url': 'https://github.com/123',
    }
    pr = {
        'state': 'open', 'base': {'ref': 'main', 'sha': BASE, 'repo': {'full_name': 'missmoode/nix-opendeck'}},
        'head': {'sha': HEAD, 'ref': 'cleanup-pass', 'repo': {'full_name': 'missmoode/nix-opendeck'}},
        'merge_commit_sha': MERGE, 'labels': [{'name': 'ready for merge'}],
        'user': {'login': 'a-contributor'},
    }
    return {'workflow_run': run}, pr, job


class FakeAPI:
    repo = 'missmoode/nix-opendeck'
    def __init__(self, pr, job):
        self.pr = pr
        self.job = job
        self.different = set()
        self.newer = False
        self.calls = []

    def request(self, path, **kwargs):
        self.calls.append((path, kwargs))
        if path.startswith('/pulls/'):
            return self.pr
        if '/runs?' in path:
            return {'workflow_runs': [
                {'id': 11, 'display_title': f'Checks PR #37 merge {MERGE}'}
            ] if self.newer else []}
        raise AssertionError('Unexpected request: ' + path)

    def content_sha(self, path, ref):
        return 'evil' if ref == MERGE and path in self.different else 'trusted'

    def jobs(self, run_id):
        return [{'name': self.job, 'conclusion': 'success'}]


class SecurityTests(unittest.TestCase):
    def test_clean_pr_tests_pass(self):
        event, pr, job = fixture()
        result = reporter.assess(event, FakeAPI(pr, job))
        self.assertEqual((result['state'], result['context']), ('success', 'nix-opendeck/tests'))

    def test_changed_workflow_fails_closed(self):
        event, pr, job = fixture()
        api = FakeAPI(pr, job)
        api.different.add('.github/workflows/checks.yml')
        self.assertEqual(reporter.assess(event, api)['state'], 'failure')

    def test_changed_reporter_script_fails_closed(self):
        event, pr, job = fixture()
        api = FakeAPI(pr, job)
        api.different.add('.github/ci/trusted_ci_report.py')
        self.assertEqual(reporter.assess(event, api)['state'], 'failure')

    def test_changed_reporter_workflow_fails_closed(self):
        event, pr, job = fixture()
        api = FakeAPI(pr, job)
        api.different.add('.github/workflows/trusted-ci-report.yml')
        self.assertEqual(reporter.assess(event, api)['state'], 'failure')

    def test_changed_target_catalogue_fails_closed(self):
        event, pr, job = fixture('Reproducibility')
        api = FakeAPI(pr, job)
        api.different.add('.github/ci/targets.nix')
        self.assertEqual(reporter.assess(event, api)['state'], 'failure')

    def test_stale_head_has_no_status(self):
        event, pr, job = fixture()
        pr['head']['sha'] = 'd' * 40
        self.assertIsNone(reporter.assess(event, FakeAPI(pr, job)))

    def test_stale_merge_has_no_status(self):
        event, pr, job = fixture()
        pr['merge_commit_sha'] = 'd' * 40
        self.assertIsNone(reporter.assess(event, FakeAPI(pr, job)))

    def test_later_run_suppresses_older_result(self):
        event, pr, job = fixture()
        api = FakeAPI(pr, job)
        api.newer = True
        self.assertIsNone(reporter.assess(event, api))

    def test_cancelled_run_has_no_status(self):
        event, pr, job = fixture()
        event['workflow_run']['conclusion'] = 'cancelled'
        self.assertIsNone(reporter.assess(event, FakeAPI(pr, job)))

    def test_label_missing_is_failure_not_success(self):
        event, pr, job = fixture('Reproducibility')
        pr['labels'] = []
        self.assertEqual(reporter.assess(event, FakeAPI(pr, job))['state'], 'failure')

    def test_missing_gate_is_failure(self):
        event, pr, job = fixture('Reproducibility')
        api = FakeAPI(pr, 'Wrong job')
        self.assertEqual(reporter.assess(event, api)['state'], 'failure')

    def test_unrelated_workflow_is_ignored(self):
        event, pr, job = fixture()
        event['workflow_run']['path'] = '.github/workflows/unrelated.yml'
        self.assertIsNone(reporter.assess(event, FakeAPI(pr, job)))

    def test_altered_title_cannot_claim_success(self):
        event, pr, job = fixture()
        event['workflow_run']['display_title'] = 'Pretend this succeeded'
        self.assertIsNone(reporter.assess(event, FakeAPI(pr, job)))

    def test_url_encoded_path_accepted(self):
        event, pr, job = fixture()
        event['workflow_run']['path'] += '@refs/pull/37/merge'
        self.assertEqual(reporter.assess(event, FakeAPI(pr, job))['state'], 'success')


if __name__ == '__main__':
    unittest.main()
