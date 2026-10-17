#!/usr/bin/env bash
# Runs the unit tests headless.
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_godot

godot_import
# --no-data-fetch: autoloads also start in script mode; tests must never hit the network.
# --settings-file: a throwaway settings file, so tests never change the user's settings.
"$GODOT" --headless --path "$CLIENT_DIR" -s res://tests/run_tests.gd -- --no-data-fetch \
  --settings-file="$(mktemp -d)/settings.cfg"
