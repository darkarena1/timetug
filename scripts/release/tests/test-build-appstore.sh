#!/usr/bin/env bash
# Tests the input validation of scripts/release/build-appstore.sh (no Xcode, no secrets).
set -uo pipefail
cd "$(dirname "$0")/../../.."
script=scripts/release/build-appstore.sh
fail=0
expect_fail() { # expect_fail <label> <expected message fragment> <env assignments...>
  local label="$1" fragment="$2"; shift 2
  out="$(env "$@" DRY_RUN=1 "$script" 2>&1)" && { echo "FAIL $label: expected an error"; fail=1; return; }
  case "$out" in *"$fragment"*) echo "ok   $label" ;; *) echo "FAIL $label: got: $out"; fail=1 ;; esac
}
expect_fail "beta suffix refused" "App Store versions must be X.Y.Z" APP_VERSION=2.0.0-beta.1 BUILD_NUMBER=20261006010101
expect_fail "two-part version refused" "App Store versions must be X.Y.Z" APP_VERSION=2.0 BUILD_NUMBER=20261006010101
expect_fail "missing version" "APP_VERSION is required" BUILD_NUMBER=20261006010101
expect_fail "missing build number" "BUILD_NUMBER is required" APP_VERSION=2.0.0
expect_fail "non-numeric build number" "BUILD_NUMBER must be digits" APP_VERSION=2.0.0 BUILD_NUMBER=abc
expect_fail "unknown destination" "DESTINATION must be export or upload" APP_VERSION=2.0.0 BUILD_NUMBER=1 DESTINATION=ship
expect_fail "upload needs a key" "ASC_KEY_PATH is required for upload" APP_VERSION=2.0.0 BUILD_NUMBER=20261006010101 DESTINATION=upload
out="$(APP_VERSION=2.0.0 BUILD_NUMBER=20261006010101 DESTINATION=export DRY_RUN=1 "$script" 2>&1)" \
  && [ "$out" = "inputs ok" ] && echo "ok   valid input" || { echo "FAIL valid input: $out"; fail=1; }
exit "$fail"
