#!/usr/bin/env bash
# Starts a local Pokémon Showdown server for development on port 8000.
# --no-security lets clients log in with any unregistered name (no login server needed).
#
# Server checkout: $PS_SERVER_DIR, default ../pokemon-showdown next to this repo.
set -euo pipefail
source "$(dirname "$0")/common.sh"

PS_SERVER_DIR="${PS_SERVER_DIR:-$(dirname "$REPO_ROOT")/pokemon-showdown}"

if [ ! -f "$PS_SERVER_DIR/pokemon-showdown" ]; then
  cat >&2 <<EOF
No Showdown server found in $PS_SERVER_DIR.
Set it up once with:

  git clone https://github.com/smogon/pokemon-showdown.git "$PS_SERVER_DIR"
  cd "$PS_SERVER_DIR" && npm install

(or set PS_SERVER_DIR to an existing checkout)
EOF
  exit 1
fi

cd "$PS_SERVER_DIR"
exec node pokemon-showdown start --no-security 8000
