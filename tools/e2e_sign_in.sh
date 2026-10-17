#!/usr/bin/env bash
# End-to-end test of the sign-in UI against the local server (tools/local_server.sh):
# the real app connects without a name, signs in through the card, signs out, and gets an
# inline error for a name another connection holds. See client/tests/e2e/sign_in_flow.gd.
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_godot
godot_import

LOG="$(mktemp)"
STATUS=0
"$GODOT" --headless --path "$CLIENT_DIR" -s res://tests/e2e/run.gd -- --no-data-fetch --e2e=sign_in_flow \
  >"$LOG" 2>&1 || STATUS=1
grep -E "\[e2e\]|ERROR" "$LOG" || true
if grep -qE "^(SCRIPT )?ERROR" "$LOG"; then
  echo "!! errors in the log"
  STATUS=1
fi
[ $STATUS -eq 0 ] && echo "E2E sign-in: OK" || echo "E2E sign-in: FAILED (log in $LOG)"
exit $STATUS
