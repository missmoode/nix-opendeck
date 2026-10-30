# Maintenance, CI and repository automation

This document explains the maintenance processes, GitHub Actions workflows,
and CI security boundaries used by nix-opendeck. It is intended for maintainers
and contributors investigating failures, updating packages, or modifying the
automation.

The repository's Nix package definitions and stated packaging goals are
authoritative. CI should validate those definitions rather than maintain a
second package inventory or introduce separate packaging policy.

Prefer focused fixes to demonstrated problems. Avoid speculative abstractions,
unnecessary fallback paths, and additional automation layers where existing
functionality is sufficient. Distinguish package-update failures, package-build
failures, and infrastructure failures before changing code.

## Repository automation map

Paths in this table are relative to `.github/`.

| File | Responsibility |
| --- | --- |
| `ci/targets.nix` | Derive supported native package targets from the flake |
| `workflows/update-packages.yml` | Discover and update packages, validate builds, create PRs and report failures |
| `ci/package_updates.py` | Isolate updater changes, prepare build targets, validate results and produce diagnostic reports |
| `ci/upstream_compatibility.py` | Detect downstream-patched updates, route them for manual review and perform optional static compatibility analysis |
| `ci/failure_audit.py` | Select relevant patch-related build failures and coordinate optional AI diagnoses |
| `ci/reconcile_update_prs.py` | Identify and close updater PRs whose proposed source changes are already present on `main` |
| `workflows/update-nixpkgs.yml` | Update the nixpkgs flake input independently of package versions |
| `workflows/checks.yml` | Run unprivileged PR tests and Nix checks |
| `workflows/pr-reproducibility.yml` | Verify changed package outputs with native builds and independent rebuilds |
| `workflows/trusted-ci-report.yml` | Verify unprivileged workflow results and publish trusted commit statuses |
| `ci/trusted_ci_report.py` | Implement trusted run identification, verification and status publication |
| `workflows/cache.yml` | Build and publish missing redistributable outputs to Cachix |
| `workflows/spot-check-reproducibility.yml` | Manually test reproducibility across supported package targets |
| `ci/test_*.py` | Regression tests for CI helper and verification logic |

The Python helpers use the standard library where practical. Their tests
exercise decision logic but do not replace native builds or live GitHub Actions
integration checks.

## Routine automation

### Package updates

`Update packages` runs daily and can also be dispatched manually.

It discovers packages with update scripts from the flake, proposes source
updates, builds affected packages on supported native systems, and routes
validated updates into pull requests.

Packages requiring downstream patch review are kept separate from ordinary
updates that are eligible for automatic merging.

Failed updates are reported without preventing unrelated successful updates
from being proposed.

### Nixpkgs updates

`Update nixpkgs` runs monthly and can also be dispatched manually.

It updates the `nixpkgs` input in `flake.lock`, leaving separately pinned
inputs untouched. It creates a pull request for the lock-file change and
requests automatic merging once the required PR checks pass.

This workflow does not update OpenDeck or plugin versions. Those are handled
by `Update packages`.

The PR reproducibility workflow identifies which package outputs actually
change under the proposed nixpkgs revision and validates those outputs.

### Pull request verification

Ready-for-review PRs trigger `Checks` and `Reproducibility`.

Draft PRs do not execute the expensive verification jobs. Verification runs
when a PR is opened ready for review, becomes ready for review, receives new
commits, or undergoes another supported PR edit.

Changing labels does not request or restart verification.

The workflows use per-PR concurrency groups to cancel superseded executions.

### Binary cache publication

`Build and publish binary cache` runs following pushes to `main` and can be
dispatched manually.

It evaluates supported package outputs, checks whether redistributable outputs
are already available in Cachix, and builds/publishes missing outputs.

Cache publication is separate from PR verification. Untrusted PR builds do
not receive cache-publishing credentials.

### Reproducibility spot checks

`Reproducibility Spot-check` is manually dispatched.

It tests the available supported package targets, including packages that
cannot be distributed through the binary cache. It obtains cached references
where available or builds local references as appropriate.

