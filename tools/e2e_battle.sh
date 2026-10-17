#!/usr/bin/env bash
# End-to-end test: two headless clients log in to the local server (tools/local_server.sh),
# search a random battle, play it with the dev-autopilot plugin and exit when it ends.
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_godot

FORMAT="${1:-gen9randombattle}"
LOG_DIR="$(mktemp -d)"
godot_import

run_bot() {
  "$GODOT" --headless --path "$CLIENT_DIR" -- \
    --plugins-dir="$PLUGINS_DIR" --enable-plugins=dev-autopilot --no-data-fetch \
    --settings-file="$LOG_DIR/$1-settings.cfg" \
    --server=local --name="$1" --search="$FORMAT" --quit-after-battle --timeout=300 \
    >"$LOG_DIR/$1.log" 2>&1
}

run_bot "E2EBotA$RANDOM" & PID_A=$!
sleep 1
run_bot "E2EBotB$RANDOM" & PID_B=$!

STATUS=0
wait $PID_A || STATUS=1
wait $PID_B || STATUS=1

for f in "$LOG_DIR"/*.log; do
  echo "--- $(basename "$f")"
  grep -E "\[automation\]|ERROR|Plugin" "$f" | awk '!seen[$0]++' | head -30 || true
  # Any engine/script error in a client fails the test (the battle screen runs the whole time).
  if grep -qE "^(SCRIPT )?ERROR" "$f"; then
    echo "!! errors in $(basename "$f")"
    STATUS=1
  fi
done
[ $STATUS -eq 0 ] && echo "E2E: OK" || echo "E2E: FAILED (logs in $LOG_DIR)"
exit $STATUS
