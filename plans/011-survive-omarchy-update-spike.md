# Plan 011: Design spike — keep CachyOS patches alive across `omarchy-update`, and chart the v4 path (investigate)

> **SCOPE UPDATE 2026-08-17 (post plan-003 execution)**: Upstream Omarchy
> v4.0.0 removed `install.sh` entirely — v4 installs via Arch packages
> (`omarchy`, `omarchy-settings`, `omarchy-keyring`) applied by
> `omarchy-apply-system` as root from an ISO chroot, with
> `OMARCHY_PATH=/usr/share/omarchy`. This repo now pins to v3.8.4 and refuses
> v4+ trees. This spike therefore has a second, more strategic question:
> **(B2) what does "Omarchy on CachyOS" even mean for v4?** Candidate shapes
> to evaluate alongside the original three designs: (i) stay a v3.8.x
> installer and freeze (EOL risk as upstream moves on); (ii) become a v4
> *package-install wrapper* — add the omarchy pacman repo, install the
> `omarchy`/`omarchy-settings`/`omarchy-keyring` packages, then run
> `omarchy-apply-system --install-user $USER --first-install` with
> CachyOS-specific pre/post adjustments (no more clone-and-patch at all);
> (iii) track a fork. Investigate (ii) concretely: read
> `bin/omarchy-apply-system`, `install/hardware/pacman.sh`, and
> `install/login/all.sh` in the v4 tree and enumerate which CachyOS
> conflicts (pacman.conf ownership, SDDM, wpa_supplicant/iwd, walker pin,
> tealdeer/tldr) still exist in v4 and where they would be neutralized.
> The `omarchy-update` survival question below remains relevant for the
> v3.8.4-pinned present, but weight the recommendation toward the v4 path.

> **Executor instructions**: This is a DESIGN SPIKE. The deliverable is a
> written design appended to this file — no production code changes. You may
> write throwaway experiments in a scratch directory. Run the verification
> steps (they check the *investigation*, not code). If anything in "STOP
> conditions" occurs, stop and report.
>
> **Drift check (run first)**: `git diff --stat f609f6c..HEAD -- bin/install-omarchy-on-cachyos.sh`
> Expected drift from plans 002–005. The facts to re-verify are upstream's
> update mechanism (Step 1), not this repo's files.

## Status

- **Priority**: P2 (highest-impact structural gap; scheduled late because it builds on 003)
- **Effort**: M (spike only; implementation is a follow-up plan)
- **Risk**: LOW (no production changes in this plan)
- **Depends on**: plans/003-fix-drifted-patches-and-pin-upstream.md
- **Category**: direction
- **Planned at**: commit `f609f6c`, 2026-08-17

## Why this matters

The installer copies the *patched* Omarchy tree — including its `.git`
directory — to `~/.local/share/omarchy`, and Omarchy's self-update tooling
(`omarchy-update`) operates on that checkout via git. The consequences today:

- The working tree is dirty (sed-modified files) or, after plan 003, at a
  pinned commit. The first `omarchy-update` a user runs will either refuse,
  conflict, or **overwrite every CachyOS patch** — silently reverting the
  tldr removal, the pacman.conf protections, the nvidia.sh replacement, and
  the login-step removals.
- Users then re-encounter exactly the bugs this project exists to fix, with
  no signal that their install has reverted to stock Omarchy behavior.

This is the project's biggest structural gap: it currently delivers a correct
*install* but not a correct *system over time*. The spike produces a decided,
scoped design for making updates safe, which becomes plan 012.

## Current state

`bin/install-omarchy-on-cachyos.sh:108-136` at f609f6c:

```bash
# Copy omarchy installation files to ~/.local/share/omarchy
mkdir -p ~/.local/share/omarchy
cp -r . ~/.local/share/omarchy
cd ~/.local/share/omarchy
...
chmod +x install.sh
./install.sh
```

(`cp -r .` from inside the patched clone — includes `.git`.)

