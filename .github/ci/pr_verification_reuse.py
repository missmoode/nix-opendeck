#!/usr/bin/env python3
"""Reuse successful native plugin verification from an earlier run of this PR.

The old workflow and target catalogue must match the trusted base exactly.
The old merge commit is re-evaluated; a successful job name alone is not proof
that it verified the same Nix derivation. Anything unverifiable is rebuilt.
"""

import json
import os
from pathlib import Path
import re
import subprocess
import sys
from tempfile import TemporaryDirectory
from urllib.parse import quote
from urllib.request import Request, urlopen

SHA = re.compile(r"[0-9a-f]{40}\Z")
RUN_TITLE = re.compile(r"Package verification PR #(\d+) merge ([0-9a-f]{40})\Z")
WORKFLOW = ".github/workflows/pr-package-verification.yml"
POLICY = (WORKFLOW, ".github/ci/targets.nix", ".github/ci/pr_verification_reuse.py")
HISTORY_LIMIT = 8  # Limit remote fetches and historical Nix evaluations.

# Evaluate with the catalogue from the current trusted base, not the old PR.
TARGETS_EXPR = r"""
let
  flake = builtins.getFlake (toString ./.);
  systems = builtins.attrNames flake.packages;
in
  builtins.concatLists (map (system:
    let
      targets = import (builtins.getEnv "TRUSTED_TARGETS") {
        inherit flake system;
      };
    in
      [ targets.core targets.opendeck ] ++ targets.plugins
  ) systems)
"""


