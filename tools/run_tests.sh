#!/usr/bin/env bash
# Runs the unit tests headless.
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_godot

godot_import
"$GODOT" --headless --path "$CLIENT_DIR" -s res://tests/run_tests.gd
