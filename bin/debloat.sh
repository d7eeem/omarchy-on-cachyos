#!/bin/bash
set -euo pipefail

# Opt-in launcher for a-la-carchy — an interactive TUI debloater for
# Omarchy v3 by Daniel Coffey (https://github.com/DanielCoffey1/a-la-carchy).
# Not vendored (upstream has no license grant); fetched at run time, pinned
# to a reviewed commit and checksum-verified so upstream changes never flow
# here unreviewed. Bump ALC_PIN/ALC_SHA256 together after re-reviewing.

ALC_PIN="f6a02bf3043ed1088f351f5914a7e99b134e35c4"          # a-la-carchy commit this repo has reviewed
ALC_SHA256="8cae9a9099b2d6d3b5cdcb40683b0c2f3fe33e518f99d5dca84fcdbefe0eb620"    # sha256 of a-la-carchy.sh at that commit
ALC_URL="https://raw.githubusercontent.com/DanielCoffey1/a-la-carchy/${ALC_PIN}/a-la-carchy.sh"

# Guard: a-la-carchy targets Omarchy v3 (waybar-era). Quattro (v4) installs
# should use Omarchy's own omarchy-remove-preinstalls instead.
if [[ -d /usr/share/omarchy && ! -d "$HOME/.local/share/omarchy" ]]; then
    echo "a-la-carchy targets Omarchy v3; on Omarchy 4 use omarchy-remove-preinstalls instead."
    exit 1
fi

if [[ ! -d "$HOME/.local/share/omarchy" ]]; then
    echo "No Omarchy v3 install found at $HOME/.local/share/omarchy."
    exit 1
fi

TMPFILE="$(mktemp)"
trap 'rm -f "$TMPFILE"' EXIT

echo "Downloading a-la-carchy (pinned commit ${ALC_PIN})..."
if ! curl -fsSL "$ALC_URL" -o "$TMPFILE"; then
    echo "Error: failed to download a-la-carchy from $ALC_URL"
    exit 1
fi

DOWNLOADED_SHA256="$(sha256sum "$TMPFILE" | awk '{print $1}')"
if [[ "$DOWNLOADED_SHA256" != "$ALC_SHA256" ]]; then
    echo "Error: checksum mismatch for a-la-carchy.sh"
    echo "  expected: $ALC_SHA256"
    echo "  got:      $DOWNLOADED_SHA256"
    echo "Upstream content changed since this repo last reviewed it; refusing to run unreviewed third-party code."
    echo "Re-review and bump ALC_PIN/ALC_SHA256 in bin/debloat.sh."
    exit 1
fi

echo ""
echo "a-la-carchy is a third-party interactive TUI (not maintained by this repo)."
echo "It will ask for your sudo password itself and only removes packages/webapps"
echo "you individually select and confirm. You can Ctrl-C out at any time."
read -r -p "Launch a-la-carchy? [y/N] " REPLY
if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    echo "Not launching a-la-carchy."
    exit 0
fi

bash "$TMPFILE"
rc=$?
exit $rc
