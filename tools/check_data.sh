#!/usr/bin/env bash
# Loads game data and sample sprites from the configured source and prints a summary.
# Check a mirror with: tools/check_data.sh --data-url=https://example.com/data/ --sprite-url=https://example.com/sprites/
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_godot

godot_import
"$GODOT" --headless --path "$CLIENT_DIR" -- --check-data "$@" 2>&1 | grep -E "^\[automation\]|Game data|ERROR|WARNING"
exit "${PIPESTATUS[0]}"