This workflow is a maintenance tool, not an additional required PR gate.

## Pull request verification and security

### Unprivileged verification

PR code executes in two unprivileged workflows:

- `Checks`: Python regression tests, all-system Nix evaluation, and native
  `nix flake check`.
- `Reproducibility`: discovery and native verification of package outputs
  affected by the PR.

These workflows have read-only repository access and do not receive the
GitHub App credentials used to publish trusted commit statuses.

Passing an ordinary GitHub Actions job does not, by itself, satisfy the
repository's trusted verification requirements.

### Reproducibility target selection

`ci/targets.nix` derives targets directly from the flake, including
`opendeck-core`, the default OpenDeck package, and exported plugins for
supported systems.

The PR reproducibility workflow evaluates the target catalogue at the PR's
base revision and proposed merge revision using the trusted base catalogue.

It compares evaluated Nix output paths:

- Changed or newly introduced targets are selected for verification.
- Unchanged outputs are not unnecessarily rebuilt.
- Removal of a previously published target is treated as an error, not as
  an empty set of changes.
- Core and wrapper targets are grouped by platform, with core built first.
- Changed plugins receive separate native build jobs.

For each selected target, CI obtains the expected output and performs an
independent `nix build --rebuild` of the selected derivation.

The rebuild checks reproducibility of that derivation; it does not imply that
every dependency has independently been rebuilt.

The workflow also validates the structure and signature of the macOS OpenDeck
application bundle where applicable.

Failures retain useful diagnostics. Redistributable differing outputs may be
archived for inspection; non-redistributable outputs must not be published.

A PR that changes no evaluated package outputs can still pass the
reproducibility gate after successful target discovery.

### Trusted status publication

`Trusted CI report` is triggered when either unprivileged verification workflow
completes.

Its implementation runs from the default branch, not from the PR under test.
It uses a short-lived GitHub App token to publish the required commit statuses:

- `nix-opendeck/tests`
- `nix-opendeck/reproducibility`

`ci/trusted_ci_report.py` must:

1. Recognise the expected workflow, run identity, and repository.
2. Confirm that the PR is open and targets `main`.
3. Match the current PR head SHA and synthetic merge SHA to the reported
   workflow revision.
4. Select an authoritative run for that exact revision, accounting safely
   for overlapping or cancelled runs.
5. Verify that the relevant verification workflow and trusted reporter files
   match the base revision. Reproducibility also protects `ci/targets.nix`.
6. Require the expected verification job to have succeeded exactly once.
7. Require the PR to be currently non-draft before publishing success.
8. Publish the verified result against the PR head SHA, not the synthetic
   merge SHA.

These checks form the security boundary between untrusted PR execution and
privileged status publication.

A successful run for an earlier commit must never certify a newer commit.
A skipped job must not be interpreted as successful verification. Cancelled
runs must not bypass the requirement for a successful authoritative run.

The reporter may recover an earlier completed result when a later run for
the identical revision was cancelled, subject to its existing run-selection
rules.

Optional comments and maintainer assignments are notifications, not
authorization or verification results. Their failure must not change whether
a verified status is published.

### Draft PRs and workflow approvals

Both verification workflows handle PR opening, reopening, new commits,
readiness changes, and edits. Converting a PR to draft cancels running
verification through the existing concurrency configuration.

The trusted reporter checks the PR's current draft state through the GitHub
API. Draft PRs and skipped verification cannot receive trusted success.
Skipped verification remains pending rather than being reported as a genuine
build failure.

GitHub commit statuses are attached to commit SHAs and may persist across
draft transitions. Draft PRs cannot merge, and making a PR ready triggers
verification again.

The repository's required-status and up-to-date merge protection must remain
enabled. The trusted reporter is not a general-purpose status revocation
service.

For public fork PRs, the intended GitHub Actions repository setting is:

`Settings → Actions → General → Approval for running fork pull request
workflows from contributors → Require approval for all external contributors`