Upstream facts to (re)verify in Step 1 — planning-time snapshot 2026-08-17:
`basecamp/omarchy` ships `bin/omarchy-update` (plus `omarchy-update-*`
helpers) and treats `~/.local/share/omarchy` (exported as `$OMARCHY_PATH` in
`config/uwsm/env`) as a git checkout it updates.

Related repo facts: plan 003 introduces `OMARCHY_PIN` (the tested upstream
commit) and `patch_or_die` (hard-verified patching) — both are building
blocks any design here should reuse.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Read the updater | `git clone --quiet https://github.com/basecamp/omarchy /tmp/claude-omarchy-spike && sed -n 1,80p /tmp/claude-omarchy-spike/bin/omarchy-update` | script contents |
| Find update entry points | `grep -rn "git pull\|git fetch\|git reset" /tmp/claude-omarchy-spike/bin/ \| head -20` | the update mechanism's git commands |
| Find hook points | `grep -rn "migration\|hook\|post-update" /tmp/claude-omarchy-spike/bin/ /tmp/claude-omarchy-spike/install/ \| head -20` | whether an extension point exists |

## Scope

**In scope**:
- This plan file (append the design)
- Scratch experiments under the session scratchpad or `/tmp` (never committed)

**Out of scope**:
- ANY change to `bin/` or `README.md` — implementation is plan 012, written
  after the maintainer approves a direction.

## Steps

### Step 1: Establish exactly how `omarchy-update` mutates the checkout

From a scratch clone, read `bin/omarchy-update` and its helpers. Answer in
writing: does it `git pull` (merge), `git reset --hard` to a remote ref, or
run migrations? How does it behave on (a) a dirty tree, (b) a detached HEAD
at `OMARCHY_PIN`, (c) local commits on top of upstream? Test (a)–(c)
empirically in the scratch clone — dirty a file, detach HEAD, commit locally,
then run the updater's *git commands manually* (never the updater itself if
it installs packages; extract just its git operations).

**Verify**: a table of (state → updater behavior) with the exact git commands
quoted, appended to this file.

### Step 2: Evaluate three candidate designs

Assess each against: patch survival, user experience on update day, failure
visibility, and maintenance cost. Use Step 1's facts, not intuition.

1. **Fork-branch model** — installer commits the CachyOS patches as real git
   commits on a local branch (`cachyos/main`) atop `OMARCHY_PIN`; updates
   become `git fetch` + rebase of the patch commits onto the new upstream
   ref, with `patch_or_die`-style verification after rebase. Conflicts
   surface as explicit rebase failures.
2. **Re-patch hook** — leave the checkout as stock upstream tracking; store
   the patch script (extracted from the installer into e.g.
   `bin/apply-cachyos-patches.sh`) and arrange for it to re-run after every
   update. Requires an upstream hook point (does `omarchy-update` have one?
   — Step 1) or wrapping/shadowing `omarchy-update` in `$PATH` (evaluate
   honestly: shadowing upstream binaries is fragile and surprising).
3. **Documented manual model** — the checkout stays pinned/patched;
   `omarchy-update` is expected to fail or be discouraged, and this project
   ships its own `omarchy-on-cachyos-update` that bumps the pin and
   re-patches. Simplest to reason about; diverges most from stock Omarchy UX.

### Step 3: Write the recommendation

Append to this file: the chosen design, why the others lost (cite Step 1
evidence), the file-level implementation sketch (which scripts change, what
new script is added, what the update-day UX is), open questions for the
maintainer, and a S/M/L estimate for plan 012.

### Step 4: Clean up

Remove scratch clones (`rm -rf /tmp/claude-omarchy-spike` and any others).

## Test plan

Spike-grade evidence standard: every behavioral claim about `omarchy-update`
must be backed by either a quoted line from its source or a reproduced
experiment in the scratch clone (state the commands run and their output).

## Done criteria

- [ ] Step 1 table appended (updater behavior on clean/dirty/detached/local-commit states, with quoted git commands)
- [ ] All three designs evaluated against the four criteria
- [ ] One recommendation with implementation sketch and open questions
- [ ] No changes outside this file (`git status --porcelain` shows only `plans/`)
- [ ] Scratch directories removed
- [ ] `plans/README.md` status row updated (DONE = design delivered, awaiting maintainer decision)

