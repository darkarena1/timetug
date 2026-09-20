#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
S=scripts/ci/compute-versions.sh
fail() { echo "FAIL: $*" >&2; exit 1; }

out="$(TT_NOW=202609191430 $S beta 34)"
base="$(sed -n 's/^ *CFBundleShortVersionString: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' Apps/macOS/project.yml | head -n 1)"
[ "$out" = "APP_VERSION=${base}-beta.34
BUILD_NUMBER=202609191430" ] || fail "beta output: $out"

out="$(TT_NOW=202609191430 $S stable v1.2.3)"
[ "$out" = "APP_VERSION=1.2.3
BUILD_NUMBER=202609191430" ] || fail "stable output: $out"

$S beta x >/dev/null 2>&1 && fail "non-numeric run accepted"
$S beta >/dev/null 2>&1 && fail "missing run accepted"
$S beta 12 34 >/dev/null 2>&1 && fail "old three-argument form accepted"
$S stable 1.2.3 >/dev/null 2>&1 && fail "tag without v accepted"
[ "$(TT_NOW=202609191430 $S stable v1.2.3-rc1 | head -n1)" = "APP_VERSION=1.2.3-rc1" ] || fail "suffix tag rejected"
out="$($S beta 1)"
echo "$out" | grep -Eq '^BUILD_NUMBER=[0-9]{12}$' || fail "default clock: $out"
echo "PASS"
