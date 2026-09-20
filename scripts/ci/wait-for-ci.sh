#!/usr/bin/env bash
# Wait until the CI workflow for <sha> concludes. Exit 0 on success, 1 on any other conclusion or timeout.
# Usage: wait-for-ci.sh <sha>   (env GH_TOKEN, GITHUB_REPOSITORY; WAIT_MINUTES default 45)
set -euo pipefail
sha="${1:?sha}"
deadline=$(( $(date +%s) + ${WAIT_MINUTES:-45} * 60 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  conclusion="$(gh api "repos/$GITHUB_REPOSITORY/actions/workflows/ci.yml/runs?head_sha=$sha&event=pull_request" \
    --jq '[.workflow_runs[] | select(.status=="completed")] | sort_by(.created_at) | last | .conclusion // ""')"
  case "$conclusion" in
    success) echo "CI succeeded for $sha"; exit 0 ;;
    "") sleep 30 ;;
    *) echo "CI concluded '$conclusion' for $sha" >&2; exit 1 ;;
  esac
done
echo "timed out waiting for CI on $sha" >&2
exit 1
