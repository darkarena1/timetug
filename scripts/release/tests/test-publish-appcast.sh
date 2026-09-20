#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q --bare "$T/remote.git"
fail() { echo "FAIL: $*" >&2; exit 1; }
pub() { # pub <version> [channel]
  local extra=(); [ -n "${2:-}" ] && extra=(--channel "$2")
  scripts/release/publish-appcast.sh "$T/remote.git" --keep-betas 2 -- \
    --title "TimeTug $1" --version "$1" --short "0.2.0-$1" --url "https://e/$1.zip" \
    --length 1 --signature S --min-system 14.0 "${extra[@]}"
}
pub 1 beta >/dev/null; pub 2 beta >/dev/null
pruned="$(pub 3 beta)"
[ "$pruned" = "https://e/1.zip" ] || fail "expected prune of 1, got '$pruned'"
git clone -q --branch gh-pages "$T/remote.git" "$T/check"
count="$(grep -c '<item>' "$T/check/appcast.xml")"
[ "$count" = 2 ] || fail "expected 2 items, got $count"
echo PASS
