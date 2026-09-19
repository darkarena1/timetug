#!/usr/bin/env bash
# Verify the layout and contents of a TimeTug installer DMG. Prints PASS or FAIL.
#
# Usage: scripts/release/verify-dmg.sh <path-to.dmg>
#
# Mounts the image read-only (not shown in Finder), checks the app, the /Applications symlink,
# the hidden background image (dmgbuild 1.6 stores it as .background.tiff), the volume icon and .DS_Store, then reads .DS_Store with the
# ds_store package from the dmgbuild virtualenv (build/dmg-venv, created by make-dmg.sh; created
# here when missing) and asserts the icon positions and window size match dmg/settings.py.
# Always detaches on exit. Runs locally and in CI, no secrets needed.
set -euo pipefail

dmg="${1:-}"
[ -n "$dmg" ] && [ -f "$dmg" ] || { echo "usage: $0 <path-to.dmg>" >&2; exit 2; }
cd "$(dirname "$0")/../.."
BUILD_DIR="${BUILD_DIR:-build}"
DMG_DIR="scripts/release/dmg"

venv="$BUILD_DIR/dmg-venv"
if [ ! -x "$venv/bin/python" ] || ! "$venv/bin/python" -c 'import ds_store' 2>/dev/null; then
  rm -rf "$venv"
  python3 -m venv "$venv"
  "$venv/bin/pip" install --quiet --disable-pip-version-check -r "$DMG_DIR/requirements.txt"
  cp "$DMG_DIR/requirements.txt" "$venv/requirements.installed"
fi

mnt="$(mktemp -d)"
attached=0
cleanup() {
  if [ "$attached" = 1 ]; then
    hdiutil detach "$mnt" -quiet 2>/dev/null || hdiutil detach "$mnt" -force -quiet 2>/dev/null || true
  fi
  rmdir "$mnt" 2>/dev/null || true
}
trap cleanup EXIT

failures=0
check() { # check <description> <command...>
  local description="$1"; shift
  if "$@"; then echo "  ok    $description"; else echo "  FAIL  $description"; failures=$((failures + 1)); fi
}

echo "Verifying $dmg"
hdiutil attach "$dmg" -nobrowse -readonly -noverify -mountpoint "$mnt" >/dev/null
attached=1

# shellcheck disable=SC2329  # invoked indirectly through check
is_applications_link() { [ -L "$mnt/Applications" ] && [ "$(readlink "$mnt/Applications")" = "/Applications" ]; }
# shellcheck disable=SC2329
has_background() { compgen -G "$mnt/.background.*" >/dev/null || compgen -G "$mnt/.background/*" >/dev/null; }

check "TimeTug.app/Contents/MacOS/TimeTug is executable" test -x "$mnt/TimeTug.app/Contents/MacOS/TimeTug"
check "Applications is a symlink to /Applications" is_applications_link
check "hidden background image (.background.tiff) exists" has_background
check ".DS_Store exists" test -f "$mnt/.DS_Store"
check ".VolumeIcon.icns exists" test -f "$mnt/.VolumeIcon.icns"

if [ -f "$mnt/.DS_Store" ]; then
  echo "  Finder layout (.DS_Store):"
  # shellcheck disable=SC2329
  layout_ok() {
    "$venv/bin/python" - "$mnt/.DS_Store" "$DMG_DIR/settings.py" <<'PY'
import re, sys
from ds_store import DSStore

store_path, settings_path = sys.argv[1], sys.argv[2]
# Expected values come from settings.py so the two cannot drift apart.
src = open(settings_path).read()
loc = {name: (int(x), int(y)) for name, x, y in re.findall(r'"?([\w.]+)"?:\s*\((\d+),\s*(\d+)\)', src.split("icon_locations", 1)[1])}
loc = {("TimeTug.app" if k == "app_name" else k): v for k, v in loc.items()}
size = tuple(int(n) for n in re.search(r"window_rect\s*=\s*\(\(\d+,\s*\d+\),\s*\((\d+),\s*(\d+)\)\)", src).groups())

ok = True
with DSStore.open(store_path, "r") as d:
    for name, expected in sorted(loc.items()):
        iloc = d[name]["Iloc"]
        actual = (iloc["x"], iloc["y"]) if isinstance(iloc, dict) else tuple(iloc[:2])
        good = actual == expected
        ok &= good
        print(f"    Iloc {name}: {actual} (expected {expected}) {'ok' if good else 'MISMATCH'}")
    bwsp = d["."]["bwsp"]
    m = re.findall(r"-?\d+(?:\.\d+)?", bwsp["WindowBounds"])
    actual_size = (int(float(m[2])), int(float(m[3])))
    good = actual_size == size
    ok &= good
    print(f"    window size: {actual_size} (expected {size}) {'ok' if good else 'MISMATCH'}")
sys.exit(0 if ok else 1)
PY
  }
  check "icon locations and window size match settings.py" layout_ok
fi

if [ "$failures" -eq 0 ]; then
  echo "PASS: $dmg"
else
  echo "FAIL: $dmg ($failures check(s) failed)" >&2
  exit 1
fi
