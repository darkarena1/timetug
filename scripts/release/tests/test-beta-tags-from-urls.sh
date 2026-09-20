#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
S=scripts/release/beta-tags-from-urls.sh
fail() { echo "FAIL: $*" >&2; exit 1; }
D=https://github.com/o/r/releases/download
check() { # check <name> <expected> <stdin>
  local out; out="$(printf '%s' "$3" | $S)"
  [ "$out" = "$2" ] || fail "$1: got '$out', want '$2'"
}

check "new tag" "v1.2.0-beta.20260920052623" "$D/v1.2.0-beta.20260920052623/TimeTug-1.2.0-beta.20260920052623.zip"$'\n'
check "dotted base" "v0.2-beta.20260920052623" "$D/v0.2-beta.20260920052623/a.zip"$'\n'
check "legacy tag" "beta-20260101000000" "$D/beta-20260101000000/TimeTug.zip"$'\n'
check "multiple" "v1.2.0-beta.20260920052623
beta-20260101000000" "$D/v1.2.0-beta.20260920052623/a.zip $D/beta-20260101000000/b.zip"
check "stable ignored" "" "$D/v1.2.3/TimeTug-1.2.3.zip"$'\n'
check "rc ignored" "" "$D/v1.2.3-rc1/a.zip"$'\n'
check "short suffix ignored" "" "$D/v1.2.3-beta.7/a.zip"$'\n'
check "long suffix ignored" "" "$D/v1.2.3-beta.202609200526230/a.zip"$'\n'
check "legacy junk ignored" "" "$D/beta-abc/a.zip"$'\n'"$D/beta-/a.zip"$'\n'
check "garbage ignored" "" "hello world"$'\n'"///"$'\n'"$D//a.zip"$'\n'
check "empty input" "" ""
check "no download segment" "" "https://github.com/o/r/releases/tag/v1.2.0-beta.20260920052623"$'\n'
check "tag with slash-suffix junk" "" "$D/v1.2.0-beta.20260920052623x/a.zip"$'\n'
check "missing asset" "" "$D/v1.2.0-beta.20260920052623"$'\n'
echo "PASS"
