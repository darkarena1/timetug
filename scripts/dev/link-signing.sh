#!/usr/bin/env bash
# Link the per-user signing override into this checkout so local builds are team-signed.
#
# Xcode's xcconfig parser cannot include files by $(HOME), so this links
# ~/.config/timetug/signing.xcconfig to Apps/macOS/Config/Local.xcconfig (git-ignored), which
# Apps/macOS/Config/Signing.xcconfig includes. Runs before every `xcodegen generate` (see
# `options.preGenCommand` in project.yml). It does nothing when the home file does not exist
# (CI, other machines), so those builds stay ad-hoc signed.
#
# Environment: TIMETUG_SIGNING_XCCONFIG overrides the source path.
set -euo pipefail

SRC="${TIMETUG_SIGNING_XCCONFIG:-${HOME:-/nonexistent}/.config/timetug/signing.xcconfig}"
DEST="$(cd "$(dirname "$0")/../.." && pwd)/Apps/macOS/Config/Local.xcconfig"

if [ ! -f "$SRC" ]; then
  # A dangling link left by a removed source would break the include; drop it.
  [ -L "$DEST" ] && rm -f "$DEST"
  exit 0
fi
[ "$(readlink "$DEST" 2>/dev/null || true)" = "$SRC" ] || ln -sfn "$SRC" "$DEST"
