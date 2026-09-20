#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
S="$PWD/scripts/ci/unpack-untrusted-app.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mk() { rm -rf "$W/src"; mkdir -p "$W/src/TimeTug.app/Contents"; echo x > "$W/src/TimeTug.app/Contents/f"; }
run() { "$S" "$W/t.tar" "$W/scratch" "$W/dist" >/dev/null 2>&1; }

mk; tar -cf "$W/t.tar" -C "$W/src" TimeTug.app
run || fail "good tar rejected"; [ -f "$W/dist/TimeTug.app/Contents/f" ] || fail "not moved"
rm -rf "$W/dist"

mk; ln -s Contents/f "$W/src/TimeTug.app/ok"; tar -cf "$W/t.tar" -C "$W/src" TimeTug.app
run || fail "benign relative symlink rejected"; rm -rf "$W/dist"

mk; ln -s /etc/passwd "$W/src/TimeTug.app/bad"; tar -cf "$W/t.tar" -C "$W/src" TimeTug.app
run && fail "absolute symlink accepted"

mk; ln -s ../../x "$W/src/TimeTug.app/bad"; tar -cf "$W/t.tar" -C "$W/src" TimeTug.app
run && fail "dotdot symlink accepted"

mk; echo y > "$W/src/Other"; tar -cf "$W/t.tar" -C "$W/src" TimeTug.app Other
run && fail "extra top-level accepted"

mk
tar -cPf "$W/t.tar" "$W/src/TimeTug.app/Contents/f" 2>/dev/null
run && fail "absolute member accepted"
[ ! -e "$W/dist/f" ] || fail "leak"
echo "PASS"
