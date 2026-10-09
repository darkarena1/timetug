#!/usr/bin/env bash
# Archive the App Store target and export it, or upload it to App Store Connect.
#
# Environment:
#   APP_VERSION     X.Y.Z, no suffix (App Store Connect rejects pre-release versions; there is no beta channel there)
#   BUILD_NUMBER    CFBundleVersion; must increase on every upload (scripts/ci/compute-versions.sh makes one)
#   DESTINATION     export (default: writes dist/appstore/TimeTug.pkg) or upload (sends it to App Store Connect)
#   TEAM_ID         default YYA6ZKMD36
#   ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID   App Store Connect API key, required for upload
#   GOOGLE_OAUTH_CLIENT_ID, GOOGLE_OAUTH_CLIENT_SECRET, MICROSOFT_OAUTH_CLIENT_ID   as for build-release.sh
#   DRY_RUN=1       validate the inputs and stop
# The Apple Distribution and Mac Installer certificates and the two App Store provisioning profiles ("TimeTug App Store"
# for the app, "TimeTug Widgets App Store" for the widget; the names are set in Apps/macOS/project.yml) must already be
# installed in the keychain / ~/Library/MobileDevice/Provisioning Profiles.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$PWD"

: "${APP_VERSION:?APP_VERSION is required}"
: "${BUILD_NUMBER:?BUILD_NUMBER is required}"
DESTINATION="${DESTINATION:-export}"
TEAM_ID="${TEAM_ID:-YYA6ZKMD36}"
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: App Store versions must be X.Y.Z, got '$APP_VERSION'" >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "error: BUILD_NUMBER must be digits, got '$BUILD_NUMBER'" >&2; exit 1; }
case "$DESTINATION" in export|upload) ;; *) echo "error: DESTINATION must be export or upload" >&2; exit 1 ;; esac
if [ "$DESTINATION" = upload ]; then
  : "${ASC_KEY_PATH:?ASC_KEY_PATH is required for upload}"
  : "${ASC_KEY_ID:?ASC_KEY_ID is required for upload}"
  : "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required for upload}"
fi
[ -z "${DRY_RUN:-}" ] || { echo "inputs ok"; exit 0; }

BUILD_DIR="${BUILD_DIR:-build}"
OUT="dist/appstore"
rm -rf "$BUILD_DIR/appstore.xcarchive" "$OUT"
mkdir -p "$OUT"

# shellcheck source=scripts/ci/google-oauth-config.sh
source "$ROOT/scripts/ci/google-oauth-config.sh"
prepare_google_oauth_xcconfig "${RUNNER_TEMP:-$BUILD_DIR}"
# shellcheck source=scripts/ci/microsoft-oauth-config.sh
source "$ROOT/scripts/ci/microsoft-oauth-config.sh"
prepare_microsoft_oauth_xcconfig "${RUNNER_TEMP:-$BUILD_DIR}"
xcodegen generate --spec Apps/macOS/project.yml

# The Release configuration of the store targets is signed manually with the Apple Distribution certificate and the
# profiles named in project.yml; the version and build number reach both Info.plists through build settings.
xcodebuild archive \
  -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug-AppStore -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$BUILD_DIR/DerivedData-store" \
  -archivePath "$BUILD_DIR/appstore.xcarchive" \
  MARKETING_VERSION="$APP_VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" DEVELOPMENT_TEAM="$TEAM_ID"

ARCHIVED_APP="$BUILD_DIR/appstore.xcarchive/Products/Applications/TimeTug.app"
for key in TimeTugGoogleClientID TimeTugMicrosoftClientID; do
  value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$ARCHIVED_APP/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$value" != *'$('* ]] || { echo "error: $key was not resolved in the built Info.plist" >&2; exit 1; }
done
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ARCHIVED_APP/Contents/Info.plist")" = "$APP_VERSION" ] \
  || { echo "error: the archive does not carry version $APP_VERSION" >&2; exit 1; }
[ ! -e "$ARCHIVED_APP/Contents/Frameworks/Sparkle.framework" ] || { echo "error: Sparkle is in the App Store build" >&2; exit 1; }

cat > "$BUILD_DIR/ExportOptions-AppStore.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>installerSigningCertificate</key><string>3rd Party Mac Developer Installer</string>
  <key>provisioningProfiles</key><dict>
    <key>com.timetug.app.store</key><string>TimeTug App Store</string>
    <key>com.timetug.app.store.widgets</key><string>TimeTug Widgets App Store</string>
  </dict>
  <key>destination</key><string>$([ "$DESTINATION" = upload ] && echo upload || echo export)</string>
</dict></plist>
PLIST

auth=()
if [ "$DESTINATION" = upload ]; then
  auth=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi
xcodebuild -exportArchive -archivePath "$BUILD_DIR/appstore.xcarchive" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions-AppStore.plist" -exportPath "$OUT" ${auth[@]+"${auth[@]}"}
echo "done: $DESTINATION ($OUT)"
