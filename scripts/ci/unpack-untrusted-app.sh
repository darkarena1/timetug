#!/usr/bin/env bash
# Safely unpack an UNTRUSTED TimeTug.tar (built by pull-request code) and move TimeTug.app into <dest-dir>.
# Usage: unpack-untrusted-app.sh <tar> <scratch-dir> <dest-dir>
# Rejects absolute paths, '..' components, any top-level name other than TimeTug.app, and symlinks whose
# target is absolute or contains '..'. Extraction happens only in <scratch-dir>, never in the checkout.
set -euo pipefail
tarball="${1:?tar}"; scratch="${2:?scratch dir}"; dest="${3:?dest dir}"
die() { echo "::error::untrusted artifact rejected: $*" >&2; exit 1; }

listing="$(tar -tf "$tarball")" || die "unreadable tar"
[ -n "$listing" ] || die "empty tar"
while IFS= read -r p; do
  case "$p" in
    /*) die "absolute path: $p" ;;
    TimeTug.app|TimeTug.app/*) ;;
    *) die "member outside TimeTug.app: $p" ;;
  esac
  case "/$p/" in
    */../*) die "'..' component: $p" ;;
  esac
done <<<"$listing"

while IFS= read -r line; do
  case "$line" in
    l*" -> "*)
      target="${line#* -> }"
      case "$target" in
        /*) die "symlink with absolute target: $line" ;;
        ..|../*|*/..|*/../*) die "symlink target contains '..': $line" ;;
      esac ;;
    h*|*" link to "*) die "hard link member: $line" ;;
  esac
done < <(tar -tvf "$tarball")

rm -rf "$scratch"; mkdir -p "$scratch" "$dest"
tar -C "$scratch" -xf "$tarball"
[ -d "$scratch/TimeTug.app" ] && [ ! -L "$scratch/TimeTug.app" ] || die "TimeTug.app missing or not a directory"
rm -rf "$dest/TimeTug.app"
mv "$scratch/TimeTug.app" "$dest/TimeTug.app"
