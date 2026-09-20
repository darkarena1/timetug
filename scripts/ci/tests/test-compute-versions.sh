#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
S=scripts/ci/compute-versions.sh
fail() { echo "FAIL: $*" >&2; exit 1; }

# beta runs against a throwaway repo: the script resolves its repo root from its own location.
mkrepo() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/ci" "$d/Apps/macOS"
  cp "$S" "$d/scripts/ci/compute-versions.sh"
  printf 'targets:\n  App:\n    info:\n      properties:\n        CFBundleShortVersionString: "0.0.0-dev"\n' > "$d/Apps/macOS/project.yml"
  git -C "$d" init -q
  git -C "$d" -c user.name=t -c user.email=t@t add -A
  git -C "$d" -c user.name=t -c user.email=t@t commit -q -m init
  echo "$d"
}
tmp="$(mkrepo)"; trap 'rm -rf "$tmp" "${tmp2:-}"' EXIT
for t in v1.0.0 v1.1.0 v0.2.1 v1.2.0-rc1 v1.2.0-beta.20260920052623 beta-20260101000000 v1.10 vfoo; do git -C "$tmp" tag "$t"; done
out="$(TT_NOW=20260920050214 "$tmp/scripts/ci/compute-versions.sh" beta)"
[ "$out" = "APP_VERSION=1.10-beta.20260920050214
BUILD_NUMBER=20260920050214" ] || fail "beta newest stable: $out"
git -C "$tmp" tag -d v1.10 >/dev/null
out="$(TT_NOW=20260920050214 "$tmp/scripts/ci/compute-versions.sh" beta)"
[ "$out" = "APP_VERSION=1.1.0-beta.20260920050214
BUILD_NUMBER=20260920050214" ] || fail "beta newest stable: $out"

tmp2="$(mkrepo)"
for t in v1.2.0-rc1 v1.2.0-beta.20260920052623 beta-20260101000000; do git -C "$tmp2" tag "$t"; done
out="$(TT_NOW=20260920050214 "$tmp2/scripts/ci/compute-versions.sh" beta)"
[ "$out" = "APP_VERSION=0.0.0-dev-beta.20260920050214
BUILD_NUMBER=20260920050214" ] || fail "beta fallback: $out"

"$tmp/scripts/ci/compute-versions.sh" beta 34 >/dev/null 2>&1 && fail "beta with argument accepted"
rc=0; "$tmp/scripts/ci/compute-versions.sh" beta 34 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "beta with argument: exit $rc, want 2"

out="$(TT_NOW=20260919143005 $S stable v1.2.3)"
[ "$out" = "APP_VERSION=1.2.3
BUILD_NUMBER=20260919143005" ] || fail "stable output: $out"

$S stable 1.2.3 >/dev/null 2>&1 && fail "tag without v accepted"
[ "$(TT_NOW=20260919143005 $S stable v1.2.3-rc1 | head -n1)" = "APP_VERSION=1.2.3-rc1" ] || fail "suffix tag rejected"
out="$($S beta)"
echo "$out" | grep -Eq '^BUILD_NUMBER=[0-9]{14}$' || fail "default clock: $out"
echo "PASS"
