# CI and repository automation

This directory contains the repository's GitHub Actions workflows and their
small, standard-library Python helpers. **The Nix package definitions and the
repository's stated packaging goals are authoritative**; CI should validate
those definitions, not maintain a second package inventory or invent policy.

Clarification for agents: This is a maintenance map, not a request to redesign
the automation. In particular, avoid adding frameworks, generic hooks, or fallback
behaviour for cases that have not occurred. Preserve the difference between an
*updater* problem, a *package build* problem, and an *infrastructure* problem.

## Where to look

| File | Responsibility |
| --- | --- |
| `ci/targets.nix` | Derive supported native targets from the flake; shared by build, cache and reproducibility workflows |
| `workflows/update-packages.yml` | Daily/manual per-package updates, native builds, PR routing and failure issue orchestration |
| `ci/package_updates.py` | Discover updater targets, isolate proposed source edits, validate native builds, compose accepted updates and render diagnostic excerpts |
| `ci/upstream_compatibility.py` | Identify accepted updates with downstream patches, split manual-review/ordinary PRs, and provide the bounded static Gemini compatibility review |
| `ci/failure_audit.py` | Select patch-relevant failed builds, deduplicate requests using persistent issue comments, and obtain/publish optional Gemini diagnoses |
| `workflows/checks.yml` | Unprivileged PR unit tests and Nix evaluation/build checks |
| `workflows/pr-reproducibility.yml` | Unprivileged native verification of changed output paths, including independent rebuilds |
| `workflows/trusted-ci-report.yml` and `ci/trusted_ci_report.py` | Default-branch, privileged verification of PR run provenance and publication of required App commit statuses |
| `workflows/cache.yml` | Publish missing *redistributable* outputs to Cachix after main changes; also supports manual repair |
| `workflows/update-nixpkgs.yml` | Propose a nixpkgs lock update, separately from package release updates |
| `workflows/spot-check-reproducibility.yml` | Manually initiated reproducibility spot checks; not a release gate |
| `ci/test_*.py` | Mocked/unit regression tests for the Python decisions; not a substitute for live native builds |

## The required PR checks: security boundary

PR code runs in the **unprivileged** `Checks` and `Reproducibility` workflows.
These runs do not receive the App's trusted status-writing token. The separate
`Trusted CI report` workflow is triggered by `workflow_run: completed` and
executes its implementation from the default branch, not from the PR.

The trusted reporter (`ci/trusted_ci_report.py`) must:

1. Recognise an expected workflow and its run-title identity.
2. Confirm that the PR is open, targets `main`, and **both the PR head SHA and
   synthetic merge SHA** match the reported revision.
3. Select an authoritative run for that *same* head/merge revision. A newer
   non-cancelled run supersedes an older one; a cancelled newer run may allow
   recovery of an older completed run **for the identical revision only**.
4. Compare the relevant workflow file and the trusted reporter files against
   the base revision. Reproducibility also protects `ci/targets.nix`.
5. Require the expected job to pass exactly once and the PR to carry the
   `run checks` label before publishing App success.
6. Publish `nix-opendeck/tests` or `nix-opendeck/reproducibility` on the
   **PR head SHA**, not the synthetic merge SHA. Optional comments/assignment
   must never determine whether the status was written.

These are **security invariants**, not merely workflow implementation details.
Do not relax them to fix an auto-merge delay. In particular, *a successful
run for an earlier commit must never certify a new commit*. Run cancellation
can affect availability, but cannot substitute for passing verification.

The reporter checks its own source and workflow as protected files. A PR that
changes these deliberately cannot certify itself. After examining the diff
and tests, deploy trusted-policy changes through the repository's explicit
trusted-maintenance/default-branch procedure; **do not remove the protection
for convenience**.

When a PR is stuck with a pending required status, check the status on the
*head commit* as well as the Actions run outcome. A green Actions run is not
proof that the trusted App published its status. Inspect the subsequent
`Trusted CI report` run. Overlapping `opened`/`labeled` events can cancel one
another; review `ci/trusted_ci_report.py` run-selection tests before changing
concurrency behaviour.

## Package update path