External workflow-run approval limits who can consume hosted CI resources.
Draft status is not an authorization mechanism.

This repository setting must be checked in GitHub itself; it is not configured
by the workflow YAML.

### Modifying trusted verification policy

The reporter verifies that its own implementation and relevant workflow files
have not been modified by the PR being certified.

Consequently, a PR changing protected verification policy cannot certify
itself through the ordinary PR checks.

Changes to the trusted reporter, verification workflows, or protected target
selection policy require explicit maintainer review and deployment through
the repository's trusted-maintenance/default-branch procedure.

Do not temporarily remove these protections to obtain a passing status.
Review the change, run the applicable tests, and preserve the separation
between trusted status publication and untrusted PR execution.

## Package update pipeline

The package updater follows this sequence:

```text
Discover updatable packages
  |
  v
Run each package updater independently
  |
  v
Collect proposed source changes
  |
  v
Build affected packages on native systems
  |
  v
Validate and finalize results
  |
  +-- Validated, ordinary update
  |     -> automatic-merge PR
  |
  +-- Validated update with downstream patches
  |     -> manual-review PR
  |     -> optional compatibility analysis
  |
  +-- Failed update or build
        -> persistent failure issue
        -> logs and diagnostic artifacts
        -> optional patch-related failure analysis
```

### Target discovery and source updates

Updatable packages are identified through the exported flake targets and their
`updateScript` attributes. The workflow does not maintain a separate list of
plugin versions.

Each package updater runs independently from the same base revision so that
changes made by one updater cannot contaminate another package's proposal.

The updater uses `nix-update` with the package's flake attribute and its
declared update script:

```sh
nix-update ATTRIBUTE --flake --use-update-script
```

Source edits are recorded separately from the subsequent native build results.

The update stage does not establish that a package builds successfully.
A package may need additional dependency updates or downstream patch repairs.

### Native build validation

The workflow prepares native build jobs from the proposed source changes.

`opendeck-core` and `nekename/starterpack` are validated together in the
default OpenDeck application where appropriate. A combined update must not
be accepted partially if doing so would invalidate the tested application.

The workflow separates:

- **Updater results:** proposed source changes and updater errors.
- **Native build results:** target identity, build outcome, optional dependency
  source edits, and diagnostic excerpts.
- **Finalization state:** validated updates, known package failures,
  infrastructure failures, and reporting information.

Only validated changes are eligible for an update PR.

A known package failure must not suppress unrelated validated updates.
Incomplete, missing, or corrupt reports must not be treated as successful
validation or lead to partially accepted updates.

A successful run that discovers no updates normally produces no PR. Check the
finalization summary before interpreting that as a problem.

### Update PR routing

Validated ordinary updates are grouped into an updater-managed PR eligible
for automatic merging after required checks succeed.

Validated updates requiring downstream patch review are grouped into a
separate manual-review PR.

A single PR may contain several package updates. Grouping is by review
policy, not by package.

The updater's static compatibility analysis can help identify concerns but
does not approve, merge, or certify packages.

If only part of a grouped PR is ready to merge, separate the required source
changes manually rather than assuming each package has its own bot PR.

### Failed update reporting

The updater maintains an `Automated package update failures` issue to report
known package failures, with links to the relevant workflow runs and diagnostic
artifacts.

Source-update artifacts are retained even when a subsequent native build
fails. Build reports may include additional dependency-update edits that are
not present in the original source-update patch.

Diagnostic excerpts are intentionally bounded. Consult the complete workflow
logs when more context is needed.

An updater failure, native build failure, missing report, and GitHub or network
failure are different problems. Investigate the failed stage before selecting
a repair.

## Manually updating and repairing packages

Use a separate repair branch. Do not make maintenance changes directly on
an updater-owned `automated/` branch: subsequent updater runs may replace it.

When repairing a downstream patch for a new upstream version, keep the version,
source hashes, dependency changes, and corresponding patch changes together
in the same PR.

A patch fix that depends on a newer upstream version should not be merged
against the older version alone.

