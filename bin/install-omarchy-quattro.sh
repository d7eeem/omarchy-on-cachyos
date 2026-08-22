#!/bin/bash
set -euo pipefail

# install-omarchy-quattro.sh — package-install wrapper for Omarchy 4
# ("Quattro"). Quattro ships as Arch packages applied by omarchy-apply-system.
# This script adds the omarchy repo, installs the
# packages, runs the apply stages, and reconciles the parts of that process
# that would otherwise clobber CachyOS state (pacman.conf, mirrorlist, boot
# hooks, snapper, user configs), then verifies the result with an assertion
# suite. See plans/012-omarchy-quattro-install.md for the design rationale.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMARCHY_KEY_ID="F0134EE680CAC571"
OMARCHY_REPO_SERVER='https://pkgs.omarchy.org/stable/$arch'
TIMESTAMP="$(date +%Y%m%d%H%M%S)"

DRY_RUN=false
ASSUME_YES=false

# ---------------------------------------------------------------------------
# The dry-run contract: every state-changing command flows through one of
# these two helpers. In --dry-run mode they print the command instead of
# running it, so review can enforce "no sudo outside run_root" with a single
# grep and "no state changes in --dry-run" by inspection of this file.
# ---------------------------------------------------------------------------
run() {
    if $DRY_RUN; then
        echo "DRYRUN: $*"
    else
        "$@"
    fi
}

run_root() {
    if $DRY_RUN; then
        echo "DRYRUN: sudo $*"
    else
        sudo "$@"
    fi
}

# Write $2 as the contents of privileged file $1 via sudo tee, or announce the
# intent and write nothing when dry-running. Content comes from stdin so
# callers can use a heredoc; that keeps quoting simple for multi-line config.
write_root_file() {
    local dest="$1"
    if $DRY_RUN; then
        echo "DRYRUN: write $dest"
        cat >/dev/null
    else
        sudo tee "$dest" >/dev/null
    fi
}

append_root_file() {
    local dest="$1"
    if $DRY_RUN; then
        echo "DRYRUN: append to $dest"
        cat >/dev/null
    else
        sudo tee -a "$dest" >/dev/null
    fi
}

usage() {
    cat <<USAGE
Usage: $(basename "$0") [--dry-run] [--yes]

  --dry-run   Print every state-changing command (prefixed DRYRUN:) instead
              of executing it. Read-only detection (bootloader, LUKS, GPU,
              current pacman/mkinitcpio state) still runs for real.
  --yes       Skip the confirmation prompt.
USAGE
}

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --yes) ASSUME_YES=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; usage >&2; exit 1 ;;
    esac
done

echo "=== install-omarchy-quattro.sh ==="
$DRY_RUN && echo "(dry-run mode: no privileged or state-changing commands will execute)"
echo ""

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

if [[ $EUID -eq 0 ]]; then
    echo "Error: do not run this script as root. It calls sudo itself where needed." >&2
    exit 1
fi

if ! command -v pacman &>/dev/null; then
    echo "Error: pacman not found. This script targets an Arch-based system (CachyOS)." >&2
    exit 1
fi

# CachyOS detection: prefer the release file, fall back to the presence of a
# cachyos repo stanza in pacman.conf (this repo's own test machine has no
# /etc/cachyos-release but does have [cachyos] repos, so both are checked).
IS_CACHYOS=false
if [[ -f /etc/cachyos-release ]]; then
    IS_CACHYOS=true
elif grep -qE '^\[cachyos' /etc/pacman.conf 2>/dev/null; then
    IS_CACHYOS=true
fi

if ! $IS_CACHYOS; then
    echo "Warning: this does not look like a CachyOS system (no /etc/cachyos-release and no [cachyos*] repo in /etc/pacman.conf)."
    echo "This script's reconciliation logic (pacman.conf/mirrorlist restore, boot hook handling) assumes CachyOS."
    if ! $ASSUME_YES; then
        read -r -p "Continue anyway? [y/N] " reply
        [[ $reply =~ ^[Yy]$ ]] || { echo "Aborting."; exit 1; }
    fi
