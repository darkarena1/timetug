#!/usr/bin/env bash
# Sign, notarize and staple TimeTug release artifacts with a Developer ID Application certificate.
#
# Usage: scripts/release/sign-and-notarize.sh [app|dmg]
#   app  (default) sign dist/TimeTug.app (hardened runtime), notarize it, staple, verify with spctl.
#   dmg  codesign the DMG, notarize it, staple the ticket, verify with spctl. Run after make-dmg.sh.
# Release flow: build app -> `app` -> make-dmg.sh -> `dmg`. Each run imports the certificate into a
# temporary keychain, so the secret handling below is shared by both modes.
#
# Needs a Mac and Apple Developer credentials. See docs/release.md for how to create them.
# Nothing here prints secrets; the temporary keychain and decoded key files are removed on exit.
#
# Environment (all required):
#   MACOS_CERTIFICATE_P12_BASE64  base64 of the Developer ID Application .p12
#   MACOS_CERTIFICATE_PASSWORD    password of that .p12
#   APPLE_TEAM_ID                 10-character Apple team id
#   NOTARY_API_KEY_ID             App Store Connect API key id
#   NOTARY_API_ISSUER_ID          App Store Connect issuer id
#   NOTARY_API_KEY_P8_BASE64      base64 of the API key .p8
# Optional:
#   APP_PATH   app bundle (default: dist/TimeTug.app)
#   DIST_DIR   scratch/output directory (default: dist)
#   DMG_PATH   disk image for `dmg` mode (default: dist/TimeTug-<dist/version.txt>.dmg)
set -euo pipefail

MODE="${1:-app}"
case "$MODE" in
  app|dmg) ;;
  *) echo "usage: $0 [app|dmg]" >&2; exit 2 ;;
esac

for var in MACOS_CERTIFICATE_P12_BASE64 MACOS_CERTIFICATE_PASSWORD APPLE_TEAM_ID \
           NOTARY_API_KEY_ID NOTARY_API_ISSUER_ID NOTARY_API_KEY_P8_BASE64; do
  if [ -z "${!var:-}" ]; then
    echo "error: required environment variable $var is not set" >&2
    exit 1
  fi
done

# Keep secrets out of the Actions log even if a tool echoes them.
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  for var in MACOS_CERTIFICATE_PASSWORD NOTARY_API_KEY_ID NOTARY_API_ISSUER_ID; do
    echo "::add-mask::${!var}"
  done
fi

cd "$(dirname "$0")/../.."
DIST_DIR="${DIST_DIR:-dist}"
APP_PATH="${APP_PATH:-$DIST_DIR/TimeTug.app}"
ENTITLEMENTS="Apps/macOS/Sources/TimeTug.entitlements"
if [ "$MODE" = app ]; then
  [ -d "$APP_PATH" ] || { echo "error: app not found at $APP_PATH" >&2; exit 1; }
  [ -f "$ENTITLEMENTS" ] || { echo "error: $ENTITLEMENTS missing (run xcodegen first)" >&2; exit 1; }
else
  if [ -z "${DMG_PATH:-}" ]; then
    [ -f "$DIST_DIR/version.txt" ] || { echo "error: set DMG_PATH (no $DIST_DIR/version.txt found)" >&2; exit 1; }
    DMG_PATH="$DIST_DIR/TimeTug-$(cat "$DIST_DIR/version.txt").dmg"
  fi
  [ -f "$DMG_PATH" ] || { echo "error: DMG not found at $DMG_PATH (run make-dmg.sh first)" >&2; exit 1; }
fi

WORK="$(mktemp -d)"
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

# 1. Import the certificate into a temporary keychain.
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
if [ -z "$IDENTITY" ]; then
  echo "error: no 'Developer ID Application' identity for team $APPLE_TEAM_ID in the certificate" >&2
  exit 1
fi
echo "Signing with: $IDENTITY"

echo "$NOTARY_API_KEY_P8_BASE64" | base64 --decode > "$WORK/AuthKey.p8"
notarize() { # notarize <file>: submit and wait; fail loudly unless Apple accepts it
  xcrun notarytool submit "$1" \
    --key "$WORK/AuthKey.p8" --key-id "$NOTARY_API_KEY_ID" --issuer "$NOTARY_API_ISSUER_ID" \
    --wait
}

if [ "$MODE" = app ]; then
  # 2. Re-sign with hardened runtime and a secure timestamp, inside-out: the widget
  #    extension first, then the app that contains it.
  APPEX="$APP_PATH/Contents/PlugIns/TimeTugWidgets.appex"
  [ -d "$APPEX" ] || { echo "error: widget extension missing at $APPEX" >&2; exit 1; }
  codesign --force --sign "$IDENTITY" --keychain "$KEYCHAIN" --options runtime --timestamp \
    --entitlements Apps/macOS/Widgets/TimeTugWidgets.entitlements "$APPEX"
  codesign --force --sign "$IDENTITY" --keychain "$KEYCHAIN" --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" "$APP_PATH"
  codesign --verify --strict --deep --verbose=2 "$APP_PATH"

  # 3. Notarize with the App Store Connect API key.
  ditto -c -k --keepParent "$APP_PATH" "$WORK/notarize.zip"
  notarize "$WORK/notarize.zip"

  # 4. Staple and verify Gatekeeper acceptance.
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
  spctl --assess --type execute --verbose=2 "$APP_PATH"
  echo "Signed, notarized and stapled: $APP_PATH"
else
  # 2. Sign the disk image itself (the app inside was signed and stapled by the `app` run).
  codesign --force --sign "$IDENTITY" --keychain "$KEYCHAIN" --timestamp "$DMG_PATH"
  codesign --verify --strict --verbose=2 "$DMG_PATH"

  # 3. Notarize the DMG, then 4. staple and verify.
  notarize "$DMG_PATH"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
  # Stapling rewrites the file, so refresh the checksum.
  (cd "$(dirname "$DMG_PATH")" && shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$DMG_PATH").sha256")
  echo "Signed, notarized and stapled: $DMG_PATH"
fi