### Starting from an updater PR

When an updater has produced a manual-review PR containing the desired
updated sources, use that proposed revision as a starting point:

```sh
gh pr checkout PR_NUMBER --detach
git switch -c repair/opendeck-core
```

If the bot PR contains multiple packages, retain only the relevant changes
when preparing a focused repair.

Modify the existing downstream patches and any additional version, source
hash, dependency lock, or dependency hash values required for the new release.

There is no need to rerun the updater if the desired source update is already
present in the branch.

### Starting without an updater PR

Start from a clean branch based on `main`:

```sh
git switch main
git pull --ff-only
git switch -c repair/opendeck-core
```

There are two ways to recover the intended update.

#### Option A: Run nix-update locally

Enter the repository's development shell from the repository root:

```sh
nix develop
```

The shell provides `nix-update` from the flake-locked nixpkgs and sets
`NIX_PATH` to the same nixpkgs checkout as the CI updater. Run the same
package update command as CI, for example on x86_64 Linux:

```sh
nix-update packages.x86_64-linux.opendeck-core \
  --flake --use-update-script
```

For a plugin:

```sh
nix-update \
  legacyPackages.x86_64-linux.opendeck-plugins.OWNER.NAME \
  --flake --use-update-script
```

Replace the system, owner, and package name with the appropriate exported
flake attribute. Use the native system appropriate to the package.

To update without entering an interactive shell, use `nix develop -c`:

```sh
nix develop -c nix-update packages.x86_64-linux.opendeck-core \
  --flake --use-update-script
```

Inspect the changes with `git diff` before proceeding.

A local update may select a newer upstream release than the one previously
attempted by CI. Use the workflow artifacts instead if reproducing the exact
failed proposal is important.

Local `nix-update` execution does not reproduce the automation's separate
native dependency-update or build-validation stages. It may also fail when
the declared update script cannot complete.

#### Option B: Recover the update proposed by CI

Open the persistent package-update failure issue and follow its workflow run
link.

Download the appropriate `updates-<system>` artifact. For example:

```sh
gh run download RUN_ID \
  -n updates-x86_64-linux \
  -D /tmp/opendeck-update

find /tmp/opendeck-update -type f -name '*.patch' -print
```

To apply the proposed update for `opendeck-core`:

```sh
git apply --check \
  /tmp/opendeck-update/updates-x86_64-linux/patches/core.patch

git apply \
  /tmp/opendeck-update/updates-x86_64-linux/patches/core.patch
```

Use the patch corresponding to the affected package. Do not apply unrelated
updates simply because they were produced by the same workflow run.

These artifacts are retained for seven days. An updater failure may prevent
a proposed source patch from being produced at all.

A recovered source update is a proposal, not proof of a working build.
Inspect native `build-<target>-<system>` artifacts and workflow logs for
additional `sourceEdits` or useful error diagnostics.

### Completing the repair

After obtaining the desired updated source:

1. Adapt the existing downstream patches with the smallest changes necessary.
2. Include any required dependency source, lock-file, or hash changes.
3. Test the affected package locally.
4. Inspect and commit the complete intended changes.
5. Open a non-draft PR targeting `main`.
6. Review the automatic checks, native reproducibility results, and final
   combined diff before merging.

For example:

```sh
nix build .#opendeck -L
nix flake check --no-build --all-systems
git diff --check
```

Use the appropriate package-specific `nix build` command for plugin repairs.

The PR verification workflows validate the combined committed state, not the
individual intermediate development steps.

A repair branch does not need to dispatch the full `Update packages` workflow.
The ordinary PR checks are sufficient for the repository's required
verification process.

A patch repair that works independently with the current upstream version
may be proposed separately, but a version-dependent repair must include its
corresponding version update.

## Updater PR ownership and cleanup

Automated update branches are managed by the updater. A later update can
replace their contents, so manual repairs should use separate branches.

`ci/reconcile_update_prs.py` identifies bot-authored updater PRs that have
been superseded by changes already merged into `main`.

