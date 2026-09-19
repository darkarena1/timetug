#!/usr/bin/env bash
# Build the drag-to-install disk image dist/TimeTug-<version>.dmg and a matching .sha256 file.
#
# The DMG shows the app icon and an /Applications shortcut over the branded background
# (scripts/release/dmg/background*.png). It is built with dmgbuild, which writes the Finder
# layout directly (no Finder scripting), so it also works on headless CI runners. dmgbuild is
# installed at the version pinned in scripts/release/dmg/requirements.txt into a throwaway
# virtualenv (build/dmg-venv); nothing is installed globally. Runs locally with no secrets.
# Signing the DMG is a separate step (scripts/release/sign-and-notarize.sh dmg).
#
# Environment:
#   VERSION      required, e.g. 1.2.3
#   APP_PATH     app bundle (default: dist/TimeTug.app)
#   DIST_DIR     output directory (default: dist)
#   BUILD_DIR    scratch directory holding the virtualenv (default: build)
#   DMG_SUFFIX   optional file name suffix, e.g. -unsigned -> TimeTug-<version>-unsigned.dmg
set -euo pipefail

: "${VERSION:?VERSION is required (e.g. 1.2.3)}"
cd "$(dirname "$0")/../.."
DIST_DIR="${DIST_DIR:-dist}"
BUILD_DIR="${BUILD_DIR:-build}"
APP_PATH="${APP_PATH:-$DIST_DIR/TimeTug.app}"
DMG_SUFFIX="${DMG_SUFFIX:-}"
DMG_DIR="scripts/release/dmg"

[ -d "$APP_PATH" ] || { echo "error: app not found at $APP_PATH" >&2; exit 1; }
[ -f "$APP_PATH/Contents/Resources/AppIcon.icns" ] \
  || { echo "error: $APP_PATH has no Contents/Resources/AppIcon.icns (needed for the volume icon)" >&2; exit 1; }
for f in background.png background@2x.png settings.py requirements.txt; do
  [ -f "$DMG_DIR/$f" ] || { echo "error: $DMG_DIR/$f is missing" >&2; exit 1; }
done

dmg_name="TimeTug-${VERSION}${DMG_SUFFIX}.dmg"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Throwaway virtualenv with the pinned dmgbuild (re-created when the pin changes).
venv="$BUILD_DIR/dmg-venv"
if [ ! -x "$venv/bin/dmgbuild" ] || ! cmp -s "$DMG_DIR/requirements.txt" "$venv/requirements.installed"; then
  rm -rf "$venv"
  python3 -m venv "$venv"
  "$venv/bin/pip" install --quiet --disable-pip-version-check -r "$DMG_DIR/requirements.txt"
  cp "$DMG_DIR/requirements.txt" "$venv/requirements.installed"
fi

# One hi-dpi TIFF so Finder picks the 1x or 2x image for the display.
tiffutil -cathidpicheck "$DMG_DIR/background.png" "$DMG_DIR/background@2x.png" \
  -out "$work/background.tiff" >/dev/null

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/$dmg_name"
"$venv/bin/dmgbuild" -s "$DMG_DIR/settings.py" \
  -D "app=$APP_PATH" -D "background=$work/background.tiff" \
  "TimeTug" "$DIST_DIR/$dmg_name"

(cd "$DIST_DIR" && shasum -a 256 "$dmg_name" > "$dmg_name.sha256")
echo "Created $DIST_DIR/$dmg_name"
cat "$DIST_DIR/$dmg_name.sha256"
