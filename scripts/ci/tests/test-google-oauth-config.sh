#!/usr/bin/env bash
# Tests scripts/ci/google-oauth-config.sh (prepare_google_oauth_xcconfig) with fake values only.
set -euo pipefail
cd "$(dirname "$0")/../../.."
H="$PWD/scripts/ci/google-oauth-config.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
[ -f "$H" ] || fail "helper $H is missing"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mode() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }

# Both set: file written 0600 with both lines, env exported, file removed on exit, prior EXIT trap kept.
out="$(env -i PATH="$PATH" GOOGLE_OAUTH_CLIENT_ID=test-client-id GOOGLE_OAUTH_CLIENT_SECRET=test-client-secret \
  RUNNER_TEMP="$T" HELPER="$H" MARK="$T/prev-trap-ran" bash -c '
  set -euo pipefail
  trap "touch \"\$MARK\"" EXIT
  source "$HELPER"
  prepare_google_oauth_xcconfig "$RUNNER_TEMP"
  f="$TIMETUG_GOOGLE_XCCONFIG"
  [ -n "$f" ] || exit 11
  printf "%s\n" "$f"
  stat -f "%Lp" "$f" 2>/dev/null || stat -c "%a" "$f"
  cat "$f"
  bash -c "[ -n \"\${TIMETUG_GOOGLE_XCCONFIG:-}\" ]" || exit 12   # exported to children
')" || fail "both set: helper failed"
f="$(printf '%s\n' "$out" | sed -n 1p)"
[ "$(printf '%s\n' "$out" | sed -n 2p)" = 600 ] || fail "both set: mode is not 600"
[ "$(printf '%s\n' "$out" | sed -n 3p)" = "GOOGLE_OAUTH_CLIENT_ID = test-client-id" ] || fail "both set: id line"
[ "$(printf '%s\n' "$out" | sed -n 4p)" = "GOOGLE_OAUTH_CLIENT_SECRET = test-client-secret" ] || fail "both set: secret line"
case "$f" in "$T"/*) ;; *) fail "both set: file not under RUNNER_TEMP";; esac
[ ! -e "$f" ] || fail "both set: temp file not removed on exit"
[ -e "$T/prev-trap-ran" ] || fail "both set: existing EXIT trap was clobbered"

# Neither set (also empty strings): nothing written, nothing exported.
for setup in "" "GOOGLE_OAUTH_CLIENT_ID= GOOGLE_OAUTH_CLIENT_SECRET="; do
  mkdir -p "$T/n"; rm -rf "$T/n"/*
  # shellcheck disable=SC2086
  env -i PATH="$PATH" $setup RUNNER_TEMP="$T/n" HELPER="$H" bash -c '
    set -euo pipefail
    source "$HELPER"
    prepare_google_oauth_xcconfig "$RUNNER_TEMP"
    [ -z "${TIMETUG_GOOGLE_XCCONFIG:-}" ] || exit 21
  ' || fail "neither set: helper failed or exported a path"
  [ -z "$(ls -A "$T/n")" ] || fail "neither set: a file was written"
done

# Exactly one set: non-zero exit, clear message, value not printed, no file.
for pair in "GOOGLE_OAUTH_CLIENT_ID=test-client-id" "GOOGLE_OAUTH_CLIENT_SECRET=test-client-secret"; do
  rm -rf "$T/o"; mkdir -p "$T/o"
  if err="$(env -i PATH="$PATH" "$pair" RUNNER_TEMP="$T/o" HELPER="$H" bash -c '
      set -euo pipefail
      source "$HELPER"
      prepare_google_oauth_xcconfig "$RUNNER_TEMP"' 2>&1)"; then
    fail "one set ($pair): expected failure"
  fi
  case "$err" in *test-client-*) fail "one set: message leaked a value";; esac
  case "$err" in *GOOGLE_OAUTH_CLIENT_ID*GOOGLE_OAUTH_CLIENT_SECRET*|*both*) ;; *) fail "one set: unclear message: $err";; esac
  [ -z "$(ls -A "$T/o")" ] || fail "one set: a file was written"
done
echo "PASS"
