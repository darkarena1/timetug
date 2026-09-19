#!/usr/bin/env bash
# Build dist/TimeTug-<version>.dmg (app plus an /Applications symlink) with hdiutil only,
# and write a matching .sha256 file.
#
# Environment:
#   VERSION    required, e.g. 1.2.3
#   APP_PATH   app bundle (default: dist/TimeTug.app)
#   DIST_DIR   output directory (default: dist)
set -euo pipefail

: "${VERSION:?VERSION is required (e.g. 1.2.3)}"
DIST_DIR="${DIST_DIR:-dist}"
APP_PATH="${APP_PATH:-$DIST_DIR/TimeTug.app}"
[ -d "$APP_PATH" ] || { echo "error: app not found at $APP_PATH" >&2; exit 1; }

dmg_name="TimeTug-${VERSION}.dmg"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

ditto "$APP_PATH" "$staging/TimeTug.app"
ln -s /Applications "$staging/Applications"

rm -f "$DIST_DIR/$dmg_name"
hdiutil create -volname "TimeTug" -srcfolder "$staging" -ov -format UDZO "$DIST_DIR/$dmg_name"
(cd "$DIST_DIR" && shasum -a 256 "$dmg_name" > "$dmg_name.sha256")
echo "Created $DIST_DIR/$dmg_name"
cat "$DIST_DIR/$dmg_name.sha256"
