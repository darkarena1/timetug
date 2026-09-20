#!/usr/bin/env bash
# Attaches release assets and publishes the release for <tag>, built from <commit>.
#
# GitHub immutable releases lock assets and the tag once a release is PUBLISHED, so assets can only be
# added while it is a draft. Behaviour by state (see release-state.sh):
#   published  exit 1: the release is immutable and cannot take assets; use a new version.
#   draft      upload every file to the draft, then publish it (draft=false). The owner's title and
#              notes are left untouched. If the git tag does not exist yet, target_commitish is set to
#              <commit> so publishing creates the tag at the built commit. make_latest is true only for
#              a version without a `-` suffix; a `-` suffix (or RELEASE_PRERELEASE=1) is a prerelease.
#   none       `gh release create` with the files, the built commit as target and generated notes.
#
# Usage: upload-release-assets.sh <tag> <commit> <files...>
# Environment (all optional):
#   RELEASE_PRERELEASE=1       force prerelease (used for unsigned builds)
#   RELEASE_TITLE_SUFFIX=...   appended to the title of a newly created release, e.g. " (unsigned)"
#   RELEASE_NOTES_PREFIX=...   text placed before the SHA-256 line in a newly created release's notes
#   DRY_PUBLISH=1              verification only: upload the assets but skip the final publish PATCH
#                              (default off; never set it in the workflow)
# Requires: gh (authenticated), jq, git, GITHUB_REPOSITORY.
set -euo pipefail

TAG="${1:?usage: upload-release-assets.sh <tag> <commit> <files...>}"
COMMIT="${2:?usage: upload-release-assets.sh <tag> <commit> <files...>}"
shift 2
[ "$#" -gt 0 ] || { echo "no files given" >&2; exit 1; }
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
HERE="$(cd "$(dirname "$0")" && pwd)"

VERSION="${TAG#v}"
PRERELEASE=false
LATEST=true
if [[ "$VERSION" == *-* || "${RELEASE_PRERELEASE:-}" == 1 ]]; then PRERELEASE=true; LATEST=false; fi

STATE="$("$HERE/release-state.sh" "$TAG")"
case "$STATE" in
  published)
    echo "::error::release $TAG is already published and immutable; assets cannot be added; use a new version"
    exit 1 ;;
  draft)
    ID="$("$HERE/release-state.sh" --id "$TAG")"
    for f in "$@"; do
      echo "Uploading $f to draft release $TAG (id $ID)"
      gh api --method POST "https://uploads.github.com/repos/${GITHUB_REPOSITORY}/releases/${ID}/assets?name=$(basename "$f")" \
        -H "Content-Type: application/octet-stream" --input "$f" >/dev/null
    done
    if [ "${DRY_PUBLISH:-}" = 1 ]; then
      echo "DRY_PUBLISH=1: assets uploaded, not publishing release $TAG (id $ID)"
      exit 0
    fi
    args=(-F draft=false -F "prerelease=$PRERELEASE" -f "make_latest=$LATEST")
    if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
      args+=(-f "target_commitish=$COMMIT")
    fi
    gh api --method PATCH "repos/${GITHUB_REPOSITORY}/releases/${ID}" "${args[@]}" >/dev/null
    echo "Published draft release $TAG" ;;
  none)
    SHA_FILE=""
    for f in "$@"; do case "$f" in *.sha256) SHA_FILE="$f"; break ;; esac; done
    NOTES="${RELEASE_NOTES_PREFIX:-}"
    [ -z "$SHA_FILE" ] || NOTES="${NOTES:+$NOTES }SHA-256: $(cut -d' ' -f1 "$SHA_FILE")"
    flags=()
    [ "$PRERELEASE" = true ] && flags+=(--prerelease)
    gh release create "$TAG" "$@" --title "TimeTug ${VERSION}${RELEASE_TITLE_SUFFIX:-}" \
      --target "$COMMIT" --generate-notes --notes "$NOTES" ${flags[@]+"${flags[@]}"} ;;
  *) echo "unexpected release state '$STATE'" >&2; exit 1 ;;
esac
