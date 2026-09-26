#!/usr/bin/env bash
# Tests scripts/ci/microsoft-oauth-config.sh (prepare_microsoft_oauth_xcconfig) with fake values only.
set -euo pipefail
cd "$(dirname "$0")/../../.."
H="$PWD/scripts/ci/microsoft-oauth-config.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
[ -f "$H" ] || fail "helper $H is missing"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# Set: file written 0600 with the line, env exported, file removed on exit, prior EXIT trap kept.
out="$(env -i PATH="$PATH" MICROSOFT_OAUTH_CLIENT_ID=test-client-id \
  RUNNER_TEMP="$T" HELPER="$H" MARK="$T/prev-trap-ran" bash -c '
  set -euo pipefail
  trap "touch \"\$MARK\"" EXIT
  source "$HELPER"
  prepare_microsoft_oauth_xcconfig "$RUNNER_TEMP"
  f="$TIMETUG_MICROSOFT_XCCONFIG"
  [ -n "$f" ] || exit 11
  printf "%s\n" "$f"
  stat -f "%Lp" "$f" 2>/dev/null || stat -c "%a" "$f"
  cat "$f"
  bash -c "[ -n \"\${TIMETUG_MICROSOFT_XCCONFIG:-}\" ]" || exit 12   # exported to children
')" || fail "set: helper failed"
f="$(printf '%s\n' "$out" | sed -n 1p)"
[ "$(printf '%s\n' "$out" | sed -n 2p)" = 600 ] || fail "set: mode is not 600"
[ "$(printf '%s\n' "$out" | sed -n 3p)" = "MICROSOFT_OAUTH_CLIENT_ID = test-client-id" ] || fail "set: id line"
case "$f" in "$T"/*) ;; *) fail "set: file not under RUNNER_TEMP";; esac
[ ! -e "$f" ] || fail "set: temp file not removed on exit"
[ -e "$T/prev-trap-ran" ] || fail "set: existing EXIT trap was clobbered"

# Unset or empty: nothing written, nothing exported.
for setup in "" "MICROSOFT_OAUTH_CLIENT_ID="; do
  mkdir -p "$T/n"; rm -rf "$T/n"/*
  # shellcheck disable=SC2086
  env -i PATH="$PATH" $setup RUNNER_TEMP="$T/n" HELPER="$H" bash -c '
    set -euo pipefail
    source "$HELPER"
    prepare_microsoft_oauth_xcconfig "$RUNNER_TEMP"
    [ -z "${TIMETUG_MICROSOFT_XCCONFIG:-}" ] || exit 21
  ' || fail "unset: helper failed or exported a path"
  [ -z "$(ls -A "$T/n")" ] || fail "unset: a file was written"
done
echo "PASS"
