#!/usr/bin/env bash
# Print APP_VERSION and BUILD_NUMBER for a beta or stable build (see docs/release.md, "Versioning").
#   compute-versions.sh beta <pr-number> <run-number>   -> <base>-beta.<pr>.<run>
#   compute-versions.sh stable <tag like v1.2.3>        -> 1.2.3
# BUILD_NUMBER is a UTC timestamp YYYYMMDDHHMM shared by beta and release so a release always outranks
# earlier betas. TT_NOW overrides the clock (tests only).
set -euo pipefail
cd "$(dirname "$0")/../.."
kind="${1:-}"
now="${TT_NOW:-$(date -u +%Y%m%d%H%M)}"
[[ "$now" =~ ^[0-9]{12}$ ]] || { echo "error: bad timestamp '$now'" >&2; exit 1; }
case "$kind" in
  beta)
    pr="${2:-}"; run="${3:-}"
    [[ "$pr" =~ ^[0-9]+$ && "$run" =~ ^[0-9]+$ ]] || { echo "usage: $0 beta <pr> <run> (numbers)" >&2; exit 2; }
    base="$(sed -n 's/^ *CFBundleShortVersionString: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' Apps/macOS/project.yml | head -n 1)"
    [ -n "$base" ] || { echo "error: no base version in project.yml" >&2; exit 1; }
    echo "APP_VERSION=${base}-beta.${pr}.${run}" ;;
  stable)
    tag="${2:-}"
    [[ "$tag" =~ ^v[0-9]+(\.[0-9]+)*([-+][0-9A-Za-z.-]+)?$ ]] || { echo "usage: $0 stable vX.Y.Z[-suffix]" >&2; exit 2; }
    echo "APP_VERSION=${tag#v}" ;;
  *) echo "usage: $0 beta <pr> <run> | stable <tag>" >&2; exit 2 ;;
esac
echo "BUILD_NUMBER=${now}"
