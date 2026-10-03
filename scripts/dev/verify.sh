#!/usr/bin/env bash
# One local entry point for deterministic TimeTug checks. Logs live under build/verify/.
set -euo pipefail
# Live provider tests require explicit, filtered commands from the operations runbook.
unset TIMETUG_LIVE_EVENTKIT TIMETUG_LIVE_GOOGLE TIMETUG_LIVE_MICROSOFT
export PYTHONDONTWRITEBYTECODE=1
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
MODE="${1:-}"
if [[ $# -gt 0 ]]; then shift; fi
BASE=""
if [[ "${1:-}" == --base && $# -eq 2 ]]; then BASE="$2"; shift 2; fi
if [[ $# -ne 0 || ! "$MODE" =~ ^(core|connectors|app|release-tools|all|affected)$ ]]; then
  echo 'usage: scripts/dev/verify.sh core|connectors|app|release-tools|all|affected [--base <git-ref>]' >&2
  exit 2
fi
if [[ -n "$BASE" ]] && ! git rev-parse --verify "${BASE}^{commit}" >/dev/null 2>&1; then
  echo "missing base ref: $BASE" >&2; exit 2
fi
START="$(date +%s)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)-$$"
LOG_DIR="$ROOT/build/verify/$STAMP"
mkdir -p "$LOG_DIR"
SUMMARY="$LOG_DIR/summary.txt"
HEAD="$(git rev-parse --short HEAD)"
DIRTY=clean
[[ -z "$(git status --porcelain)" ]] || DIRTY=dirty
printf 'mode=%s\nhead=%s\nstate=%s\nplatform=%s\nlog_dir=%s\n' "$MODE" "$HEAD" "$DIRTY" "$(uname -s)" "$LOG_DIR" > "$SUMMARY"
PASS=0; FAIL=0; SKIP=0
finish() {
  local code=$?
  printf 'passed=%s failed=%s skipped=%s elapsed_seconds=%s exit_code=%s\n' "$PASS" "$FAIL" "$SKIP" "$(( $(date +%s) - START ))" "$code" >> "$SUMMARY"
  cat "$SUMMARY"
}
trap finish EXIT
need() { if ! command -v "$1" >/dev/null 2>&1; then echo "missing prerequisite: $1" >&2; exit 2; fi; }
run() {
  local name="$1"; shift
  printf 'RUN %s\n' "$name" | tee -a "$SUMMARY"
  if "$@" > "$LOG_DIR/$name.log" 2>&1; then
    PASS=$((PASS+1)); printf 'PASS %s\n' "$name" | tee -a "$SUMMARY"
  else
    local status=$?; FAIL=$((FAIL+1)); printf 'FAIL %s exit=%s (see %s)\n' "$name" "$status" "$LOG_DIR/$name.log" | tee -a "$SUMMARY"
    tail -30 "$LOG_DIR/$name.log" >&2
    return "$status"
  fi
}
run_pkg() { need swift; run "$1" swift test --package-path "$2"; }
run_app() {
  need xcodegen; need xcodebuild
  run xcodegen xcodegen generate --spec Apps/macOS/project.yml
  run app xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test
}
run_release() {
  need bash; need python3; need node
  python3 -c 'import yaml' >/dev/null 2>&1 || { echo 'missing prerequisite: PyYAML (scripts/ci/requirements-test.txt)' >&2; exit 2; }
  for test in scripts/ci/tests/test-*.sh scripts/release/tests/test-*.sh; do run "$(basename "$test" .sh)" bash "$test"; done
  run wrapper-tests bash scripts/dev/tests/test-verify.sh
  run python-appcast python3 -m unittest discover -s scripts/release/tests -p 'test_*.py'
  run website node --test site/tests/download.test.js
  run website-syntax node --check site/public/download.js
  run website-config python3 -m json.tool site/firebase.json
}
run_contracts() { need python3; run repository-contracts python3 scripts/ci/check-repository-contracts.py; }
skip_check() { SKIP=$((SKIP+1)); printf 'SKIP %s (not selected)\n' "$1" >> "$SUMMARY"; }
# Files are NUL-delimited so spaces and unusual source names route correctly.
if [[ "$MODE" == affected ]]; then
  CHANGED=()
  if [[ -n "$BASE" ]]; then
    while IFS= read -r -d '' file; do CHANGED+=("$file"); done < <(git diff --name-only -z "$BASE" --)
  else
    while IFS= read -r -d '' file; do CHANGED+=("$file"); done < <(git diff --name-only -z --)
    while IFS= read -r -d '' file; do CHANGED+=("$file"); done < <(git diff --cached --name-only -z --)
  fi
  while IFS= read -r -d '' file; do CHANGED+=("$file"); done < <(git ls-files --others --exclude-standard -z)
  if [[ ${#CHANGED[@]} -eq 0 ]]; then echo 'No changed files; no checks selected.' | tee -a "$SUMMARY"; exit 0; fi
  WANT_CORE=0; WANT_CONNECTORS=0; WANT_APP=0; WANT_RELEASE=0; WANT_CONTRACTS=0
  for file in "${CHANGED[@]}"; do
    case "$file" in
      Packages/CalendarConnectors/*|Packages/CalendarApple/*|Packages/EventKitSource/*)
        WANT_CONNECTORS=1; WANT_CORE=1; WANT_APP=1;;
      Packages/TimeTugCore/*|Packages/CalendarBridge/*|Packages/AppleIntelligenceInference/*)
        WANT_CORE=1; WANT_APP=1;;
      Apps/macOS/*) WANT_APP=1;;
      scripts/release/*|scripts/ci/*|scripts/dev/*|.github/workflows/*|.github/dependabot.yml|site/*)
        WANT_RELEASE=1;;
      docs/*|AGENTS.md|README.md) WANT_CONTRACTS=1;;
      *) WANT_CORE=1; WANT_CONNECTORS=1; WANT_APP=1; WANT_RELEASE=1; WANT_CONTRACTS=1;;
    esac
  done
else
  WANT_CORE=0; WANT_CONNECTORS=0; WANT_APP=0; WANT_RELEASE=0; WANT_CONTRACTS=0
  case "$MODE" in
    core) WANT_CORE=1;;
    connectors) WANT_CONNECTORS=1;;
    app) WANT_APP=1;;
    release-tools) WANT_RELEASE=1; WANT_CONTRACTS=1;;
    all) WANT_CORE=1; WANT_CONNECTORS=1; WANT_APP=1; WANT_RELEASE=1; WANT_CONTRACTS=1;;
  esac
fi
[[ "$WANT_CORE" == 1 ]] || { skip_check core; skip_check bridge; skip_check inference; }
[[ "$WANT_CONNECTORS" == 1 || "$WANT_CORE" == 1 ]] || skip_check connectors
[[ "$WANT_CONNECTORS" == 1 ]] || { skip_check calendar-apple; skip_check eventkit; }
[[ "$WANT_APP" == 1 ]] || skip_check app
[[ "$WANT_RELEASE" == 1 ]] || skip_check release-tools
[[ "$WANT_CONTRACTS" == 1 ]] || skip_check repository-contracts
if [[ "$WANT_CONNECTORS" == 1 ]]; then
  run_pkg connectors Packages/CalendarConnectors
  run_pkg calendar-apple Packages/CalendarApple
  run_pkg eventkit Packages/EventKitSource
fi
if [[ "$WANT_CORE" == 1 ]]; then
  run_pkg core Packages/TimeTugCore
  [[ "$WANT_CONNECTORS" == 1 ]] || run_pkg connectors Packages/CalendarConnectors
  run_pkg bridge Packages/CalendarBridge
  run_pkg inference Packages/AppleIntelligenceInference
fi
if [[ "$WANT_APP" == 1 ]]; then run_app; fi
if [[ "$WANT_RELEASE" == 1 ]]; then run_release; fi
if [[ "$WANT_CONTRACTS" == 1 ]]; then run_contracts; fi
printf 'MANUAL: macOS window/status-item checklist and Linux portability are separate checks.\n' | tee -a "$SUMMARY"
