#!/usr/bin/env python3
"""Reconcile explicitly acknowledged manual repairs of updater failure issues.

An issue is not evidence that a particular upstream version was attempted. An
unverified version increase alone must not clear it. This path requires an
explicit **merge-commit trailer** and the exact tree certified by trusted CI.
Scheduled updater reconciliation remains authoritative for all other cases.
"""

import base64
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from package_updates import previous_failed_packages

TITLE = "Automated package update failures"
WORKFLOWS = {
    "nix-opendeck/tests": (".github/workflows/checks.yml", "Checks"),
    "nix-opendeck/package-verification": (
        ".github/workflows/pr-package-verification.yml",
        "Package verification",
    ),
}
ISSUE_MARKER = re.compile(
    r"(?m)^<!-- nix-opendeck-failed-packages:[A-Za-z0-9_-]+={0,2} -->$"
)
# This explicit acknowledgement is for cases where the issue has no reliable
# attempted upstream version, e.g. a source-update script failed before writing.
ACKNOWLEDGEMENT = re.compile(
    r"(?m)^Resolves-Update-Failure: #([0-9]+) (opendeck-core|[A-Za-z0-9_-]+/[A-Za-z0-9_-]+)$"
)
VERSION = re.compile(r'^\s*version\s*=\s*"([^"]+)"\s*;', re.M)
NUMERIC_VERSION = re.compile(r"[0-9]+(?:\.[0-9]+)*\Z")
PLUGIN = re.compile(r"[A-Za-z0-9_-]+/[A-Za-z0-9_-]+\Z")
SHA = re.compile(r"[0-9a-f]{40}\Z")


def execute(*args):
    return subprocess.run(
        args, check=True, capture_output=True, text=True
    ).stdout.strip()


def api(path):
    # The GITHUB_TOKEN handles reads; reserve the short-lived App token for writes.
    env = os.environ.copy()
    env["GH_TOKEN"] = os.environ["READ_GH_TOKEN"]
    result = subprocess.run(
        ["gh", "api", path], check=True, capture_output=True, text=True, env=env
    )
    return json.loads(result.stdout)


def package_path(label):
    if label == "opendeck-core":
        return "src/packages/opendeck/default.nix"
    if not PLUGIN.fullmatch(label):
        raise ValueError("invalid package label in issue metadata")
    return f"src/packages/plugins/{label}/default.nix"


def version_at(rev, path):
    result = subprocess.run(
        ["git", "show", f"{rev}:{path}"], capture_output=True, text=True
    )
    if result.returncode:
        return None  # Removal is not a verified new package version.
    matches = VERSION.findall(result.stdout)
    return matches[0] if len(matches) == 1 else None


def advanced(old, new):
    if (
        not old
        or not new
        or not NUMERIC_VERSION.fullmatch(old)
        or not NUMERIC_VERSION.fullmatch(new)
    ):
        return False
    before = [int(part) for part in old.split(".")]
    after = [int(part) for part in new.split(".")]
    n = max(len(before), len(after))
    return tuple(after + [0] * (n - len(after))) > tuple(
        before + [0] * (n - len(before))
    )


def updated_packages(labels, before, after):
    changed = {}
    for label in sorted(labels):
        path = package_path(label)
        old, new = version_at(before, path), version_at(after, path)
        if advanced(old, new):
            changed[label] = (old, new)
    return changed


def latest_statuses(statuses):
    """GitHub's combined-status response is ordered newest first."""
    latest = {}
    for status in statuses:
        latest.setdefault(status.get("context"), status)
    return latest


