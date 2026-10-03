#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
if ! command -v shellcheck >/dev/null 2>&1; then echo 'ShellCheck 0.11.0 is required' >&2; exit 2; fi
version="$(shellcheck --version | sed -n 's/^version: //p')"
if [[ "$version" != 0.11.0 ]]; then echo "ShellCheck 0.11.0 is required; found $version" >&2; exit 2; fi
shellcheck -s bash scripts/dev/verify.sh scripts/dev/tests/test-verify.sh scripts/ci/tests/test-workflows.sh
