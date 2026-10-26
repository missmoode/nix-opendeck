#!/usr/bin/env python3
"""Internal GitHub Actions orchestration for independently validated package updates.

Only standard-library Python is needed. The flake catalogue supplies all platform
information; this module does not maintain a second list of supported plugins.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

SYSTEM_PREFERENCE = ("x86_64-linux", "aarch64-linux", "aarch64-darwin")


def load(path):
    return json.loads(Path(path).read_text())


def save(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def run(*argv, check=True, **kwargs):
    print("+", " ".join(str(part) for part in argv), flush=True)
    return subprocess.run(list(map(str, argv)), check=check, **kwargs)


def identifier(label):
    if label == "opendeck-core":
        return "core"
    readable = re.sub(r"[^a-z0-9-]", "-", label.lower()).strip("-")[:45]
    digest = hashlib.sha256(label.encode()).hexdigest()[:10]
    return f"plugin-{readable}-{digest}"


def discover(args):
    targets = load(args.targets)
    by_label = {}
    for target in targets:
        if target["kind"] not in ("plugin", "core") or not target["updatable"]:
            continue
        by_label.setdefault(target["label"], []).append(target)

    packages = []
    for label in sorted(by_label):
        variants = sorted(
            by_label[label],
            key=lambda target: SYSTEM_PREFERENCE.index(target["system"]),
        )
        chosen = variants[0]
        packages.append({
            "id": identifier(label),
            "label": label,
            "system": chosen["system"],
            "attr": chosen["attr"],
        })

    matrix = []
    for system in SYSTEM_PREFERENCE:
        selected = [p for p in packages if p["system"] == system]
        if selected:
            target = next(t for t in targets if t["system"] == system)
            matrix.append({"system": system, "runner": target["runner"]})
    plan = {"packages": packages, "updaters": matrix}
    save(Path(args.output) / "plan.json", plan)
    save(Path(args.output) / "targets.json", targets)
    print(f"Discovered {len(packages)} updatable packages on {len(matrix)} native runners")


def clean_tree(base="HEAD"):
    run("git", "reset", "--hard", base)
    run("git", "clean", "-fd")


def update(args):
    plan = load(args.plan)
    packages = [p for p in plan["packages"] if p["system"] == args.system]
    output = Path(args.output)
    (output / "patches").mkdir(parents=True, exist_ok=True)
    results = []
    base = run("git", "rev-parse", "HEAD", capture_output=True, text=True).stdout.strip()
    for pkg in packages:
        label = pkg["label"]
        print(f"\n::group::Update {label}", flush=True)
        record = {"id": pkg["id"], "label": label, "system": args.system}
        try:
            # Every update starts from the same base; no updater sees another
            # plugin's proposed source changes.
            clean_tree(base)
            proc = run("nix-update", pkg["attr"], "--flake", "--use-update-script", check=False)
            if proc.returncode:
                raise RuntimeError(f"nix-update exited with {proc.returncode}")
            current = run("git", "rev-parse", "HEAD", capture_output=True, text=True).stdout.strip()
            if current != base:
                raise RuntimeError("updater created a commit instead of leaving a working-tree change")
            run("git", "add", "-A")
            changed = run("git", "diff", "--cached", "--quiet", check=False)
            if changed.returncode == 0:
                record["status"] = "unchanged"
            elif changed.returncode != 1:
                raise RuntimeError("git diff could not inspect the updated files")
            else:
                changed_files = run("git", "diff", "--cached", "--name-only", capture_output=True, text=True).stdout.splitlines()
                # Automated package updates may change derivations and their
                # checked-in dependency locks, but must not edit CI, the flake
                # inputs, or other repository infrastructure.
                unexpected = [path for path in changed_files if not path.startswith("src/")]
                if unexpected:
                    raise RuntimeError(
                        "updater modified files outside src/: " + ", ".join(unexpected)
                    )
                patch = run("git", "diff", "--cached", "--binary", capture_output=True).stdout
                if not patch:
                    raise RuntimeError("changed files produced an empty Git patch")
                patch_path = output / "patches" / f"{pkg['id']}.patch"
                patch_path.write_bytes(patch)
                record["status"] = "changed"
                record["sha256"] = hashlib.sha256(patch).hexdigest()
        except Exception as exc:
            record["status"] = "failed"
            record["error"] = str(exc)
            print(f"::warning::Update failed for {label}: {exc}", flush=True)
        finally:
            results.append(record)
            clean_tree(base)
            print("::endgroup::", flush=True)
            # Save incrementally, including on a later fatal runner error.
            save(output / "results.json", results)
    print(f"Updater results for {args.system}: {len(results)} packages")


def collect_updates(plan, root):
    root = Path(root)
    records = {}
    errors = []
    for updater in plan["updaters"]:
        system = updater["system"]
        result_path = root / f"updates-{system}" / "results.json"
        if not result_path.exists():
            errors.append(f"Missing updater report for {system}")
            continue
        try:
            items = load(result_path)
            system_records = {}
            for record in items:
                identity = record.get("id")
                expected = next((p for p in plan["packages"] if p["id"] == identity), None)
                if (not expected or expected["system"] != system or
                        record.get("label") != expected["label"] or identity in records or identity in system_records):
                    raise ValueError(f"unexpected/duplicate result: {record}")
                if record.get("status") not in ("unchanged", "changed", "failed"):
                    raise ValueError(f"invalid update result: {record}")
                if record["status"] == "changed":
                    patch_path = root / f"updates-{system}" / "patches" / f"{identity}.patch"
                    if not patch_path.is_file():
                        raise ValueError(f"missing patch for {identity}")
                    if hashlib.sha256(patch_path.read_bytes()).hexdigest() != record.get("sha256"):
                        raise ValueError(f"patch checksum mismatch for {identity}")
                system_records[identity] = record
            records.update(system_records)
        except (ValueError, OSError, json.JSONDecodeError) as exc:
            errors.append(f"Invalid updater report for {system}: {exc}")
    for pkg in plan["packages"]:
        if pkg["id"] not in records:
            errors.append(f"Missing update result for {pkg['label']}")
    return records, errors


def prepare(args):
    plan = load(args.plan)
    targets = load(args.targets)
    records, errors = collect_updates(plan, args.updates)
    changed = [p | {"sha256": records[p["id"]]["sha256"]}
               for p in plan["packages"]
               if records.get(p["id"], {}).get("status") == "changed"]
    per_label = {}
    for target in targets:
        per_label.setdefault((target["kind"], target["label"]), []).append(target)

    plugin_builds = []
    for pkg in changed:
        if pkg["label"] == "opendeck-core":
            continue
        supported = per_label.get(("plugin", pkg["label"]), [])
        if not supported:
            errors.append(f"No supported build targets for {pkg['label']}")
        for target in supported:
            plugin_builds.append({
                "id": pkg["id"], "label": pkg["label"],
                "system": target["system"], "runner": target["runner"],
                "attr": target["attr"], "patches": [pkg],
            })

    # The default OpenDeck package bundles Starter Pack. When both it and Core
    # change, test their combination instead of two misleading isolated builds.
    app_patches = [p for p in changed if p["label"] in ("opendeck-core", "nekename/starterpack")]
    app_builds = []
    if app_patches:
        for target in per_label.get(("opendeck", "opendeck"), []):
            app_builds.append({
                "id": "opendeck", "label": "opendeck",
                "system": target["system"], "runner": target["runner"],
                "attr": target["attr"], "patches": app_patches,
            })
        if not app_builds:
            errors.append("Default OpenDeck has no build targets")

    output = Path(args.output)
    save(output / "prepared.json", {
        "updateResults": list(records.values()), "errors": errors,
        "plugins": plugin_builds, "opendeck": app_builds,
    })
    save(output / "plugins.json", plugin_builds)
    save(output / "opendeck.json", app_builds)
    print(f"Selected {len(plugin_builds)} plugin builds and {len(app_builds)} OpenDeck builds")
    for message in errors:
        print(f"::warning::{message}", flush=True)


def apply_patch(pkg, root):
    patch_path = Path(root) / f"updates-{pkg['system']}" / "patches" / f"{pkg['id']}.patch"
    patch = patch_path.read_bytes()
    report_sha = pkg.get("sha256")
    if report_sha and hashlib.sha256(patch).hexdigest() != report_sha:
        raise RuntimeError(f"patch checksum mismatch for {pkg['label']}")
    run("git", "apply", "--check", "--index", str(patch_path))
    run("git", "apply", "--index", str(patch_path))


def update_platform_deps(target, output):
    """Run an optional package-owned native dependency updater."""
    attr = target["attr"]
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", attr):
        raise ValueError("unsafe flake attribute")
    # Use Nix attribute selection, not an environment-specific package list.
    pkg = f"(builtins.getFlake (toString ./.)).{attr}"
    has_hook = run("nix", "eval", "--impure", "--json", "--expr",
                   f"let pkg = {pkg}; in pkg ? updatePlatformDeps",
                   capture_output=True, text=True).stdout.strip()
    if has_hook == "false":
        return []
    if has_hook != "true":
        raise ValueError(f"invalid platform updater probe: {has_hook}")
    script = run("nix", "build", "--impure", "--no-link", "--print-out-paths",
                 "--expr", f"{pkg}.updatePlatformDeps",
                 capture_output=True, text=True).stdout.strip()
    if not script.startswith("/nix/store/") or "\n" in script:
        raise ValueError("platform updater did not produce a single store path")
    edits_file = output.with_suffix(".edits.json")
    run(script, attr, str(edits_file))
    edits = load(edits_file)
    if not isinstance(edits, list):
        raise ValueError("platform updater must return a JSON list of source edits")
    return edits


def build(args):
    target = json.loads(os.environ["TARGET"])
    output = Path(args.output)
    result = {k: target[k] for k in ("id", "label", "system", "attr")}
    try:
        for pkg in target["patches"]:
            apply_patch(pkg, args.updates)
        result["sourceEdits"] = update_platform_deps(target, output)
        proc = run("nix", "build", "--no-link", "-L", ".#" + target["attr"], check=False)
        result["status"] = "success" if proc.returncode == 0 else "failed"
        if proc.returncode:
            result["error"] = f"nix build exited with {proc.returncode}"
    except Exception as exc:
        result["status"] = "failed"
        result["error"] = str(exc)
    save(output, result)
    if result["status"] == "failed":
        print(f"::error::{target['label']} ({target['system']}): {result['error']}")
        return 1
    return 0


def check_builds(prepared, build_root):
    """Separate failed builds from missing or untrustworthy build reports."""
    failures = []
    infrastructure_errors = []
    successful = set()
    for target in prepared["plugins"] + prepared["opendeck"]:
        key = (target["id"], target["system"])
        path = Path(build_root) / f"build-{target['id']}-{target['system']}" / "result.json"
        try:
            got = load(path)
            if not isinstance(got, dict) or any(
                got.get(k) != target[k] for k in ("id", "label", "system", "attr")
            ):
                raise ValueError("build report identity mismatch")
            if got.get("status") == "success":
                successful.add(key)
            elif got.get("status") == "failed":
                failures.append(f"{target['label']} ({target['system']}): {got.get('error', 'build failed')}")
            else:
                raise ValueError("invalid build report status")
        except (ValueError, OSError, json.JSONDecodeError, TypeError) as exc:
            infrastructure_errors.append(f"Missing or invalid build report for {target['label']} ({target['system']}): {exc}")
    return successful, failures, infrastructure_errors


def apply_source_edits(accepted, prepared, build_root):
    """Combine independent, successful native updates without merging patches."""
    accepted_ids = {pkg["id"] for pkg in accepted}
    app_accepted = any(pkg["label"] in ("opendeck-core", "nekename/starterpack")
                       for pkg in accepted)
    edits = {}
    for target in prepared["plugins"] + prepared["opendeck"]:
        if target["id"] not in accepted_ids and not (target["id"] == "opendeck" and app_accepted):
            continue
        path = Path(build_root) / f"build-{target['id']}-{target['system']}" / "result.json"
        report = load(path)
        if report.get("status") != "success":
            raise ValueError(f"unvalidated platform edits for {target['label']}")
        for edit in report.get("sourceEdits", []):
            if set(edit) != {"path", "before", "after"}:
                raise ValueError("invalid source edit")
            relative = Path(edit["path"])
            if (relative.is_absolute() or ".." in relative.parts or
                    not relative.parts or relative.parts[0] != "src" or
                    relative.suffix != ".nix" or
                    not all(isinstance(edit[k], str) for k in edit) or
                    not edit["before"] or "\n" in edit["before"] or
                    "\n" in edit["after"]):
                raise ValueError("unsafe source edit")
            key = (edit["path"], edit["before"])
            if key in edits and edits[key] != edit["after"]:
                raise ValueError(f"conflicting source edits in {edit['path']}")
            edits[key] = edit["after"]
    touched = set()
    for (path, before), after in sorted(edits.items()):
        source = Path(path)
        content = source.read_text()
        if content.count(before) != 1:
            raise ValueError(f"cannot uniquely apply validated source edit in {path}")
        source.write_text(content.replace(before, after, 1))
        touched.add(path)
    if touched:
        run("git", "add", "--", *sorted(touched))


def finalize(args):
    plan = load(args.plan)
    prepared = load(args.prepared)
    updates = {r["id"]: r for r in prepared["updateResults"]}
    successes, build_failures, report_errors = check_builds(prepared, args.builds)
    infrastructure_errors = list(prepared["errors"]) + report_errors
    accepted = []
    rejected = []

    app_targets = prepared["opendeck"]
    app_ok = bool(app_targets) and all((b["id"], b["system"]) in successes for b in app_targets)
    plugin_targets = prepared["plugins"]
    # When Core and Starter Pack are both proposed, the default-app build
    # tested them together. Do not accept only half of that combination.
    app_changed = [p for p in plan["packages"]
                   if p["label"] in ("opendeck-core", "nekename/starterpack")
                   and updates.get(p["id"], {}).get("status") == "changed"]
    starter_builds = [b for b in plugin_targets if b["label"] == "nekename/starterpack"]
    starter_ok = bool(starter_builds) and all((b["id"], b["system"]) in successes for b in starter_builds)
    app_group_ok = app_ok and (len(app_changed) < 2 or starter_ok)
    for pkg in plan["packages"]:
        status = updates.get(pkg["id"], {}).get("status", "failed")
        if status == "unchanged":
            continue
        if status == "failed":
            rejected.append(
                f"{pkg['label']}: updater failed ({updates.get(pkg['id'], {}).get('error', 'missing result')})"
            )
            continue
        builds = [b for b in plugin_targets if b["id"] == pkg["id"]]
        plugin_ok = bool(builds) and all((b["id"], b["system"]) in successes for b in builds)
        if pkg["label"] == "opendeck-core":
            pkg_ok = app_group_ok
        else:
            pkg_ok = plugin_ok and (pkg["label"] != "nekename/starterpack" or app_group_ok)
        if pkg_ok:
            accepted.append(pkg)
        else:
            rejected.append(f"{pkg['label']}: one or more native builds failed")

    # A known updater/build failure is not a reason to reject other packages.
    # An incomplete report or obsolete base IS: we cannot validate the set.
    package_failures = build_failures + rejected
    base_ok = args.base_unchanged == "true"
    if not base_ok:
        infrastructure_errors.append("base branch changed while this update was running; rerun against its latest revision")

    final_check = "skipped"
    if accepted and not infrastructure_errors:
        try:
            for pkg in accepted:
                record = updates[pkg["id"]]
                apply_patch(pkg | record, args.updates)
            apply_source_edits(accepted, prepared, args.builds)
            run("nix", "flake", "check", "--no-build", "--all-systems")
            final_check = "passed"
        except Exception as exc:
            final_check = "failed"
            infrastructure_errors.append(f"combined flake evaluation or patch application failed: {exc}")
            # Never publish partially applied or unvalidated changes.
            clean_tree()

    if infrastructure_errors:
        accepted = []

    ready = bool(accepted) and final_check == "passed" and not infrastructure_errors
    failures = infrastructure_errors + package_failures
    report = [
        "## Automated OpenDeck package updates", "",
        f"- Accepted updates: **{len(accepted)}**",
        f"- Unchanged packages: **{sum(r.get('status') == 'unchanged' for r in updates.values())}**",
        f"- Failed updates or validation checks: **{len(failures)}**",
        f"- Combined flake evaluation: **{final_check}**", "",
        f"[Workflow run]({os.environ.get('GITHUB_SERVER_URL','https://github.com')}/"
        f"{os.environ.get('GITHUB_REPOSITORY','')}/actions/runs/{os.environ.get('GITHUB_RUN_ID','')})", "",
        "### Accepted", "",
    ]
    report += [f"- `{p['label']}`" for p in accepted] or ["- None"]
    report += ["", "### Failed or rejected", ""]
    report += [f"- {e}" for e in failures] or ["- None"]
    report += ["", "### Unchanged", ""]
    report += [f"- `{r['label']}`" for r in updates.values() if r.get("status") == "unchanged"] or ["- None"]
    report.append("")
    Path(args.report).write_text("\n".join(report))

    # The PR should describe the updates it actually proposes. Failed updates
    # are tracked separately in a persistent GitHub issue.
    pr_report = [
        "## Automated OpenDeck package updates", "",
        "Only updates passing their required native builds and combined flake evaluation are included.", "",
        "### Validated updates", "",
    ]
    pr_report += [f"- `{p['label']}`" for p in accepted] or ["- None"]
    pr_report += ["", "The package-update workflow records the complete validation results.", ""]
    Path(args.pr_report).write_text("\n".join(pr_report))

    save(args.state, {
        "ready": ready,
        "failed": bool(failures),
        "infrastructureFailure": bool(infrastructure_errors),
        "infrastructureErrors": infrastructure_errors,
        "packageFailures": package_failures,
        "accepted": [p["label"] for p in accepted],
    })
    print("\n".join(report))
    # Publish validated changes and report known failures separately.
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    d = commands.add_parser("discover")
    d.add_argument("--targets", required=True)
    d.add_argument("--output", required=True)
    u = commands.add_parser("update")
    u.add_argument("--plan", required=True)
    u.add_argument("--system", choices=SYSTEM_PREFERENCE, required=True)
    u.add_argument("--output", required=True)
    p = commands.add_parser("prepare")
    p.add_argument("--plan", required=True)
    p.add_argument("--targets", required=True)
    p.add_argument("--updates", required=True)
    p.add_argument("--output", required=True)
    b = commands.add_parser("build")
    b.add_argument("--updates", required=True)
    b.add_argument("--output", required=True)
    f = commands.add_parser("finalize")
    f.add_argument("--plan", required=True)
    f.add_argument("--prepared", required=True)
    f.add_argument("--updates", required=True)
    f.add_argument("--builds", required=True)
    f.add_argument("--base-unchanged", required=True)
    f.add_argument("--report", required=True)
    f.add_argument("--pr-report", required=True)
    f.add_argument("--state", required=True)
    args = parser.parse_args()
    return {"discover": discover, "update": update, "prepare": prepare, "build": build, "finalize": finalize}[args.command](args) or 0


if __name__ == "__main__":
    sys.exit(main())
