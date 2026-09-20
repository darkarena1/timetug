#!/usr/bin/env bash
# Add an item to appcast.xml on the gh-pages branch of <remote> and push. Never force-pushes: a rejected
# push is fetched, rebased and retried (bounded). Serialise callers with the `appcast` concurrency group.
# Usage: publish-appcast.sh <remote> [--keep-betas N] -- <appcast.py add args, without --file>
# Prints the enclosure URL of every pruned beta, one per line (stdout); progress goes to stderr.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
remote="${1:?remote}"; shift
keep=""
if [ "${1:-}" = "--keep-betas" ]; then keep="$2"; shift 2; fi
[ "${1:-}" = "--" ] && shift

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
if git ls-remote --exit-code --heads "$remote" gh-pages >/dev/null 2>&1; then
  git clone -q --branch gh-pages "$remote" "$work/repo"
else
  git init -q "$work/repo"
  git -C "$work/repo" checkout -q --orphan gh-pages
  git -C "$work/repo" remote add origin "$remote"
  touch "$work/repo/.nojekyll"
fi
repo="$work/repo"

for attempt in 1 2 3 4 5; do
  python3 "$ROOT/scripts/release/appcast.py" add --file "$repo/appcast.xml" "$@"
  pruned=""
  if [ -n "$keep" ]; then
    pruned="$(python3 "$ROOT/scripts/release/appcast.py" prune-betas --file "$repo/appcast.xml" --keep "$keep")"
  fi
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "appcast: update" || true
  if git -C "$repo" push -q origin gh-pages >&2 2>&1; then
    [ -n "$pruned" ] && echo "$pruned"
    exit 0
  fi
  echo "push rejected (attempt $attempt); rebasing" >&2
  git -C "$repo" fetch -q origin gh-pages
  git -C "$repo" reset -q --hard origin/gh-pages
done
echo "error: could not push gh-pages after 5 attempts" >&2
exit 1
