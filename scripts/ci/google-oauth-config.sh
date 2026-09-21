#!/usr/bin/env bash
# Sourceable helper: hand the Google Desktop OAuth client to the build without writing it into the repo.
#
# prepare_google_oauth_xcconfig [DIR]
#   When GOOGLE_OAUTH_CLIENT_ID and GOOGLE_OAUTH_CLIENT_SECRET are both non-empty, writes them as xcconfig
#   lines to a mode-600 temp file under DIR (default: ${RUNNER_TEMP:-$TMPDIR}), exports TIMETUG_GOOGLE_XCCONFIG
#   pointing at it (scripts/dev/link-signing.sh links it in during `xcodegen generate`) and removes the file on
#   exit, keeping any EXIT trap that already exists. When neither is set it does nothing (local and PR builds stay
#   Google-less). When only one is set it fails; values are never printed.
# The client secret of a Desktop-app OAuth client is not confidential to Google, but it stays out of git.

_tt_google_cleanup() { [ -z "${_TT_GOOGLE_TMP:-}" ] || rm -f "$_TT_GOOGLE_TMP"; }

prepare_google_oauth_xcconfig() {
  local dir="${1:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}}"
  local id="${GOOGLE_OAUTH_CLIENT_ID:-}" secret="${GOOGLE_OAUTH_CLIENT_SECRET:-}"
  if [ -z "$id" ] && [ -z "$secret" ]; then
    return 0
  fi
  if [ -z "$id" ] || [ -z "$secret" ]; then
    echo "error: set both GOOGLE_OAUTH_CLIENT_ID and GOOGLE_OAUTH_CLIENT_SECRET, or neither" >&2
    return 1
  fi
  mkdir -p "$dir"
  local umask_old; umask_old="$(umask)"
  umask 077
  _TT_GOOGLE_TMP="$(mktemp "$dir/google-oauth.XXXXXX")" || { umask "$umask_old"; return 1; }
  umask "$umask_old"
  chmod 600 "$_TT_GOOGLE_TMP"
  printf 'GOOGLE_OAUTH_CLIENT_ID = %s\nGOOGLE_OAUTH_CLIENT_SECRET = %s\n' "$id" "$secret" > "$_TT_GOOGLE_TMP"
  # Chain onto an existing EXIT trap instead of replacing it.
  local prev=""
  eval "set -- $(trap -p EXIT)"
  [ "${1:-}" = "trap" ] && prev="${3:-}"
  # shellcheck disable=SC2064
  trap "${prev:+$prev; }_tt_google_cleanup" EXIT
  export TIMETUG_GOOGLE_XCCONFIG="$_TT_GOOGLE_TMP"
}
