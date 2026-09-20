#!/usr/bin/env bash
set -euo pipefail
export COPYFILE_DISABLE=1  # no AppleDouble ._ members from macOS tar
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

# Hostile archives built with Python tarfile (exact metadata, not text).
hostile() { python3 - "$W/t.tar" "$1" <<'PY'
import tarfile, io, sys
out, kind = sys.argv[1], sys.argv[2]
t = tarfile.open(out, "w")
def add(name, typ=tarfile.REGTYPE, link="", data=b""):
    i = tarfile.TarInfo(name); i.type = typ; i.linkname = link; i.mode = 0o755
    i.size = len(data) if typ == tarfile.REGTYPE else 0
    t.addfile(i, io.BytesIO(data) if typ == tarfile.REGTYPE else None)
add("TimeTug.app", tarfile.DIRTYPE)
add("TimeTug.app/f", data=b"x")
if kind == "arrowname": add("TimeTug.app/a -> b", tarfile.SYMTYPE, "/etc/passwd")
if kind == "hardlink":  add("TimeTug.app/h", tarfile.LNKTYPE, "TimeTug.app/f")
if kind == "chain":
    add("TimeTug.app/d", tarfile.DIRTYPE)
    add("TimeTug.app/d/l", tarfile.SYMTYPE, "../../x")
if kind == "chain2":
    add("TimeTug.app/l1", tarfile.SYMTYPE, "d/..")
if kind == "fifo":      add("TimeTug.app/p", tarfile.FIFOTYPE)
t.close()
PY
}
for k in arrowname hardlink chain chain2 fifo; do
  hostile "$k"; rm -rf "$W/dist"
  run && fail "hostile $k accepted"
  [ ! -e "$W/dist/TimeTug.app" ] || fail "hostile $k reached dist"
done
hostile none; rm -rf "$W/dist"; run || fail "python-built good tar rejected"
# Post-extraction tree check, exercised directly.
V=scripts/ci/validate-tar.py
mk; python3 "$V" tree "$W/src" >/dev/null 2>&1 || fail "tree: good rejected"
mk; ln -s /etc "$W/src/TimeTug.app/esc"; python3 "$V" tree "$W/src" >/dev/null 2>&1 && fail "tree: escaping symlink accepted"
mk; ln "$W/src/TimeTug.app/Contents/f" "$W/src/TimeTug.app/hard"; python3 "$V" tree "$W/src" >/dev/null 2>&1 && fail "tree: hard link accepted"
mk; mkfifo "$W/src/TimeTug.app/p"; python3 "$V" tree "$W/src" >/dev/null 2>&1 && fail "tree: fifo accepted"
echo "PASS"