def certified_tree(repo, pr, bot_login):
    """Get tree tested for both PR checks; fail closed if unavailable or stale.

    Trusted CI publishes the results on the PR *head*, not on the synthetic
    merge. Each status points to a workflow run whose title identifies its
    synthetic merge SHA. Matching the tree, rather than just the head SHA,
    handles base-branch changes and squash commits without guessing.
    """
    head = pr.get("head", {}).get("sha", "")
    if not SHA.fullmatch(head):
        return None
    statuses = latest_statuses(
        api(f"repos/{repo}/commits/{head}/status").get("statuses", [])
    )
    expected_tree = None
    for context, (workflow_path, workflow_title) in WORKFLOWS.items():
        status = statuses.get(context, {})
        if (
            status.get("state") != "success"
            or status.get("creator", {}).get("login") != bot_login
        ):
            return None
        # Do not follow an arbitrary URL from a status. Run IDs are fetched
        # through the fixed repository API, never through status.target_url.
        url = status.get("target_url", "")
        match = re.fullmatch(
            rf"https://github\.com/{re.escape(repo)}/actions/runs/([0-9]+)", url
        )
        if not match:
            return None
        run = api(f"repos/{repo}/actions/runs/{match.group(1)}")
        title_match = re.fullmatch(
            rf"{re.escape(workflow_title)} PR #{pr['number']} merge ([0-9a-f]{{40}})",
            run.get("display_title", ""),
        )
        if (
            not title_match
            or run.get("event") != "pull_request"
            or run.get("status") != "completed"
            or run.get("conclusion") != "success"
            or run.get("head_sha") != head
            or run.get("repository", {}).get("full_name") != repo
            or (run.get("path") or "").split("@", 1)[0] != workflow_path
        ):
            return None
        merge_sha = title_match.group(1)
        # A synthetic merge may expire. Missing evidence means no closure;
        # never fall back to treating the PR head's status as merge evidence.
        merge_tree = (
            api(f"repos/{repo}/git/commits/{merge_sha}").get("tree", {}).get("sha")
        )
        if not isinstance(merge_tree, str) or not SHA.fullmatch(merge_tree):
            return None
        if expected_tree is not None and expected_tree != merge_tree:
            return None
        expected_tree = merge_tree
    return expected_tree


def matching_merged_pr(repo, before, after, branch):
    if not SHA.fullmatch(before) or not SHA.fullmatch(after):
        return None
    if execute("git", "rev-parse", "HEAD") != after:
        return None
    # Only a single merge push. If several commits land together, do not
    # attribute their combined diff to a single PR or status set.
    if execute("git", "rev-parse", f"{after}^1") != before:
        return None
    prs = api(f"repos/{repo}/commits/{after}/pulls?per_page=100")
    matching = [
        pr
        for pr in prs
        if pr.get("merged_at")
        and pr.get("merge_commit_sha") == after
        and pr.get("base", {}).get("ref") == branch
        and pr.get("base", {}).get("repo", {}).get("full_name") == repo
    ]
    return matching[0] if len(matching) == 1 else None


def acknowledged_labels(merge_message, issue_no):
    # The merged commit is immutable. PR bodies and labels may be edited after
    # merge by their authors, so they cannot authorise the bot's issue writes.
    return {
        label
        for number, label in ACKNOWLEDGEMENT.findall(merge_message)
        if number == str(issue_no)
    }


def remaining_issue_body(body, outstanding, resolved):
    """Update the shared failure marker and visible list, preserve diagnostics."""
    previous = previous_failed_packages(body)
    if not resolved or previous - resolved != outstanding:
        raise ValueError("inconsistent issue reconciliation")
    encoded = base64.urlsafe_b64encode(
        json.dumps(sorted(outstanding)).encode()
    ).decode()
    new_body, count = ISSUE_MARKER.subn(
        f"<!-- nix-opendeck-failed-packages:{encoded} -->", body
    )
    if count != 1:
        raise ValueError("unrecognised failure metadata")
    start = new_body.find("## Outstanding package update failures\n")
    end = new_body.find("\n### ", start)
    if start < 0 or end < 0:
        raise ValueError("unrecognised failure issue layout")
    section = new_body[start:end]
    seen = set()
    remaining_lines = []
    for line in section.splitlines():
        match = re.fullmatch(r"- ([^:]+): .*", line)
        if match and match.group(1) in previous:
            seen.add(match.group(1))
            if match.group(1) in resolved:
                continue
        remaining_lines.append(line)
    if seen != previous:
        raise ValueError("failure issue list disagrees with metadata")
    remaining_lines += [
        "",
        "**Manual reconciliation:** Removed entries were explicitly acknowledged "
        "by a verified merged PR. The original updater diagnostics remain below.",
    ]
    return new_body[:start] + "\n".join(remaining_lines) + new_body[end:]


