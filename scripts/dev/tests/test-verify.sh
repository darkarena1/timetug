#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo/scripts/dev" "$T/repo/scripts/ci/tests" "$T/repo/scripts/release/tests" "$T/repo/site/tests" "$T/bin"
cp "$ROOT/scripts/dev/verify.sh" "$T/repo/scripts/dev/verify.sh"
cat > "$T/repo/scripts/dev/tests-placeholder" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
mkdir -p "$T/repo/scripts/dev/tests"
mv "$T/repo/scripts/dev/tests-placeholder" "$T/repo/scripts/dev/tests/test-verify.sh"
for name in swift xcodegen xcodebuild python3 node; do
  cat > "$T/bin/$name" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$*" >> "$VERIFY_CALLS"
if [[ "$(basename "$0")" == swift ]] &&
   [[ -n "${TIMETUG_LIVE_EVENTKIT:-}${TIMETUG_LIVE_GOOGLE:-}${TIMETUG_LIVE_MICROSOFT:-}" ]]; then
  printf 'LIVE_FLAGS_INHERITED\n' >> "$VERIFY_CALLS"
fi
SCRIPT
  chmod +x "$T/bin/$name"
done
cat > "$T/repo/scripts/ci/tests/test-dummy.sh" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
cp "$T/repo/scripts/ci/tests/test-dummy.sh" "$T/repo/scripts/release/tests/test-dummy.sh"
cd "$T/repo"
git init -q
git config user.email test@example.com
git config user.name Test
printf 'base\n' > README.md
printf 'build/\n' > .gitignore
git add .
git commit -qm base
export VERIFY_CALLS="$T/calls" PATH="$T/bin:$PATH"
fail() { echo "FAIL: $*" >&2; exit 1; }
run_mode() { : > "$VERIFY_CALLS"; scripts/dev/verify.sh "$@" >/dev/null; }
run_mode core
grep -q 'swift test --package-path Packages/TimeTugCore' "$VERIFY_CALLS" || fail 'core omitted'
[ "$(grep -c 'swift test --package-path Packages/CalendarConnectors' "$VERIFY_CALLS")" = 1 ] || fail 'connectors duplicated'
export TIMETUG_LIVE_EVENTKIT=1 TIMETUG_LIVE_GOOGLE=1 TIMETUG_LIVE_MICROSOFT=1
run_mode core
if grep -q LIVE_FLAGS_INHERITED "$VERIFY_CALLS"; then fail 'live-test flags reached package tests'; fi
mkdir -p Apps/macOS
echo x > Apps/macOS/'file with spaces.swift'
run_mode affected
grep -q 'xcodegen generate' "$VERIFY_CALLS" || fail 'untracked app with spaces omitted'
if grep -q '^swift ' "$VERIFY_CALLS"; then fail 'app-only change ran packages'; fi
rm Apps/macOS/'file with spaces.swift'
mkdir -p docs
echo docs > docs/change.md
run_mode affected
grep -q 'python3 scripts/ci/check-repository-contracts.py' "$VERIFY_CALLS" || fail 'documentation check omitted'
if grep -q '^swift\|^xcodebuild' "$VERIFY_CALLS"; then fail 'documentation ran build'; fi
rm docs/change.md
mkdir -p Packages/CalendarConnectors/Sources/CalendarCore
echo model > Packages/CalendarConnectors/Sources/CalendarCore/'model with spaces.swift'
run_mode affected
grep -q 'swift test --package-path Packages/CalendarApple' "$VERIFY_CALLS" || fail 'connector dependents omitted'
grep -q 'xcodebuild ' "$VERIFY_CALLS" || fail 'connector app dependent omitted'
rm Packages/CalendarConnectors/Sources/CalendarCore/'model with spaces.swift'
mkdir -p .github/workflows
echo workflow > .github/workflows/new.yml
run_mode affected
grep -q 'node --test site/tests/download.test.js' "$VERIFY_CALLS" || fail 'workflow release-tools omitted'
if grep -q '^swift\|^xcodebuild' "$VERIFY_CALLS"; then fail 'workflow change ran build'; fi
rm .github/workflows/new.yml
run_mode affected
[ ! -s "$VERIFY_CALLS" ] || fail 'no-change run executed checks'
if scripts/dev/verify.sh affected --base missing-ref >/dev/null 2>&1; then fail 'missing base accepted'; fi
cat > "$T/bin/swift" <<'SCRIPT'
#!/usr/bin/env bash
exit 7
SCRIPT
chmod +x "$T/bin/swift"
if scripts/dev/verify.sh core >/dev/null 2>&1; then fail 'failed subprocess accepted'; fi
echo PASS
