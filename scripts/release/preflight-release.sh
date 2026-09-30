#!/usr/bin/env bash
# Fails fast, before the 30 minute build, on the two mistakes that only show up at the end of a release run.
#
# 1. A manual run (workflow_dispatch) for a tag that does not exist. Publishing the draft would have to create the tag
#    as the workflow's token, which the "Protect release tags" ruleset refuses (HTTP 422 after the build). A published
#    release always has its tag, so the publish flow never hits this.
# 2. Release notes that do not say what changed. The workflow copies the release body into the appcast, and that is what
#    the update window shows, so a stable release's notes must be GitHub's generated list against the previous stable
#    tag: a "What's Changed" section and a "Full Changelog" link for compare/<previous stable>...<tag>. A tag with a `-`
#    suffix (a release candidate, beta channel) is exempt.
#
# Usage: preflight-release.sh <tag> <event>     event: release | workflow_dispatch
# Run from a checkout with every tag fetched. Requires: gh (authenticated), jq, git, GITHUB_REPOSITORY.
set -euo pipefail

TAG="${1:?usage: preflight-release.sh <tag> <event>}"
EVENT="${2:?usage: preflight-release.sh <tag> <event>}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ "$EVENT" = workflow_dispatch ] && ! git rev-parse -q --verify "refs/tags/$TAG^{commit}" >/dev/null; then
  echo "::error::tag $TAG does not exist. A manual run cannot create it (the release-tags ruleset only lets an admin do that). Publish the release in the GitHub UI, or with 'gh release edit $TAG --draft=false', and the published release starts this workflow itself."
  exit 1
fi

VERSION="${TAG#v}"
if [[ "$VERSION" == *-* ]]; then
  echo "$TAG has a suffix (beta channel); release notes are not checked."
  exit 0
fi

ID="$("$HERE/release-state.sh" --id "$TAG")"
if [ -z "$ID" ]; then
  echo "::error::no release exists for $TAG; draft one with notes first."
  exit 1
fi
BODY="$(gh api "repos/${GITHUB_REPOSITORY}/releases/${ID}" --jq '.body // ""')"

if [ -z "${BODY//[[:space:]]/}" ]; then
  echo "::error::the release notes are empty. Use 'Generate release notes' against the previous stable tag so the update window lists what changed."
  exit 1
fi
if ! grep -qF "What's Changed" <<<"$BODY"; then
  echo "::error::the release notes have no \"What's Changed\" section. They must list every change since the previous stable release (use 'Generate release notes' against that tag, even for a republish); the notes become the update window's text."
  exit 1
fi

# The newest stable tag below this one, by version order.
PREV="$(git tag -l 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | { grep -vxF "$TAG" || true; } \
  | { cat; echo "$TAG"; } | sort -V | awk -v t="$TAG" '$0 == t { print prev; exit } { prev = $0 }')"
if [ -n "$PREV" ] && ! grep -qF "compare/${PREV}...${TAG}" <<<"$BODY"; then
  echo "::error::the release notes do not cover the changes since $PREV: expected a \"Full Changelog\" link for compare/${PREV}...${TAG}. Regenerate the notes with $PREV as the previous tag."
  exit 1
fi
echo "Release notes for $TAG look complete${PREV:+ (changes since $PREV)}."
