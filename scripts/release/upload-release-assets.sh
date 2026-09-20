#!/usr/bin/env bash
# Attaches release assets and publishes the release for <tag>, built from <commit>.
#
# GitHub immutable releases lock assets and the tag once a release is PUBLISHED, so assets can only be
# added while it is a draft. Behaviour by state (see release-state.sh):
#   published-immutable  exit 1: an immutable release cannot take assets; use a new version.
#   published  `gh release upload --clobber`; title, notes and published state untouched (a `-` suffix
#              or RELEASE_PRERELEASE=1 also runs `gh release edit --prerelease`).
#   draft      upload every file to the draft (an existing asset of the same name is deleted first, so a
#              re-run recovers a stuck draft), then publish it (draft=false). The owner's title and
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
  published-immutable)
    echo "::error::release $TAG is published and immutable; cannot add assets to an immutable release; use a new version"
    exit 1 ;;
  published)
    # Not immutable: attach the assets; title, notes and published state stay as the owner left them.
    gh release upload "$TAG" "$@" --clobber
    if [ "$PRERELEASE" = true ]; then gh release edit "$TAG" --prerelease; fi ;;
  draft)
    ID="$("$HERE/release-state.sh" --id "$TAG")"
    for f in "$@"; do
      NAME="$(basename "$f")"
      # A re-run: replace an asset of the same name left by an earlier attempt.
      gh api --paginate "repos/${GITHUB_REPOSITORY}/releases/${ID}/assets" \
        | jq -r --arg n "$NAME" '.[] | select(.name == $n) | .id' \
        | while read -r aid; do
            gh api --method DELETE "repos/${GITHUB_REPOSITORY}/releases/assets/${aid}" >/dev/null
          done
      echo "Uploading $f to draft release $TAG (id $ID)"
      ENC="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$NAME")"
      gh api --method POST "https://uploads.github.com/repos/${GITHUB_REPOSITORY}/releases/${ID}/assets?name=${ENC}" \
        -H "Content-Type: application/octet-stream" --input "$f" >/dev/null
    done
    if [ "${DRY_PUBLISH:-}" = 1 ]; then
      echo "DRY_PUBLISH=1: assets uploaded, not publishing release $TAG (id $ID)"
      exit 0
    fi
    # Keep a prerelease flag the owner set on the draft.
    if [ "$(gh api "repos/${GITHUB_REPOSITORY}/releases/${ID}" --jq .prerelease 2>/dev/null || true)" = true ]; then
      PRERELEASE=true; LATEST=false
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
