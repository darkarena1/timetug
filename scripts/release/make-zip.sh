#!/usr/bin/env bash
# Package an UNSIGNED (ad-hoc signed) TimeTug.app as dist/TimeTug-<version>-unsigned.zip
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

zip_name="TimeTug-${VERSION}-unsigned.zip"
ditto -c -k --keepParent "$APP_PATH" "$DIST_DIR/$zip_name"
(cd "$DIST_DIR" && shasum -a 256 "$zip_name" > "$zip_name.sha256")
echo "Created $DIST_DIR/$zip_name"
cat "$DIST_DIR/$zip_name.sha256"