The reconciliation is deliberately conservative:

- It considers only the known updater-managed branches.
- It verifies the bot identity and current PR head.
- It compares the actual changed source files with `main`.
- It closes a PR only when every proposed source change is already present.

Matching package version numbers alone does not prove that two PRs contain
equivalent source changes.

If a repair modifies an updater's proposed source files further, automatic
cleanup may leave the original bot PR open. Review it and close it manually
when appropriate.

Cleanup is best effort. GitHub API or branch-deletion failures produce
warnings and must not invalidate otherwise successful package updates.

Closing an updater PR before its proposed version reaches `main` may result
in the updater proposing that version again.

## AI-assisted update analysis

AI analysis is advisory. It does not determine whether a package builds,
whether an update is accepted, or whether a PR may merge.

### Successful-build compatibility analysis

`ci/upstream_compatibility.py` examines validated updates that use downstream
patches.

It identifies checked-in patch references and, for supported upstream source
layouts, looks for new upstream code paths that might bypass patched code.

This is a bounded static analysis, not a native build or functional test.

Patched updates require manual review regardless of the analysis outcome.

If the upstream layout or analysis service is unsupported or unavailable,
report that limitation rather than treating it as evidence of compatibility.

### Failed-build diagnosis

`ci/failure_audit.py` selects failures with concrete evidence of downstream
patch problems.

Eligible cases include patch-application errors and supported compiler errors
associated with changed, downstream-patched source.

Generic compiler failures, network errors, updater errors, and infrastructure
failures do not automatically justify an AI diagnosis.

The process separates deterministic selection, persistent reservation,
analysis, and publication.

Reservations prevent repeated analysis of the same proposed source and patch
combination, including when an earlier request timed out.

A materially different proposal can be analysed separately.

A reservation is not evidence that analysis succeeded. The original failure,
build logs, and source changes remain authoritative.

The AI service's credentials do not grant repository write access or approve
changes. GitHub operations use the separately authorized automation identity.

## Binary cache management

`cache.yml` evaluates supported native package targets using
`ci/targets.nix`.

It only publishes outputs explicitly identified as redistributable by the
relevant package metadata.

Missing or restrictive license metadata excludes a package from publication
without preventing that package from being built or tested.

The workflow checks the corresponding Cachix narinfo before deciding to
build and publish a missing output.

A cache lookup failure is an infrastructure problem, not evidence that the
OpenDeck package cannot build.

The cache workflow supports manual dispatch for recovering missing outputs
after a failure.

Cache publication must remain separate from untrusted PR code execution.
Do not add `CACHIX_AUTH_TOKEN` or equivalent publication credentials to PR
verification workflows.

The package-update, nixpkgs-update, and reproducibility spot-check workflows
share a maintenance concurrency group to avoid overlapping maintenance
operations.

PR verification has separate per-PR cancellation groups. Cache publication
has its own concurrency configuration.

## Repository configuration

The automation depends on the following GitHub configuration.

| Setting | Purpose |
| --- | --- |
| `trusted-automation` environment | Restrict jobs receiving sensitive automation credentials |
| `AUTOMATION_APP_CLIENT_ID` | Identify the GitHub App used for trusted automation |
| `AUTOMATION_APP_PRIVATE_KEY` | Create short-lived App tokens |
| `UPDATE_MAINTAINERS` | Identify maintainers for update-related review and failure assignments |
| `GEMINI_API_KEY` | Enable optional static compatibility and failure analysis |
| `CACHIX_AUTH_TOKEN` | Authorize redistributable binary-cache publication |
| Required commit statuses | Enforce trusted tests and reproducibility verification before merging |
| Up-to-date merge protection | Prevent merging a PR whose verification is stale relative to the base |
| Fork workflow approval policy | Restrict unapproved external contributors from consuming CI resources |

The App token is used only by authorized workflows. Untrusted PR code must
not receive it.

`UPDATE_MAINTAINERS` is required for the updater's manual-review routing.
AI availability must not determine whether a validated package update passes
its native verification.

