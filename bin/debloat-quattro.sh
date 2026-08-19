#!/bin/bash
set -euo pipefail

# Per-item preinstall removal for Omarchy 4 ("Quattro") — an a-la-carte
# alternative to Omarchy's all-or-nothing omarchy-remove-preinstalls.
# Derived from basecamp/omarchy's bin/omarchy-remove-preinstalls and the
# enumeration logic of omarchy-webapp-remove-all / omarchy-tui-remove-all,
# © David Heinemeier Hansson, MIT license. Removal is delegated to Omarchy's
# own tools (omarchy-pkg-drop, omarchy-webapp-remove, omarchy-tui-remove),
# so behavior tracks upstream.

# Test-only overrides (not documented in --help, mock dirs/scripts only):
#   DQ_APP_DIR       — override the .desktop directory scanned for web apps/TUIs
#   DQ_BIN_DIR        — override the directory scanned/targeted for agent CLI stubs
#   DQ_OMARCHY_SCRIPT — override the omarchy-remove-preinstalls copy to parse
# When any of these are set and the mode is --list, the Omarchy-4 guard below
# is relaxed so the enumeration/parsing logic can be exercised on a non-Quattro
# (e.g. v3 development) machine without a real Omarchy 4 install present.

# Fallback snapshots, used only if parsing the installed omarchy-remove-preinstalls
# yields nothing (e.g. upstream reshuffles its script format).
PKG_FALLBACK=(aether cliamp libreoffice-fresh xournalpp pinta obsidian obs-studio kdenlive moonlight-qt lazydocker omacut omacalc omawrite)
STUB_FALLBACK=(codex claude gemini copilot gh opencode playwright playwright-cli pi omp grok crush ghui hunk)

MODE="interactive"
DRY_RUN=0

print_help() {
    cat <<'EOF'
Usage: debloat-quattro.sh [--list|--dry-run|--help]

Per-item preinstall removal for Omarchy 4 (Quattro), an a-la-carte
alternative to Omarchy's built-in omarchy-remove-preinstalls.

  --list      Print enumerated removal candidates per category and exit.
              Read-only; no selection UI, no changes.
  --dry-run   Run the selection UI, but print each removal action with a
              DRYRUN: prefix instead of performing it.
  --help      Show this help and exit.

With no flags, runs interactively: enumerate candidates, let you pick
per-item via gum, confirm, then remove your selections.

Restoring: re-run Omarchy's own omarchy-install-preinstalls to bring
everything back.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --list) MODE="list" ;;
        --dry-run) DRY_RUN=1 ;;
        --help|-h) print_help; exit 0 ;;
        *)
            echo "Unknown argument: $arg" >&2
            print_help >&2
            exit 1
            ;;
    esac
done

# --- Guard -------------------------------------------------------------

test_override_active=0
if [[ -n "${DQ_APP_DIR:-}" || -n "${DQ_BIN_DIR:-}" || -n "${DQ_OMARCHY_SCRIPT:-}" ]]; then
    test_override_active=1
fi

guard_ok=1
if [[ ! -d /usr/share/omarchy ]] || ! command -v omarchy-pkg-drop >/dev/null 2>&1 || ! command -v gum >/dev/null 2>&1; then
    guard_ok=0
fi

if [[ "$guard_ok" -eq 0 ]]; then
    if [[ "$MODE" == "list" && "$test_override_active" -eq 1 ]]; then
        : # test-only relaxation, see comment block above
    else
        echo "Omarchy 4 not detected — this tool is for Quattro installs (v3 users: see bin/debloat.sh)"
        exit 1
    fi
fi

# --- Enumeration ---------------------------------------------------------

APP_DIR="${DQ_APP_DIR:-$HOME/.local/share/applications}"
BIN_DIR="${DQ_BIN_DIR:-$HOME/.local/bin}"
OMARCHY_SCRIPT="${DQ_OMARCHY_SCRIPT:-/usr/share/omarchy/bin/omarchy-remove-preinstalls}"

# Parse the `omarchy-pkg-drop pkg1 pkg2 ...` argument block (possibly
# backslash-continued across lines) out of the installed
# omarchy-remove-preinstalls script.
parse_pkg_list() {
    local script="$1"
    [[ -f "$script" ]] || return 0
    awk '
        /^[[:space:]]*omarchy-pkg-drop([[:space:]]|\\|$)/ { capture=1 }
        capture {
            line = $0
            sub(/^[[:space:]]*omarchy-pkg-drop/, "", line)
            cont = (line ~ /\\[[:space:]]*$/)
            gsub(/\\[[:space:]]*$/, "", line)
            n = split(line, words)
            for (i = 1; i <= n; i++) if (words[i] != "") print words[i]
            if (!cont) capture = 0
        }
    ' "$script" 2>/dev/null || true
}

