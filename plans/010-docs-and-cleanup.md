# Plan 010: Fix README inaccuracies, installer typos, and the duplicate funding file

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in "STOP conditions" occurs, stop and report.
>
> **Drift check (run first)**: `git diff --stat f609f6c..HEAD -- README.md bin/install-omarchy-on-cachyos.sh github/ .github/`
> Plans 003/005/006/009 edit README sections — reconcile with their diffs;
> apply this plan's edits to the *current* text, preserving their changes.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: best run last (after 003, 005, 006, 009 settle the README's technical content)
- **Category**: docs
- **Planned at**: commit `f609f6c`, 2026-08-17

## Why this matters

The README is the product's front door and its instructions are followed
verbatim by users about to modify a fresh OS install. It currently
contradicts itself ("does the following three things" followed by four
items), has a broken numbered list (1, 2, 3, 5), an empty heading, and the
installer prints user-facing typos ("deskop", "aboves"). A dead duplicate
funding file (`github/funding.yml` — note lowercase dir; GitHub only reads
`.github/FUNDING.yml`) adds repo noise.

## Current state

`README.md` at f609f6c (section/line refs may shift after plans 003/005/006 —
match on content):

- Line 11: "This installation script does the following three things:" —
  followed by FOUR numbered items (lines 13–16).
- Lines 18–23: the "does not" list is numbered `1) 2) 3) 5)` — no item 4.
- Line 57: `4. Graphics Drivers for NVIDIA users:` — empty item, immediately
  followed by item 5 that actually covers the topic. (Plan 005 rewrites this
  area for AMD; if it already has, skip the parts it fixed.)
- Line 3: "UPDATE 1-October-2025" banner — stale relative to the pin-based
  behavior introduced by plan 003; fold into normal prose or refresh.

`bin/install-omarchy-on-cachyos.sh` user-facing echoes at f609f6c:

```bash
echo "IMPORTANT: If you installed CachyOS without a deskop environment, ..."   # line 125: "deskop"
echo "The aboves script will modify your boot to start Omarchy's Hyprland desktop automatically."  # line 129: "aboves"
```

Also line 117 echoes reference "packages.sh" while the actual patched file is
`install/omarchy-base.packages` — align the wording with whatever plan 003
left in place.

Funding duplicates (byte-identical content):
- `.github/FUNDING.yml` — the one GitHub reads. KEEP.
- `github/funding.yml` — dead duplicate in a lowercase non-special directory
  (added by commit `19f33aa`, superseded by `b270cfc`). DELETE (this removes
  the now-empty `github/` directory too).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Syntax check | `bash -n bin/install-omarchy-on-cachyos.sh` | exit 0 |
| Typo sweep | `grep -rn "deskop\|aboves" bin/ README.md` | no matches (after fix) |
| Funding check | `test -f .github/FUNDING.yml && test ! -e github` | exit 0 (after fix) |

## Scope

**In scope**:
- `README.md`
- `bin/install-omarchy-on-cachyos.sh` — echo strings ONLY (no logic)
- `github/funding.yml` (delete; directory disappears with it)

**Out of scope**:
- `.github/FUNDING.yml` (keep byte-identical)
- Any non-echo line of the installer
- Technical claims owned by other plans (login model → 006, AMD → 005,
  mise/pin → 003) — do not re-litigate their wording, only mechanical fixes.

## Git workflow

- Branch: `advisor/010-docs-and-cleanup`
- Commits: one for README+echoes, one for the funding file removal.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Fix README list mechanics

- "three things" → "four things" (or reword to "does the following:"), so the
  count matches the items.
- Renumber the "does not" list to 1–4.
- Merge/renumber the §4 prerequisites so no empty heading remains (fold the
  empty "Graphics Drivers" item into the item that follows it, unless plan
  005 already restructured this — then just verify numbering).

**Verify**: `grep -n "three things" README.md` → no matches;
`awk '/does not:/,/^$/' README.md` shows sequential numbering.

### Step 2: Fix installer echo typos and stale references

- `deskop` → `desktop`; `The aboves script` → `The above script`.
- Align the "packages.sh" echo with the real filename used by the patch list
  in the current script text.

**Verify**: `grep -rn "deskop\|aboves" bin/` → no matches;
`bash -n bin/install-omarchy-on-cachyos.sh` → exit 0.

### Step 3: Remove the duplicate funding file

`git rm github/funding.yml` (leaves `.github/FUNDING.yml` untouched).

**Verify**: `test ! -e github && test -f .github/FUNDING.yml && echo ok` → `ok`;
`git diff --cached --stat` (or `git status`) shows only the deletion.

## Test plan

Mechanical text changes; the greps above are the tests. Read the final README
§§1–5 top to bottom once and confirm no list numbering is broken — record
"read-through done" in your report.

## Done criteria

- [ ] `grep -rn "deskop\|aboves\|three things" README.md bin/` → 0 matches
- [ ] No numbered list in README skips a number
- [ ] `github/` directory gone; `.github/FUNDING.yml` unchanged (`git diff .github/` empty)
- [ ] `bash -n bin/install-omarchy-on-cachyos.sh` exits 0
- [ ] Only in-scope files + `plans/README.md` modified
- [ ] `plans/README.md` status row updated
- [ ] (If plan 001 landed) tighten `.github/workflows/lint.yml` shellcheck
      `severity: error` → `severity: warning` per plan 001's maintenance note,
      and confirm CI-equivalent locally: `bash -n` all scripts

## STOP conditions

- README sections referenced here were substantially rewritten by plans
  003/005/006 in ways that already fixed these items — skip the fixed ones,
  report which.
- `.github/FUNDING.yml` and `github/funding.yml` are NOT identical — decide
  nothing; report the diff (someone edited one copy).

## Maintenance notes

- Reviewer: pure text/deletion diff; check nothing in the installer's logic
  lines changed (`git diff` should show only quoted strings).
- The stale "UPDATE 1-October-2025" banner pattern will recur — suggest the
  maintainer keep a short CHANGELOG section in README instead of dated
  banners (deferred; editorial call).
