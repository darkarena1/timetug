#!/usr/bin/env bash
# Download the pinned Sparkle tools (sign_update, generate_keys), verify the checksum, print the bin dir.
set -euo pipefail
cd "$(dirname "$0")/../.."
dest="${1:?destination directory}"
# shellcheck disable=SC1091
source scripts/release/sparkle-version.txt
mkdir -p "$dest"
tarball="$dest/Sparkle-$VERSION.tar.xz"
curl -sSL --fail -o "$tarball" "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz"
actual="$(shasum -a 256 "$tarball" | cut -d' ' -f1)"
[ "$actual" = "$SHA256" ] || { echo "error: Sparkle checksum mismatch ($actual)" >&2; exit 1; }
tar -xf "$tarball" -C "$dest" ./bin
[ -x "$dest/bin/sign_update" ] || { echo "error: sign_update missing" >&2; exit 1; }
echo "$dest/bin"
