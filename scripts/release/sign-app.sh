#!/usr/bin/env bash
# Sign TimeTug.app with a Developer ID Application certificate (hardened runtime), inside-out. No notarization.
# Usage: scripts/release/sign-app.sh [APP_PATH]   (default dist/TimeTug.app)
# Environment: MACOS_CERTIFICATE_P12_BASE64, MACOS_CERTIFICATE_PASSWORD, APPLE_TEAM_ID.
#   MACOS_PROVISIONING_PROFILE_BASE64 (optional): base64 of the Developer ID .provisionprofile for com.timetug.app. When set,
#   it is embedded and the app is signed with the keychain-access-groups entitlement (shared credentials); when unset
#   the app keeps its own private keychain item.
# SIGN_IDENTITY=-  signs ad hoc instead (local smoke test; needs no secrets and skips the timestamp).
# SIGN_IDENTITY="Developer ID Application: ..."  signs with that identity from the login keychain (local test of a
# profile-signed build; with a profile, also set APPLE_TEAM_ID and MACOS_PROVISIONING_PROFILE_BASE64).
# The temporary keychain and decoded certificate are removed on exit. Nothing here prints secrets.
set -euo pipefail
cd "$(dirname "$0")/../.."
APP_PATH="${1:-dist/TimeTug.app}"
ENTITLEMENTS="Apps/macOS/Sources/TimeTug.entitlements"
WIDGET_ENTITLEMENTS="Apps/macOS/Widgets/TimeTugWidgets.entitlements"
[ -d "$APP_PATH" ] || { echo "error: app not found at $APP_PATH" >&2; exit 1; }
APPEX="$APP_PATH/Contents/PlugIns/TimeTugWidgets.appex"
[ -d "$APPEX" ] || { echo "error: widget extension missing at $APPEX" >&2; exit 1; }

WORK="$(mktemp -d)"
KEYCHAIN_ARGS=()
TIMESTAMP=(--timestamp)
if [ -n "${SIGN_IDENTITY:-}" ]; then
  IDENTITY="$SIGN_IDENTITY"
  [ "$IDENTITY" = "-" ] && TIMESTAMP=()
  trap 'rm -rf "$WORK"' EXIT
else
  for var in MACOS_CERTIFICATE_P12_BASE64 MACOS_CERTIFICATE_PASSWORD APPLE_TEAM_ID; do
    [ -n "${!var:-}" ] || { echo "error: required environment variable $var is not set" >&2; exit 1; }
  done
  if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::add-mask::${MACOS_CERTIFICATE_PASSWORD}"; fi
  KEYCHAIN="$WORK/signing.keychain-db"
  KEYCHAIN_PASSWORD="$(uuidgen)"
  ORIGINAL_KEYCHAINS="$(security list-keychains -d user | tr -d '"' | tr '\n' ' ')"
  cleanup() {
    # shellcheck disable=SC2086
    security list-keychains -d user -s $ORIGINAL_KEYCHAINS >/dev/null 2>&1 || true
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
    rm -rf "$WORK"
  }
  trap cleanup EXIT
  echo "$MACOS_CERTIFICATE_P12_BASE64" | base64 --decode > "$WORK/cert.p12"
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  security set-keychain-settings -lut 21600 "$KEYCHAIN"
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  security import "$WORK/cert.p12" -k "$KEYCHAIN" -P "$MACOS_CERTIFICATE_PASSWORD" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
  # shellcheck disable=SC2086
  security list-keychains -d user -s "$KEYCHAIN" $ORIGINAL_KEYCHAINS
  IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" \
    | sed -n "s/.*\"\(Developer ID Application: .*(${APPLE_TEAM_ID})\)\".*/\1/p" | head -n 1)"
  [ -n "$IDENTITY" ] || { echo "error: no 'Developer ID Application' identity for team $APPLE_TEAM_ID" >&2; exit 1; }
  KEYCHAIN_ARGS=(--keychain "$KEYCHAIN")
  echo "Signing with: $IDENTITY"
fi

sign() { codesign --force --sign "$IDENTITY" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} --options runtime ${TIMESTAMP[@]+"${TIMESTAMP[@]}"} "$@"; }

# Inside-out: Sparkle's nested helpers, then the framework, then the widget extension, then the app.
FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
if [ -d "$FRAMEWORK" ]; then
  while IFS= read -r xpc; do sign --preserve-metadata=entitlements "$xpc"; done \
    < <(find "$FRAMEWORK" -name '*.xpc' -type d)
  [ -f "$FRAMEWORK/Versions/B/Autoupdate" ] || { echo "error: $FRAMEWORK/Versions/B/Autoupdate not found (Sparkle layout changed?)" >&2; exit 1; }
  [ -d "$FRAMEWORK/Versions/B/Updater.app" ] || { echo "error: $FRAMEWORK/Versions/B/Updater.app not found (Sparkle layout changed?)" >&2; exit 1; }
  sign "$FRAMEWORK/Versions/B/Autoupdate"
  sign "$FRAMEWORK/Versions/B/Updater.app"
  sign "$FRAMEWORK"
else
  echo "warning: Sparkle.framework not found in the app; signing without it" >&2
fi
sign --entitlements "$WIDGET_ENTITLEMENTS" "$APPEX"
APP_ENTITLEMENTS="$ENTITLEMENTS"
if [ -n "${MACOS_PROVISIONING_PROFILE_BASE64:-}" ] && [ "${SIGN_IDENTITY:-}" != "-" ]; then
  echo "$MACOS_PROVISIONING_PROFILE_BASE64" | base64 --decode > "$WORK/embedded.provisionprofile"
  # `security cms -D` also fails when the file was damaged in transfer (a text conversion turns bytes into U+FFFD).
  security cms -D -i "$WORK/embedded.provisionprofile" > "$WORK/profile.plist" 2>/dev/null \
    || { echo "error: MACOS_PROVISIONING_PROFILE_BASE64 is not an intact provisioning profile (download the .provisionprofile from the developer portal as a binary file)" >&2; exit 1; }
  profile_app_id="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$WORK/profile.plist")"
  [ "$profile_app_id" = "${APPLE_TEAM_ID}.com.timetug.app" ] \
    || { echo "error: the provisioning profile is for $profile_app_id, not ${APPLE_TEAM_ID}.com.timetug.app" >&2; exit 1; }
  cp "$WORK/embedded.provisionprofile" "$APP_PATH/Contents/embedded.provisionprofile"
  APP_ENTITLEMENTS="$WORK/app.entitlements"
  cp "$ENTITLEMENTS" "$APP_ENTITLEMENTS"
  PB=/usr/libexec/PlistBuddy
  $PB -c "Add :com.apple.application-identifier string ${APPLE_TEAM_ID}.com.timetug.app" "$APP_ENTITLEMENTS"
  $PB -c "Add :com.apple.developer.team-identifier string ${APPLE_TEAM_ID}" "$APP_ENTITLEMENTS"
  $PB -c "Add :keychain-access-groups array" -c "Add :keychain-access-groups:0 string ${APPLE_TEAM_ID}.com.timetug.shared" "$APP_ENTITLEMENTS"
  echo "Embedded the provisioning profile; the app shares credentials through ${APPLE_TEAM_ID}.com.timetug.shared"
fi
sign --entitlements "$APP_ENTITLEMENTS" "$APP_PATH"
codesign --verify --strict --deep --verbose=2 "$APP_PATH"
echo "Signed (not notarized): $APP_PATH"
