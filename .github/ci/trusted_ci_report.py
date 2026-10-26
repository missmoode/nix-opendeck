#!/usr/bin/env python3
"""Publish App-signed CI statuses; execute only from the default branch.

The trigger is an unprivileged PR workflow. Its verdict is accepted only if
GitHub confirms that the exact merge commit is still current and the workflow
source matches the PR base. No PR code or artifacts are downloaded or executed.
"""

import json
import os
import re
import sys
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen

WORKFLOWS = {
    "Checks": (".github/workflows/checks.yml", "Tests and evaluation", "nix-opendeck/tests"),
    "Reproducibility": (
        ".github/workflows/pr-reproducibility.yml",
        "Reproducibility gate",
        "nix-opendeck/reproducibility",
    ),
}
TITLE = re.compile(r"\bPR #(\d+) merge ([0-9a-f]{40})\b")


class GitHub:
    def __init__(self, repo, read_token, app_token):
        self.repo = repo
        self.read_token = read_token
        self.app_token = app_token

    def request(self, path, *, method="GET", payload=None, app=False):
        if not path.startswith("/") or ".." in path:
            raise ValueError("Invalid GitHub API path")
        body = None if payload is None else json.dumps(payload).encode()
        req = Request(
            "https://api.github.com/repos/" + self.repo + path,
            data=body,
            method=method,
            headers={
                "Accept": "application/vnd.github+json",
                "Authorization": "Bearer " + (self.app_token if app else self.read_token),
                "X-GitHub-Api-Version": "2022-11-28",
                "Content-Type": "application/json",
            },
        )
        with urlopen(req, timeout=30) as response:
            raw = response.read()
            return json.loads(raw) if raw else None

    def jobs(self, run_id):
        jobs = []
        page = 1
        while True:
            result = self.request(f"/actions/runs/{run_id}/jobs?per_page=100&page={page}")
            batch = result["jobs"]
            jobs.extend(batch)
            if len(batch) < 100:
                return jobs
            page += 1

    def content_sha(self, path, ref):
        result = self.request("/contents/" + path + "?ref=" + quote(ref, safe=""))
        return result["sha"]

    def status(self, sha, context, state, description, url):
        self.request(
            "/statuses/" + sha,
            method="POST",
            app=True,
            payload={
                "state": state,
                "context": context,
                "description": description[:140],
                "target_url": url,
            },
        )

    def comments(self, number):
        comments = []
        page = 1
        while True:
            batch = self.request(f"/issues/{number}/comments?per_page=100&page={page}")
            comments.extend(batch)
            if len(batch) < 100:
                return comments
            page += 1