## STOP conditions

- `omarchy-update` no longer exists upstream or the update mechanism is not
  git-based — the premise changed; document what you found and stop.
- The updater's flow can't be exercised safely (e.g. it is inseparable from
  package installation) — analyze from source only and say so; do not run
  package operations on this machine.

## Spike results (executed 2026-08-17; full evidence in the executor transcript — key facts and decision below)

### Question A — update survival at v3.8.4: the premise was wrong in our favor

`omarchy-update` (v3.8.4) runs `git -C $OMARCHY_PATH pull --autostash` under
`set -e`. Because this installer clones with `-b v3.8.4` (a TAG), the
`~/.local/share/omarchy` checkout is a **detached HEAD with no upstream
tracking** — and `git pull` there fails immediately (empirically reproduced:
"You are not currently on a branch", exit 1) whether the tree is clean or
dirty. Nothing downstream (package updates, migrations, hooks) ever runs.
**CachyOS patches are never reverted — the entire update path is a loud dead
end instead.** Users ARE nagged (waybar polls `omarchy-update-available`
every 6h; first-run notification; menu entry), so the click→error UX is real.

Designs evaluated: fork-branch (works mechanically — rebase experiments
passed — but requires a whole new update command for a version line upstream
has abandoned); re-patch hook (`~/.config/omarchy/hooks/post-update.d/` is
real and durable but **unreachable** — it only fires after the `git pull`
that always fails; making it reachable means abandoning the pin);
**documented manual model — CHOSEN**: updates = re-run this installer
against a newer `TESTED_OMARCHY_REF`; document that `omarchy-update` is not
usable (its failure is non-destructive). No git-machinery code change —
the accidental fail-closed behavior is load-bearing; do not "fix" it.

### Question B — the v4 path: package-install wrapper (option ii) chosen

`omarchy-apply-system` requires root + an existing user and has no ISO
guard, but every stage is a blank-chroot full-apply (mass `cp -R` over
`~/.config`, unconditional snapper/pacman.conf clobbers); its `--upgrade`
flag is a **no-op** (zero references to `$OMARCHY_UPGRADE` under install/).
Upstream's own live-migration path is the separate, far more careful
2370-line `omarchy-upgrade-to-quattro` (config hashing, backups, surgical
awk pacman.conf edit, service transitions) — strong evidence apply-system is
chroot-only in practice, and the right model to adapt.

v4 conflict status: walker pin **moot** (walker/elephant retired for a
quickshell suite); iwd conflict **likely resolved** (v4 disables iwd,
NetworkManager by default — verify vs CachyOS defaults); `/etc/sddm.conf`
monolith **gone** (drop-ins only); tldr **unchanged**; pacman.conf clobber
**worse** in the ISO path, surgical in the upgrade path;
plymouth/limine **now package-owned drop-ins** (post-fix reconciliation or
NoExtract, not sed); nvidia.sh kernel-header regex **still misses
linux-cachyos kernels**.

Wrapper sketch: add omarchy repo+keyring → pacman-install
omarchy/omarchy-settings/omarchy-keyring/omarchy-nvim → run install stages
with CachyOS pre/post reconciliation around the known clobber points →
replace `patch_or_die` with a **post-apply assertion suite** (package-owned
files can't be sed-patched). Effort: **M** fresh-install-only; **L** with an
in-place v3.8.4→v4 upgrade path.

Open questions for the maintainer: (1) CachyOS network default vs v4's
NetworkManager switch; (2) access to the omarchy-pkgs PKGBUILD repo for
dependency review; (3) adapt `omarchy-upgrade-to-quattro` as a library vs
reference; (4) fresh-install-only or also in-place upgrades (drives M vs L).

**Implementation is plan 012 — do not start without maintainer sign-off.**

## Maintenance notes

- The chosen design becomes plan 012; do not start it without maintainer
  sign-off (this is a strategy decision, not a bug fix).
- Whoever implements plan 012 must update plan 003's pin-bump ritual to match
  the new update flow.
