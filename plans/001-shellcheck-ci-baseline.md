# Plan 001: Establish a shellcheck + syntax-check CI baseline

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat ed6ae20..HEAD -- bin/ .github/`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: dx
- **Planned at**: commit `ed6ae20`, 2026-08-17 (post-rebase onto mroboff/omarchy-on-cachyos main)

## Why this matters

This repository is ~300 lines of Bash whose job is to modify a user's freshly
installed operating system. It has **no CI, no linting, and no syntax checking
of any kind** — a broken quoting change ships straight to end users' machines.
The upstream repo's open PR queue is dominated by path/robustness bugs
(PRs #50, #51, #56, #59, #69, #71, #72 all address variants of the same
class), several of which shellcheck or a review gate would have flagged. This
plan creates the verification baseline that every other plan in `plans/` uses
as its quality gate.

## Current state

- `bin/install-omarchy-on-cachyos.sh` — main installer (no `set -e`; known
  CWD-dependent paths — plan 002's problem, not yours).
- `bin/fetch-omarchy.sh` — interactive version-selection clone helper (added
  upstream via PR #48; has unquoted expansions shellcheck will flag).
- `bin/nvidia.sh` — NVIDIA detect-and-respect config (rewritten upstream via
  PR #47).
- `bin/gpu-detect.sh`, `bin/gpu-setup.sh`, `bin/amd-rocm.sh` — GPU helpers
  (local commits, not yet integrated).
- `.github/` contains only `FUNDING.yml`. There is **no** `.github/workflows/`
  directory.
- No lint config, no Makefile, no test framework. `shellcheck` was not
  installed on the planning machine, so CI is the authoritative gate; local
  checks use `bash -n`.

Known pre-existing shellcheck findings you must NOT fix in this plan (owned by
other plans): CWD-dependent paths and non-fatal error branches in
`install-omarchy-on-cachyos.sh` (plan 002), unquoted `$BRANCH_ARGS`/array
handling in `fetch-omarchy.sh` (plan 002), unquoted `$HOME` redirect in
`amd-rocm.sh` (plan 004). To keep this plan purely additive, the workflow
starts at `severity: error` (see Step 1's rationale).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Syntax check all scripts | `for f in bin/*.sh; do bash -n "$f" || echo "FAIL: $f"; done` | no FAIL lines (6 scripts) |
| Validate workflow YAML | `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/lint.yml'))"` | exit 0 (skip if PyYAML missing; note it) |

## Scope

**In scope** (the only files you should create/modify):
- `.github/workflows/lint.yml` (create)
- `plans/README.md` (status row update)

**Out of scope** (do NOT touch):
- Any file in `bin/` — this plan adds the gate only; fixes belong to plans 002–009.
- `github/funding.yml` / `.github/FUNDING.yml` — plan 010.

## Git workflow

- Branch: `advisor/001-shellcheck-ci-baseline`
- Single commit; imperative capitalized message (matches repo history), e.g.
  `Add shellcheck and bash syntax CI workflow`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Create the workflow file

Create `.github/workflows/lint.yml` with exactly this content:

```yaml
name: lint

on:
  push:
    branches: [main]
  pull_request:

jobs:
  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Bash syntax check
        run: |
          set -e
          for f in bin/*.sh; do
            bash -n "$f"
            echo "OK: $f"
          done
      - name: ShellCheck
        uses: ludeeus/action-shellcheck@2.0.0
        with:
          scandir: ./bin
          severity: error
```

Rationale for `severity: error`: the repo has pre-existing `warning`-level
findings owned by plans 002–009. Gating on `error` makes CI green today while
still catching syntax-level breakage. After plans 002–009 land, tighten to
`severity: warning` (plan 010 carries that step).

**Verify**: `test -f .github/workflows/lint.yml && echo present` → `present`

### Step 2: Confirm the scripts pass the syntax gate locally

```
for f in bin/*.sh; do bash -n "$f" && echo "OK: $f"; done
```

**Verify**: six `OK:` lines (amd-rocm, fetch-omarchy, gpu-detect, gpu-setup,
install-omarchy-on-cachyos, nvidia), exit 0. All six passed at planning time —
a failure means drift: STOP.

### Step 3: Update the plans index

Set plan 001's status to DONE in `plans/README.md`.

**Verify**: `grep -n "001" plans/README.md` shows the updated row.

## Test plan

No test framework exists and none is being introduced. The workflow itself is
the test: once pushed, the `lint` action must run green on GitHub. Local
proxy: Step 2's `bash -n` loop.

## Done criteria

- [ ] `.github/workflows/lint.yml` exists with a shellcheck step scoped to `./bin`
- [ ] `for f in bin/*.sh; do bash -n "$f" || exit 1; done` exits 0
- [ ] `git status --porcelain` shows changes only to `.github/workflows/lint.yml` and `plans/README.md`
- [ ] `plans/README.md` status row updated

## STOP conditions

- A `.github/workflows/` directory already exists with a lint workflow.
- Any script in `bin/` fails `bash -n` at current HEAD.
- You feel compelled to fix a shellcheck finding in `bin/` — another plan's scope.

## Maintenance notes

- Every subsequent plan uses `bash -n` + this CI as its gate. Tightening to
  `severity: warning` happens in plan 010 once `bin/` fixes have landed.
- Reviewer: check the action is pinned to a tag (`@2.0.0`), not `@master`.
- Deferred: bats-core tests for `gpu-detect.sh`/`fetch-omarchy.sh` (needs
  lspci/git mocking; revisit after plan 005 wires the GPU scripts in).
