#!/usr/bin/env python3
"""Certify unprivileged PR workflow results without executing PR code.

Only this default-branch workflow has the App token. Commit statuses are the
security boundary; comments and assignees are best-effort notifications.
"""

import json
import os
import re
import sys
from urllib.error import URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

WORKFLOWS = {
    ".github/workflows/checks.yml": ("Checks", "Tests and evaluation", "nix-opendeck/tests"),
    ".github/workflows/pr-reproducibility.yml": (
        "Reproducibility", "Reproducibility gate", "nix-opendeck/reproducibility"
    ),
}
REPORTER_PATHS = (".github/workflows/trusted-ci-report.yml", ".github/ci/trusted_ci_report.py")
COMMENT_MARKER = "<!-- nix-opendeck-reproducibility -->"
SHA = r"[0-9a-f]{40}"


class GitHub:
    def __init__(self, repo, read_token, app_token):
        self.repo = repo
        self.read_token = read_token
        self.app_token = app_token

    def request(self, path, *, method="GET", payload=None, app=False):
        if not path.startswith("/") or ".." in path:
            raise ValueError("Invalid API path")
        request = Request(
            "https://api.github.com/repos/" + self.repo + path,
            data=json.dumps(payload).encode() if payload is not None else None,
            method=method,
            headers={
                "Accept": "application/vnd.github+json",
                "Authorization": "Bearer " + (self.app_token if app else self.read_token),
                "X-GitHub-Api-Version": "2022-11-28",
                "Content-Type": "application/json",
            },
        )
        with urlopen(request, timeout=30) as response:
            body = response.read()
            return json.loads(body) if body else None

    def pages(self, path, key=None):
        page = 1
        while True:
            sep = "&" if "?" in path else "?"
            data = self.request(f"{path}{sep}per_page=100&page={page}")
            items = data[key] if key else data
            yield from items
            if len(items) < 100:
                return
            page += 1

    def content_sha(self, path, ref):
        return self.request("/contents/" + path + "?ref=" + quote(ref, safe=""))["sha"]

    def status(self, result):
        # Verification runs against the merge commit, but GitHub may
        # regenerate that commit. Publish on the stable PR head instead.
        self.request(
            "/statuses/" + result["head"], method="POST", app=True,
            payload={
                "state": result["state"],
                "context": result["context"],
                "description": result["description"],
                "target_url": result["url"],
            },
        )


def select_authoritative_run(event_run, recent, expected_title, head_sha):
    """Select a completed run for one exact head/merge pair.

    A cancellation event may recover a prior completed run if it was previously
    superseded. Never accept a different commit or let a cancelled newer run
    invalidate an otherwise authoritative success. Called only after PR identity
    and current-revision validation.
    """
    # A newer run for the same PR merge takes precedence, even if it has not
    # finished yet (e.g. after adding/removing the ready-for-merge label).
    # Cancelled runs are not authoritative: an overlapping PR event can cancel
    # a newer run while leaving an earlier successful verification usable.
    run = event_run
    if run.get("conclusion") == "cancelled":
        # The earlier completion event may already have been ignored while
        # this run was pending. Reconsider it now that this run is cancelled.
        previous = [
            other for other in recent
            if other["id"] < run["id"]
            and other.get("display_title") == expected_title
            and other.get("head_sha") == head_sha
            and other.get("status") == "completed"
            and other.get("conclusion") != "cancelled"
        ]
        if not previous:
            return None
        run = max(previous, key=lambda other: other["id"])
    if any(
        other["id"] > run["id"] and other.get("display_title") == expected_title
        and other.get("conclusion") != "cancelled"
        # The triggering cancellation can precede the list API's update.
        and not (other["id"] == event_run["id"]
                 and event_run.get("conclusion") == "cancelled")
        for other in recent
    ):
        print("Superseded by a newer run; ignoring", file=sys.stderr)
        return None

    return run


