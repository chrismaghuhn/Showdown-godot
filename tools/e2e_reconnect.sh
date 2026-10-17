#!/usr/bin/env bash
# End-to-end reconnect test against the local server (tools/local_server.sh): like
# e2e_battle.sh, but bot A talks to the server through tools/net_fault_proxy.py. In turn 3
# the proxy cuts A's connection (like a server restart), in turn 8 it goes silent without
# closing anything (like a pulled network cable) and comes back after 8 s. A must notice,
# reconnect, sign in again, get its battle back and play it to the end, both times.
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_godot

FORMAT="${1:-gen9randombattle}"
PROXY_PORT="${PROXY_PORT:-8001}"
CONTROL_PORT="${CONTROL_PORT:-8002}"
LOG_DIR="$(mktemp -d)"
godot_import

python3 -I "$REPO_ROOT/tools/net_fault_proxy.py" --listen "$PROXY_PORT" --control "$CONTROL_PORT" \
  >"$LOG_DIR/proxy.log" 2>&1 &
PROXY_PID=$!
trap 'kill $PROXY_PID 2>/dev/null || true' EXIT
timeout 10 bash -c "until (echo > /dev/tcp/127.0.0.1/$CONTROL_PORT) 2>/dev/null; do sleep 0.2; done"

run_bot() {
  local name="$1"
  shift
  "$GODOT" --headless --path "$CLIENT_DIR" -- \
    --plugins-dir="$PLUGINS_DIR" --enable-plugins=dev-autopilot --no-data-fetch \
    --settings-file="$LOG_DIR/$name-settings.cfg" \
    --server=local --name="$name" --search="$FORMAT" --quit-after-battle --timeout=300 "$@" \
    >"$LOG_DIR/$name.log" 2>&1
}

BOT_A="E2EReconnA$RANDOM"
BOT_B="E2EReconnB$RANDOM"
run_bot "$BOT_A" --server-url="ws://127.0.0.1:$PROXY_PORT/showdown/websocket" --heartbeat=2 \
  --fault-proxy="$CONTROL_PORT" --faults=3:cut,8:blackhole --fault-hold=8 & PID_A=$!
sleep 1
run_bot "$BOT_B" & PID_B=$!

STATUS=0
wait $PID_A || STATUS=1
wait $PID_B || STATUS=1

for f in "$LOG_DIR"/*.log; do
  echo "--- $(basename "$f")"
  grep -E "\[automation\]|\[proxy\]|ERROR|Plugin" "$f" | awk '!seen[$0]++' | head -40 || true
  if grep -qE "^(SCRIPT )?ERROR" "$f"; then
    echo "!! errors in $(basename "$f")"
    STATUS=1
  fi
done

# Both faults must have happened, and A must have come back with its battle each time.
A_LOG="$LOG_DIR/$BOT_A.log"
for expected in "proxy: cut" "proxy: blackhole" "proxy: normal"; do
  grep -q "\[automation\] $expected" "$A_LOG" || { echo "!! missing: $expected"; STATUS=1; }
done
RESTORED=$(grep -c "\[automation\] battles restored: 1" "$A_LOG" || true)
if [ "$RESTORED" -lt 2 ]; then
  echo "!! expected 2 restored battles after the faults, got $RESTORED"
  STATUS=1
fi
grep -q "\[automation\] battle ended" "$A_LOG" || { echo "!! A did not finish the battle"; STATUS=1; }

[ $STATUS -eq 0 ] && echo "E2E reconnect: OK" || echo "E2E reconnect: FAILED (logs in $LOG_DIR)"
exit $STATUS
