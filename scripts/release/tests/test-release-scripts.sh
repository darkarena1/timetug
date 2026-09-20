#!/usr/bin/env bash
# Tests release-state.sh and upload-release-assets.sh against a fake `gh` on PATH.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir "$T/bin"
cat > "$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Records every call; `gh api --paginate .../releases` returns $FAKE_RELEASES.
printf '%s\n' "$*" >> "$FAKE_LOG"
if [ "${1:-}" = api ] && [ "${2:-}" = --paginate ]; then cat "$FAKE_RELEASES"; fi
exit 0
STUB
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH" GITHUB_REPOSITORY=o/r FAKE_LOG="$T/log" FAKE_RELEASES="$T/releases.json"

git init -q "$T/repo"; cd "$T/repo"
git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git tag v1.0.0   # a tag that exists locally
printf 'dmg' > a.dmg; echo "abc123  a.dmg" > a.dmg.sha256

# Two pages: the wanted releases are on the second page.
cat > "$FAKE_RELEASES" <<'J'
[{"id":1,"tag_name":"v0.9.0","draft":false}]
[{"id":42,"tag_name":"v1.1.0","draft":true},
 {"id":43,"tag_name":"v1.0.0","draft":true},
 {"id":44,"tag_name":"v0.8.0","draft":false},
 {"id":45,"tag_name":"v2.0.0-rc1","draft":true}]
J
S="$ROOT/scripts/release/release-state.sh"; U="$ROOT/scripts/release/upload-release-assets.sh"
reset() { : > "$FAKE_LOG"; }

echo "=== release-state ===" >&2
[ "$($S v3.0.0)" = none ] || fail "none"
[ "$($S v1.1.0)" = draft ] || fail "draft with no git tag"
[ "$($S v0.8.0)" = published ] || fail "published (page 2)"
[ "$($S v0.9.0)" = published ] || fail "published (page 1)"
[ "$($S --id v1.1.0)" = 42 ] || fail "id"
echo "PASS" >&2

echo "=== published: fails, no uploads ===" >&2
reset
out="$($U v0.8.0 deadbeef a.dmg 2>&1)" && fail "published should exit non-zero"
grep -q "already published and immutable" <<<"$out" || fail "message: $out"
grep -q "POST\|PATCH\|release create" "$FAKE_LOG" && fail "made changes for published"
echo "PASS" >&2

echo "=== draft, tag missing: upload then PATCH with target_commitish ===" >&2
reset
$U v1.1.0 deadbeef a.dmg a.dmg.sha256 >/dev/null
[ "$(grep -c 'method POST.*releases/42/assets?name=' "$FAKE_LOG")" = 2 ] || fail "two uploads"
patch="$(grep 'method PATCH' "$FAKE_LOG")"
grep -q 'releases/42' <<<"$patch" || fail "patch id: $patch"
grep -q -- '-F draft=false' <<<"$patch" || fail "draft=false: $patch"
grep -q 'target_commitish=deadbeef' <<<"$patch" || fail "target_commitish: $patch"
grep -q 'make_latest=true' <<<"$patch" || fail "make_latest true: $patch"
grep -q 'prerelease=false' <<<"$patch" || fail "prerelease false: $patch"
[ "$(grep -n 'POST' "$FAKE_LOG" | tail -1 | cut -d: -f1)" -lt "$(grep -n PATCH "$FAKE_LOG" | cut -d: -f1)" ] || fail "upload before publish"
grep -q 'title\|notes' <<<"$patch" && fail "must not touch title/notes"
echo "PASS" >&2

echo "=== draft, tag exists: no target_commitish ===" >&2
reset
$U v1.0.0 deadbeef a.dmg >/dev/null
grep 'method PATCH' "$FAKE_LOG" | grep -q target_commitish && fail "target_commitish set for existing tag"
echo "PASS" >&2

echo "=== draft, suffixed version: prerelease, not latest ===" >&2
reset
$U v2.0.0-rc1 deadbeef a.dmg >/dev/null
patch="$(grep 'method PATCH' "$FAKE_LOG")"
grep -q 'prerelease=true' <<<"$patch" || fail "prerelease true: $patch"
grep -q 'make_latest=false' <<<"$patch" || fail "make_latest false: $patch"
echo "PASS" >&2

echo "=== draft, unsigned (RELEASE_PRERELEASE=1) ===" >&2
reset
RELEASE_PRERELEASE=1 $U v1.1.0 deadbeef a.dmg >/dev/null
grep 'method PATCH' "$FAKE_LOG" | grep -q 'prerelease=true' || fail "unsigned prerelease"
echo "PASS" >&2

echo "=== DRY_PUBLISH=1: uploads, no PATCH ===" >&2
reset
DRY_PUBLISH=1 $U v1.1.0 deadbeef a.dmg >/dev/null
grep -q 'method POST' "$FAKE_LOG" || fail "no upload"
grep -q PATCH "$FAKE_LOG" && fail "patched under DRY_PUBLISH"
echo "PASS" >&2

echo "=== none: gh release create ===" >&2
reset
$U v3.0.0 deadbeef a.dmg a.dmg.sha256 >/dev/null
c="$(grep 'release create' "$FAKE_LOG")"
for want in 'create v3.0.0 a.dmg a.dmg.sha256' '--title TimeTug 3.0.0' '--target deadbeef' '--generate-notes' '--notes SHA-256: abc123'; do
  grep -qF -- "$want" <<<"$c" || fail "missing '$want' in: $c"
done
grep -q -- '--prerelease' <<<"$c" && fail "stable must not be prerelease"
echo "PASS" >&2

echo "=== none, suffixed / unsigned ===" >&2
reset
$U v3.0.0-rc1 deadbeef a.dmg >/dev/null
grep 'release create' "$FAKE_LOG" | grep -q -- '--prerelease' || fail "suffixed prerelease"
reset
RELEASE_PRERELEASE=1 RELEASE_TITLE_SUFFIX=" (unsigned)" RELEASE_NOTES_PREFIX="Unsigned build." $U v3.0.0 deadbeef a.dmg a.dmg.sha256 >/dev/null
c="$(grep 'release create' "$FAKE_LOG")"
grep -q -- '--prerelease' <<<"$c" || fail "unsigned prerelease"
grep -qF -- 'TimeTug 3.0.0 (unsigned)' <<<"$c" || fail "unsigned title: $c"
grep -qF -- 'Unsigned build. SHA-256: abc123' <<<"$c" || fail "unsigned notes: $c"
echo "PASS" >&2
echo "ALL PASS"
