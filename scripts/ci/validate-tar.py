#!/usr/bin/env python3
"""Validate an UNTRUSTED TimeTug.tar using exact tar metadata (never text parsing).

  validate-tar.py archive <tar>   check member types, names and symlink targets before extraction
  validate-tar.py tree <dir>      check the extracted <dir>/TimeTug.app tree afterwards
Exit 0 if acceptable, 1 with an ::error:: line otherwise. This module only reads; extraction is bsdtar's job.
"""
import os
import posixpath
import stat
import sys
import tarfile

TOP = "TimeTug.app"


def die(msg):
    print(f"::error::untrusted artifact rejected: {msg!r}", file=sys.stderr)
    sys.exit(1)


def check_archive(path):
    try:
        tf = tarfile.open(path, "r:")
    except (tarfile.TarError, OSError) as e:
        die(f"unreadable tar: {e}")
    n = 0
    with tf:
        for m in tf:
            n += 1
            name = m.name
            if not (m.isreg() or m.isdir() or m.issym()):
                die(f"disallowed member type for {name}")
            if name.startswith("/") or "\\" in name or "\x00" in name:
                die(f"bad member name {name}")
            parts = name.split("/")
            if ".." in parts:
                die(f"'..' component in {name}")
            if name != TOP and not name.startswith(TOP + "/"):
                die(f"member outside {TOP}: {name}")
            if m.issym():
                link = m.linkname
                if not link or link.startswith("/") or ".." in link.split("/"):
                    die(f"unsafe symlink target for {name}: {link}")
                resolved = posixpath.normpath(posixpath.join(posixpath.dirname(name), link))
                if resolved != TOP and not resolved.startswith(TOP + "/"):
                    die(f"symlink escapes {TOP}: {name} -> {link}")
    if n == 0:
        die("empty tar")


def check_tree(scratch):
    app = os.path.join(scratch, TOP)
    if os.path.islink(app) or not os.path.isdir(app):
        die(f"{TOP} missing or not a directory")
    root = os.path.realpath(app)
    entries = [app]
    for dirpath, dirnames, filenames in os.walk(app, followlinks=False):
        entries += [os.path.join(dirpath, n) for n in dirnames + filenames]
    for p in entries:
        st = os.lstat(p)
        if stat.S_ISLNK(st.st_mode):
            real = os.path.realpath(p)
            if real != root and not real.startswith(root + os.sep):
                die(f"symlink resolves outside app: {p} -> {real}")
        elif stat.S_ISREG(st.st_mode):
            if st.st_nlink > 1:
                die(f"hard-linked file: {p}")
        elif not stat.S_ISDIR(st.st_mode):
            die(f"special file: {p}")


if __name__ == "__main__" :
    if len(sys.argv) != 3 or sys.argv[1] not in ("archive", "tree"):
        print("usage: validate-tar.py archive <tar> | tree <dir>", file=sys.stderr)
        sys.exit(2)
    (check_archive if sys.argv[1] == "archive" else check_tree)(sys.argv[2])
