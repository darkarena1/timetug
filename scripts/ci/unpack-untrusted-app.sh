#!/usr/bin/env bash
# Safely unpack an UNTRUSTED TimeTug.tar (built by pull-request code) and move TimeTug.app into <dest-dir>.
# The tar's directory must contain nothing but TimeTug.tar.
# Usage: unpack-untrusted-app.sh <tar> <scratch-dir> <dest-dir>
# The archive is validated from exact tar metadata (validate-tar.py archive), extracted by bsdtar into
# <scratch-dir> only (never the checkout), and the extracted tree is re-validated before the move.
set -euo pipefail
tarball="${1:?tar}"; scratch="${2:?scratch dir}"; dest="${3:?dest dir}"
here="$(cd "$(dirname "$0")" && pwd)"

# The download directory must hold exactly one regular file named TimeTug.tar (nothing else the PR uploaded).
[ "$(basename "$tarball")" = "TimeTug.tar" ] && [ -f "$tarball" ] && [ ! -L "$tarball" ] \
  || { echo "error: $tarball is not a regular file named TimeTug.tar" >&2; exit 1; }
if [ "$(ls -A "$(dirname "$tarball")")" != "TimeTug.tar" ]; then
  echo "error: unexpected files next to TimeTug.tar in $(dirname "$tarball")" >&2; exit 1
fi

python3 "$here/validate-tar.py" archive "$tarball"
rm -rf "$scratch"; mkdir -p "$scratch" "$dest"
tar -C "$scratch" -xf "$tarball"
python3 "$here/validate-tar.py" tree "$scratch"
rm -rf "$dest/TimeTug.app"
mv "$scratch/TimeTug.app" "$dest/TimeTug.app"
