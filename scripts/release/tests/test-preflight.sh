#!/usr/bin/env bash
# Tests preflight-release.sh against a fake `gh` on PATH and a throwaway git repo.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir "$T/bin"
cat > "$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
# `gh api --paginate .../releases` returns $FAKE_RELEASES; `gh api .../releases/<id> --jq .body` returns that release's body.
if [ "${1:-}" = api ] && [ "${2:-}" = --paginate ]; then cat "$FAKE_RELEASES"; exit 0; fi
if [ "${1:-}" = api ]; then
  id="${2##*/}"
  jq -rs --arg id "$id" '.[] | .[] | select((.id | tostring) == $id) | .body' "$FAKE_RELEASES"
  exit 0
fi
exit 0
STUB
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH" GITHUB_REPOSITORY=o/r FAKE_RELEASES="$T/releases.json"
P="$ROOT/scripts/release/preflight-release.sh"

git init -q "$T/repo"; cd "$T/repo"
git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
for t in v1.0.0 v1.3.0 v1.4.0-rc1 v1.5.0 beta-20260101000000; do git tag "$t"; done

good='## What'"'"'s Changed\n* A change by @me in https://x/pull/1\n\n**Full Changelog**: https://github.com/o/r/compare/v1.3.0...v1.5.0'
cat > "$FAKE_RELEASES" <<J
[{"id":1,"tag_name":"v1.5.0","draft":false,"body":"$good"},
 {"id":2,"tag_name":"v1.6.0","draft":true,"body":"$good"},
 {"id":3,"tag_name":"v1.7.0","draft":true,"body":""},
 {"id":4,"tag_name":"v1.8.0","draft":true,"body":"Had to republish 1.7.0"},
 {"id":5,"tag_name":"v1.9.0-rc1","draft":true,"body":"quick candidate"},
 {"id":6,"tag_name":"v0.9.0","draft":true,"body":"first release, nothing before it"}]
J

echo "=== a manual run needs the tag to exist ===" >&2
out="$($P v1.6.0 workflow_dispatch 2>&1)" && fail "missing tag accepted for a manual run"
grep -q "tag v1.6.0 does not exist" <<<"$out" || fail "message: $out"
grep -q "Publish" <<<"$out" || fail "message should say to publish the release: $out"
$P v1.5.0 workflow_dispatch >/dev/null 2>&1 || fail "existing tag with good notes rejected"
echo "PASS" >&2

echo "=== a release event's tag exists by construction ===" >&2
$P v1.5.0 release >/dev/null 2>&1 || fail "release event with good notes rejected"
echo "PASS" >&2

echo "=== stable notes must list the changes since the previous stable release ===" >&2
git tag v1.6.0; git tag v1.7.0; git tag v1.8.0; git tag v0.9.0
out="$($P v1.7.0 release 2>&1)" && fail "empty notes accepted"
grep -q "notes are empty" <<<"$out" || fail "empty: $out"
out="$($P v1.8.0 release 2>&1)" && fail "hand-written notes accepted"
grep -q "What's Changed" <<<"$out" && grep -q "Generate release notes" <<<"$out" || fail "hand-written: $out"
out="$($P v1.6.0 release 2>&1)" && fail "changelog from the wrong tag accepted"
grep -q "compare/v1.5.0...v1.6.0" <<<"$out" || fail "should name the expected compare range: $out"
echo "PASS" >&2

echo "=== the first stable release has no previous tag to compare with ===" >&2
$P v0.9.0 release >/dev/null 2>&1 && fail "notes without What's Changed accepted for the first release"
echo "PASS" >&2

echo "=== a suffixed (beta channel) tag is exempt from the notes check ===" >&2
git tag v1.9.0-rc1
$P v1.9.0-rc1 release >/dev/null 2>&1 || fail "prerelease notes were checked"
echo "PASS" >&2

echo "=== a release must exist ===" >&2
git tag v2.0.0
out="$($P v2.0.0 release 2>&1)" && fail "no release accepted"
grep -q "no release" <<<"$out" || fail "none: $out"
echo "PASS" >&2
echo "ALL PASS" >&2