def status_comment(changed, remaining, pr, repo, run_url):
    number = pr["number"]
    lines = [
        "## Manual package update reconciliation",
        "",
        f"Verified [PR #{number}](https://github.com/{repo}/pull/{number}) explicitly "
        "acknowledged these failed package updates:",
        "",
    ]
    lines.extend(
        f"- `{label}`: `{old}` → `{new}`"
        for label, (old, new) in sorted(changed.items())
    )
    lines += [
        "",
        f"**Outstanding failures:** {len(remaining)} package(s).",
        "",
        "This records a verified manual repair, **not** proof that the updater "
        "itself was fixed. The scheduled updater will still check for failures.",
        "",
        f"[Reconciliation run]({run_url})",
    ]
    if not remaining:
        lines += ["", "No tracked failures remain; closing this incident."]
    return "\n".join(lines) + "\n"


def main():
    repo = os.environ["GH_REPO"]
    branch = os.environ["BASE_BRANCH"]
    bot = os.environ["APP_BOT_LOGIN"]
    issue_no = os.environ["ISSUE_NUMBER"]
    before = os.environ["BEFORE_SHA"]
    after = os.environ["AFTER_SHA"]
    if not re.fullmatch(r"[0-9]+", issue_no):
        raise ValueError("invalid failure issue number")

    issue = api(f"repos/{repo}/issues/{issue_no}")
    if (
        issue.get("state") != "open"
        or issue.get("title") != TITLE
        or issue.get("user", {}).get("login") != bot
    ):
        raise ValueError("issue is not an open bot-owned package failure incident")
    old_body = issue.get("body") or ""
    previous = previous_failed_packages(old_body)
    if not previous:
        return

    pr = matching_merged_pr(repo, before, after, branch)
    if pr is None:
        print("No single merged PR for this push; leave issue to scheduled updater")
        return
    requested = previous & acknowledged_labels(
        execute("git", "show", "-s", "--format=%B", after), issue_no
    )
    if not requested:
        print("No immutable merge-commit acknowledgment for an outstanding failure")
        return
    changes = updated_packages(requested, before, after)
    if not changes:
        print("No explicitly acknowledged tracked package version increased")
        return

    expected_tree = certified_tree(repo, pr, bot)
    if (
        expected_tree is None
        or execute("git", "rev-parse", f"{after}^{{tree}}") != expected_tree
    ):
        print("Merged tree lacks matching trusted CI verification; leave issue open")
        return

    # The run may be obsolete because a newer push already reached main.
    ref = api(f"repos/{repo}/git/ref/heads/{branch}")
    if ref.get("object", {}).get("sha") != after:
        print("main advanced during reconciliation; leaving issue untouched")
        return

    remaining = previous - changes.keys()
    new_body = (
        remaining_issue_body(old_body, remaining, set(changes)) if remaining else None
    )
    run_url = (
        f"{os.environ.get('GITHUB_SERVER_URL', 'https://github.com')}/{repo}"
        f"/actions/runs/{os.environ.get('GITHUB_RUN_ID', '')}"
    )
    comment = status_comment(changes, remaining, pr, repo, run_url)
    current = api(f"repos/{repo}/issues/{issue_no}")
    if current.get("state") != "open" or current.get("body") != old_body:
        raise ValueError(
            "failure issue changed during verification; no write performed"
        )

    with tempfile.TemporaryDirectory() as temp:
        path = Path(temp) / "comment.md"
        path.write_text(comment)
        execute("gh", "issue", "comment", issue_no, "--body-file", str(path))
        if new_body is not None:
            path.write_text(new_body)
            execute("gh", "issue", "edit", issue_no, "--body-file", str(path))
        else:
            execute("gh", "issue", "close", issue_no, "--reason", "completed")
    print(
        f"Acknowledged {len(changes)} verified repair(s); {len(remaining)} outstanding"
    )


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as exc:
        print(f"::error::{exc}", file=sys.stderr)
        sys.exit(1)