def github_api(repo, path):
    request = Request(
        f"https://api.github.com/repos/{repo}{path}",
        headers={
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urlopen(request, timeout=25) as response:
        return json.load(response)


def jobs_for_run(repo, run_id):
    jobs = []
    page = 1
    while True:
        data = github_api(
            repo, f"/actions/runs/{run_id}/jobs?filter=latest&per_page=100&page={page}"
        )
        batch = data["jobs"]
        jobs.extend(batch)
        if len(batch) < 100:
            return jobs
        page += 1


def run_identity(run, *, repo, pr_number, current_run_id):
    """Return prior synthetic merge SHA only for a completed run of this PR."""
    if (
        type(run.get("id")) is not int
        or run["id"] >= current_run_id
        or run.get("event") != "pull_request"
        or run.get("status") != "completed"
        or run.get("conclusion") not in ("success", "failure")
        or run.get("repository", {}).get("full_name") != repo
    ):
        return None
    match = RUN_TITLE.fullmatch(run.get("display_title") or "")
    if not match or int(match[1]) != pr_number or not SHA.fullmatch(run.get("head_sha") or ""):
        return None
    attached_prs = run.get("pull_requests") or []
    if attached_prs and not any(p.get("number") == pr_number for p in attached_prs):
        return None
    return match[2]


def git(*args, cwd=None, timeout=30):
    return subprocess.run(
        ["git", *args], cwd=cwd, text=True, capture_output=True, check=True, timeout=timeout
    ).stdout.strip()


def ensure_commit(sha):
    if not SHA.fullmatch(sha):
        return False
    try:
        git("cat-file", "-e", f"{sha}^{{commit}}")
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        try:
            # Old GitHub-generated PR merge commits are not necessarily in
            # the checkout after a synchronize event. A missing commit is not
            # grounds to trust the old job; failure to fetch means rebuild.
            git("fetch", "--no-tags", "origin", sha, timeout=60)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            return False
    try:
        git("cat-file", "-e", f"{sha}^{{commit}}")
        return True
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return False


def blob_entry(commit, path):
    try:
        line = git("ls-tree", commit, "--", path)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return None
    # Include Git mode and type, not just the blob SHA (symlinks matter).
    match = re.fullmatch(r"(\d{6}) (blob|tree) ([0-9a-f]{40})\t(.+)", line)
    if not match or match[4] != path:
        return None
    return match.group(1), match.group(2), match.group(3)


def trusted_revision(merge_sha, base_sha, expected_head_sha):
    if not ensure_commit(merge_sha):
        return False
    try:
        parents = git("rev-list", "--parents", "-n", "1", merge_sha).split()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return False
    # Confirm that the old synthetic merge actually merges the PR head
    # reported by GitHub, rather than an unrelated commit with a spoofed title.
    if len(parents) != 3 or parents[2] != expected_head_sha:
        return False
    return all(
        (entry := blob_entry(base_sha, path)) is not None
        and entry == blob_entry(merge_sha, path)
        for path in POLICY
    )


def nix_eval_environment(trusted_targets):
    # The old flake is untrusted and evaluated with --impure: do not forward
    # GITHUB_TOKEN/GH_TOKEN/ACTIONS_RUNTIME_TOKEN or arbitrary runner secrets.
    allowed_env = (
        "PATH", "HOME", "TMPDIR", "NIX_PROFILES",
        "NIX_SSL_CERT_FILE", "SSL_CERT_FILE", "NIX_REMOTE",
        "USER", "XDG_CACHE_HOME",
        "XDG_CONFIG_HOME", "LANG", "LC_ALL",
    )
    env = {key: os.environ[key] for key in allowed_env if key in os.environ}
    env["TRUSTED_TARGETS"] = str(trusted_targets)
    return env


def evaluate_old(merge_sha, trusted_targets):
    with TemporaryDirectory(prefix="pr-verified-") as temp:
        worktree = Path(temp) / "old-merge"
        try:
            git("worktree", "add", "--detach", str(worktree), merge_sha, timeout=60)
            result = subprocess.run(
                ["nix", "eval", "--impure", "--json", "--expr", TARGETS_EXPR],
                cwd=worktree,
                env=nix_eval_environment(trusted_targets),
                text=True,
                capture_output=True,
                check=True,
                timeout=180,
            )
            catalogue = json.loads(result.stdout)
            if not isinstance(catalogue, list):
                return None
            attrs = [item.get("attr") for item in catalogue]
            if len(set(attrs)) != len(attrs):
                return None
            return {item["attr"]: item for item in catalogue}
        except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError,
                subprocess.TimeoutExpired) as exc:
            print(f"Prior merge {merge_sha[:12]} cannot be evaluated: {exc}", file=sys.stderr)
            return None
        finally:
            if worktree.exists():
                try:
                    git("worktree", "remove", "--force", str(worktree), timeout=30)
                except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
                    pass


def select_reused(changed, runs, *, repo, pr_number, current_run_id, job_lookup, old_catalogue):
    """Pure selection: old_catalogue(run, merge_sha) validates policy and re-evaluates."""
    pending = {
        item["attr"]: item for item in changed if item.get("kind") == "plugin"
    }
    reused = []
    eligible = []
    for run in runs:
        merge_sha = run_identity(
            run, repo=repo, pr_number=pr_number, current_run_id=current_run_id
        )
        if merge_sha is not None:
            eligible.append((run, merge_sha))
    eligible.sort(key=lambda pair: pair[0]["id"], reverse=True)

    for run, merge_sha in eligible[:HISTORY_LIMIT]:
        if not pending:
            break
        try:
            jobs = job_lookup(run["id"])
            successes = {}
            for job in jobs:
                if job.get("conclusion") == "success":
                    successes.setdefault(job.get("name"), []).append(job)
            names_needed = {
                f"Rebuild: {item['system']} / {item['label']}" for item in pending.values()
            }
            if not any(name in successes for name in names_needed):
                continue
            catalogue = old_catalogue(run, merge_sha)
            if catalogue is None:
                continue
            for attr, current in list(pending.items()):
                old = catalogue.get(attr)
                if not isinstance(old, dict):
                    continue
                if not all(old.get(key) == current.get(key) for key in
                           ("attr", "system", "kind", "label", "storePath")):
                    continue
                name = f"Rebuild: {current['system']} / {current['label']}"
                matches = successes.get(name, [])
                if len(matches) != 1 or not matches[0].get("html_url"):
                    continue
                reused.append({
                    "attr": attr,
                    "system": current["system"],
                    "label": current["label"],
                    "storePath": current["storePath"],
                    "jobUrl": matches[0]["html_url"],
                })
                del pending[attr]
        except (OSError, KeyError, TypeError, ValueError) as exc:
            # Historical evidence is optional. The current run still has to
            # build everything whose provenance could not be established.
            print(f"Unable to inspect historical run {run['id']}: {exc}", file=sys.stderr)
    return reused


def main():
    targets_path, output_path = map(Path, sys.argv[1:3])
    # Always create a valid empty result first; a failed optimization must
    # never turn into an implicit success or break package verification.
    output_path.write_text("[]\n", encoding="utf-8")
    changed = json.loads(targets_path.read_text(encoding="utf-8"))
    if not any(t.get("kind") == "plugin" for t in changed):
        return
    repo = os.environ["GITHUB_REPOSITORY"]
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
        raise ValueError("Unexpected repository")
    pr_number = int(os.environ["PR_NUMBER"])
    current_run_id = int(os.environ["GITHUB_RUN_ID"])
    base_sha = os.environ["BASE_SHA"]
    if not SHA.fullmatch(base_sha):
        raise ValueError("Invalid trusted base SHA")
    trusted_targets = Path(os.environ["TRUSTED_TARGETS"]).resolve()
    if not trusted_targets.is_file():
        raise ValueError("Missing trusted target catalogue")

    data = github_api(
        repo,
        f"/actions/workflows/{quote(WORKFLOW.rsplit('/', 1)[-1])}/runs"
        "?event=pull_request&per_page=100&page=1",
    )
    runs = data["workflow_runs"]

    def historical(run, merge_sha):
        if not trusted_revision(merge_sha, base_sha, run["head_sha"]):
            return None
        return evaluate_old(merge_sha, trusted_targets)

    reused = select_reused(
        changed, runs,
        repo=repo,
        pr_number=pr_number,
        current_run_id=current_run_id,
        job_lookup=lambda run_id: jobs_for_run(repo, run_id),
        old_catalogue=historical,
    )
    output_path.write_text(json.dumps(reused, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"Reusing {len(reused)} previously verified plugin target(s).")


if __name__ == "__main__":
    main()
