#!/usr/bin/env bash
# Reads release-asset URLs (whitespace separated) on stdin and prints the tag of each one that is a
# beta build, one per line: `v<version>-beta.<14-digit build>` or the legacy `beta-<digits>`.
# Every other tag (stable, rc, malformed) is never printed, so callers can delete what it prints.
set -euo pipefail
tr -s '[:space:]' '\n' | while IFS= read -r u || [ -n "$u" ]; do
  case "$u" in */download/*/*) ;; *) continue ;; esac
  rest="${u#*/download/}"
  tag="${rest%%/*}"
  if [[ "$tag" =~ ^v[0-9]+(\.[0-9]+)*-beta\.[0-9]{14}$ ]] || [[ "$tag" =~ ^beta-[0-9]+$ ]]; then
    printf '%s\n' "$tag"
  fi
done
