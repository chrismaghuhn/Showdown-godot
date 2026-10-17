#!/usr/bin/env bash
# End-to-end tests of the app's UI flows against the local server (tools/local_server.sh).
# Each flow in client/tests/e2e/<name>_flow.gd drives the real app (cards, tabs, keys):
#   sign_in_flow    sign in through the card, sign out, a taken name shows an inline error
#   app_shell_flow  start screen -> quick battle -> battle tab -> restart -> rejoin with Enter
#   lobby_flow      searchable formats, a challenge round trip (sent, declined, cancelled,
#                   declined, accepted), then a ladder battle and the rating in the lobby
# Usage: tools/e2e_ui.sh [flow ...]   (default: all flows)
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_godot
godot_import

FLOWS=("$@")
if [ ${#FLOWS[@]} -eq 0 ]; then
  for f in "$CLIENT_DIR"/tests/e2e/*_flow.gd; do FLOWS+=("$(basename "$f" .gd)"); done
fi

STATUS=0
SETTINGS_DIR="$(mktemp -d)"
trap 'rm -rf "$SETTINGS_DIR"' EXIT
for flow in "${FLOWS[@]}"; do
  LOG="$(mktemp)"
  echo "--- $flow"
  "$GODOT" --headless --path "$CLIENT_DIR" -s res://tests/e2e/run.gd -- --no-data-fetch --screen=start --e2e="$flow" \
    --settings-file="$SETTINGS_DIR/$flow-settings.cfg" \
    >"$LOG" 2>&1 || STATUS=1
  grep -E "\[e2e\]|ERROR" "$LOG" || true
  if grep -qE "^(SCRIPT )?ERROR" "$LOG"; then
    echo "!! errors in the log ($LOG)"
    STATUS=1
  fi
done
[ $STATUS -eq 0 ] && echo "E2E UI: OK" || echo "E2E UI: FAILED"
exit $STATUS
