#!/usr/bin/env bash
# Tests check-architecture.sh: the real repo passes, a clean fixture passes, and each rule catches its violation.
set -euo pipefail
cd "$(dirname "$0")/../../.."
S="$PWD/scripts/ci/check-architecture.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

"$S" >/dev/null || { "$S" >&2; fail "the repository itself violates the architecture rules"; }

# A minimal repo shaped like this one that follows every rule.
pkg() { # pkg <name> <dependency paths...>
  local name="$1" deps="" d; shift
  for d in "$@"; do deps="$deps.package(path: \"$d\"), "; done
  mkdir -p "$T/Packages/$name/Sources/$name" "$T/Packages/$name/Tests/${name}Tests"
  printf '// swift-tools-version: 6.0\nlet package = Package(name: "%s", dependencies: [%s])\n' "$name" "$deps" \
    > "$T/Packages/$name/Package.swift"
  printf 'import Foundation\n' > "$T/Packages/$name/Sources/$name/A.swift"
}
pkg CalendarConnectors
mkdir -p "$T/Packages/CalendarConnectors/Sources/CalendarCore" "$T/Packages/CalendarConnectors/Sources/CalendarOAuth"
pkg TimeTugCore ../CalendarConnectors
pkg CalendarBridge ../TimeTugCore ../CalendarConnectors
pkg EventKitSource ../CalendarConnectors
pkg CalendarApple ../CalendarConnectors
pkg AppleIntelligenceInference ../TimeTugCore ../CalendarConnectors
printf 'import FoundationModels\nimport TimeTugCore\n' > "$T/Packages/AppleIntelligenceInference/Sources/AppleIntelligenceInference/B.swift"
printf 'import EventKit\n' > "$T/Packages/EventKitSource/Sources/EventKitSource/B.swift"
printf 'import AppKit\nimport CalendarOAuth\n' > "$T/Packages/CalendarApple/Sources/CalendarApple/B.swift"
printf '@preconcurrency import CalendarCore\nimport struct Foundation.Date\n' > "$T/Packages/TimeTugCore/Sources/TimeTugCore/B.swift"
printf 'import Testing\n@testable import TimeTugCore\n' > "$T/Packages/TimeTugCore/Tests/TimeTugCoreTests/T.swift"
printf '#if canImport(FoundationNetworking)\nimport FoundationNetworking\n#endif\nimport CalendarOAuth\n' \
  > "$T/Packages/CalendarConnectors/Sources/CalendarCore/B.swift"
printf 'func f(now: Date) -> Date { now } // never Date() here\n// Date() in a comment is fine\nlet a = x.startDate(); let b = someDate.now; let c = Date.distantPast\nlet s = "// Date()"; let e = Date(timeIntervalSince1970: 0)\n' \
  > "$T/Packages/TimeTugCore/Sources/TimeTugCore/Clock.swift"
mkdir -p "$T/Apps/macOS/Sources" "$T/Apps/macOS/Widgets" "$T/Apps/macOS/Shared"
printf 'import Sparkle\nimport EventKit\nimport SwiftUI\n' > "$T/Apps/macOS/Sources/App.swift"
printf 'import WidgetKit\nimport TimeTugCore\n' > "$T/Apps/macOS/Widgets/W.swift"

out="$("$S" "$T")" || fail "clean fixture rejected: $out"

# expect <file> <content> <message substring>: writing <content> to <file> must make the check fail with the message.
expect() {
  local f="$T/$1" had=0 out
  [ -e "$f" ] && { had=1; cp "$f" "$f.orig"; }
  mkdir -p "$(dirname "$f")"; printf '%b' "$2" > "$f"
  if out="$("$S" "$T" 2>/dev/null)"; then fail "accepted $1 containing: $2"; fi
  case "$out" in *"$3"*) ;; *) fail "for $1 expected '$3' in: $out" ;; esac
  case "$out" in "Packages/"*|"Apps/"*) ;; *) fail "violation is not reported as path:line: $out" ;; esac
  if [ "$had" = 1 ]; then mv "$f.orig" "$f"; else rm "$f"; fi
}
C=Packages/TimeTugCore/Sources/TimeTugCore/X.swift
expect "$C" 'import AppKit\n' "TimeTugCore may not import AppKit"
expect "$C" 'import CalendarOAuth\n' "TimeTugCore may not import CalendarOAuth"
expect "$C" '@testable import CalendarBridge\n' "TimeTugCore may not import CalendarBridge"
expect "$C" 'let t = Date()\n' "Date()"
expect "$C" 'Date()\n' "Date()"
expect "$C" 'f(x:Date())\n' "Date()"
expect "$C" 'if Date.now > x {}\n' "Date()"
expect "$C" 'let t = Date(timeIntervalSinceNow: 5)\n' "Date()"
expect Packages/TimeTugCore/Tests/TimeTugCoreTests/X.swift 'import EventKit\n' "TimeTugCore may not import EventKit"
expect Packages/CalendarConnectors/Sources/CalendarCore/X.swift 'import TimeTugCore\n' "CalendarConnectors may not import TimeTugCore"
expect Packages/CalendarConnectors/Tests/CalendarCoreTests/X.swift 'import Security\n' "CalendarConnectors may not import Security"
expect Packages/CalendarBridge/Sources/CalendarBridge/X.swift 'import SwiftUI\n' "CalendarBridge may not import SwiftUI"
expect Packages/EventKitSource/Sources/EventKitSource/X.swift 'import AppKit\n' "EventKitSource may not import AppKit"
expect Packages/EventKitSource/Sources/EventKitSource/X.swift 'import TimeTugCore\n' "EventKitSource may not import TimeTugCore"
expect Packages/CalendarApple/Sources/CalendarApple/X.swift 'import SwiftUI\n' "CalendarApple may not import SwiftUI"
expect Packages/CalendarApple/Sources/CalendarApple/X.swift 'import Sparkle\n' "Sparkle is app-only) may not import Sparkle"
expect Packages/AppleIntelligenceInference/Sources/AppleIntelligenceInference/X.swift 'import CalendarBridge\n' \
  "AppleIntelligenceInference may not import CalendarBridge"
expect Apps/macOS/Sources/X.swift 'import FoundationModels\n' "FoundationModels"
expect Apps/macOS/Widgets/X.swift 'import EventKit\n' "may not import EventKit"
expect Apps/macOS/Shared/X.swift 'import Sparkle\n' "may not import Sparkle"
expect Packages/TimeTugCore/Package.swift 'let package = Package(dependencies: [.package(path: "../CalendarBridge")])\n' \
  "TimeTugCore may not depend on ../CalendarBridge"
expect Packages/CalendarConnectors/Package.swift \
  'let package = Package(dependencies: [.package(url: "https://github.com/x/y", from: "1.0.0")])\n' \
  "CalendarConnectors may not depend on https://github.com/x/y"
expect Packages/NewThing/Package.swift 'let package = Package()\n' "no rule for Packages/NewThing"

# An explicit, commented exception to the clock rule is allowed.
printf 'let t = Date() // architecture-check: allow (wall clock for logging only)\n' > "$T/$C"
out="$("$S" "$T")" || fail "allow marker ignored: $out"
echo "PASS"
