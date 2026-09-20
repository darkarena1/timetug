#!/usr/bin/env bash
# Safely unpack an UNTRUSTED TimeTug.tar (built by pull-request code) and move TimeTug.app into <dest-dir>.
# Usage: unpack-untrusted-app.sh <tar> <scratch-dir> <dest-dir>
# The archive is validated from exact tar metadata (validate-tar.py archive), extracted by bsdtar into
# <scratch-dir> only (never the checkout), and the extracted tree is re-validated before the move.
set -euo pipefail
tarball="${1:?tar}"; scratch="${2:?scratch dir}"; dest="${3:?dest dir}"
here="$(cd "$(dirname "$0")" && pwd)"

python3 "$here/validate-tar.py" archive "$tarball"
rm -rf "$scratch"; mkdir -p "$scratch" "$dest"
tar -C "$scratch" -xf "$tarball"
python3 "$here/validate-tar.py" tree "$scratch"
rm -rf "$dest/TimeTug.app"
mv "$scratch/TimeTug.app" "$dest/TimeTug.app"
