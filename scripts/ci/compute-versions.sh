#!/usr/bin/env bash
# Print APP_VERSION and BUILD_NUMBER for a beta or stable build (see docs/release.md, "Versioning").
#   compute-versions.sh beta                            -> <base>-beta.<BUILD_NUMBER>
#     <base> is the newest stable v* tag (v1.2.3, no suffix); with none, CFBundleShortVersionString in project.yml.
#   compute-versions.sh stable <tag like v1.2.3>        -> 1.2.3
# BUILD_NUMBER is a UTC timestamp YYYYMMDDHHMMSS shared by beta and release so a release always outranks
# earlier betas. TT_NOW overrides the clock (tests only).
set -euo pipefail
cd "$(dirname "$0")/../.."
kind="${1:-}"
now="${TT_NOW:-$(date -u +%Y%m%d%H%M%S)}"
[[ "$now" =~ ^[0-9]{14}$ ]] || { echo "error: bad timestamp '$now'" >&2; exit 1; }
case "$kind" in
  beta)
    [ $# -eq 1 ] || { echo "usage: $0 beta (no arguments)" >&2; exit 2; }
    base="$(git tag --list 'v*' | grep -E '^v[0-9]+(\.[0-9]+)*$' | sort -V | tail -n 1 | sed 's/^v//' || true)"
    if [ -z "$base" ]; then
      base="$(sed -n 's/^ *CFBundleShortVersionString: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' Apps/macOS/project.yml | head -n 1)"
    fi
    [ -n "$base" ] || { echo "error: no base version (no stable tag, none in project.yml)" >&2; exit 1; }
    echo "APP_VERSION=${base}-beta.${now}" ;;
  stable)
    tag="${2:-}"
    [[ "$tag" =~ ^v[0-9]+(\.[0-9]+)*([-+][0-9A-Za-z.-]+)?$ ]] || { echo "usage: $0 stable vX.Y.Z[-suffix]" >&2; exit 2; }
    echo "APP_VERSION=${tag#v}" ;;
  *) echo "usage: $0 beta | stable <tag>" >&2; exit 2 ;;
esac
echo "BUILD_NUMBER=${now}"
