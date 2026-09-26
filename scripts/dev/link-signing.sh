#!/usr/bin/env bash
# Link the per-user signing, Google OAuth and Microsoft OAuth overrides into this checkout so local builds are
# team-signed and can offer Google Calendar and Microsoft.
#
# Xcode's xcconfig parser cannot include files by $(HOME), so this links
# ~/.config/timetug/signing.xcconfig to Apps/macOS/Config/Local.xcconfig and
# ~/.config/timetug/google-oauth.xcconfig to Apps/macOS/Config/GoogleOAuth.xcconfig and
# ~/.config/timetug/microsoft-oauth.xcconfig to Apps/macOS/Config/MicrosoftOAuth.xcconfig (all git-ignored), which
# Apps/macOS/Config/Signing.xcconfig includes. Runs before every `xcodegen generate` (see
# `options.preGenCommand` in project.yml). It does nothing for a home file that does not exist
# (CI, other machines), so those builds stay ad-hoc signed and Google and Microsoft are not offered.
#
# Environment: TIMETUG_SIGNING_XCCONFIG, TIMETUG_GOOGLE_XCCONFIG and TIMETUG_MICROSOFT_XCCONFIG override the source paths.
set -euo pipefail

link_one() {   # link_one SRC DEST
  local src="$1" dest="$2"
  if [ ! -f "$src" ]; then
    # A dangling link left by a removed source would break the include; drop it.
    [ -L "$dest" ] && rm -f "$dest"
    return 0
  fi
  [ "$(readlink "$dest" 2>/dev/null || true)" = "$src" ] || ln -sfn "$src" "$dest"
}

CONFIG_DIR="$(cd "$(dirname "$0")/../.." && pwd)/Apps/macOS/Config"
link_one "${TIMETUG_SIGNING_XCCONFIG:-${HOME:-/nonexistent}/.config/timetug/signing.xcconfig}" "$CONFIG_DIR/Local.xcconfig"
link_one "${TIMETUG_GOOGLE_XCCONFIG:-${HOME:-/nonexistent}/.config/timetug/google-oauth.xcconfig}" "$CONFIG_DIR/GoogleOAuth.xcconfig"
link_one "${TIMETUG_MICROSOFT_XCCONFIG:-${HOME:-/nonexistent}/.config/timetug/microsoft-oauth.xcconfig}" "$CONFIG_DIR/MicrosoftOAuth.xcconfig"
