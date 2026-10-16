#!/usr/bin/env bash
# Runs the unit tests headless.
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_godot

godot_import
# --no-data-fetch: autoloads also start in script mode; tests must never hit the network.
"$GODOT" --headless --path "$CLIENT_DIR" -s res://tests/run_tests.gd -- --no-data-fetch
