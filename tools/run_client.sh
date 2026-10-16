#!/usr/bin/env bash
# Starts the client with the repo's plugins/ folder available and the example plugin enabled.
# Extra arguments are passed to the client, e.g.: tools/run_client.sh --server=local --name=Chris
set -euo pipefail
source "$(dirname "$0")/common.sh"

"$GODOT" --path "$CLIENT_DIR" -- --plugins-dir="$PLUGINS_DIR" --enable-plugins=battle-stats "$@"