def assess(event, api):
    """None means an irrelevant/obsolete run; otherwise return a checked verdict."""
    run = event["workflow_run"]
    path = (run.get("path") or "").split("@", 1)[0]
    if run.get("event") != "pull_request" or path not in WORKFLOWS:
        return None
    if run.get("status") != "completed" or run.get("repository", {}).get("full_name") != api.repo:
        return None

    kind, job_name, context = WORKFLOWS[path]
    match = re.fullmatch(rf"{kind} PR #(\d+) merge ({SHA})", run.get("display_title") or "")
    if not match or not re.fullmatch(SHA, run.get("head_sha") or ""):
        print("Unrecognised run identity; refusing to certify", file=sys.stderr)
        return None
    pr_number, merge_sha = int(match[1]), match[2]
    head_sha = run["head_sha"]
    pr = api.request(f"/pulls/{pr_number}")
    if (
        pr["state"] != "open"
        or pr["base"]["repo"]["full_name"] != api.repo
        or pr["base"]["ref"] != "main"
        or pr["head"]["sha"] != head_sha
        or pr.get("merge_commit_sha") != merge_sha
    ):
        print("PR revision is no longer current; ignoring", file=sys.stderr)
        return None
    if run.get("pull_requests") and pr_number not in [p["number"] for p in run["pull_requests"]]:
        return None

    # Runs are evaluated only for the current PR head and merge commit. Run
    # selection does not itself certify any job or produce a GitHub status.
    expected_title = f"{kind} PR #{pr_number} merge {merge_sha}"
    recent = list(api.pages(
        f"/actions/workflows/{path.rsplit('/', 1)[-1]}/runs"
        f"?event=pull_request&head_sha={head_sha}", key="workflow_runs"
    ))
    run = select_authoritative_run(run, recent, expected_title, head_sha)
    if run is None:
        return None
    # PR-authored changes to verification policy cannot produce App success.
    protected = (path, *REPORTER_PATHS)
    if kind == "Reproducibility":
        protected += (".github/ci/targets.nix",)
    unchanged = all(
        api.content_sha(file, merge_sha) == api.content_sha(file, pr["base"]["sha"])
        for file in protected
    )
    jobs = list(api.pages(f"/actions/runs/{run['id']}/jobs", key="jobs"))
    matching = [job for job in jobs if job["name"] == job_name]
    job_pass = len(matching) == 1 and matching[0]["conclusion"] == "success"
    # Both checks require an actively labelled PR. A skipped Actions job
    # counts as success to GitHub, so the App status must enforce the gate.
    requested = any(label["name"] == "ready for merge" for label in pr["labels"])
    passed = unchanged and requested and run["conclusion"] == "success" and job_pass
    if not unchanged:
        description = "PR changed CI policy; trusted verification unavailable"
    elif not requested:
        description = "Add 'ready for merge' to request verification"
    elif passed:
        description = "Verified by trusted CI reporter"
    else:
        description = "CI verification failed (see workflow run)"
    return {
        "pr": pr_number, "head": head_sha, "merge": merge_sha,
        "kind": kind, "context": context,
        "state": "pending" if not requested else ("success" if passed else "failure"), "description": description,
        "url": run["html_url"],
        "report_failure": unchanged and requested and not passed,
        "automated": (
            kind == "Reproducibility"
            and pr["user"]["login"] == os.environ.get("APP_BOT_LOGIN")
            and pr["head"]["repo"]["full_name"] == api.repo
            and pr["head"]["ref"] in ("automated/package-updates", "automated/nixpkgs-update")
        ),
    }



def notify(api, result):
    """Optional, best-effort PR comment and automated-update assignment."""
    if result["kind"] != "Reproducibility":
        return
    if result["report_failure"] and result["automated"]:
        maintainers = [m.strip() for m in os.environ.get("UPDATE_MAINTAINERS", "").split(",") if m.strip()]
        if maintainers:
            try:
                api.request(f"/issues/{result['pr']}/assignees", method="POST",
                            payload={"assignees": maintainers}, app=True)
            except URLError as exc:
                print(f"Optional assignment failed: {exc}", file=sys.stderr)

    # Only edit comments created by our App, never merely a matching marker.
    bot = os.environ.get("APP_BOT_LOGIN")
    if not bot:
        print("No App bot identity; skipping optional PR comment", file=sys.stderr)
        return
    comments = [
        c for c in api.pages(f"/issues/{result['pr']}/comments")
        if c["user"]["login"] == bot and COMMENT_MARKER in (c.get("body") or "")
    ]
    if not result["report_failure"]:
        for comment in comments:
            api.request(f"/issues/comments/{comment['id']}", method="DELETE", app=True)
    else:
        body = (
            f"{COMMENT_MARKER}\n### Reproducibility verification failed\n\n"
            f"[View failing verification run]({result['url']}).\n"
        )
        if comments:
            api.request(f"/issues/comments/{comments[-1]['id']}", method="PATCH",
                        payload={"body": body}, app=True)
        else:
            api.request(f"/issues/{result['pr']}/comments", method="POST",
                        payload={"body": body}, app=True)


def main():
    with open(os.environ["GITHUB_EVENT_PATH"], encoding="utf-8") as f:
        event = json.load(f)
    repo = os.environ["GITHUB_REPOSITORY"]
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
        raise ValueError("Unexpected repository")
    api = GitHub(repo, os.environ["GH_TOKEN"], os.environ["APP_TOKEN"])
    result = assess(event, api)
    if result is None:
        return
    api.status(result)  # Security-critical: failures here must fail the job.
    print(f"Published {result['state']} for {result['context']} on PR #{result['pr']}")
    try:
        notify(api, result)
    except Exception as exc:
        # Notifications are never part of the security verdict. Even a bug in
        # this convenience code must not retroactively fail a signed status.
        print(f"Optional notification failed: {exc}", file=sys.stderr)


if __name__ == "__main__":
    main()
