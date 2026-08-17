#!/bin/bash

# The Omarchy version this repo's CachyOS patches are tested against.
# Update when re-verifying the patch set (see plans/003).
TESTED_OMARCHY_REF="v3.8.4"

# Target destination (relative to this script's location)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${OMARCHY_DIR:-$(dirname "$SCRIPT_DIR")/omarchy}"
REPO_URL="https://github.com/basecamp/omarchy"

# Fetch available stable version tags from the remote repository cleanly
echo "Fetching available stable releases from GitHub..."
RELEASES=($(git ls-remote --tags --refs $REPO_URL 2>/dev/null | awk -F/ '{print $3}' | sort -rV | head -n 5))

echo "-----------------------------------------------"
echo "Select the Omarchy version you want to install:"
echo "-----------------------------------------------"
echo "1) Bleeding Edge (dev/main branch - Unstable)"

# Dynamically list the stable versions fetched from the repository
for i in "${!RELEASES[@]}"; do
    if [ "${RELEASES[i]}" = "$TESTED_OMARCHY_REF" ]; then
        echo "$((i+2))) Stable Release (${RELEASES[i]}) (tested)"
    else
        echo "$((i+2))) Stable Release (${RELEASES[i]})"
    fi
done

read -r -p "Enter your choice (1-$(( ${#RELEASES[@]} + 1 ))): " CHOICE

if [[ -n "$CHOICE" && ! "$CHOICE" =~ ^[0-9]+$ ]] || { [[ -n "$CHOICE" ]] && (( CHOICE < 1 || CHOICE > ${#RELEASES[@]} + 1 )); }; then
    echo "Invalid choice '$CHOICE'. Defaulting to Bleeding Edge."
    CHOICE=1
fi

# Formulate arguments based on selection
if [ "$CHOICE" -eq 1 ] || [ -z "$CHOICE" ]; then
    BRANCH_ARGS=""
    SELECTED_TAG=""
    echo "Cloning bleeding-edge dev tree..."
else
    SELECTED_TAG="${RELEASES[$((CHOICE-2))]}"
    BRANCH_ARGS="-b $SELECTED_TAG"
    echo "Cloning stable version: $SELECTED_TAG..."
fi

# The safe path is the tested version. Anything else (bleeding edge, or a
# stable tag other than TESTED_OMARCHY_REF) requires explicit confirmation:
# Omarchy v4.0.0+ removed install.sh and switched to a package/ISO-based
# install architecture that this repo's clone-and-patch approach cannot
# support, and other versions are only verified at patch time (see
# patch_or_die in bin/install-omarchy-on-cachyos.sh), not guaranteed to work.
if [ -z "$SELECTED_TAG" ] || [ "$SELECTED_TAG" != "$TESTED_OMARCHY_REF" ]; then
    echo ""
    echo "Warning: Omarchy v4.0.0+ removed install.sh and is not supported by this installer."
    echo "CachyOS patches are tested against $TESTED_OMARCHY_REF; other versions are verified at patch time and will abort on mismatch, but are not guaranteed to work end-to-end."
    read -r -p "Continue with untested version anyway? [y/N]: " GOAHEAD
    if [[ ! "${GOAHEAD,,}" =~ ^(y|yes)$ ]]; then
        echo "Aborting. Re-run and select the tested version ($TESTED_OMARCHY_REF) to proceed."
        exit 1
    fi
fi

# Ensure target directory is clean before git cloning to prevent fatal conflicts
if [ -d "$TARGET_DIR" ]; then
    echo ""
    echo "⚠️  Warning: An existing installation directory was found at $TARGET_DIR"
    read -r -p "Would you like to delete it and proceed with a clean install? [y/N]: " CONFIRM
    
    if [[ "${CONFIRM,,}" =~ ^(y|yes)$ ]]; then
        echo "Cleaning up previous installation files at $TARGET_DIR..."
        rm -rf "$TARGET_DIR"
    else
        echo "Proceeding with existing files in $TARGET_DIR..."
        # If user chooses not to delete, we should skip the clone but continue the script
        exit 0
    fi
fi

# Execute clean, quiet checkout bypassing standard detached HEAD advice warnings
echo "Cloning into $TARGET_DIR..."
if ! git -c advice.detachedHead=false clone --quiet $BRANCH_ARGS $REPO_URL "$TARGET_DIR"; then
    echo "Error: Failed to clone Omarchy repo."
    exit 1
fi

echo "Successfully cloned Omarchy repository layout."
