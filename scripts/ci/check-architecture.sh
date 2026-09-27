#!/usr/bin/env bash
# Checks the layering rules from AGENTS.md ("Rules") that the compiler does not enforce on its own.
# Usage: scripts/ci/check-architecture.sh [repo-root]
# Prints one "path:line: message" per violation and exits 1 if there are any.
# Imports are matched at the start of a line (Swift style here); `import A; import B` on one line is not checked.
# To add a package, give it a line in allowed_deps and, if it needs them, import rules below.
set -euo pipefail
cd "${1:-$(dirname "$0")/../..}"
bad=0
report() { echo "$1: $2"; bad=$((bad + 1)); }
has() { case " $1 " in *" $2 "*) return 0 ;; esac; return 1; }

# imports <path...>: prints "file:line Module" for each Swift import (attributes and import kinds stripped).
imports() {
  local p existing=()
  for p in "$@"; do [ -e "$p" ] && existing+=("$p"); done
  [ ${#existing[@]} -gt 0 ] || return 0
  grep -rnE --include='*.swift' '^[[:space:]]*(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*import[[:space:]]' "${existing[@]}" |
    sed -E 's/^([^:]+:[0-9]+):[[:space:]]*(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*).*/\1 \6/' || true
}
# only <label> <allowed modules> <path...>: every import must be in the allowed list.
only() {
  local label="$1" allowed="$2" loc mod; shift 2
  while read -r loc mod; do
    has "$allowed" "$mod" || report "$loc" "$label may not import $mod (allowed: $allowed)"
  done < <(imports "$@")
}
# never <label> <forbidden modules> <path...>: no import may be in the forbidden list.
never() {
  local label="$1" forbidden="$2" loc mod; shift 2
  while read -r loc mod; do
    has "$forbidden" "$mod" && report "$loc" "$label may not import $mod"
  done < <(imports "$@")
  return 0
}

UI="AppKit SwiftUI UIKit WidgetKit"
LIB="$(ls Packages/CalendarConnectors/Sources 2>/dev/null | tr '\n' ' ')"
P=Packages

# Core is platform-neutral and builds on Linux: Foundation and the connector model only.
only TimeTugCore "Foundation CalendarCore TimeTugCore Testing" $P/TimeTugCore/Sources $P/TimeTugCore/Tests
# The connector library imports nothing from TimeTug and nothing Apple-only (it builds on Linux).
only CalendarConnectors "Foundation FoundationNetworking Testing $LIB" $P/CalendarConnectors/Sources $P/CalendarConnectors/Tests
# The bridge is minimal glue between Core and the library.
only CalendarBridge "Foundation TimeTugCore CalendarCore" $P/CalendarBridge/Sources
# Source adapters speak the library, contain no UI and never see TimeTug.
never EventKitSource "$UI TimeTugCore CalendarBridge CalendarApple AppleIntelligenceInference" $P/EventKitSource/Sources
never CalendarApple "SwiftUI UIKit WidgetKit TimeTugCore CalendarBridge EventKitSource AppleIntelligenceInference" $P/CalendarApple/Sources
never AppleIntelligenceInference "$UI CalendarBridge EventKitSource CalendarApple" $P/AppleIntelligenceInference/Sources
# Foundation Models only in the inference package; Sparkle only in the app target.
for d in $P/*; do
  [ "$d" = $P/AppleIntelligenceInference ] || never "$d" FoundationModels "$d"
done
never "Apps/macOS (use AppleIntelligenceInference)" FoundationModels Apps
never "$P (Sparkle is app-only)" Sparkle $P
# Widgets read the snapshot; they never touch EventKit or Sparkle.
never "Apps/macOS/Widgets and Shared" "EventKit Sparkle" Apps/macOS/Widgets Apps/macOS/Shared

# Time is passed in: Core never reads the clock. Mark a justified exception with "architecture-check: allow".
if [ -d $P/TimeTugCore/Sources ]; then
  while IFS= read -r hit; do
    report "$(echo "$hit" | cut -d: -f1,2)" "TimeTugCore reads the clock (Date()/Date.now); pass now: Date in instead"
  done < <(grep -rn --include='*.swift' 'Date' $P/TimeTugCore/Sources | grep -v 'architecture-check: allow' |
    sed -E -e 's#^([^:]+:[0-9]+:)[[:space:]]*//.*#\1#' -e 's#[[:space:]]//.*##' |
    grep -E '^[^:]+:[0-9]+:(.*[^A-Za-z0-9_])?Date(\(\)|\.now([^A-Za-z0-9_]|$)|\(timeIntervalSinceNow)' || true)
fi

# Package dependencies point toward Core and the connector library, which has none.
allowed_deps() {
  case "$1" in
    CalendarConnectors) echo "" ;;
    TimeTugCore | EventKitSource | CalendarApple) echo "../CalendarConnectors" ;;
    CalendarBridge | AppleIntelligenceInference) echo "../TimeTugCore ../CalendarConnectors" ;;
    *) return 1 ;;
  esac
}
for manifest in $P/*/Package.swift; do
  [ -e "$manifest" ] || continue
  name="$(basename "$(dirname "$manifest")")"
  if ! allowed="$(allowed_deps "$name")"; then
    report "$manifest:1" "no rule for $P/$name in scripts/ci/check-architecture.sh; add its allowed dependencies (and AGENTS.md Rules)"
    continue
  fi
  # Read the manifest as one line so a .package(...) wrapped across lines is still seen.
  while IFS= read -r dep; do
    line="$(grep -nF "\"$dep\"" "$manifest" | head -1 | cut -d: -f1)"
    has "$allowed" "$dep" || report "$manifest:${line:-1}" "$name may not depend on $dep (allowed: ${allowed:-none})"
  done < <(tr '\n' ' ' < "$manifest" | grep -oE '\.package\([^)]*\)' |
    sed -E 's/.*(path|url):[[:space:]]*"([^"]*)".*/\2/' || true)
done

[ "$bad" = 0 ] || { echo "$bad architecture violation(s); the rules are in AGENTS.md (Rules)" >&2; exit 1; }
