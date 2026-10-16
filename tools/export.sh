#!/usr/bin/env bash
# Exports release builds for Linux, Windows and macOS into build/ and packs them into build/dist/.
# Needs the export templates for the exact Godot version
# (Godot editor: Editor > Manage Export Templates, or see .github/actions/setup-godot).
#
# Usage: tools/export.sh [version]   (default: config/version from project.godot)
set -euo pipefail
source "$(dirname "$0")/common.sh"

VERSION="${1:-$(sed -n 's/^config\/version="\(.*\)"/\1/p' "$CLIENT_DIR/project.godot")}"
BUILD="$REPO_ROOT/build"

rm -rf "$BUILD"
mkdir -p "$BUILD"/{linux,windows,macos,dist}
godot_import

export_preset() {
  local preset="$1" output="$2"
  echo "Exporting $preset..."
  "$GODOT" --headless --path "$CLIENT_DIR" --export-release "$preset"
  if [ ! -s "$output" ]; then
    echo "Export '$preset' failed: $output was not created" >&2
    exit 1
  fi
}

export_preset Linux "$BUILD/linux/ShowdownDesktop.x86_64"
export_preset Windows "$BUILD/windows/ShowdownDesktop.exe"
export_preset macOS "$BUILD/macos/ShowdownDesktop.zip"

tar -czf "$BUILD/dist/ShowdownDesktop-$VERSION-linux-x86_64.tar.gz" -C "$BUILD/linux" .
(cd "$BUILD/windows" && zip -qr "$BUILD/dist/ShowdownDesktop-$VERSION-windows-x86_64.zip" .)
cp "$BUILD/macos/ShowdownDesktop.zip" "$BUILD/dist/ShowdownDesktop-$VERSION-macos-universal.zip"

echo "Builds:"
ls -lh "$BUILD/dist"
