"""Regression tests for failure evidence and unprivileged native-job annotations."""

import unittest

import verification_diagnostics as diag


class DiagnosticsTests(unittest.TestCase):
    def test_selects_cause_over_generic_build_wrapper(self):
        log = [
            "opendeck> error: failed to run custom build command for `libgit2-sys`\n",
            "opendeck>   The system library `libgit2` required by crate `libgit2-sys` was not found.\n",
            "error: Cannot build '/nix/store/something.drv'.\n",
        ]
        self.assertIn("system library `libgit2`", diag.extract_error(log))

    def test_aws_lc_and_compiler_errors(self):
        self.assertIn(
            "AWS_LC_SYS_USE_SYSTEM=1",
            diag.extract_error(
                [
                    "AWS_LC_SYS_USE_SYSTEM=1 requires a system-installed AWS-LC, but none was found."
                ]
            ),
        )
        self.assertEqual(
            diag.extract_error(["error[E0308]: mismatched types"]),
            "error[E0308]: mismatched types",
        )
        self.assertEqual(diag.extract_error(["downloaded 300 crates"]), "")

    def test_untrusted_annotation_escaping(self):
        result = diag.annotation(
            "package,::bad\n::warning::oops",
            "reference build",
            "line1\n::warning::fake%",
        )
        self.assertEqual(result.count("\n"), 0)
        self.assertIn("%0A", result)
        self.assertIn("%2C", result)
        self.assertIn("%25", result)
        self.assertEqual(result.count("::error"), 1)
        with self.assertRaises(ValueError):
            diag.annotation("x", "invalid", "y")

    def test_groups_same_error_across_architectures(self):
        jobs = []
        for i, system in enumerate(("x86_64-linux", "aarch64-linux"), 1):
            jobs.append(
                {
                    "name": f"Rebuild: {system} / opendeck-core + opendeck",
                    "conclusion": "failure",
                    "id": i,
                    "check_run_url": f"https://api.github.com/repos/missmoode/nix-opendeck/check-runs/{i}",
                }
            )

        # A matrix name for Core + wrapper legitimately differs from the target name.
        # The reporter accepts a target-specific annotated title from that job.
        def fetch(_):
            return [
                {
                    "annotation_level": "failure",
                    "title": "Native verification: opendeck-core [reference build]",
                    "message": "The system library `libgit2` was not found.",
                }
            ]

        result = diag.render_job_failures(jobs, "missmoode/nix-opendeck", 30, fetch)
        self.assertEqual(result.count("**opendeck-core**"), 1)
        self.assertIn("x86\\_64-linux", result)
        self.assertIn("aarch64-linux", result)
        self.assertIn("blocked by the core failure", result)

    def test_distinct_errors_not_grouped(self):
        jobs = [
            {
                "name": f"Rebuild: {s} / abc/weather",
                "conclusion": "failure",
                "id": i,
                "check_run_url": f"https://api.github.com/repos/missmoode/nix-opendeck/check-runs/{i}",
            }
            for i, s in enumerate(("x86_64-linux", "aarch64-darwin"), 1)
        ]

        def fetch(n):
            return [
                {
                    "annotation_level": "failure",
                    "title": "Native verification: abc/weather [reference build]",
                    "message": "Missing A" if n == 1 else "Missing B",
                }
            ]

        result = diag.render_job_failures(jobs, "missmoode/nix-opendeck", 30, fetch)
        self.assertEqual(result.count("**abc/weather**"), 2)

    def test_missing_annotations_do_not_hide_failures(self):
        jobs = [
            {"name": "Discover changed packages", "conclusion": "failure", "id": 10}
        ]
        result = diag.render_job_failures(
            jobs, "missmoode/nix-opendeck", 30, lambda _: self.fail("should not fetch")
        )
        self.assertIn("Discover changed packages", result)
        self.assertIn("job/10", result)

    def test_do_not_follow_external_check_run_urls(self):
        job = {
            "name": "Rebuild: aarch64-linux / abc/weather",
            "conclusion": "failure",
            "id": 10,
            "check_run_url": "https://evil.test/check-runs/9",
        }
        result = diag.render_job_failures(
            [job], "missmoode/nix-opendeck", 30, lambda _: self.fail("SSRF")
        )
        self.assertIn("abc/weather", result)
        self.assertNotIn("evil.test", result)

    def test_updater_groups_matching_errors_but_not_distinct_platform_errors(self):
        evidence = lambda system, error: {
            "label": "jfms7s/weather",
            "phase": "nix-build",
            "system": system,
            "error": "nix build exited with 1",
            "excerpt": error,
        }
        items = [
            evidence("x86_64-linux", "The system library `libgit2` was not found"),
            evidence("aarch64-linux", "The system library `libgit2` was not found"),
            evidence(
                "aarch64-darwin",
                "AWS_LC_SYS_USE_SYSTEM=1 requires a system-installed AWS-LC, but none was found",
            ),
        ]
        out = "\n".join(diag.render_update_diagnostics(items))
        self.assertEqual(out.count("**jfms7s/weather**"), 2)
        self.assertIn("x86\\_64-linux", out)
        self.assertIn("aarch64-darwin", out)
        self.assertIn("One representative excerpt", out)

    def test_updater_unknown_errors_stay_separate(self):
        items = [
            {
                "label": "x",
                "phase": "updater",
                "system": system,
                "error": "updater exited",
                "excerpt": "No interesting error",
            }
            for system in ("aarch64-linux", "x86_64-linux")
        ]
        out = "\n".join(diag.render_update_diagnostics(items))
        self.assertEqual(out.count("**x**"), 2)

    def test_mentions_and_markdown_escaped(self):
        self.assertIn("@\u200beveryone", diag.safe_text("@everyone"))
        self.assertIn("\\`", diag.safe_text("`bad`"))
        self.assertNotIn("\n", diag.safe_text("one\ntwo"))


if __name__ == "__main__":
    unittest.main()
