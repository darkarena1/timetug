#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
# shellcheck disable=SC1091
source scripts/ci/wait-for-ci.sh
fail() { echo "FAIL: $*" >&2; exit 1; }
t() { local want="$1" json="$2" got; got="$(printf '%s' "$json" | newest_conclusion)"; [ "$got" = "$want" ] || fail "want '$want' got '$got' for $json"; }

t "" '{"workflow_runs":[]}'
t "success" '{"workflow_runs":[{"run_number":1,"status":"completed","conclusion":"success"}]}'
t "failure" '{"workflow_runs":[{"run_number":1,"status":"completed","conclusion":"failure"}]}'
# newer in-progress run must not be masked by an older success
t "" '{"workflow_runs":[{"run_number":1,"status":"completed","conclusion":"success"},{"run_number":2,"status":"in_progress","conclusion":null}]}'
# newer failure beats older success, regardless of array order
t "failure" '{"workflow_runs":[{"run_number":2,"status":"completed","conclusion":"failure"},{"run_number":1,"status":"completed","conclusion":"success"}]}'
# newer success beats older failure
t "success" '{"workflow_runs":[{"run_number":1,"status":"completed","conclusion":"failure"},{"run_number":2,"status":"completed","conclusion":"success"}]}'
echo "PASS"
