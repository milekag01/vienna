#!/usr/bin/env bash
# Install vienna CLI — creates a symlink in /usr/local/bin
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_PATH="$SCRIPT_DIR/bin/vienna.sh"
LINK_PATH="/usr/local/bin/vienna"

if [[ ! -f "$BIN_PATH" ]]; then
    echo "Error: vienna.sh not found at $BIN_PATH"
    exit 1
fi

chmod +x "$BIN_PATH"

if [[ -L "$LINK_PATH" ]]; then
    echo "Removing existing symlink at $LINK_PATH"
    rm "$LINK_PATH"
elif [[ -f "$LINK_PATH" ]]; then
    echo "Error: $LINK_PATH already exists and is not a symlink"
    exit 1
fi

ln -s "$BIN_PATH" "$LINK_PATH"
echo "Installed: vienna → $BIN_PATH"
echo ""
echo "You can now run 'vienna' from anywhere."
echo "  vienna help           Show usage"
echo "  vienna spawn <name> --branch <branch>"
echo "  vienna list"
echo "  vienna destroy <name>"
