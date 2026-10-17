#!/usr/bin/env bash
# Runs the unit tests headless.
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_godot

# Tests change settings and write files under user://, so unless XDG_DATA_HOME is set they get
# a fresh, temporary user data dir (Linux) instead of your real settings, themes and sounds.
if [ -z "${XDG_DATA_HOME:-}" ]; then
  TEST_DATA_DIR="$(mktemp -d)"
  trap 'rm -rf "$TEST_DATA_DIR"' EXIT
  export XDG_DATA_HOME="$TEST_DATA_DIR"
fi

godot_import
# --no-data-fetch: autoloads also start in script mode; tests must never hit the network.
# --settings-file: a throwaway settings file, so tests never change the user's settings.
SETTINGS_DIR="$(mktemp -d)"
trap 'rm -rf "$SETTINGS_DIR"' EXIT
"$GODOT" --headless --path "$CLIENT_DIR" -s res://tests/run_tests.gd -- --no-data-fetch \
  --settings-file="$SETTINGS_DIR/settings.cfg"
