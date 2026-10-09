#!/usr/bin/env bash
# Install (or remove) the App Store signing material on a CI runner. Nothing here prints secrets.
#
# Usage: scripts/release/appstore-signing.sh install | remove
# Environment for install (all base64 except the password):
#   APPSTORE_DISTRIBUTION_CERT_P12, APPSTORE_INSTALLER_CERT_P12, APPSTORE_CERT_PASSWORD,
#   APPSTORE_APP_PROFILE, APPSTORE_WIDGET_PROFILE, ASC_KEY_P8 (and RUNNER_TEMP)
# install writes the App Store Connect key to $RUNNER_TEMP/AuthKey.p8 and puts the certificates in a temporary keychain
# that is searched first; remove undoes both.
set -euo pipefail
action="${1:-}"
TMP="${RUNNER_TEMP:?RUNNER_TEMP is required}"
KEYCHAIN="$TMP/appstore-signing.keychain-db"
PROFILES="$HOME/Library/MobileDevice/Provisioning Profiles"

case "$action" in
  install)
    for var in APPSTORE_DISTRIBUTION_CERT_P12 APPSTORE_INSTALLER_CERT_P12 APPSTORE_CERT_PASSWORD \
               APPSTORE_APP_PROFILE APPSTORE_WIDGET_PROFILE ASC_KEY_P8; do
      [ -n "${!var:-}" ] || { echo "error: required environment variable $var is not set" >&2; exit 1; }
    done
    if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::add-mask::${APPSTORE_CERT_PASSWORD}"; fi
    password="$(uuidgen)"
    original="$(security list-keychains -d user | tr -d '"' | tr '\n' ' ')"
    security create-keychain -p "$password" "$KEYCHAIN"
    security set-keychain-settings -lut 21600 "$KEYCHAIN"
    security unlock-keychain -p "$password" "$KEYCHAIN"
    for var in APPSTORE_DISTRIBUTION_CERT_P12 APPSTORE_INSTALLER_CERT_P12; do
      echo "${!var}" | base64 --decode > "$TMP/$var.p12"
      security import "$TMP/$var.p12" -k "$KEYCHAIN" -P "$APPSTORE_CERT_PASSWORD" \
        -T /usr/bin/codesign -T /usr/bin/productbuild -T /usr/bin/security >/dev/null
      rm -f "$TMP/$var.p12"
    done
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$KEYCHAIN" >/dev/null
    # shellcheck disable=SC2086
    security list-keychains -d user -s "$KEYCHAIN" $original
    mkdir -p "$PROFILES"
    echo "$APPSTORE_APP_PROFILE" | base64 --decode > "$PROFILES/timetug-app-store.provisionprofile"
    echo "$APPSTORE_WIDGET_PROFILE" | base64 --decode > "$PROFILES/timetug-widgets-app-store.provisionprofile"
    for file in timetug-app-store timetug-widgets-app-store; do
      if ! security cms -D -i "$PROFILES/$file.provisionprofile" > "$TMP/$file.plist" 2>/dev/null; then
        echo "error: the $file profile secret is not a valid provisioning profile (re-encode the downloaded file with base64 -i, without opening or pasting it)" >&2
        exit 1
      fi
      echo "profile: $(/usr/libexec/PlistBuddy -c 'Print :Name' "$TMP/$file.plist") for $(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$TMP/$file.plist")"
      rm -f "$TMP/$file.plist"
    done
    echo "$ASC_KEY_P8" | base64 --decode > "$TMP/AuthKey.p8"
    chmod 600 "$TMP/AuthKey.p8"
    security find-identity -v "$KEYCHAIN" | sed -n 's/^ *[0-9]*) [0-9A-F]* "\(.*\)"$/identity: \1/p'
    ;;
  remove)
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
    rm -f "$TMP/AuthKey.p8" "$PROFILES/timetug-app-store.provisionprofile" "$PROFILES/timetug-widgets-app-store.provisionprofile"
    ;;
  *) echo "usage: $0 install | remove" >&2; exit 2 ;;
esac
