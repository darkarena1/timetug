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

# The plist has a fixed version; stamp the release version and re-sign ad hoc if it differs.
PLIST="$APP/Contents/Info.plist"
current="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
if [ "$current" != "$VERSION" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
  codesign --force --sign - --options runtime \
    --entitlements Apps/macOS/Sources/TimeTug.entitlements "$APP"
fi

codesign --verify --strict "$APP"
printf '%s\n' "$VERSION" > "$DIST_DIR/version.txt"
echo "Built $ROOT/$APP (version $VERSION)"
