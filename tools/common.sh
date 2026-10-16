# Shared helpers for tools/*.sh - source this file, don't run it.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLIENT_DIR="$REPO_ROOT/client"
PLUGINS_DIR="$REPO_ROOT/plugins"

# Resolves $GODOT: $GODOT, then `godot` on PATH, then ~/Apps/godot/.
# Only scripts that run Godot call this, so e.g. local_server.sh works without Godot.
require_godot() {
  if [ -z "${GODOT:-}" ]; then
    if command -v godot >/dev/null 2>&1; then
      GODOT="$(command -v godot)"
    else
      GODOT="$( (ls ~/Apps/godot/Godot_v4*_linux.x86_64 2>/dev/null || true) | sort -V | tail -n 1)"
    fi
  fi
  if [ -z "$GODOT" ] || [ ! -x "$GODOT" ]; then
    echo "Godot not found. Set GODOT=/path/to/Godot_v4.x_linux.x86_64" >&2
    exit 1
  fi
}

# Imports the project once so class_name scripts are registered (needed for headless runs).
godot_import() {
  require_godot
  "$GODOT" --headless --path "$CLIENT_DIR" --import >/dev/null 2>&1 || true
}
