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
#   BUILD_NUMBER  CFBundleVersion to stamp (default: GITHUB_RUN_NUMBER, else the project's value)
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

if [ -n "$tag" ]; then
  VERSION="${tag#v}"
else
  VERSION="$(sed -n 's/^ *CFBundleShortVersionString: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' "$SPEC" | head -n 1)"
fi
if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+)*([-+][0-9A-Za-z.-]+)?$ ]]; then
  echo "error: could not determine a valid version (got '${VERSION}'); use a tag like v1.2.3" >&2
  exit 1
fi
echo "Building TimeTug $VERSION"

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
BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-}}"
changed=0
current="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
if [ "$current" != "$VERSION" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
  changed=1
fi
if [ -n "$BUILD_NUMBER" ]; then
  current="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
  if [ "$current" != "$BUILD_NUMBER" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
    changed=1
  fi
fi
if [ "$changed" = 1 ]; then
  codesign --force --sign - --options runtime \
    --entitlements Apps/macOS/Sources/TimeTug.entitlements "$APP"
fi

codesign --verify --strict "$APP"
printf '%s\n' "$VERSION" > "$DIST_DIR/version.txt"
echo "Built $ROOT/$APP (version $VERSION)"
