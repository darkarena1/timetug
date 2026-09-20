#!/usr/bin/env bash
# Wait until the NEWEST CI workflow run for <sha> concludes. Exit 0 on success, 1 on any other conclusion
# or timeout. A newer in-progress run (e.g. a re-run) is waited for, never masked by an older result.
# Usage: wait-for-ci.sh <sha>   (env GH_TOKEN, GITHUB_REPOSITORY; WAIT_MINUTES default 45)
set -euo pipefail

# Reads the workflow-runs API JSON on stdin; prints the newest run's conclusion, or nothing if there is
# no run yet or the newest run has not completed.
newest_conclusion() {
  jq -r '[.workflow_runs[]] | sort_by(.run_number) | last
         | if . == null or .status != "completed" then "" else (.conclusion // "unknown") end'
}

main() {
  local sha="${1:?sha}" conclusion
  local deadline=$(( $(date +%s) + ${WAIT_MINUTES:-45} * 60 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    conclusion="$(gh api "repos/$GITHUB_REPOSITORY/actions/workflows/ci.yml/runs?head_sha=$sha&event=pull_request" \
      | newest_conclusion)"
    case "$conclusion" in
      success) echo "CI succeeded for $sha"; exit 0 ;;
      "") sleep 30 ;;
      *) echo "CI concluded '$conclusion' for $sha" >&2; exit 1 ;;
    esac
  done
  echo "timed out waiting for CI on $sha" >&2
  exit 1
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
