#!/usr/bin/env bash
# Build the TimeTug app in Release configuration and place TimeTug.app under dist/.
#
# Runs locally with no secrets: the result is ad-hoc signed (the project's default).
# The release workflow re-signs it with a Developer ID certificate when secrets exist
# (scripts/release/sign-and-notarize.sh).
#
# Environment (all optional):
#   TAG        release tag such as v1.2.3 (falls back to GITHUB_REF_NAME when it looks like v*)
#   DIST_DIR   output directory (default: dist)
#   BUILD_DIR  scratch directory for DerivedData and the archive (default: build)
#   BUILD_NUMBER  CFBundleVersion to stamp (default: the project's value; never GITHUB_RUN_NUMBER, run numbers are per workflow)
#   APP_VERSION   display version; overrides the tag and project.yml
#   GOOGLE_OAUTH_CLIENT_ID, GOOGLE_OAUTH_CLIENT_SECRET  Google Desktop OAuth client baked into the app (both or
#              neither; without them Google is not offered). Never printed; see scripts/ci/google-oauth-config.sh.
#   MICROSOFT_OAUTH_CLIENT_ID  Microsoft Entra client id baked into the app (optional; without it Microsoft is not
#              offered). Never printed; see scripts/ci/microsoft-oauth-config.sh.
#
# Version: from the tag (v1.2.3 -> 1.2.3), else CFBundleShortVersionString in Apps/macOS/project.yml.
# Outputs: dist/TimeTug.app and dist/version.txt (the resolved version).
set -euo pipefail

cd "$(dirname "$0")/../.."
ROOT="$PWD"
DIST_DIR="${DIST_DIR:-dist}"
BUILD_DIR="${BUILD_DIR:-build}"
SPEC="Apps/macOS/project.yml"

tag="${TAG:-}"
if [ -z "$tag" ] && [[ "${GITHUB_REF_NAME:-}" == v* ]]; then
  tag="$GITHUB_REF_NAME"
fi

if [ -n "${APP_VERSION:-}" ]; then
  VERSION="$APP_VERSION"
elif [ -n "$tag" ]; then
  VERSION="${tag#v}"
else
  VERSION="$(sed -n 's/^ *CFBundleShortVersionString: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' "$SPEC" | head -n 1)"
fi
if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+)*([-+][0-9A-Za-z.-]+)?$ ]]; then
  echo "error: could not determine a valid version (got '${VERSION}'); use a tag like v1.2.3" >&2
  exit 1
fi
echo "Building TimeTug $VERSION"

# shellcheck source=scripts/ci/google-oauth-config.sh
source "$ROOT/scripts/ci/google-oauth-config.sh"
prepare_google_oauth_xcconfig "${RUNNER_TEMP:-$BUILD_DIR}"
# shellcheck source=scripts/ci/microsoft-oauth-config.sh
source "$ROOT/scripts/ci/microsoft-oauth-config.sh"
prepare_microsoft_oauth_xcconfig "${RUNNER_TEMP:-$BUILD_DIR}"
xcodegen generate --spec "$SPEC"

rm -rf "$DIST_DIR" "$BUILD_DIR/TimeTug.xcarchive"
mkdir -p "$DIST_DIR"

xcodebuild archive \
  -project Apps/macOS/TimeTug.xcodeproj \
  -scheme TimeTug \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -archivePath "$BUILD_DIR/TimeTug.xcarchive"

APP="$DIST_DIR/TimeTug.app"
ditto "$BUILD_DIR/TimeTug.xcarchive/Products/Applications/TimeTug.app" "$APP"

# The plist has fixed values; stamp the release version and build number, re-signing ad hoc on change.
PLIST="$APP/Contents/Info.plist"
APPEX="$APP/Contents/PlugIns/TimeTugWidgets.appex"
[ -d "$APPEX" ] || { echo "error: widget extension missing at $APPEX" >&2; exit 1; }
APPEX_PLIST="$APPEX/Contents/Info.plist"
BUILD_NUMBER="${BUILD_NUMBER:-}"
changed=0
current="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
if [ "$current" != "$VERSION" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APPEX_PLIST"
  changed=1
fi
if [ -n "$BUILD_NUMBER" ]; then
  current="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
  if [ "$current" != "$BUILD_NUMBER" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APPEX_PLIST"
    changed=1
  fi
fi
if [ "$changed" = 1 ]; then
  # Inside-out: the extension is signed before the app that contains it.
  codesign --force --sign - --options runtime \
    --entitlements Apps/macOS/Widgets/TimeTugWidgets.entitlements "$APPEX"
  codesign --force --sign - --options runtime \
    --entitlements Apps/macOS/Sources/TimeTug.entitlements "$APP"
fi

# Verify the Google client landed in the app without printing it.
google_id="$(/usr/libexec/PlistBuddy -c 'Print :TimeTugGoogleClientID' "$PLIST" 2>/dev/null || true)"
if [ -n "${TIMETUG_GOOGLE_XCCONFIG:-}" ]; then
  if [ -z "$google_id" ] || [[ "$google_id" == *'$('* ]]; then
    echo "error: Google OAuth client was provided but is missing from the built Info.plist" >&2
    exit 1
  fi
  echo "Google OAuth client: configured"
else
  echo "Google OAuth client: absent"
fi

# Verify the Microsoft client id landed in the app without printing it.
microsoft_id="$(/usr/libexec/PlistBuddy -c 'Print :TimeTugMicrosoftClientID' "$PLIST" 2>/dev/null || true)"
if [ -n "${TIMETUG_MICROSOFT_XCCONFIG:-}" ]; then
  if [ -z "$microsoft_id" ] || [[ "$microsoft_id" == *'$('* ]]; then
    echo "error: Microsoft client id was provided but is missing from the built Info.plist" >&2
    exit 1
  fi
  echo "Microsoft client id: configured"
else
  echo "Microsoft client id: absent"
fi

codesign --verify --strict --deep "$APP"
printf '%s\n' "$VERSION" > "$DIST_DIR/version.txt"
echo "Built $ROOT/$APP (version $VERSION)"
