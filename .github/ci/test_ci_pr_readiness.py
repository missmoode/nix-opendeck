"""Keep the two unprivileged PR workflows and updater triggers consistent.

Text-based on purpose: the repository's CI suite has no YAML parser dependency.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
EVENTS = (
    'opened', 'reopened', 'synchronize',
    'ready_for_review', 'converted_to_draft', 'edited',
)


class PrReadinessWorkflowTests(unittest.TestCase):
    def test_both_pr_workflows_rely_on_readiness_not_labels(self):
        for filename in ('checks.yml', 'pr-package-verification.yml'):
            with self.subTest(workflow=filename):
                source = (ROOT / '.github/workflows' / filename).read_text()
                self.assertIn('types: [' + ', '.join(EVENTS) + ']', source)
                self.assertNotIn('labeled', source)
                self.assertNotIn('unlabeled', source)
                self.assertIn('github.event.pull_request.draft == false', source)
                self.assertNotIn("contains(github.event.pull_request.labels", source)

    def test_package_updaters_do_not_apply_verification_label(self):
        for filename in ('update-packages.yml', 'update-nixpkgs.yml'):
            with self.subTest(workflow=filename):
                source = (ROOT / '.github/workflows' / filename).read_text()
                self.assertNotIn('            run checks\n', source)

    def test_trusted_reporter_checks_current_state(self):
        source = (ROOT / '.github/ci/trusted_ci_report.py').read_text()
        self.assertIn('pr.get("draft") is False', source)
        self.assertNotIn('any(label["name"] == "run checks"', source)
        self.assertIn('pr.get("merge_commit_sha") != merge_sha', source)
        self.assertIn('pr["head"]["sha"] != head_sha', source)


if __name__ == '__main__':
    unittest.main()
