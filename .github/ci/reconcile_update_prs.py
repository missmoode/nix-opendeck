#!/usr/bin/env python3
"""Close obsolete updater PRs after their proposed source changes reach main.

Only the two known bot-maintained branches are considered. This intentionally
requires exact file equivalence for every proposed source change: a different
source file is ambiguous and must be reviewed by a maintainer, not closed here.
"""

import json
import os
import subprocess
from urllib.parse import urlencode


BOT_BRANCHES = ("automated/package-updates", "automated/patched-package-updates")


def execute(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True).stdout.strip()


def redundant_source_changes(base, head):
    """True iff every path the PR changed has exactly its current main content."""
    ancestor = execute("git", "merge-base", base, head)
    changed = subprocess.run(
        ["git", "diff", "--no-renames", "--name-only", "-z", ancestor, head],
        check=True, capture_output=True,
    ).stdout
    paths = [os.fsdecode(path) for path in changed.split(b"\0") if path]
    # Bot PRs may only contain source updates. Never infer redundancy from
    # modified workflow files, or from only a subset of the proposed changes.
    if any(not path.startswith("src/") for path in paths):
        return False
    for path in paths:
        comparison = subprocess.run(
            ["git", "diff", "--quiet", base, head, "--", path], check=False,
        )
        if comparison.returncode != 0:
            return False  # also fail closed on git errors
    return True


def matching_pr(repo, base, branch, bot_login):
    owner = repo.partition("/")[0]
    query = urlencode({"state": "open", "base": base, "head": f"{owner}:{branch}", "per_page": "100"})
    matches = json.loads(execute("gh", "api", f"repos/{repo}/pulls?{query}"))
    matches = [pr for pr in matches
               if pr.get("state") == "open"
               and pr.get("user", {}).get("login") == bot_login
               and pr.get("head", {}).get("ref") == branch
               and pr.get("head", {}).get("repo", {}).get("full_name") == repo
               and pr.get("base", {}).get("ref") == base]
    # Multiple matching PRs should not exist. Do not choose arbitrarily.
    return matches[0] if len(matches) == 1 else None


def main():
    repo = os.environ["GH_REPO"]
    base = os.environ["BASE_BRANCH"]
    login = os.environ["APP_BOT_LOGIN"]
    # For this workflow only the default branch can publish trusted updates.
    execute("git", "fetch", "--no-tags", "origin",
            f"+refs/heads/{base}:refs/remotes/origin/{base}")
    base_ref = f"refs/remotes/origin/{base}"
    for branch in BOT_BRANCHES:
        pr = matching_pr(repo, base, branch, login)
        if pr is None:
            continue
        head_ref = f"refs/remotes/origin/{branch}"
        try:
            execute("git", "fetch", "--no-tags", "origin",
                    f"+refs/heads/{branch}:{head_ref}")
        except subprocess.CalledProcessError:
            print(f"::warning::Cannot inspect {branch}; leaving PR open")
            continue
        head_sha = execute("git", "rev-parse", head_ref)
        if head_sha != pr["head"]["sha"]:
            print(f"Skipping PR #{pr['number']}: its head changed while inspecting")
            continue
        if not redundant_source_changes(base_ref, head_ref):
            print(f"Keeping PR #{pr['number']} ({branch}): source changes not fully present on {base}")
            continue
        # Recheck immediately before the write: another run or maintainer may
        # have updated the PR while the source comparison was in progress.
        live = json.loads(execute("gh", "api", f"repos/{repo}/pulls/{pr['number']}"))
        if live.get("state") != "open" or live.get("head", {}).get("sha") != head_sha:
            print(f"Skipping PR #{pr['number']}: PR changed before closure")
            continue
        print(f"Closing obsolete updater PR #{pr['number']} ({branch})")
        execute("gh", "pr", "close", str(pr["number"]), "--delete-branch", "--repo", repo)


if __name__ == "__main__":
    main()