Secrets must not appear in build logs, generated source diffs, untrusted
workflow environments, or PR-authored executable code.

Repository settings and required-status protection are maintained in GitHub;
they are not all represented by this repository's YAML files.

## Diagnosing failures

### Package update problems

Start with the `Update packages` workflow summary.

Inspect the failed stage:

| Job | Investigate |
| --- | --- |
| `discover` | Flake evaluation, target discovery, updater availability |
| `update` | Upstream release discovery, source hash updates, updater scripts |
| `prepare-builds` | Proposed patches, target selection, build preparation |
| `plugins` | Native plugin builds and dependency problems |
| `opendeck` | Native OpenDeck/core integration and bundled-plugin builds |
| `finalize` | Validation reports, PR creation, issue updates and GitHub API operations |

For a package failure, inspect the persistent failure issue, the relevant
source-update artifact, native build report, and full build logs.

For an incomplete or missing report, investigate infrastructure and artifact
handling before treating the package as broken.

### PR checks or auto-merge are stuck

Check both the unprivileged Actions jobs and the trusted App statuses on the
PR head commit.

A successful Actions run is not proof that a trusted status was published.

Inspect the corresponding `Trusted CI report` run when:

- Required statuses are absent or pending.
- An Actions run succeeded but GitHub will not merge the PR.
- Runs were cancelled or superseded.
- The PR changed protected CI files.
- The PR changed between draft and ready states.

Confirm the current PR head and merge revision, draft state, trusted workflow
file comparisons, and authoritative run selection.

Do not weaken reporter checks or mark a result successful manually to work
around an unexplained verification failure.

### Cache publication fails

Inspect `Build and publish binary cache`.

Determine whether the failure occurred during:

1. Target evaluation.
2. Cache availability lookup.
3. Native package building.
4. Upload to Cachix.

A failed HTTP request or temporary GitHub infrastructure problem does not
necessarily require rebuilding the package.

### A bot PR remains open unexpectedly

Check whether the proposed source files actually match `main`.

Inspect the updater cleanup result and associated warnings.

If the PR is obsolete but cannot satisfy the conservative equality check,
close it manually after reviewing the diff.

Do not rerun expensive native builds merely to troubleshoot PR cleanup.

## Making changes safely

Run the relevant local checks from the repository root:

```sh
python3 -m unittest discover -s .github/ci -p 'test_*.py'
nix flake check --no-build --all-systems
nix flake check
git diff --check
```

For package updates, also build the affected outputs on their supported
native systems.

For downstream OpenDeck patches:

- Minimize the amount of upstream code changed.
- Prefer small, focused, additive changes where practical.
- Modify an existing relevant patch instead of layering another patch over it.
- Preserve unchanged upstream lines as context.
- Avoid replacing whole functions when a small change is sufficient.
- Preserve unrelated upstream behaviour, plugin state, settings, and profiles.
- Keep Nix compatibility fixes separate from Home Manager-specific policy.
- Verify patch application against the pinned upstream source, formatting,
  compilation, and relevant functionality.

For CI changes:

1. Identify the actual failure mode or invariant before modifying the workflow.
2. Prefer the smallest change that addresses it.
3. Preserve the separation between untrusted PR execution and privileged
   status publication.
4. Preserve exact commit and workflow identity verification.
5. Never interpret missing artifacts, skipped jobs, cancelled verification,
   or inconclusive AI output as success.
6. Do not trust verification policy files modified by the PR under review.
7. Add focused regression tests for changed decision logic.
8. Check GitHub Actions event and permission behaviour where applicable.
9. Update this guide when maintenance procedures or meaningful CI behaviour
   change.

The Python tests are intentionally network-free where practical. Passing
tests do not prove native builds, GitHub Actions event ordering, App
permissions, or Cachix availability.

Treat CI as a mechanism for validating the repository's packages and
protecting releases, not as a reason to introduce additional abstractions
or maintenance work without a demonstrated benefit.
