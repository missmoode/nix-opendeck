#!/usr/bin/env python3
"""Nix-specific OpenDeck integration checks: does it start, did we break it?"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys

from harness import OpenDeckHarness, PLUGIN_ID


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "package", type=Path, help="already-built Nix opendeck package output"
    )
    parser.add_argument(
        "--artifacts", type=Path, help="copy application logs here before cleanup"
    )
    args = parser.parse_args()
    passed = []
    failures = []
    skipped = []

    def fail(name, error):
        print(f"FAIL: {name}: {error}", file=sys.stderr, flush=True)
        reason = " ".join(str(error).splitlines())
        failures.append((name, reason))
        if os.environ.get("GITHUB_ACTIONS") == "true":
            print(
                f"::error title=OpenDeck runtime test::{name}: {reason.replace('%', '%25')}",
                flush=True,
            )

    def check(name, condition):
        try:
            if not condition():
                raise AssertionError("expected condition was false")
        except Exception as error:
            fail(name, error)
            return False
        print(f"PASS: {name}", flush=True)
        passed.append(name)
        return True

    def skip(name, reason):
        print(f"SKIP: {name}: {reason}", flush=True)
        skipped.append(name)

    try:
        with OpenDeckHarness(args.package, args.artifacts) as app:
            app.prepare()
            plugin = app.plugin_dir / PLUGIN_ID
            bundled = check(
                "Bundled StarterPack manifest exists",
                lambda: (plugin / "manifest.json").is_file(),
            )

            # Act: launch the complete packaged application once.
            app.start()
            ready = check("Packaged OpenDeck starts", app.wait_ready)
            bus_ready = True
            if sys.platform == "linux":
                if app.is_running():
                    bus_ready = check(
                        "Private D-Bus single-instance name acquired", app.wait_bus_name
                    )
                else:
                    skip(
                        "Private D-Bus single-instance name acquired",
                        "test application exited",
                    )
                    bus_ready = False

            # Patch 0004 + wrapOpenDeck: register the packaged plugin without
            # installing a writable copy. This does not require HTTP readiness.
            if bundled and app.is_running():
                registered = check(
                    "Bundled StarterPack registers",
                    lambda: app.wait_registered(PLUGIN_ID),
                )
                check(
                    "No bundled plugin copied into user config",
                    lambda: not (app.config / "plugins" / PLUGIN_ID).exists(),
                )
            else:
                reason = (
                    "bundle manifest missing"
                    if not bundled
                    else "test application exited"
                )
                skip("Bundled StarterPack registers", reason)
                skip("No bundled plugin copied into user config", reason)
                registered = False

            # Patch 0003: authorization checks are independent of plugin
            # registration but require the HTTP server to be available.
            allowed = app.config / "local.svg"
            symlinked = app.config / "plugins/runtime.assets.sdPlugin/icons/test.svg"
            forbidden = app.root / "forbidden.svg"
            unrelated = Path(os.environ["OPENDECK_TEST_UNRELATED_ASSET"])
            traversal = app.config / "plugins/../local.svg"

            def expect_asset(path, expected_status):
                status, body = app.request(path)
                if status != expected_status:
                    raise AssertionError(
                        f"GET {path} (resolves to {path.resolve()}): "
                        f"HTTP {status}, expected {expected_status}"
                    )
                if expected_status == 200:
                    expected = path.read_bytes()
                    if body != expected:
                        raise AssertionError(
                            f"GET {path}: response body differs "
                            f"({len(body)} bytes received, {len(expected)} expected)"
                        )
                return True

            asset_checks = [
                ("User-config asset allowed", lambda: expect_asset(allowed, 200)),
                (
                    "Symlinked plugin asset allowed",
                    lambda: expect_asset(symlinked, 200),
                ),
                (
                    "Outside-config asset forbidden",
                    lambda: expect_asset(forbidden, 403),
                ),
                (
                    "Unrelated Nix-store asset forbidden",
                    lambda: expect_asset(unrelated, 403),
                ),
                (
                    "Parent-component traversal forbidden",
                    lambda: expect_asset(traversal, 403),
                ),
            ]
            if bundled:
                package_asset = next(
                    (
                        p
                        for suffix in ("*.svg", "*.png", "*.html")
                        for p in plugin.rglob(suffix)
                        if p.is_file()
                    ),
                    plugin / "manifest.json",
                )
                asset_checks.insert(
                    2,
                    (
                        "Bundled plugin asset allowed",
                        lambda: expect_asset(package_asset, 200),
                    ),
                )
            else:
                skip("Bundled plugin asset allowed", "bundle manifest missing")

            if ready and app.is_running():
                for name, assertion in asset_checks:
                    check(name, assertion)
            else:
                for name, _ in asset_checks:
                    skip(name, "asset server unavailable")

            # A process that exited after reaching readiness must not turn
            # subsequent dependency skips into an overall successful run.
            check("OpenDeck remains running", app.is_running)

            # Patch 0009: only reload a plugin that actually registered.
            reload_checks = (
                "Running-instance reload command exits",
                "Plugin re-registers after reload",
                "Reload did not terminate OpenDeck",
            )
            if registered and bus_ready and app.is_running():
                registrations = app.log_count(f"Registered plugin {PLUGIN_ID}")
                try:
                    reload = app.command("--reload-plugin", PLUGIN_ID)
                except Exception as error:
                    fail(reload_checks[0], error)
                    command_ok = False
                else:
                    command_ok = check(reload_checks[0], lambda: reload.returncode == 0)
                if command_ok:
                    check(
                        reload_checks[1],
                        lambda: app.wait_registered(PLUGIN_ID, registrations + 1),
                    )
                else:
                    skip(reload_checks[1], "reload command failed")
                check(reload_checks[2], app.is_running)
            else:
                for name in reload_checks:
                    skip(
                        name,
                        "plugin not registered, single-instance unavailable, or app exited",
                    )

            # Stop while preserving the private session bus and test settings.
            app.stop()
            stopped = check("Test instance stopped", app.assert_no_instance)
            if stopped:
                try:
                    inactive = app.command("--restart-if-running")
                except Exception as error:
                    fail("Inactive restart command exits", error)
                else:
                    check(
                        "Inactive restart command exits",
                        lambda: inactive.returncode == 0,
                    )
                check(
                    "Inactive restart does not start OpenDeck", app.assert_no_instance
                )
            else:
                skip("Inactive restart command exits", "test instance did not stop")
                skip(
                    "Inactive restart does not start OpenDeck",
                    "test instance did not stop",
                )

    except Exception as error:
        fail("test harness", error)

    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        lines = [
            "### OpenDeck runtime tests",
            "",
            f"**{'FAILED' if failures else 'PASSED'}** — "
            f"{len(passed)} passed, {len(failures)} failed, {len(skipped)} skipped.",
        ]
        if failures:
            lines += [
                "",
                "**Failed checks:**",
                *(f"- **{name}**: {reason}" for name, reason in failures),
            ]
        if skipped:
            lines += ["", "**Skipped checks:**", *(f"- {name}" for name in skipped)]
        try:
            with open(summary_path, "a", encoding="utf-8") as summary:
                summary.write("\n".join(lines) + "\n")
        except OSError as error:
            print(f"Could not write runtime test summary: {error}", file=sys.stderr)

    print(
        f"Runtime checks: {'FAILED' if failures else 'PASSED'} "
        f"({len(failures)} failure(s), {len(skipped)} skipped)",
        flush=True,
    )
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
