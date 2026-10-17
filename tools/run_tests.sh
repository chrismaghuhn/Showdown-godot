#!/usr/bin/env bash
# Runs the unit tests headless.
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_godot

# Everything created here is removed on exit (one trap: a second `trap ... EXIT` would replace it).
# The ${a[@]+...} form keeps an empty array legal under `set -u` in bash 3.2 (macOS), and a
# failed rm must not change the tests' exit code.
CLEANUP=()
trap 'rm -rf ${CLEANUP[@]+"${CLEANUP[@]}"} || true' EXIT

# Tests change settings and write files under user://, so unless XDG_DATA_HOME is set they get
# a fresh, temporary user data dir (Linux) instead of your real settings, themes and sounds.
if [ -z "${XDG_DATA_HOME:-}" ]; then
  TEST_DATA_DIR="$(mktemp -d)"
  CLEANUP+=("$TEST_DATA_DIR")
  export XDG_DATA_HOME="$TEST_DATA_DIR"
fi

godot_import
# --no-data-fetch: autoloads also start in script mode; tests must never hit the network.
# --settings-file: a throwaway settings file, also where XDG_DATA_HOME doesn't apply (macOS,
# Windows), so tests never change the user's settings.
SETTINGS_DIR="$(mktemp -d)"
CLEANUP+=("$SETTINGS_DIR")
"$GODOT" --headless --path "$CLIENT_DIR" -s res://tests/run_tests.gd -- --no-data-fetch \
  --settings-file="$SETTINGS_DIR/settings.cfg"