# Parse the `rm -f ~/.local/bin/name1 ~/.local/bin/name2 ...` stub-removal
# block (possibly backslash-continued) out of the installed
# omarchy-remove-preinstalls script.
parse_stub_list() {
    local script="$1"
    [[ -f "$script" ]] || return 0
    awk '
        /^[[:space:]]*rm -f ~\/\.local\/bin\// { capture=1 }
        capture {
            line = $0
            cont = (line ~ /\\[[:space:]]*$/)
            gsub(/\\[[:space:]]*$/, "", line)
            n = split(line, words)
            for (i = 1; i <= n; i++) {
                w = words[i]
                if (w ~ /^~\/\.local\/bin\//) {
                    sub(/^~\/\.local\/bin\//, "", w)
                    print w
                }
            }
            if (!cont) capture = 0
        }
    ' "$script" 2>/dev/null || true
}

pkg_warning=""
mapfile -t parsed_pkgs < <(parse_pkg_list "$OMARCHY_SCRIPT")
if [[ "${#parsed_pkgs[@]}" -eq 0 ]]; then
    parsed_pkgs=("${PKG_FALLBACK[@]}")
    pkg_warning="Warning: could not parse the package list from $OMARCHY_SCRIPT; using the built-in snapshot (may be stale)."
fi

stub_warning=""
mapfile -t parsed_stubs < <(parse_stub_list "$OMARCHY_SCRIPT")
if [[ "${#parsed_stubs[@]}" -eq 0 ]]; then
    parsed_stubs=("${STUB_FALLBACK[@]}")
    stub_warning="Warning: could not parse the agent CLI stub list from $OMARCHY_SCRIPT; using the built-in snapshot (may be stale)."
fi

# Packages: filter the parsed/fallback list to what's actually installed.
pkg_candidates=()
if command -v pacman >/dev/null 2>&1; then
    declare -A installed_exact=()
    while IFS= read -r name; do
        installed_exact[$name]=1
    done < <(pacman -Qq 2>/dev/null || true)
    for pkg in "${parsed_pkgs[@]}"; do
        if [[ -n "${installed_exact[$pkg]:-}" ]]; then
            pkg_candidates+=("$pkg")
        fi
    done
fi

# Web apps / TUIs: same enumeration grep patterns as upstream's
# omarchy-webapp-remove-all / omarchy-tui-remove-all.
webapp_candidates=()
tui_candidates=()
if [[ -d "$APP_DIR" ]]; then
    while IFS= read -r -d '' file; do
        if grep -q "Exec=omarchy-launch-webapp\|Exec=omarchy-webapp-handler" "$file" 2>/dev/null; then
            webapp_candidates+=("$(basename "${file%.desktop}")")
        elif grep -q "Exec=xdg-terminal-exec --app-id=TUI\." "$file" 2>/dev/null; then
            tui_candidates+=("$(basename "${file%.desktop}")")
        fi
    done < <(find "$APP_DIR" -maxdepth 1 -name '*.desktop' -print0 2>/dev/null)
fi

# Agent CLI stubs: which of the parsed/fallback stub names exist in BIN_DIR.
stub_present=()
for stub in "${parsed_stubs[@]}"; do
    if [[ -e "$BIN_DIR/$stub" ]]; then
        stub_present+=("$stub")
    fi
done

# --- --list mode -----------------------------------------------------------

if [[ "$MODE" == "list" ]]; then
    echo "Packages:"
    if [[ "${#pkg_candidates[@]}" -eq 0 ]]; then
        echo "  (none)"
    else
        for p in "${pkg_candidates[@]}"; do echo "  $p"; done
    fi
    [[ -n "$pkg_warning" ]] && echo "  $pkg_warning"

    echo "Web apps:"
    if [[ "${#webapp_candidates[@]}" -eq 0 ]]; then
        echo "  (none)"
    else
        for w in "${webapp_candidates[@]}"; do echo "  $w"; done
    fi

    echo "TUIs:"
    if [[ "${#tui_candidates[@]}" -eq 0 ]]; then
        echo "  (none)"
    else
        for t in "${tui_candidates[@]}"; do echo "  $t"; done
    fi

    echo "Agent CLI stubs:"
    if [[ "${#stub_present[@]}" -eq 0 ]]; then
        echo "  (none)"
    else
        echo "  Agent CLI stubs (${stub_present[*]})"
    fi
    [[ -n "$stub_warning" ]] && echo "  $stub_warning"

    exit 0
fi

# --- Selection UI ------------------------------------------------------

any_candidates=0
[[ "${#pkg_candidates[@]}" -gt 0 || "${#webapp_candidates[@]}" -gt 0 || "${#tui_candidates[@]}" -gt 0 || "${#stub_present[@]}" -gt 0 ]] && any_candidates=1

if [[ "$any_candidates" -eq 0 ]]; then
    echo "Nothing removable found."
    exit 0
fi

selected_pkgs=()
if [[ "${#pkg_candidates[@]}" -gt 0 ]]; then
    mapfile -t selected_pkgs < <(gum choose --no-limit --header "Packages" "${pkg_candidates[@]}")
else
    echo "No packages found — skipping."
fi

selected_webapps=()
if [[ "${#webapp_candidates[@]}" -gt 0 ]]; then
    mapfile -t selected_webapps < <(gum choose --no-limit --header "Web apps" "${webapp_candidates[@]}")
else
    echo "No web apps found — skipping."
fi

selected_tuis=()
if [[ "${#tui_candidates[@]}" -gt 0 ]]; then
    mapfile -t selected_tuis < <(gum choose --no-limit --header "TUIs" "${tui_candidates[@]}")
else
    echo "No TUIs found — skipping."
fi

stubs_selected=0
if [[ "${#stub_present[@]}" -gt 0 ]]; then
    stub_label="Agent CLI stubs (${stub_present[*]})"
    mapfile -t stub_choice < <(gum choose --no-limit --header "Agent CLI stubs" "$stub_label")
    [[ "${#stub_choice[@]}" -gt 0 ]] && stubs_selected=1
else
    echo "No agent CLI stubs found — skipping."
fi

total_selected=$(( ${#selected_pkgs[@]} + ${#selected_webapps[@]} + ${#selected_tuis[@]} + (stubs_selected * ${#stub_present[@]}) ))

if [[ "$total_selected" -eq 0 ]]; then
    echo "Nothing selected."
    exit 0
fi

# --- Summary + confirm ---------------------------------------------------

echo ""
echo "Selected for removal:"
if [[ "${#selected_pkgs[@]}" -gt 0 ]]; then
    echo "  Packages: ${selected_pkgs[*]}"
fi
if [[ "${#selected_webapps[@]}" -gt 0 ]]; then
    echo "  Web apps: ${selected_webapps[*]}"
fi
if [[ "${#selected_tuis[@]}" -gt 0 ]]; then
    echo "  TUIs: ${selected_tuis[*]}"
fi
if [[ "$stubs_selected" -eq 1 ]]; then
    echo "  Agent CLI stubs: ${stub_present[*]}"
fi
echo ""

if ! gum confirm "Remove the $total_selected selected items?"; then
    echo "Cancelled."
    exit 0
fi

# --- Execution -----------------------------------------------------------

if [[ "${#selected_pkgs[@]}" -gt 0 ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "DRYRUN: omarchy-pkg-drop ${selected_pkgs[*]}"
    else
        omarchy-pkg-drop "${selected_pkgs[@]}"
    fi
fi

for name in "${selected_webapps[@]}"; do
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "DRYRUN: omarchy-webapp-remove $name"
    else
        omarchy-webapp-remove "$name"
    fi
done

for name in "${selected_tuis[@]}"; do
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "DRYRUN: omarchy-tui-remove $name"
    else
        omarchy-tui-remove "$name"
    fi
done

if [[ "$stubs_selected" -eq 1 ]]; then
    for stub in "${stub_present[@]}"; do
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "DRYRUN: rm -f $BIN_DIR/$stub"
        else
            rm -f "$BIN_DIR/$stub"
        fi
    done
fi

# --- Marker semantics ------------------------------------------------------

full_selection=1
[[ "${#pkg_candidates[@]}" -gt 0 && "${#selected_pkgs[@]}" -ne "${#pkg_candidates[@]}" ]] && full_selection=0
[[ "${#webapp_candidates[@]}" -gt 0 && "${#selected_webapps[@]}" -ne "${#webapp_candidates[@]}" ]] && full_selection=0
[[ "${#tui_candidates[@]}" -gt 0 && "${#selected_tuis[@]}" -ne "${#tui_candidates[@]}" ]] && full_selection=0
[[ "${#stub_present[@]}" -gt 0 && "$stubs_selected" -ne 1 ]] && full_selection=0

if [[ "$full_selection" -eq 1 ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "DRYRUN: mkdir -p ~/.local/state/omarchy && touch ~/.local/state/omarchy/preinstalls-removed"
    else
        mkdir -p "$HOME/.local/state/omarchy"
        touch "$HOME/.local/state/omarchy/preinstalls-removed"
    fi
else
    echo "Partial removal: Omarchy's preinstalls-removed flag was left unset, so Hyprland keybindings/menu entries for removed apps may linger until you remove the rest (or re-run omarchy-install-preinstalls to restore)."
fi

if command -v hyprctl >/dev/null 2>&1; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "DRYRUN: hyprctl reload"
    else
        hyprctl reload || true
    fi
fi

echo ""
echo "Restore everything at any time with: omarchy-install-preinstalls"