fi

# Bootloader detection: read-only, via installed packages (avoids needing
# root to read /boot, which is 0700 on this class of system).
BOOTLOADER="unknown"
if pacman -Qq limine &>/dev/null; then
    BOOTLOADER="limine"
elif pacman -Qq grub &>/dev/null; then
    BOOTLOADER="grub"
elif pacman -Qq systemd-boot &>/dev/null || command -v bootctl &>/dev/null && bootctl is-installed &>/dev/null; then
    BOOTLOADER="systemd-boot"
fi

# LUKS detection: either a crypto_LUKS block device or a non-comment
# /etc/crypttab entry counts.
LUKS_DETECTED=false
if lsblk -o FSTYPE 2>/dev/null | grep -q crypto_LUKS; then
    LUKS_DETECTED=true
elif [[ -f /etc/crypttab ]] && grep -vE '^\s*#|^\s*$' /etc/crypttab &>/dev/null; then
    LUKS_DETECTED=true
fi

# Capture the EFFECTIVE current mkinitcpio HOOKS the same way mkinitcpio
# itself resolves them: source /etc/mkinitcpio.conf, then every
# /etc/mkinitcpio.conf.d/*.conf in lexical order (later files win). This is
# the array we must re-assert after Omarchy's own omarchy_hooks.conf lands,
# because mkinitcpio conf.d assignments replace HOOKS wholesale rather than
# merging it.
CURRENT_HOOKS=""
if [[ -f /etc/mkinitcpio.conf ]]; then
    CURRENT_HOOKS="$(
        HOOKS=()
        # shellcheck disable=SC1091
        source /etc/mkinitcpio.conf 2>/dev/null || true
        shopt -s nullglob
        for f in /etc/mkinitcpio.conf.d/*.conf; do
            # shellcheck disable=SC1090
            source "$f" 2>/dev/null || true
        done
        echo "${HOOKS[*]}"
    )"
fi

if $LUKS_DETECTED && [[ $CURRENT_HOOKS != *encrypt* ]]; then
    echo "Error: LUKS was detected but the current effective mkinitcpio HOOKS contain no encrypt/sd-encrypt hook (HOOKS=($CURRENT_HOOKS))." >&2
    echo "Refusing to continue — capturing this as the 'known good' HOOKS to re-assert would not protect boot." >&2
    exit 1
fi

# GPU vendor: read-only lspci probe via this repo's own detector.
GPU_TYPE="$(bash "$SCRIPT_DIR/gpu-detect.sh")"

REPO_ALREADY_PRESENT=false
grep -qE '^\[omarchy\]' /etc/pacman.conf 2>/dev/null && REPO_ALREADY_PRESENT=true

echo "Plan summary:"
echo "  CachyOS system:        $IS_CACHYOS"
echo "  Bootloader:             $BOOTLOADER"
echo "  LUKS detected:          $LUKS_DETECTED"
echo "  Current mkinitcpio HOOKS: ($CURRENT_HOOKS)"
echo "  GPU vendor:              $GPU_TYPE"
echo "  [omarchy] repo present: $REPO_ALREADY_PRESENT"
echo "  Target user:             $USER"
echo ""
echo "This will: add the omarchy repo (if missing), install omarchy-settings/omarchy/omarchy-nvim,"
echo "run omarchy-apply-system, then reconcile pacman.conf, mirrorlist, mkinitcpio HOOKS, snapper,"
echo "boot-loader integration, and your user configs so CachyOS state survives."
echo ""

if ! $ASSUME_YES && ! $DRY_RUN; then
    read -r -p "Proceed? [y/N] " reply
    [[ $reply =~ ^[Yy]$ ]] || { echo "Aborting."; exit 1; }
fi

# ---------------------------------------------------------------------------
# Repo + keyring
# ---------------------------------------------------------------------------

echo ""
echo "--- Repo + keyring ---"

# Bootstraps trust for the very first transaction that fetches omarchy-keyring
# itself (the package's own postinstall, if any, takes over from there).
run_root pacman-key --recv-keys "$OMARCHY_KEY_ID"
run_root pacman-key --lsign-key "$OMARCHY_KEY_ID"

if $REPO_ALREADY_PRESENT; then
    echo "[omarchy] repo already present in /etc/pacman.conf, skipping append."
else
    printf '\n[omarchy]\nSigLevel = Required DatabaseOptional\nServer = %s\n' "$OMARCHY_REPO_SERVER" |
        append_root_file /etc/pacman.conf
fi

# ---------------------------------------------------------------------------
# Pre-install reconciliation
#
# This MUST happen before the pacman transaction that installs omarchy (Step
# below), not merely before omarchy-apply-system: omarchy-settings ships
# /etc/mkinitcpio.conf.d/omarchy_hooks.conf, and the omarchy package depends
# on limine-mkinitcpio-hook, a pacman hook that can rebuild the initramfs as
# part of the SAME transaction that lays that file down. Writing our
# HOOKS-preserving drop-in only right before omarchy-apply-system would be
# too late to protect that first automatic rebuild.
# ---------------------------------------------------------------------------

echo ""
echo "--- Pre-install reconciliation ---"

PACMAN_CONF_BACKUP="/etc/pacman.conf.omarchy-quattro-backup-$TIMESTAMP"
MIRRORLIST_BACKUP="/etc/pacman.d/mirrorlist.omarchy-quattro-backup-$TIMESTAMP"
run_root cp -a /etc/pacman.conf "$PACMAN_CONF_BACKUP"
if [[ -f /etc/pacman.d/mirrorlist ]]; then
    run_root cp -a /etc/pacman.d/mirrorlist "$MIRRORLIST_BACKUP"
fi

SNAPPER_CONFIG=/etc/snapper/configs/root
SNAPPER_BACKUP="/etc/snapper/configs/root.omarchy-quattro-backup-$TIMESTAMP"
if [[ -f $SNAPPER_CONFIG ]]; then
    run_root cp -a "$SNAPPER_CONFIG" "$SNAPPER_BACKUP"
else
    echo "No existing $SNAPPER_CONFIG to back up."
fi

# HOOKS-preserving drop-in. "zz-" sorts after "omarchy_hooks.conf"
# alphabetically, so it is sourced last and wins per mkinitcpio's conf.d
# semantics (later assignment replaces HOOKS wholesale).
ZZ_HOOKS_CONF=/etc/mkinitcpio.conf.d/zz-cachyos-keep-hooks.conf
if [[ -n $CURRENT_HOOKS ]]; then
    run_root mkdir -p /etc/mkinitcpio.conf.d
    printf '# Written by install-omarchy-quattro.sh: re-assert the pre-install HOOKS\n# so a package-shipped mkinitcpio.conf.d file (e.g. omarchy_hooks.conf) cannot\n# silently switch initramfs generation styles (encrypt vs sd-encrypt) and\n# break boot. Sorts after "omarchy_hooks.conf" so this wins.\nHOOKS=(%s)\n' "$CURRENT_HOOKS" |
        write_root_file "$ZZ_HOOKS_CONF"
else
    echo "Warning: could not determine current mkinitcpio HOOKS; skipping zz-cachyos-keep-hooks.conf." >&2
fi

# SDDM: /etc/sddm.conf (if present) outranks every file in /etc/sddm.conf.d/,
# and Omarchy's SDDM theme/session config ships as package-owned
# sddm.conf.d/*.conf files. Remove any stale /etc/sddm.conf before those
# land so they actually take effect (PR #28 / plan 006 rationale).
if [[ -f /etc/sddm.conf ]]; then
    echo "Removing stale /etc/sddm.conf so package-shipped sddm.conf.d drop-ins win."
    run_root rm -f /etc/sddm.conf
fi

# ---------------------------------------------------------------------------
# Install packages
# ---------------------------------------------------------------------------

echo ""
echo "--- Installing omarchy packages ---"
run_root pacman -Syu --needed --noconfirm omarchy-settings omarchy omarchy-nvim

# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------

echo ""
echo "--- Running omarchy-apply-system ---"
run_root omarchy-apply-system --install-user "$USER" --first-install

# ---------------------------------------------------------------------------
# Post-apply pacman reconciliation
#
# Ordered immediately after apply-system returns, and before GPU dispatch:
# install/post-install/pacman.sh (run inside apply-system) does
# `cp -f .../pacman-stable.conf /etc/pacman.conf` and the matching mirrorlist,
# wiping the CachyOS repos. amd-rocm.sh's own `sudo pacman -S rocm-core ...`
# call needs those repos back BEFORE it runs, so this cannot wait until the
# very end of the script.
# ---------------------------------------------------------------------------

echo ""
echo "--- Post-apply pacman.conf/mirrorlist reconciliation ---"
run_root cp -a "$PACMAN_CONF_BACKUP" /etc/pacman.conf
if [[ -f $MIRRORLIST_BACKUP ]]; then
    run_root cp -a "$MIRRORLIST_BACKUP" /etc/pacman.d/mirrorlist
fi
# Defense in depth: the backup already contains [omarchy] (it was taken after
# the repo/keyring step above), but re-check/append in case that invariant
# ever changes.
if $DRY_RUN; then
    echo "DRYRUN: ensure [omarchy] stanza present in restored /etc/pacman.conf"
else
    if ! grep -qE '^\[omarchy\]' /etc/pacman.conf; then
        printf '\n[omarchy]\nSigLevel = Required DatabaseOptional\nServer = %s\n' "$OMARCHY_REPO_SERVER" |
            append_root_file /etc/pacman.conf
    fi
fi
run_root pacman -Sy --noconfirm

# ---------------------------------------------------------------------------
# User-level seeding for the existing user
#
# omarchy-apply-system's --install-user only drives root-owned hardware setup
# (omarchy-apply-hardware). Per-user config seeding is a separate, user-run
# step: /etc/skel only fires at useradd, so an already-existing user is
# re-synced via omarchy-reinstall-configs (replays /etc/skel over $HOME) and
# then omarchy-provision-user --first-install (== "omarchy finalize user",
# runtime tweaks /etc/skel can't do: xdg dirs, skill symlinks, install/user/*).
# ---------------------------------------------------------------------------

echo ""
echo "--- User-level config seeding ---"

if [[ -f /etc/skel/.bashrc || -d /etc/skel ]]; then
    HOME_BACKUP_DIR="$HOME/.omarchy-quattro-backup-$TIMESTAMP"
    if $DRY_RUN; then
        echo "DRYRUN: back up \$HOME entries shadowed by /etc/skel to $HOME_BACKUP_DIR before omarchy-reinstall-configs"
    else
        mkdir -p "$HOME_BACKUP_DIR"
        shopt -s dotglob nullglob
        for entry in /etc/skel/*; do
            name="$(basename "$entry")"
            if [[ -e "$HOME/$name" ]]; then
                mkdir -p "$(dirname "$HOME_BACKUP_DIR/$name")"
                cp -a "$HOME/$name" "$HOME_BACKUP_DIR/$name"
            fi
        done
        shopt -u dotglob nullglob
        echo "Backed up pre-existing \$HOME entries shadowed by /etc/skel to $HOME_BACKUP_DIR"
    fi
else
    echo "No /etc/skel found; skipping pre-seeding backup (nothing omarchy-reinstall-configs would overwrite)."
fi

if command -v omarchy-reinstall-configs &>/dev/null; then
    run omarchy-reinstall-configs
else
    echo "Warning: omarchy-reinstall-configs not found on PATH; skipping user config resync." >&2
fi

if command -v omarchy-provision-user &>/dev/null; then
    run omarchy-provision-user --first-install
else
    echo "Warning: omarchy-provision-user not found on PATH; skipping user finalization." >&2
fi

# Fish integrations (mise + zoxide): Omarchy only wires these for Bash. Lives
# in the user's fish config so it survives upstream changes.
FISH_CONF_DIR="$HOME/.config/fish/conf.d"
FISH_CONF_FILE="$FISH_CONF_DIR/omocachy.fish"
if $DRY_RUN; then
    echo "DRYRUN: write $FISH_CONF_FILE"
else
    mkdir -p "$FISH_CONF_DIR"
    cat >"$FISH_CONF_FILE" <<'EOF'
# Added by omocachy
if status is-interactive
    command -q mise; and mise activate fish | source
    command -q zoxide; and zoxide init fish | source
end
EOF
fi

# GPU dispatch: this repo's vendor dispatcher (nvidia.sh respects whatever
# CachyOS driver is present; amd-rocm.sh installs the AMDGPU/ROCm profile).
# Runs after the pacman.conf restore above so its own internal `sudo pacman
# -S` calls see the CachyOS repos.
echo ""
echo "--- GPU setup ---"
case "$GPU_TYPE" in
    nvidia) echo "Detected NVIDIA GPU -> dispatch target: bin/nvidia.sh (via gpu-setup.sh)" ;;
    amd)    echo "Detected AMD GPU -> dispatch target: bin/amd-rocm.sh (via gpu-setup.sh)" ;;
    none)   echo "No GPU detected -> gpu-setup.sh will no-op" ;;
esac
run bash "$SCRIPT_DIR/gpu-setup.sh"

# ---------------------------------------------------------------------------
# Remaining post-apply reconciliation
# ---------------------------------------------------------------------------

echo ""
echo "--- Snapper reconciliation ---"
if [[ -f $SNAPPER_BACKUP ]]; then
    run_root cp -a "$SNAPPER_BACKUP" "$SNAPPER_CONFIG"
else
    echo "No pre-install snapper backup was taken; leaving Omarchy's $SNAPPER_CONFIG in place."
fi

echo ""
echo "--- Bootloader reconciliation ---"
if [[ $BOOTLOADER == "limine" ]]; then
    echo "limine is the active bootloader; leaving Omarchy's limine integration (limine-snapper-sync, limine-mkinitcpio-hook) active."
else
    echo "Active bootloader is '$BOOTLOADER', not limine; disabling Omarchy's limine integration."
    run_root systemctl disable --now limine-snapper-sync.service

    # Neuter limine-mkinitcpio-hook without touching the package-owned hook
    # file: pacman.conf(5) documents that hooks in a later HookDir
    # (/etc/pacman.d/hooks, the default custom dir) take precedence over a
    # same-named hook in the system dir (/usr/share/libalpm/hooks). Dropping
    # a same-named hook whose Trigger matches nothing fully overrides it in a
    # pacman-safe way: it survives package upgrades/removals untouched, and
    # deleting our override file restores stock behavior.
    # (This lookup is read-only and runs in both modes so --dry-run can name
    # the actual file it would override instead of speaking generically.)
    hook_files="$(pacman -Ql limine-mkinitcpio-hook 2>/dev/null | awk '{print $2}' | grep '\.hook$' || true)"
    if [[ -z $hook_files ]]; then
        echo "Warning: limine-mkinitcpio-hook package not found or ships no .hook file; nothing to override." >&2
    else
        run_root mkdir -p /etc/pacman.d/hooks
        while IFS= read -r hf; do
            [[ -z $hf ]] && continue
            base="$(basename "$hf")"
            override="/etc/pacman.d/hooks/$base"
            printf '[Trigger]\nType = Path\nOperation = Install\nOperation = Upgrade\nOperation = Remove\nTarget = var/lib/omocachy/never-matches\n\n[Action]\nDescription = Disabled by omocachy (non-limine bootloader)\nWhen = PostTransaction\nExec = /usr/bin/true\n' |
                write_root_file "$override"
            echo "Overrode $hf with a no-op at $override"
        done <<<"$hook_files"
    fi
fi

echo ""
echo "--- Rebuilding initramfs ---"
run_root mkinitcpio -P

# ---------------------------------------------------------------------------
# Assertion suite
# ---------------------------------------------------------------------------

echo ""
echo "--- Assertion suite ---"

ASSERT_FAILED=false

assert() {
    local desc="$1" ok="$2"
    if $DRY_RUN; then
        echo "WOULD ASSERT: $desc"
        return 0
    fi
    if $ok; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc" >&2
        ASSERT_FAILED=true
    fi
}

if $DRY_RUN; then
    assert "CachyOS repos present in /etc/pacman.conf and [omarchy] present" true
    assert "effective mkinitcpio HOOKS still contain the pre-install encrypt hook (if LUKS) and zz-cachyos-keep-hooks.conf exists" true
    assert "non-limine machine has limine-snapper-sync.service disabled" true
    assert "sddm enabled; NetworkManager enabled" true
    assert "/etc/sddm.conf absent (sddm.conf.d drop-ins take effect)" true
    assert "/etc/snapper/configs/root matches the pre-install backup" true
    assert "the v4 CLI entrypoint (omarchy) is present" true
else
    cachyos_repo_ok=false
    grep -qE '^\[cachyos' /etc/pacman.conf 2>/dev/null && cachyos_repo_ok=true
    omarchy_repo_ok=false
    grep -qE '^\[omarchy\]' /etc/pacman.conf 2>/dev/null && omarchy_repo_ok=true
    if $cachyos_repo_ok && $omarchy_repo_ok; then repo_ok=true; else repo_ok=false; fi
    assert "CachyOS repos present in /etc/pacman.conf and [omarchy] present" "$repo_ok"

    hooks_ok=true
    [[ -f $ZZ_HOOKS_CONF ]] || hooks_ok=false
    if $LUKS_DETECTED; then
        effective_hooks_now="$(
            HOOKS=()
            # shellcheck disable=SC1091
            source /etc/mkinitcpio.conf 2>/dev/null || true
            shopt -s nullglob
            for f in /etc/mkinitcpio.conf.d/*.conf; do
                # shellcheck disable=SC1090
                source "$f" 2>/dev/null || true
            done
            echo "${HOOKS[*]}"
        )"
        [[ $effective_hooks_now == *encrypt* ]] || hooks_ok=false
    fi
    assert "effective mkinitcpio HOOKS still contain the pre-install encrypt hook (if LUKS) and zz-cachyos-keep-hooks.conf exists" "$hooks_ok"

    if [[ $BOOTLOADER == "limine" ]]; then
        assert "non-limine machine has limine-snapper-sync.service disabled (n/a: limine is the bootloader)" true
    else
        limine_service_ok=true
        systemctl is-enabled --quiet limine-snapper-sync.service 2>/dev/null && limine_service_ok=false
        assert "non-limine machine has limine-snapper-sync.service disabled" "$limine_service_ok"
    fi

    sddm_nm_ok=true
    systemctl is-enabled --quiet sddm.service 2>/dev/null || sddm_nm_ok=false
    systemctl is-enabled --quiet NetworkManager.service 2>/dev/null || sddm_nm_ok=false
    assert "sddm enabled; NetworkManager enabled" "$sddm_nm_ok"

    # A fresh CachyOS install (or any tool) may recreate /etc/sddm.conf after
    # the pre-install removal above; it silently outranks every sddm.conf.d
    # drop-in, so its absence is part of the contract, not just a setup step.
    sddm_conf_ok=true
    [[ -f /etc/sddm.conf ]] && sddm_conf_ok=false
    assert "/etc/sddm.conf absent (sddm.conf.d drop-ins take effect)" "$sddm_conf_ok"

    snapper_ok=true
    if [[ -f $SNAPPER_BACKUP ]]; then
        cmp -s "$SNAPPER_BACKUP" "$SNAPPER_CONFIG" || snapper_ok=false
    fi
    assert "/etc/snapper/configs/root matches the pre-install backup" "$snapper_ok"

    cli_ok=false
    command -v omarchy &>/dev/null && cli_ok=true
    assert "the v4 CLI entrypoint (omarchy) is present" "$cli_ok"
fi

if $ASSERT_FAILED; then
    echo "" >&2
    echo "One or more post-install assertions failed. See FAIL lines above." >&2
    exit 1
fi

echo ""
echo "Done."