def assess(event, api):
    """Return None for stale/unrelated runs, or a validated report dict."""
    run = event["workflow_run"]

    # The run's name may contain a custom run-name, so identify the
    # workflow by GitHub's reported workflow file path instead.
    workflow_path = (run.get("path") or "").split("@", 1)[0]
    name = next(
        (
            kind
            for kind, (path, _, _) in WORKFLOWS.items()
            if path == workflow_path
        ),
        None,
    )

    if run.get("event") != "pull_request" or name is None:
        return None

    path, required_job, context = WORKFLOWS[name]
    if run.get("status") != "completed":
        return None
    if run.get("repository", {}).get("full_name") != api.repo:
        return None
    # A cancelled run is obsolete; never overwrite a newer status.
    if run.get("conclusion") == "cancelled":
        return None
    match = TITLE.search(run.get("display_title") or "")
    if not match:
        print(f"Unrecognised run title for {name}; refusing to sign a status")
        return None
    number, merge_sha = int(match.group(1)), match.group(2)
    head_sha = run.get("head_sha", "")
    if not re.fullmatch(r"[0-9a-f]{40}", head_sha):
        return None
    pr = api.request(f"/pulls/{number}")
    if (
        pr["state"] != "open"
        or pr["base"]["repo"]["full_name"] != api.repo
        or pr["base"]["ref"] != "main"
        or pr["head"]["sha"] != head_sha
        or pr.get("merge_commit_sha") != merge_sha
    ):
        print("Run is stale or not for an open PR to main; ignoring")
        return None
    # Check GitHub's association of the workflow run with this PR where
    # populated. Run title alone is insufficient to authenticate identity.
    associated = run.get("pull_requests") or []
    if associated and number not in [p["number"] for p in associated]:
        return None

    # A late reporter from an older labeled/unlabeled run must not overwrite
    # a newer verdict for the same revision, even if the old run completed.
    recent = api.request(
        "/actions/workflows/" + path.rsplit("/", 1)[-1]
        + "/runs?event=pull_request&head_sha=" + head_sha + "&per_page=100"
    )["workflow_runs"]
    if any(
        r["id"] > run["id"]
        and (m := TITLE.search(r.get("display_title") or ""))
        and int(m.group(1)) == number
        and m.group(2) == merge_sha
        for r in recent
    ):
        print("Newer run exists for this PR revision; ignoring older result")
        return None

    # The PR cannot alter the verifier or the privileged reporter while
    # still receiving an App-issued success. CI infrastructure changes need
    # an intentional, separately reviewed bootstrap merge.
    trusted_paths = [
        path,
        ".github/workflows/trusted-ci-report.yml",
        ".github/ci/trusted_ci_report.py",
    ]
    verified_source = all(
        api.content_sha(p, merge_sha) == api.content_sha(p, pr["base"]["sha"])
        for p in trusted_paths
    )
    if name == "Reproducibility":
        # A PR must not redefine the target catalogue used to select builds.
        verified_source &= api.content_sha(".github/ci/targets.nix", merge_sha) == api.content_sha(
            ".github/ci/targets.nix", pr["base"]["sha"]
        )

    jobs = api.jobs(run["id"])
    matching_jobs = [j for j in jobs if j["name"] == required_job]
    job_pass = len(matching_jobs) == 1 and matching_jobs[0]["conclusion"] == "success"
    requested = name != "Reproducibility" or any(
        label["name"] == "ready for merge" for label in pr["labels"]
    )
    passed = verified_source and requested and run["conclusion"] == "success" and job_pass
    if not verified_source:
        description = "PR changed CI policy; trusted verification unavailable"
    elif not requested:
        description = "Add 'ready for merge' to request verification"
    elif passed:
        description = "Verified by trusted CI reporter"
    else:
        description = "CI verification failed (see workflow run)"
    return {
        "pr": number,
        "head": head_sha,
        "merge": merge_sha,
        "kind": name,
        "context": context,
        "state": "success" if passed else "failure",
        "description": description,
        "url": run["html_url"],
        "report_failure": verified_source and requested and not passed,
        "comment_marker": "<!-- nix-opendeck-reproducibility -->",
        "automated": (
            name == "Reproducibility"
            and pr["user"]["login"] == os.environ.get("AUTOMATION_APP_BOT_LOGIN", "")
            and pr["head"]["repo"]["full_name"] == api.repo
            and pr["head"]["ref"] in ("automated/package-updates", "automated/nixpkgs-update")
        ),
    }


def publish(api, result):
    # Publish only to the tested PR merge commit, not the PR head.
    api.status(
        result["merge"],
        result["context"],
        result["state"],
        result["description"],
        result["url"],
    )

    if result["kind"] != "Reproducibility":
        return
    if result["report_failure"] and result["automated"]:
        maintainers = [x.strip() for x in os.environ.get("UPDATE_MAINTAINERS", "").split(",") if x.strip()]
        if maintainers:
            try:
                api.request(
                    f"/issues/{result['pr']}/assignees",
                    method="POST",
                    payload={"assignees": maintainers},
                    app=True,
                )
            except HTTPError as exc:
                print(f"Warning: could not assign maintainer ({exc.code})", file=sys.stderr)
    # Failure messages are informational. The App-signed status is authoritative.
    marker = result["comment_marker"]
    existing = [
        c for c in api.comments(result["pr"])
        if marker in (c.get("body") or "") and c.get("user", {}).get("type") == "Bot"
    ]
    # Be conservative: only update an existing comment created by our App.
    # The marker is unique enough for display; do not delete another bot's note.
    # Correct matching uses an installation identity supplied via env below.
    bot_login = os.environ.get("AUTOMATION_APP_BOT_LOGIN", "")
    existing = [c for c in existing if bot_login and c["user"]["login"] == bot_login]
    if result["state"] == "success" or not result["report_failure"]:
        for c in existing:
            api.request(f"/issues/comments/{c['id']}", method="DELETE", app=True)
        return
    body = (
        f"{marker}\n### Reproducibility verification failed\n\n"
        f"[View failing verification run]({result['url']}).\n"
    )
    if existing:
        api.request(f"/issues/comments/{existing[-1]['id']}", method="PATCH", payload={"body": body}, app=True)
    else:
        api.request(f"/issues/{result['pr']}/comments", method="POST", payload={"body": body}, app=True)


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
    publish(api, result)
    print(f"Published {result['state']} for {result['context']} on PR #{result['pr']}")


if __name__ == "__main__":
    try:
        main()
    except HTTPError as exc:
        print(f"GitHub API error: {exc.code}", file=sys.stderr)
        raise
