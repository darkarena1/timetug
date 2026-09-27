#!/usr/bin/env bash
# Tests affected-tests.sh in a throwaway repo built from this repo's real manifests.
set -euo pipefail
cd "$(dirname "$0")/../../.."
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
g() { git -C "$T" -c user.name=t -c user.email=t@t "$@"; }

mkdir -p "$T/scripts/dev" "$T/Apps/macOS/Sources" "$T/scripts/ci/tests" "$T/scripts/release/tests" "$T/docs"
cp scripts/dev/affected-tests.sh "$T/scripts/dev/"
cp Apps/macOS/project.yml "$T/Apps/macOS/"
for m in Packages/*/Package.swift; do mkdir -p "$T/$(dirname "$m")/Sources"; cp "$m" "$T/$m"; touch "$T/$(dirname "$m")/Sources/A.swift"; done
touch "$T/Apps/macOS/Sources/App.swift" "$T/scripts/ci/tests/test-a.sh" "$T/scripts/ci/tests/test-workflows.sh" \
  "$T/scripts/release/tests/test-b.sh" "$T/scripts/release/tests/test_c.py" "$T/scripts/release/tests/old.sh.bak" \
  "$T/scripts/release/make-dmg.sh" "$T/docs/a.md"
printf '*.xcodeproj\n' > "$T/.gitignore"
g init -q -b master; g add -A; g commit -q -m init; g checkout -q -b feature
mkdir "$T/Apps/macOS/TimeTug.xcodeproj"   # generated project present

A="$T/scripts/dev/affected-tests.sh"
ARCH=scripts/ci/check-architecture.sh
APP="xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test"
GEN="xcodegen generate --spec Apps/macOS/project.yml"
st() { echo "swift test --package-path Packages/$1"; }
lines() { printf '%s\n' "$@"; }
check() { # check <description> <expected output> <args...>
  local desc="$1" want="$2" got; shift 2
  got="$("$A" "$@" 2>/dev/null)" || fail "$desc: exit $?"
  [ "$got" = "$want" ] || fail "$desc:
--- want
$want
--- got
$got"
}

check "leaf package" "$(lines $ARCH "$(st CalendarBridge)" "$APP")" Packages/CalendarBridge/Sources/A.swift
check "Core and its dependents" \
  "$(lines $ARCH "$(st TimeTugCore)" "$(st AppleIntelligenceInference)" "$(st CalendarBridge)" "$APP")" \
  Packages/TimeTugCore/Sources/A.swift
check "the library reaches everything, dependencies first" \
  "$(lines $ARCH "$(st CalendarConnectors)" "$(st EventKitSource)" "$(st TimeTugCore)" \
     "$(st AppleIntelligenceInference)" "$(st CalendarApple)" "$(st CalendarBridge)" "$APP")" \
  Packages/CalendarConnectors/Package.swift
check "absolute paths work" "$(lines $ARCH "$(st CalendarBridge)" "$APP")" "$T/Packages/CalendarBridge/Sources/A.swift"
check "existing app file" "$(lines $ARCH "$APP")" Apps/macOS/Sources/App.swift
check "project.yml regenerates" "$(lines "$GEN" "$APP")" Apps/macOS/project.yml
check "new app file regenerates" "$(lines $ARCH "$GEN" "$APP")" Apps/macOS/Sources/New.swift
check "docs only" "" docs/a.md
check "script dir tests" "$(lines scripts/release/tests/test-b.sh "python3 scripts/release/tests/test_c.py")" \
  scripts/release/make-dmg.sh
check "workflows" "$(lines scripts/ci/tests/test-workflows.sh)" .github/workflows/ci.yml
check "duplicates collapse" "$(lines $ARCH "$(st CalendarBridge)" "$APP")" \
  Packages/CalendarBridge/Sources/A.swift Packages/CalendarBridge/Package.swift Apps/macOS/Sources/App.swift

rmdir "$T/Apps/macOS/TimeTug.xcodeproj"
check "missing project regenerates" "$(lines $ARCH "$GEN" "$APP")" Apps/macOS/Sources/App.swift
mkdir "$T/Apps/macOS/TimeTug.xcodeproj"

# With no paths: committed, staged, unstaged and untracked changes since the merge base with master.
check "clean branch" ""
echo x >> "$T/Packages/EventKitSource/Sources/A.swift"; g commit -q -am "committed"
g checkout -q master; echo x >> "$T/Packages/TimeTugCore/Sources/A.swift"; g commit -q -am "master moved on"; g checkout -q feature
echo x >> "$T/docs/a.md"; g add docs/a.md
echo x >> "$T/Packages/CalendarApple/Sources/A.swift"
touch "$T/Packages/CalendarBridge/Sources/Untracked.swift"
check "git discovery ignores master's own changes" \
  "$(lines $ARCH "$(st CalendarApple)" "$(st CalendarBridge)" "$(st EventKitSource)" "$APP")"
check "--base" "$(lines $ARCH "$(st CalendarApple)" "$(st CalendarBridge)" "$APP")" --base HEAD

g add -A; g commit -q -m wip; g mv Apps/macOS/Sources/App.swift Apps/macOS/Sources/Renamed.swift; g commit -q -m rename
check "a renamed app file regenerates" "$(lines $ARCH "$GEN" "$APP")" --base HEAD~1

# --run executes in order and stops at the first failure.
printf '#!/bin/sh\necho ran-a\nexit 3\n' > "$T/scripts/ci/tests/test-workflows.sh"; chmod +x "$T/scripts/ci/tests/test-workflows.sh"
out="$("$A" --run .github/workflows/ci.yml 2>&1)" && fail "--run hid a failing command"
case "$out" in *ran-a*) ;; *) fail "--run did not run the command: $out" ;; esac
"$A" --bogus >/dev/null 2>&1 && fail "accepted an unknown option"
echo "PASS"
