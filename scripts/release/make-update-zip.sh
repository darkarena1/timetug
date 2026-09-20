#!/usr/bin/env bash
# Zip an app bundle for Sparkle. ditto keeps resource forks and symlinks intact (plain `zip` breaks them).
set -euo pipefail
app="${1:?app path}"; out="${2:?output zip}"
[ -d "$app" ] || { echo "error: $app not found" >&2; exit 1; }
rm -f "$out"
ditto -c -k --keepParent "$app" "$out"
echo "$out"
