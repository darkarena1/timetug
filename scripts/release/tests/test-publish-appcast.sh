#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q --bare "$T/remote.git"
fail() { echo "FAIL: $*" >&2; exit 1; }

echo "=== Test 1: Basic publish with pruning ===" >&2
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
echo "PASS: Test 1" >&2

echo "=== Test 2: Commit fails when git identity is missing ===" >&2
T2="$(mktemp -d)"; trap 'rm -rf "$T" "$T2"' EXIT
git init -q --bare "$T2/remote.git"
git_config_global="$(mktemp)"; trap 'rm -rf "$T" "$T2" "$git_config_global"' EXIT
# Create a git config that requires identity but doesn't provide it
echo "[user]" > "$git_config_global"
echo "  useConfigOnly = true" >> "$git_config_global"
# Run script with no git identity configured
(
  export GIT_CONFIG_GLOBAL="$git_config_global"
  export GIT_CONFIG_NOSYSTEM=1
  unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
  scripts/release/publish-appcast.sh "$T2/remote.git" -- \
    --title "Test" --version "100" --short "1.0" --url "https://e/1.zip" \
    --length 1 --signature S --min-system 14.0 2>/dev/null
) && fail "expected non-zero exit when git identity is missing" || true
# Verify no commit was made on the remote
remote_commits=$(git -C "$T2/remote.git" rev-list --all 2>/dev/null | wc -l)
[ "$remote_commits" -eq 0 ] || fail "remote should have no commits when git identity is missing, but has $remote_commits"
echo "PASS: Test 2" >&2

echo "=== Test 3: Retry on rejected push ===" >&2
T3="$(mktemp -d)"; trap 'rm -rf "$T" "$T2" "$T3"' EXIT
git init -q --bare "$T3/remote.git"
# Initialize gh-pages branch with a dummy commit so it exists for the retry
(
  git clone -q "$T3/remote.git" "$T3/init"
  cd "$T3/init"
  git checkout -q --orphan gh-pages
  touch .nojekyll
  git add .nojekyll
  git -c user.name=t -c user.email=t@t commit -q -m "init"
  git push -q origin gh-pages
)
# Create pre-receive hook that rejects first push
cat > "$T3/remote.git/hooks/pre-receive" << 'HOOK'
#!/bin/bash
counter_file="$GIT_DIR/../hook_counter"
[ -f "$counter_file" ] && count=$(cat "$counter_file") || count=0
count=$((count + 1))
echo "$count" > "$counter_file"
if [ "$count" -eq 1 ]; then
  echo "pre-receive: rejecting first push" >&2
  exit 1
fi
exit 0
HOOK
chmod +x "$T3/remote.git/hooks/pre-receive"
# Run script and expect retry message
output="$(scripts/release/publish-appcast.sh "$T3/remote.git" -- \
  --title "Test" --version "200" --short "1.0" --url "https://e/1.zip" \
  --length 1 --signature S --min-system 14.0 2>&1)" || true
echo "$output" | grep -q "push rejected (attempt 1)" || fail "expected 'push rejected (attempt 1)' in output: $output"
# Verify the item was added
git clone -q --branch gh-pages "$T3/remote.git" "$T3/check"
grep -q "https://e/1.zip" "$T3/check/appcast.xml" || fail "expected item URL in appcast.xml"
# Verify no force push was used in the script
grep -q '\-\-force\|+gh-pages' scripts/release/publish-appcast.sh && fail "script should not use --force or force syntax"
echo "PASS: Test 3" >&2

echo "ALL TESTS PASS"