```text
Discover flake targets
  -> independently run package updaters (record staged changes)
  -> build proposed packages on their native systems
  -> finalize: accept only validated changes, reject failures
      -> unpatched accepted sources: ordinary PR / auto-merge after required checks
      -> patched accepted sources: manual-review PR + static Gemini comment
      -> rejected package: persistent failure issue + bounded log excerpts
           -> optional, selectively triggered failure diagnosis
```

`opendeck-core` and `nekename/starterpack` are validated together in the
default application where appropriate; do not accidentally accept just half
of an invalidated combined update. Infrastructure failures or incomplete
reports **must not** turn into accepted source edits. A known package failure
should not suppress unrelated valid updates.

The updater separates three kinds of information:

- **Updater results:** one isolated attempt per package, including an
  optional proposed patch and its SHA-256.
- **Native build reports:** status, identity, optional source edits, and an
  error excerpt on failure. The full output stays in Actions logs.
- **Finalization state:** accepted packages, known package failures,
  infrastructure errors, and failure diagnostics. This is consumed by the
  workflow; the package-failure issue is a notification, not an approval.

See `ci/package_updates.py` for the actual JSON field names and validation.
Do not infer accepted updates from the presence of staged files or from a
Gemini response.

### AI reviews are advisory, not CI gates

The **successful-build compatibility audit** in `ci/upstream_compatibility.py`
looks for new upstream paths that might bypass checked-in downstream patches.
It is a static analysis, not a runtime test or automatic approval. A review
failure should say that the review is unavailable; it must not silently mean
"compatible". Patched updates always require manual review.

The **failed-build diagnosis** in `ci/failure_audit.py` is deliberately narrower:
only changed-version builds with concrete patch-application or patched-source
compiler evidence are candidates. Generic build, network, cache, and updater
failures still produce a diagnostic excerpt without spending Gemini tokens.
The selection and API operations are separate: `select` runs without tokens;
`reserve` writes a bot-owned marker before `review` calls Gemini; `publish`
updates that reservation. A fingerprint covers the relevant proposed source
and downstream patch contents, not volatile build logs or run IDs. Thus the
next scheduled attempt does not request the same analysis again—even if the
model timed out. A materially new source/patch combination can be analysed.

A reserved marker is **not evidence that the diagnosis succeeded**. The
original build failure and its logs remain authoritative.

## Binary cache and reproducibility

`workflows/cache.yml` checks the Cachix narinfo for evaluated store paths and
builds/publishes only missing redistributable outputs. A network error while
querying Cachix is an **infrastructure failure**, not a failed OpenDeck build;
inspect the `prepare` job before attributing it to package changes. The PR
reproducibility workflow independently rebuilds changed outputs and never
publishes binaries from an untrusted PR.

The package-update, nixpkgs-update and spot-check workflows share a maintenance
concurrency group so their proposed changes do not race. PR verification uses
separate per-PR groups with cancellation enabled; the trusted reporter must
still handle overlapping events safely.

## Making changes safely

Run from the repository root:

```sh
python3 -m unittest discover -s .github/ci -p 'test_*.py'
nix flake check --no-build --all-systems
nix flake check
git diff --check
```

The Python suite is network-free with mocked APIs/Git where appropriate. A
passing unit suite does **not** prove native packaging, Actions event ordering,
App permissions, or Cachix networking. Re-run relevant native jobs and examine
their actual outputs after altering workflow wiring.

For CI changes:

1. Name the existing invariant or failure mode first. Preserve the current
   control flow if a comment or a small helper makes it understandable.
2. Prefer focused transformations and tests over a broad rewrite. Keep
   untrusted PR execution separate from App credentials, and keep Gemini
   credentials separate from GitHub write credentials.
3. Never let missing/corrupt artifacts, inconclusive AI output, a skipped
   Actions job, or a cancelled new-commit run become a successful status.
4. Compare exact run and commit identities. Avoid mutable branch names in
   security decisions, and don't silently trust files changed in the PR.
5. Verify tests, check any modified workflow against actual Actions behaviour,
   and document changes to accepted/rejected update semantics here.

If automated changes are merged but the cache publication fails, first
determine whether the failure was in target discovery, cache lookup, a native
build, or upload. Do not use an expensive rebuild to diagnose a transient
`curl` error.
