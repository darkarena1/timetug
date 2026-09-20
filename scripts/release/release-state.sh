#!/usr/bin/env bash
# Prints the state of the GitHub release for a tag in $GITHUB_REPOSITORY: exactly one of
#   none       no release has this tag_name
#   draft      a draft release has it (assets can still be attached)
#   published  a published release has it (assets can still be added unless it is immutable)
#   published-immutable  a published release whose `immutable` field is true (assets and tag are locked)
# Looks at ALL releases including drafts. A draft created in the UI for a tag that does not exist yet
# still carries that tag_name (there is just no git tag), so the tag_name is what is matched.
#
# Usage: release-state.sh <tag>            print the state
#        release-state.sh --id <tag>       print the numeric release id (empty when none)
#        release-state.sh --prerelease <tag>  print true when the release's own prerelease flag is set
#                                          (drafts included), else false (also when there is no release)
# Requires: gh (authenticated), jq, GITHUB_REPOSITORY.
set -euo pipefail

mode=state
case "${1:-}" in
  --id) mode=id; shift ;;
  --prerelease) mode=prerelease; shift ;;
esac
TAG="${1:?usage: release-state.sh [--id] <tag>}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

# --paginate prints one JSON array per page; jq reads the stream.
row="$(gh api --paginate "repos/${GITHUB_REPOSITORY}/releases" \
  | jq -r --arg t "$TAG" '.[] | select(.tag_name == $t) | "\(.id) \(.draft) \(.immutable // false) \(.prerelease // false)"' | head -n 1)"

if [ "$mode" = id ]; then
  echo "${row%% *}"
  exit 0
fi
if [ "$mode" = prerelease ]; then
  case "$row" in *" true") echo true ;; *) echo false ;; esac
  exit 0
fi
read -r _ draft immutable _ <<<"$row"
if [ -z "$row" ]; then echo none
elif [ "$draft" = true ]; then echo draft
elif [ "$immutable" = true ]; then echo published-immutable
else echo published; fi
