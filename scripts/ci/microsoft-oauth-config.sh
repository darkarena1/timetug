#!/usr/bin/env bash
# Sourceable helper: hand the Microsoft Entra client id to the build without writing it into the repo.
#
# prepare_microsoft_oauth_xcconfig [DIR]
#   When MICROSOFT_OAUTH_CLIENT_ID is non-empty, writes it as an xcconfig line to a mode-600 temp file under DIR
#   (default: ${RUNNER_TEMP:-$TMPDIR}), exports TIMETUG_MICROSOFT_XCCONFIG pointing at it
#   (scripts/dev/link-signing.sh links it in during `xcodegen generate`) and removes the file on exit, keeping any
#   EXIT trap that already exists. When it is unset or empty it does nothing (local and PR builds stay Microsoft-less).
# A public client id is not confidential (it ships inside the app and appears in the sign-in URL), but it stays out of
# git and logs.

_tt_microsoft_cleanup() { [ -z "${_TT_MICROSOFT_TMP:-}" ] || rm -f "$_TT_MICROSOFT_TMP"; }

prepare_microsoft_oauth_xcconfig() {
  local dir="${1:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}}"
  local id="${MICROSOFT_OAUTH_CLIENT_ID:-}"
  [ -n "$id" ] || return 0
  mkdir -p "$dir"
  local umask_old; umask_old="$(umask)"
  umask 077
  _TT_MICROSOFT_TMP="$(mktemp "$dir/microsoft-oauth.XXXXXX")" || { umask "$umask_old"; return 1; }
  umask "$umask_old"
  chmod 600 "$_TT_MICROSOFT_TMP"
  printf 'MICROSOFT_OAUTH_CLIENT_ID = %s\n' "$id" > "$_TT_MICROSOFT_TMP"
  # Chain onto an existing EXIT trap instead of replacing it.
  local prev=""
  eval "set -- $(trap -p EXIT)"
  [ "${1:-}" = "trap" ] && prev="${3:-}"
  # shellcheck disable=SC2064
  trap "${prev:+$prev; }_tt_microsoft_cleanup" EXIT
  export TIMETUG_MICROSOFT_XCCONFIG="$_TT_MICROSOFT_TMP"
}
