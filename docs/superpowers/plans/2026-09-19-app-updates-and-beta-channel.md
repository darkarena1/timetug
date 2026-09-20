# App Updates and Beta Channel Implementation Plan

> **Superseded in part.** Tasks 7 and 8 (the PR-triggered beta-build and beta-publish workflows and the tag-push release) were superseded by a redesign: betas build on merge to `master` (`.github/workflows/beta.yml`), the stable release runs when a GitHub Release is published (`release.yml`), and the build number is a 14-digit timestamp `YYYYMMDDHHMMSS`. This plan is kept as a historical record. The spec (`docs/superpowers/specs/2026-09-19-app-updates-and-beta-channel-design.md`) and the code are authoritative.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** TimeTug updates itself through Sparkle, with Software-Update-style settings (including beta), and CI publishes a signed beta for the latest green same-repo PR; a tagged release also publishes the stable update.

**Architecture:** Sparkle 2 in the app behind a small `UpdaterDriving` protocol. One appcast (`appcast.xml` on `gh-pages`) with a `beta` channel. Beta is two workflows: an unprivileged build (no secrets) and a privileged publish that runs only default-branch scripts on the downloaded artifact. Ordering key is a UTC-timestamp `CFBundleVersion`.

**Tech Stack:** Sparkle 2 (SwiftPM), XcodeGen, SwiftUI/AppKit, XCTest, bash, Python 3 stdlib, GitHub Actions, `gh`.

Spec: `docs/superpowers/specs/2026-09-19-app-updates-and-beta-channel-design.md`.

## Global Constraints
- Core (`Packages/TimeTugCore`) is untouched; update code lives in `Apps/macOS` only (AGENTS.md layering).
- App and EventKitSource use Swift 5 language mode.
- Generated `*.xcodeproj` is git-ignored; run `xcodegen generate --spec Apps/macOS/project.yml` after editing `project.yml`.
- `CFBundleVersion` is a UTC timestamp `YYYYMMDDHHMM` (12 digits), never a hash and never `GITHUB_RUN_NUMBER`.
- Beta display version: `<base>-beta.<PR number>.<run number>`; stable: tag without `v`. `<base>` is `CFBundleShortVersionString` in `Apps/macOS/project.yml`.
- Betas are Developer-ID signed, NOT notarized. Every zip carries a Sparkle EdDSA signature.
- Keep the newest 5 betas.
- The base version in `project.yml` (`CFBundleShortVersionString`, currently `0.0.0-dev`) may carry a suffix; the beta version is `<base>-beta.<PR>.<run>` and validators must accept it.
- Secrets never enter PR-authored code: `SPARKLE_PRIVATE_KEY` and the certificate are used only by workflows that run default-branch scripts.
- Never commit certificates, keys or the Sparkle private key.
- Keep logic in scripts, not YAML (AGENTS.md).
- Commit messages end with `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.

## File Structure
| File | Responsibility |
|---|---|
| `scripts/ci/compute-versions.sh` (new) | Prints `APP_VERSION=` and `BUILD_NUMBER=` for beta or stable |
| `scripts/ci/tests/test-compute-versions.sh` (new) | Shell test for the above |
| `scripts/ci/build-release.sh` (modify) | Accept `APP_VERSION`; stop defaulting build number to run number |
| `scripts/ci/wait-for-ci.sh` (new) | Poll until CI for a SHA succeeds or fails |
| `scripts/release/appcast.py` (new) | Add an item, prune betas in `appcast.xml` (stdlib only) |
| `scripts/release/tests/test_appcast.py` (new) | unittest for `appcast.py` |
| `scripts/release/sign-app.sh` (new) | Developer ID sign inside-out (Sparkle, widget, app), no notarization |
| `scripts/release/sign-and-notarize.sh` (modify) | `app` mode calls `sign-app.sh` then notarizes |
| `scripts/release/make-update-zip.sh` (new) | `ditto` zip of the app |
| `scripts/release/fetch-sparkle-tools.sh` (new) | Download pinned Sparkle tools, verify checksum |
| `scripts/release/publish-appcast.sh` (new) | Check out `gh-pages`, run `appcast.py`, commit, push with retry |
| `scripts/release/tests/test-publish-appcast.sh` (new) | Test against a local bare repo |
| `Apps/macOS/Sources/UpdateController.swift` (new) | `UpdaterDriving`, `UpdateController`, `SparkleUpdater` adapter |
| `Apps/macOS/Sources/UpdatesSection.swift` (new) | Settings UI section |
| `Apps/macOS/Tests/UpdateControllerTests.swift` (new) | Unit tests with a fake updater |
| `.github/workflows/beta-build.yml`, `beta-publish.yml` (new) | Beta pipeline |
| `.github/workflows/release.yml` (modify) | Stable Sparkle zip and appcast |
| `docs/release.md`, `AGENTS.md`, `docs/decisions/0011-...md`, `docs/manual-tests/macos-checklist.md` | Docs |

---

### Task 1: Version and build-number computation

**Files:**
- Create: `scripts/ci/compute-versions.sh`, `scripts/ci/tests/test-compute-versions.sh`
- Modify: `scripts/ci/build-release.sh:12-13,30-33,61`

**Interfaces:**
- Produces: `scripts/ci/compute-versions.sh beta <pr> <run>` and `... stable <tag>` print two lines `APP_VERSION=<v>` and `BUILD_NUMBER=<12 digits>`. Env `TT_NOW` (a `date -u` format string result such as `202609191430`) overrides the clock for tests. `build-release.sh` honours env `APP_VERSION` (beats tag and project.yml) and `BUILD_NUMBER`.

- [ ] **Step 1: Write the failing test** `scripts/ci/tests/test-compute-versions.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
S=scripts/ci/compute-versions.sh
fail() { echo "FAIL: $*" >&2; exit 1; }

out="$(TT_NOW=202609191430 $S beta 12 34)"
base="$(sed -n 's/^ *CFBundleShortVersionString: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' Apps/macOS/project.yml | head -n 1)"
[ "$out" = "APP_VERSION=${base}-beta.12.34
BUILD_NUMBER=202609191430" ] || fail "beta output: $out"

out="$(TT_NOW=202609191430 $S stable v1.2.3)"
[ "$out" = "APP_VERSION=1.2.3
BUILD_NUMBER=202609191430" ] || fail "stable output: $out"

$S beta x 1 >/dev/null 2>&1 && fail "non-numeric PR accepted"
$S stable 1.2.3 >/dev/null 2>&1 && fail "tag without v accepted"
[ "$(TT_NOW=202609191430 $S stable v1.2.3-rc1 | head -n1)" = "APP_VERSION=1.2.3-rc1" ] || fail "suffix tag rejected"
out="$($S beta 1 1)"
echo "$out" | grep -Eq '^BUILD_NUMBER=[0-9]{12}$' || fail "default clock: $out"
echo "PASS"
```

- [ ] **Step 2: Run it, expect failure**

Run: `bash scripts/ci/tests/test-compute-versions.sh`
Expected: `No such file or directory` for `compute-versions.sh`.

- [ ] **Step 3: Implement** `scripts/ci/compute-versions.sh`

```bash
#!/usr/bin/env bash
# Print APP_VERSION and BUILD_NUMBER for a beta or stable build (see docs/release.md, "Versioning").
#   compute-versions.sh beta <pr-number> <run-number>   -> <base>-beta.<pr>.<run>
#   compute-versions.sh stable <tag like v1.2.3>        -> 1.2.3
# BUILD_NUMBER is a UTC timestamp YYYYMMDDHHMM shared by beta and release so a release always outranks
# earlier betas. TT_NOW overrides the clock (tests only).
set -euo pipefail
cd "$(dirname "$0")/../.."
kind="${1:-}"
now="${TT_NOW:-$(date -u +%Y%m%d%H%M)}"
[[ "$now" =~ ^[0-9]{12}$ ]] || { echo "error: bad timestamp '$now'" >&2; exit 1; }
case "$kind" in
  beta)
    pr="${2:-}"; run="${3:-}"
    [[ "$pr" =~ ^[0-9]+$ && "$run" =~ ^[0-9]+$ ]] || { echo "usage: $0 beta <pr> <run> (numbers)" >&2; exit 2; }
    base="$(sed -n 's/^ *CFBundleShortVersionString: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' Apps/macOS/project.yml | head -n 1)"
    [ -n "$base" ] || { echo "error: no base version in project.yml" >&2; exit 1; }
    echo "APP_VERSION=${base}-beta.${pr}.${run}" ;;
  stable)
    tag="${2:-}"
    [[ "$tag" =~ ^v[0-9]+(\.[0-9]+)*([-+][0-9A-Za-z.-]+)?$ ]] || { echo "usage: $0 stable vX.Y.Z[-suffix]" >&2; exit 2; }
    echo "APP_VERSION=${tag#v}" ;;
  *) echo "usage: $0 beta <pr> <run> | stable <tag>" >&2; exit 2 ;;
esac
echo "BUILD_NUMBER=${now}"
```

Run `chmod +x scripts/ci/compute-versions.sh scripts/ci/tests/test-compute-versions.sh`.

- [ ] **Step 4: Run test, expect PASS**

Run: `bash scripts/ci/tests/test-compute-versions.sh`
Expected: `PASS`

- [ ] **Step 5: Modify `scripts/ci/build-release.sh`.** Change the header line 12 to `#   BUILD_NUMBER  CFBundleVersion to stamp (default: the project's value; never GITHUB_RUN_NUMBER, run numbers are per workflow)` and add `#   APP_VERSION   display version; overrides the tag and project.yml`. Replace the version block:

```bash
if [ -n "${APP_VERSION:-}" ]; then
  VERSION="$APP_VERSION"
elif [ -n "$tag" ]; then
  VERSION="${tag#v}"
else
  VERSION="$(sed -n 's/^ *CFBundleShortVersionString: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' "$SPEC" | head -n 1)"
fi
```

and replace `BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-}}"` with `BUILD_NUMBER="${BUILD_NUMBER:-}"`.

- [ ] **Step 6: Verify the script still parses and the override works**

Run: `bash -n scripts/ci/build-release.sh && ! grep -q '^[^#]*GITHUB_RUN_NUMBER' scripts/ci/build-release.sh && echo ok`
Expected: prints `ok` (no non-comment line mentions `GITHUB_RUN_NUMBER`).

- [ ] **Step 7: Commit**

```bash
git add scripts/ci
git commit -m "build: timestamp build number and version override for release scripts

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Appcast editing (`appcast.py`)

**Files:**
- Create: `scripts/release/appcast.py`, `scripts/release/tests/test_appcast.py`

**Interfaces:**
- Produces (CLI):
  - `appcast.py add --file appcast.xml --title T --version 202609191430 --short 0.2.0-beta.12.34 --url https://... --length 123 --signature SIG --min-system 14.0 [--channel beta] [--notes-url URL]` creates the file if missing, inserts the item first (newest first), replaces an existing item with the same `sparkle:version`.
  - `appcast.py prune-betas --file appcast.xml --keep 5` removes beta items beyond the newest `keep` by `sparkle:version` (numeric) and prints one removed `sparkle:shortVersionString`-independent tag per line: the enclosure URL of each removed item.
- Python 3 stdlib only.

- [ ] **Step 1: Write the failing tests** `scripts/release/tests/test_appcast.py`

```python
import os, subprocess, sys, tempfile, unittest
import xml.etree.ElementTree as ET

SCRIPT = os.path.join(os.path.dirname(__file__), "..", "appcast.py")
NS = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}

def run(*args):
    return subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True)

def add(path, version, channel=None, short=None):
    args = ["add", "--file", path, "--title", f"TimeTug {version}", "--version", str(version),
            "--short", short or f"0.2.0-{version}", "--url", f"https://example.com/{version}.zip",
            "--length", "100", "--signature", "SIG==", "--min-system", "14.0"]
    if channel:
        args += ["--channel", channel]
    r = run(*args)
    assert r.returncode == 0, r.stderr

def items(path):
    return ET.parse(path).getroot().findall("./channel/item")

def version(item):
    return item.find("sparkle:version", NS).text

class AppcastTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.path = os.path.join(self.dir, "appcast.xml")

    def test_add_creates_file_with_one_item(self):
        add(self.path, 202609191430)
        it = items(self.path)
        self.assertEqual(len(it), 1)
        self.assertEqual(version(it[0]), "202609191430")
        enc = it[0].find("enclosure")
        self.assertEqual(enc.get("url"), "https://example.com/202609191430.zip")
        self.assertEqual(enc.get("length"), "100")
        self.assertEqual(enc.get("{%s}edSignature" % NS["sparkle"]), "SIG==")
        self.assertEqual(it[0].find("sparkle:minimumSystemVersion", NS).text, "14.0")

    def test_stable_has_no_channel_and_beta_has(self):
        add(self.path, 1, channel="beta")
        add(self.path, 2)
        by_version = {version(i): i for i in items(self.path)}
        self.assertEqual(by_version["1"].find("sparkle:channel", NS).text, "beta")
        self.assertIsNone(by_version["2"].find("sparkle:channel", NS))

    def test_newest_first_and_same_version_replaces(self):
        add(self.path, 5)
        add(self.path, 9)
        add(self.path, 9)
        self.assertEqual([version(i) for i in items(self.path)], ["9", "5"])

    def test_prune_keeps_newest_betas_and_all_stable(self):
        for v in (1, 2, 3, 4):
            add(self.path, v, channel="beta")
        add(self.path, 0)  # stable, oldest
        r = run("prune-betas", "--file", self.path, "--keep", "2")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(sorted(r.stdout.split()), ["https://example.com/1.zip", "https://example.com/2.zip"])
        self.assertEqual(sorted(version(i) for i in items(self.path)), ["0", "3", "4"])

    def test_prune_compares_versions_numerically(self):
        add(self.path, 999999999999, channel="beta")
        add(self.path, 1000000000000, channel="beta")
        run("prune-betas", "--file", self.path, "--keep", "1")
        self.assertEqual([version(i) for i in items(self.path)], ["1000000000000"])

    def test_rejects_non_numeric_version(self):
        r = run("add", "--file", self.path, "--title", "t", "--version", "abc", "--short", "1",
                "--url", "https://e/x.zip", "--length", "1", "--signature", "s", "--min-system", "14.0")
        self.assertNotEqual(r.returncode, 0)

if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run, expect failure**

Run: `python3 scripts/release/tests/test_appcast.py -v`
Expected: errors because `appcast.py` does not exist.

- [ ] **Step 3: Implement** `scripts/release/appcast.py`

```python
#!/usr/bin/env python3
"""Edit the Sparkle appcast (appcast.xml). Stdlib only. See docs/release.md."""
import argparse
import os
import sys
import xml.etree.ElementTree as ET
from email.utils import formatdate

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)
ET.register_namespace("dc", "http://purl.org/dc/elements/1.1/")


def q(tag):
    return "{%s}%s" % (SPARKLE, tag)


def load(path):
    if os.path.exists(path):
        return ET.parse(path)
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "TimeTug"
    return ET.ElementTree(rss)


def version_of(item):
    node = item.find(q("version"))
    return int(node.text) if node is not None and node.text.isdigit() else -1


def is_beta(item):
    node = item.find(q("channel"))
    return node is not None and node.text == "beta"


def save(tree, path):
    ET.indent(tree, space="  ")
    tree.write(path, encoding="utf-8", xml_declaration=True)


def cmd_add(a):
    if not a.version.isdigit():
        sys.exit("error: --version must be numeric")
    tree = load(a.file)
    channel = tree.getroot().find("channel")
    for old in [i for i in channel.findall("item") if i.findtext(q("version")) == a.version]:
        channel.remove(old)
    item = ET.Element("item")
    ET.SubElement(item, "title").text = a.title
    ET.SubElement(item, "pubDate").text = formatdate(usegmt=True)
    ET.SubElement(item, q("version")).text = a.version
    ET.SubElement(item, q("shortVersionString")).text = a.short
    ET.SubElement(item, q("minimumSystemVersion")).text = a.min_system
    if a.channel:
        ET.SubElement(item, q("channel")).text = a.channel
    if a.notes_url:
        ET.SubElement(item, q("releaseNotesLink")).text = a.notes_url
    ET.SubElement(item, "enclosure", {
        "url": a.url, "length": a.length, "type": "application/octet-stream",
        q("edSignature"): a.signature,
    })
    first = next((i for i, e in enumerate(channel) if e.tag == "item"), len(channel))
    channel.insert(first, item)
    items = sorted(channel.findall("item"), key=version_of, reverse=True)
    for i in items:
        channel.remove(i)
    for i in items:
        channel.append(i)
    save(tree, a.file)


def cmd_prune(a):
    tree = load(a.file)
    channel = tree.getroot().find("channel")
    betas = sorted((i for i in channel.findall("item") if is_beta(i)), key=version_of, reverse=True)
    for item in betas[a.keep:]:
        print(item.find("enclosure").get("url"))
        channel.remove(item)
    save(tree, a.file)


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    add = sub.add_parser("add")
    for name in ("file", "title", "version", "short", "url", "length", "signature", "min-system"):
        add.add_argument("--" + name, required=True, dest=name.replace("-", "_"))
    add.add_argument("--channel")
    add.add_argument("--notes-url", dest="notes_url")
    add.set_defaults(fn=cmd_add)
    prune = sub.add_parser("prune-betas")
    prune.add_argument("--file", required=True)
    prune.add_argument("--keep", type=int, required=True)
    prune.set_defaults(fn=cmd_prune)
    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run tests, expect PASS**

Run: `python3 scripts/release/tests/test_appcast.py -v`
Expected: `OK` (6 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/release/appcast.py scripts/release/tests
git commit -m "build: appcast.py to add and prune Sparkle appcast items

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Publish the appcast to `gh-pages`

**Files:**
- Create: `scripts/release/publish-appcast.sh`, `scripts/release/tests/test-publish-appcast.sh`

**Interfaces:**
- Consumes: `appcast.py add` arguments (Task 2).
- Produces: `publish-appcast.sh <remote-url-or-path> [--keep-betas N] -- <appcast.py add args without --file>`. It clones `gh-pages` (creating an orphan branch if missing), runs `appcast.py add`, optionally `prune-betas` (printing pruned URLs to stdout), commits, pushes. On a rejected push it fetches, rebases and retries up to 5 times; never force-pushes. Env `GIT_AUTHOR_*`/`GIT_COMMITTER_*` are respected.

- [ ] **Step 1: Write the failing test** `scripts/release/tests/test-publish-appcast.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q --bare "$T/remote.git"
fail() { echo "FAIL: $*" >&2; exit 1; }
pub() { # pub <version> [channel]
  local extra=(); [ -n "${2:-}" ] && extra=(--channel "$2")
  scripts/release/publish-appcast.sh "$T/remote.git" --keep-betas 2 -- \
    --title "TimeTug $1" --version "$1" --short "0.2.0-$1" --url "https://e/$1.zip" \
    --length 1 --signature S --min-system 14.0 "${extra[@]}"
}
pub 1 beta >/dev/null; pub 2 beta >/dev/null
pruned="$(pub 3 beta)"
[ "$pruned" = "https://e/1.zip" ] || fail "expected prune of 1, got '$pruned'"
git clone -q --branch gh-pages "$T/remote.git" "$T/check"
count="$(grep -c '<item>' "$T/check/appcast.xml")"
[ "$count" = 2 ] || fail "expected 2 items, got $count"
echo PASS
```

- [ ] **Step 2: Run, expect failure**

Run: `bash scripts/release/tests/test-publish-appcast.sh`
Expected: `publish-appcast.sh: No such file or directory`.

- [ ] **Step 3: Implement** `scripts/release/publish-appcast.sh`

```bash
#!/usr/bin/env bash
# Add an item to appcast.xml on the gh-pages branch of <remote> and push. Never force-pushes: a rejected
# push is fetched, rebased and retried (bounded). Serialise callers with the `appcast` concurrency group.
# Usage: publish-appcast.sh <remote> [--keep-betas N] -- <appcast.py add args, without --file>
# Prints the enclosure URL of every pruned beta, one per line (stdout); progress goes to stderr.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
remote="${1:?remote}"; shift
keep=""
if [ "${1:-}" = "--keep-betas" ]; then keep="$2"; shift 2; fi
[ "${1:-}" = "--" ] && shift

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
if git ls-remote --exit-code --heads "$remote" gh-pages >/dev/null 2>&1; then
  git clone -q --branch gh-pages "$remote" "$work/repo"
else
  git init -q "$work/repo"
  git -C "$work/repo" checkout -q --orphan gh-pages
  git -C "$work/repo" remote add origin "$remote"
  touch "$work/repo/.nojekyll"
fi
repo="$work/repo"

for attempt in 1 2 3 4 5; do
  python3 "$ROOT/scripts/release/appcast.py" add --file "$repo/appcast.xml" "$@"
  pruned=""
  if [ -n "$keep" ]; then
    pruned="$(python3 "$ROOT/scripts/release/appcast.py" prune-betas --file "$repo/appcast.xml" --keep "$keep")"
  fi
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "appcast: update" || true
  if git -C "$repo" push -q origin gh-pages >&2 2>&1; then
    [ -n "$pruned" ] && echo "$pruned"
    exit 0
  fi
  echo "push rejected (attempt $attempt); rebasing" >&2
  git -C "$repo" fetch -q origin gh-pages
  git -C "$repo" reset -q --hard origin/gh-pages
done
echo "error: could not push gh-pages after 5 attempts" >&2
exit 1
```

Note: after a rejected push we reset to the remote head and re-apply the edit, which is the safe way to rebase an XML edit.

Run `chmod +x` on both scripts.

- [ ] **Step 4: Run test, expect PASS**

Run: `bash scripts/release/tests/test-publish-appcast.sh`
Expected: `PASS`

- [ ] **Step 5: Commit**

```bash
git add scripts/release
git commit -m "build: publish-appcast.sh pushes appcast.xml to gh-pages with retry

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Signing and packaging scripts

**Files:**
- Create: `scripts/release/sign-app.sh`, `scripts/release/make-update-zip.sh`, `scripts/release/fetch-sparkle-tools.sh`, `scripts/release/sparkle-version.txt`
- Modify: `scripts/release/sign-and-notarize.sh` (app mode)

**Interfaces:**
- Produces:
  - `sign-app.sh [APP_PATH]`: env `MACOS_CERTIFICATE_P12_BASE64`, `MACOS_CERTIFICATE_PASSWORD`, `APPLE_TEAM_ID` (or `SIGN_IDENTITY=-` for an ad-hoc local smoke test). Signs inside-out: every `Sparkle.framework` XPC service, `Autoupdate`, `Updater.app`, the framework, the widget extension, the app. Hardened runtime, timestamp (skipped for ad hoc). Does not notarize.
  - `make-update-zip.sh <app> <out.zip>`: `ditto -c -k --keepParent`.
  - `fetch-sparkle-tools.sh <dest-dir>`: downloads the pinned Sparkle release tarball, verifies its SHA-256, extracts `bin/`, prints the directory containing `sign_update`.

- [ ] **Step 1: Pin Sparkle and record its checksum.** Look up the latest 2.x release and write the version and checksum:

```bash
gh api repos/sparkle-project/Sparkle/releases/latest --jq .tag_name
```

Take that tag (for example `2.x.y`), then:

```bash
V=<tag from above>
curl -sSL -o /tmp/sparkle.tar.xz "https://github.com/sparkle-project/Sparkle/releases/download/$V/Sparkle-$V.tar.xz"
printf 'VERSION=%s\nSHA256=%s\n' "$V" "$(shasum -a 256 /tmp/sparkle.tar.xz | cut -d' ' -f1)" > scripts/release/sparkle-version.txt
cat scripts/release/sparkle-version.txt
```

Expected: two lines, `VERSION=` and a 64-hex `SHA256=`. This same version is pinned in `project.yml` in Task 5.

- [ ] **Step 2: Write `scripts/release/fetch-sparkle-tools.sh`**

```bash
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
```

- [ ] **Step 3: Write `scripts/release/make-update-zip.sh`**

```bash
#!/usr/bin/env bash
# Zip an app bundle for Sparkle. ditto keeps resource forks and symlinks intact (plain `zip` breaks them).
set -euo pipefail
app="${1:?app path}"; out="${2:?output zip}"
[ -d "$app" ] || { echo "error: $app not found" >&2; exit 1; }
rm -f "$out"
ditto -c -k --keepParent "$app" "$out"
echo "$out"
```

- [ ] **Step 4: Write `scripts/release/sign-app.sh`** by extracting the certificate import and signing steps from `sign-and-notarize.sh` (lines for keychain setup and `IDENTITY` lookup are copied unchanged), with the inside-out signing extended for Sparkle:

```bash
#!/usr/bin/env bash
# Sign TimeTug.app with a Developer ID Application certificate (hardened runtime), inside-out. No notarization.
# Usage: scripts/release/sign-app.sh [APP_PATH]   (default dist/TimeTug.app)
# Environment: MACOS_CERTIFICATE_P12_BASE64, MACOS_CERTIFICATE_PASSWORD, APPLE_TEAM_ID.
# SIGN_IDENTITY=-  signs ad hoc instead (local smoke test; needs no secrets and skips the timestamp).
# The temporary keychain and decoded certificate are removed on exit. Nothing here prints secrets.
set -euo pipefail
cd "$(dirname "$0")/../.."
APP_PATH="${1:-dist/TimeTug.app}"
ENTITLEMENTS="Apps/macOS/Sources/TimeTug.entitlements"
WIDGET_ENTITLEMENTS="Apps/macOS/Widgets/TimeTugWidgets.entitlements"
[ -d "$APP_PATH" ] || { echo "error: app not found at $APP_PATH" >&2; exit 1; }
APPEX="$APP_PATH/Contents/PlugIns/TimeTugWidgets.appex"
[ -d "$APPEX" ] || { echo "error: widget extension missing at $APPEX" >&2; exit 1; }

WORK="$(mktemp -d)"
KEYCHAIN_ARGS=()
TIMESTAMP=(--timestamp)
if [ "${SIGN_IDENTITY:-}" = "-" ]; then
  IDENTITY="-"; TIMESTAMP=()
  trap 'rm -rf "$WORK"' EXIT
else
  for var in MACOS_CERTIFICATE_P12_BASE64 MACOS_CERTIFICATE_PASSWORD APPLE_TEAM_ID; do
    [ -n "${!var:-}" ] || { echo "error: required environment variable $var is not set" >&2; exit 1; }
  done
  if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::add-mask::${MACOS_CERTIFICATE_PASSWORD}"; fi
  KEYCHAIN="$WORK/signing.keychain-db"
  KEYCHAIN_PASSWORD="$(uuidgen)"
  ORIGINAL_KEYCHAINS="$(security list-keychains -d user | tr -d '"' | tr '\n' ' ')"
  cleanup() {
    # shellcheck disable=SC2086
    security list-keychains -d user -s $ORIGINAL_KEYCHAINS >/dev/null 2>&1 || true
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
    rm -rf "$WORK"
  }
  trap cleanup EXIT
  echo "$MACOS_CERTIFICATE_P12_BASE64" | base64 --decode > "$WORK/cert.p12"
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  security set-keychain-settings -lut 21600 "$KEYCHAIN"
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  security import "$WORK/cert.p12" -k "$KEYCHAIN" -P "$MACOS_CERTIFICATE_PASSWORD" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
  # shellcheck disable=SC2086
  security list-keychains -d user -s "$KEYCHAIN" $ORIGINAL_KEYCHAINS
  IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" \
    | sed -n "s/.*\"\(Developer ID Application: .*(${APPLE_TEAM_ID})\)\".*/\1/p" | head -n 1)"
  [ -n "$IDENTITY" ] || { echo "error: no 'Developer ID Application' identity for team $APPLE_TEAM_ID" >&2; exit 1; }
  KEYCHAIN_ARGS=(--keychain "$KEYCHAIN")
  echo "Signing with: $IDENTITY"
fi

sign() { codesign --force --sign "$IDENTITY" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} --options runtime ${TIMESTAMP[@]+"${TIMESTAMP[@]}"} "$@"; }

# Inside-out: Sparkle's nested helpers, then the framework, then the widget extension, then the app.
FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
if [ -d "$FRAMEWORK" ]; then
  while IFS= read -r xpc; do sign --preserve-metadata=entitlements "$xpc"; done \
    < <(find "$FRAMEWORK" -name '*.xpc' -type d)
  [ -f "$FRAMEWORK/Versions/B/Autoupdate" ] && sign "$FRAMEWORK/Versions/B/Autoupdate"
  [ -d "$FRAMEWORK/Versions/B/Updater.app" ] && sign "$FRAMEWORK/Versions/B/Updater.app"
  sign "$FRAMEWORK"
else
  echo "warning: Sparkle.framework not found in the app; signing without it" >&2
fi
sign --entitlements "$WIDGET_ENTITLEMENTS" "$APPEX"
sign --entitlements "$ENTITLEMENTS" "$APP_PATH"
codesign --verify --strict --deep --verbose=2 "$APP_PATH"
echo "Signed (not notarized): $APP_PATH"
```

`chmod +x` all three new scripts.

- [ ] **Step 5: Wire `sign-and-notarize.sh` app mode to call `sign-app.sh`.** In app mode, replace step "2. Re-sign ..." (the `APPEX=` block through `codesign --verify --strict --deep`) with:

```bash
  # 2. Re-sign with hardened runtime and a secure timestamp, inside-out (scripts/release/sign-app.sh).
  scripts/release/sign-app.sh "$APP_PATH"
```

Leave the certificate import for `dmg` mode as it is (it still needs the keychain), and leave step 3 onward unchanged (notarization only needs the API key). Also update the header comment of `sign-and-notarize.sh` to mention that `app` mode delegates to `sign-app.sh`.

- [ ] **Step 6: Smoke-test ad hoc signing locally** (needs a built app; the Sparkle framework arrives in Task 5, so this run exercises the "framework not found" branch and the widget/app path)

```bash
scripts/ci/build-release.sh
SIGN_IDENTITY=- scripts/release/sign-app.sh
scripts/release/make-update-zip.sh dist/TimeTug.app dist/TimeTug-test.zip
unzip -l dist/TimeTug-test.zip | tail -1
```

Expected: `Signed (not notarized): dist/TimeTug.app`, then a file count line. (Re-run after Task 5 to confirm the Sparkle helpers are signed: `codesign -dv dist/TimeTug.app/Contents/Frameworks/Sparkle.framework 2>&1 | head -3`.)

- [ ] **Step 7: Commit**

```bash
git add scripts/release
git commit -m "build: sign-app.sh (Developer ID, no notarization), update zip and Sparkle tool fetch

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: Sparkle in the app (`UpdateController`)

**Files:**
- Modify: `Apps/macOS/project.yml` (package, dependency, Info properties)
- Create: `Apps/macOS/Sources/UpdateController.swift`, `Apps/macOS/Tests/UpdateControllerTests.swift`

**Interfaces:**
- Produces:
  - `protocol UpdaterDriving: AnyObject { var automaticallyChecksForUpdates: Bool { get set }; var lastUpdateCheckDate: Date? { get }; func checkForUpdates() }`
  - `@MainActor final class UpdateController: ObservableObject` with `@Published var automaticallyChecks: Bool`, `@Published var includeBetas: Bool`, `var lastCheckDate: Date?`, `let currentVersion: String`, `func checkForUpdates()`, `static func allowedChannels(includeBetas: Bool) -> Set<String>`, `init(driver: UpdaterDriving, defaults: UserDefaults = .standard, currentVersion: String)`.
  - `final class SparkleUpdater: NSObject, UpdaterDriving, SPUUpdaterDelegate` created as `SparkleUpdater(includeBetas: @escaping () -> Bool)`.
- Consumes: none from earlier tasks except the pinned version in `scripts/release/sparkle-version.txt`.

- [ ] **Step 1: Write the failing tests** `Apps/macOS/Tests/UpdateControllerTests.swift`

```swift
import XCTest
@testable import TimeTug

@MainActor
final class UpdateControllerTests: XCTestCase {
    private final class FakeDriver: UpdaterDriving {
        var automaticallyChecksForUpdates = true
        var lastUpdateCheckDate: Date?
        var checks = 0
        func checkForUpdates() { checks += 1 }
    }

    private func freshDefaults() -> UserDefaults {
        let name = "TimeTugTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func make(_ driver: FakeDriver = FakeDriver(), defaults: UserDefaults? = nil) -> UpdateController {
        UpdateController(driver: driver, defaults: defaults ?? freshDefaults(), currentVersion: "0.2.0")
    }

    func testBetasOffByDefault() {
        XCTAssertFalse(make().includeBetas)
    }

    func testIncludeBetasPersists() {
        let defaults = freshDefaults()
        make(defaults: defaults).includeBetas = true
        XCTAssertTrue(make(defaults: defaults).includeBetas)
    }

    func testAllowedChannels() {
        XCTAssertEqual(UpdateController.allowedChannels(includeBetas: true), ["beta"])
        XCTAssertEqual(UpdateController.allowedChannels(includeBetas: false), [])
    }

    func testAutomaticChecksReadFromAndWrittenToDriver() {
        let driver = FakeDriver()
        driver.automaticallyChecksForUpdates = false
        let controller = make(driver)
        XCTAssertFalse(controller.automaticallyChecks)
        controller.automaticallyChecks = true
        XCTAssertTrue(driver.automaticallyChecksForUpdates)
    }

    func testCheckForUpdatesForwards() {
        let driver = FakeDriver()
        make(driver).checkForUpdates()
        XCTAssertEqual(driver.checks, 1)
    }

    func testLastCheckDateAndVersionExposed() {
        let driver = FakeDriver()
        let date = Date(timeIntervalSince1970: 100)
        driver.lastUpdateCheckDate = date
        let controller = make(driver)
        XCTAssertEqual(controller.lastCheckDate, date)
        XCTAssertEqual(controller.currentVersion, "0.2.0")
    }
}
```

- [ ] **Step 2: Add Sparkle to `project.yml`.** Under `packages:` add (use the version from `scripts/release/sparkle-version.txt`):

```yaml
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    exactVersion: <VERSION from scripts/release/sparkle-version.txt>
```

Under the `TimeTug` target `dependencies:` add:

```yaml
      - package: Sparkle
        product: Sparkle
```

Under the `TimeTug` target `info.properties:` add:

```yaml
        SUFeedURL: https://darkarena1.github.io/timetug/appcast.xml
        SUPublicEDKey: <public key, see Task 10 step 1>
        SUEnableAutomaticChecks: true
```

Until Task 10 produces the real key, run `generate_keys` yourself now (it stores the private key in your login keychain and prints the public key): download tools with `scripts/release/fetch-sparkle-tools.sh /tmp/sparkle-tools`, run `/tmp/sparkle-tools/bin/generate_keys`, and paste the printed public key. The public key is not secret.

- [ ] **Step 3: Run the tests, expect a compile failure**

Run: `xcodegen generate --spec Apps/macOS/project.yml && xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test -only-testing:TimeTugTests/UpdateControllerTests 2>&1 | tail -15`
Expected: `cannot find 'UpdaterDriving' in scope`.

- [ ] **Step 4: Implement** `Apps/macOS/Sources/UpdateController.swift`

```swift
import Foundation
import Sparkle

/// What the app needs from an updater. Tests use a fake; production uses Sparkle.
protocol UpdaterDriving: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var lastUpdateCheckDate: Date? { get }
    func checkForUpdates()
}

/// The Software Update state the Settings pane and the menu need. Sparkle owns the automatic-check
/// preference; the beta opt-in is ours and lives in UserDefaults.
@MainActor
final class UpdateController: ObservableObject {
    private static let betaKey = "updates.includeBetas.v1"
    private let driver: UpdaterDriving
    private let defaults: UserDefaults
    let currentVersion: String

    @Published var automaticallyChecks: Bool {
        didSet { driver.automaticallyChecksForUpdates = automaticallyChecks }
    }
    @Published var includeBetas: Bool {
        didSet { defaults.set(includeBetas, forKey: Self.betaKey) }
    }

    var lastCheckDate: Date? { driver.lastUpdateCheckDate }

    init(driver: UpdaterDriving, defaults: UserDefaults = .standard, currentVersion: String) {
        self.driver = driver
        self.defaults = defaults
        self.currentVersion = currentVersion
        self.automaticallyChecks = driver.automaticallyChecksForUpdates
        self.includeBetas = defaults.bool(forKey: Self.betaKey)
    }

    func checkForUpdates() { driver.checkForUpdates() }

    /// Sparkle channels this Mac may receive. Stable items have no channel and are always allowed.
    nonisolated static func allowedChannels(includeBetas: Bool) -> Set<String> {
        includeBetas ? ["beta"] : []
    }
}

/// Production updater: Sparkle's standard controller with our channel policy.
final class SparkleUpdater: NSObject, UpdaterDriving, SPUUpdaterDelegate {
    private let includeBetas: () -> Bool
    private var controller: SPUStandardUpdaterController!

    init(includeBetas: @escaping () -> Bool) {
        self.includeBetas = includeBetas
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
    var lastUpdateCheckDate: Date? { controller.updater.lastUpdateCheckDate }
    func checkForUpdates() { controller.checkForUpdates(nil) }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        UpdateController.allowedChannels(includeBetas: includeBetas())
    }
}
```

The delegate closure reads the persisted flag at check time, so toggling Beta Updates takes effect on the next check without recreating Sparkle.

- [ ] **Step 5: Run the tests, expect PASS**

Run: the command from Step 3.
Expected: `Test Suite 'UpdateControllerTests' passed` (6 tests). If the build fails on Sparkle API names, check the pinned version's headers under `build/DerivedData/SourcePackages/checkouts/Sparkle`.

- [ ] **Step 6: Commit**

```bash
git add Apps/macOS/project.yml Apps/macOS/Sources/UpdateController.swift Apps/macOS/Tests/UpdateControllerTests.swift
git commit -m "feat(updates): Sparkle-backed UpdateController with beta opt-in

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: Settings UI, search and menu item

**Files:**
- Create: `Apps/macOS/Sources/UpdatesSection.swift`
- Modify: `Apps/macOS/Sources/SettingsSearch.swift`, `GeneralPane.swift`, `SettingsView.swift`, `StatusItemController.swift`, `AppCoordinator.swift`; tests `SettingsSearchTests.swift`, `StatusMenuTests.swift`

**Interfaces:**
- Consumes: `UpdateController` (Task 5).
- Produces: `UpdatesSection(updates:navigation:)`; `SettingsText.checkForUpdates/automaticUpdates/betaUpdates`; catalog ids `software-update`, `automatic-updates`, `beta-updates`; `StatusItemController.makeMenu(target:about:checkForUpdates:settings:)`.

- [ ] **Step 1: Write failing tests.** In `SettingsSearchTests.swift` add:

```swift
    func testUpdateSettingsAreFoundInGeneral() {
        for (query, id) in [("update", "software-update"), ("automatic updates", "automatic-updates"), ("beta updates", "beta-updates")] {
            let hit = SettingsSearch.results(for: query, calendars: []).first { $0.id == id }
            XCTAssertEqual(hit?.pane, .general, query)
        }
    }
```

In `StatusMenuTests.swift` replace `Target` and the two tests:

```swift
    private final class Target: NSObject {
        @objc func about() {}
        @objc func checkForUpdates() {}
        @objc func settings() {}
    }

    private func menu(_ t: Target) -> NSMenu {
        StatusItemController.makeMenu(target: t, about: #selector(Target.about),
                                      checkForUpdates: #selector(Target.checkForUpdates),
                                      settings: #selector(Target.settings))
    }

    func testMenuLayoutMatchesAppleMenuOrder() {
        let items = menu(Target()).items
        XCTAssertEqual(items.map { $0.isSeparatorItem ? "<separator>" : $0.title },
                       ["About TimeTug", "Check for Updates…", "<separator>", "Settings…", "<separator>", "Quit TimeTug"])
    }

    func testKeyEquivalents() {
        let items = menu(Target()).items
        XCTAssertEqual(items[0].keyEquivalent, "")
        XCTAssertEqual(items[1].keyEquivalent, "")
        XCTAssertEqual(items[3].keyEquivalent, ",")
        XCTAssertEqual(items[5].keyEquivalent, "q")
    }
```

- [ ] **Step 2: Run, expect failure**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test -only-testing:TimeTugTests/StatusMenuTests -only-testing:TimeTugTests/SettingsSearchTests 2>&1 | tail -15`
Expected: compile error (`extra argument 'checkForUpdates'`).

- [ ] **Step 3: Menu.** In `StatusItemController.swift` add `private let onCheckForUpdates: () -> Void`, extend the `init` with `onCheckForUpdates: @escaping () -> Void` (before `onOpenAbout`), and change `makeMenu` and its caller:

```swift
    static func makeMenu(target: AnyObject, about: Selector, checkForUpdates: Selector, settings: Selector) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "About TimeTug", action: about, keyEquivalent: "").target = target
        menu.addItem(withTitle: "Check for Updates…", action: checkForUpdates, keyEquivalent: "").target = target
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: settings, keyEquivalent: ",").target = target
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit TimeTug", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }
```

`showMenu` passes `checkForUpdates: #selector(checkForUpdates)` and add `@objc private func checkForUpdates() { onCheckForUpdates() }`.

- [ ] **Step 4: Search catalog.** In `SettingsText` add:

```swift
    static let checkForUpdates = "Check for Updates"
    static let automaticUpdates = "Automatic updates"
    static let betaUpdates = "Beta updates"
```

and to `SettingsSearch.catalog` (keywords avoid "start"/"startup", which other tests assert on):

```swift
        .init(id: "software-update", title: SettingsText.checkForUpdates,
              keywords: ["update", "updates", "upgrade", "version", "software update", "sparkle"], pane: .general),
        .init(id: "automatic-updates", title: SettingsText.automaticUpdates,
              keywords: ["update", "updates", "automatic", "download", "install", "software update"], pane: .general),
        .init(id: "beta-updates", title: SettingsText.betaUpdates,
              keywords: ["update", "updates", "beta", "prerelease", "pre-release", "preview", "early access", "software update"], pane: .general),
```

- [ ] **Step 5: The section view** `Apps/macOS/Sources/UpdatesSection.swift`

```swift
import SwiftUI

/// Software Update controls laid out like System Settings: status, Check for Updates, Automatic, Beta.
struct UpdatesSection: View {
    @ObservedObject var updates: UpdateController
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        Section("Software Update") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TimeTug \(updates.currentVersion)").font(.headline)
                    Text(lastChecked).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Button(SettingsText.checkForUpdates) { updates.checkForUpdates() }
            }
            .settingsHighlight("software-update", navigation: navigation)
            VStack(alignment: .leading, spacing: 4) {
                Toggle(SettingsText.automaticUpdates, isOn: $updates.automaticallyChecks)
                    .settingsHighlight("automatic-updates", navigation: navigation)
                Text("TimeTug checks for new versions in the background and asks before installing.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Toggle(SettingsText.betaUpdates, isOn: $updates.includeBetas)
                    .settingsHighlight("beta-updates", navigation: navigation)
                Text("Get early builds before they are released. Turning this off keeps a beta until the next full release replaces it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var lastChecked: String {
        guard let date = updates.lastCheckDate else { return "Not checked yet" }
        return "Last checked " + date.formatted(date: .abbreviated, time: .shortened)
    }
}
```

- [ ] **Step 6: Wire it.** `GeneralPane` gets `@ObservedObject var updates: UpdateController` and, as its FIRST `Section`, `UpdatesSection(updates: updates, navigation: navigation)`. `SettingsView` gains `let updates: UpdateController` (initializer parameter) and passes it: `GeneralPane(settings: settings, navigation: navigation, updates: updates)`. In `AppCoordinator`:

```swift
    let updates = UpdateController(
        driver: SparkleUpdater(includeBetas: { UserDefaults.standard.bool(forKey: "updates.includeBetas.v1") }),
        currentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
```

pass `updates: updates` into `SettingsView(...)`, and add `onCheckForUpdates: { [weak self] in self?.updates.checkForUpdates() }` to the `StatusItemController(...)` call. The duplicated key string is a smell: expose it as `UpdateController.betaKey` (`nonisolated static let betaKey = "updates.includeBetas.v1"`, make the existing private constant use it) and reference that in the closure.

- [ ] **Step 7: Run the whole app suite**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test 2>&1 | tail -15`
Expected: `** TEST SUCCEEDED **`. Fix any existing `SettingsSearchTests` that asserted exact lists affected by the new keywords.

- [ ] **Step 8: Commit**

```bash
git add Apps/macOS
git commit -m "feat(updates): Software Update section in Settings, search entries and menu item

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: CI gate script and beta workflows

**Files:**
- Create: `scripts/ci/wait-for-ci.sh`, `.github/workflows/beta-build.yml`, `.github/workflows/beta-publish.yml`

**Interfaces:**
- Consumes: `compute-versions.sh` (Task 1), `sign-app.sh`, `make-update-zip.sh`, `fetch-sparkle-tools.sh` (Task 4), `publish-appcast.sh` (Task 3).
- Produces: a workflow artifact `beta-app` containing `TimeTug.tar` (a `tar` of `TimeTug.app`); GitHub prereleases tagged `beta-<timestamp>`.

- [ ] **Step 1: `scripts/ci/wait-for-ci.sh`**

```bash
#!/usr/bin/env bash
# Wait until the CI workflow for <sha> concludes. Exit 0 on success, 1 on any other conclusion or timeout.
# Usage: wait-for-ci.sh <sha>   (env GH_TOKEN, GITHUB_REPOSITORY; WAIT_MINUTES default 45)
set -euo pipefail
sha="${1:?sha}"
deadline=$(( $(date +%s) + ${WAIT_MINUTES:-45} * 60 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  conclusion="$(gh api "repos/$GITHUB_REPOSITORY/actions/workflows/ci.yml/runs?head_sha=$sha&event=pull_request" \
    --jq '[.workflow_runs[] | select(.status=="completed")] | sort_by(.created_at) | last | .conclusion // ""')"
  case "$conclusion" in
    success) echo "CI succeeded for $sha"; exit 0 ;;
    "") sleep 30 ;;
    *) echo "CI concluded '$conclusion' for $sha" >&2; exit 1 ;;
  esac
done
echo "timed out waiting for CI on $sha" >&2
exit 1
```

`chmod +x`.

- [ ] **Step 2: `.github/workflows/beta-build.yml`** (no secrets)

```yaml
# Builds the app for a same-repo pull request. Holds NO secrets: PR-authored scripts run here.
# beta-publish.yml signs and publishes the result with trusted default-branch scripts.
name: Beta build

on:
  pull_request:

concurrency:
  group: beta-build-${{ github.event.pull_request.number }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  build:
    if: github.event.pull_request.head.repo.full_name == github.repository
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v7
      - name: Select newest Xcode
        run: scripts/ci/select-xcode.sh
      - name: Install XcodeGen
        run: brew install xcodegen
      - name: Compute versions
        run: scripts/ci/compute-versions.sh beta "${{ github.event.pull_request.number }}" "${{ github.run_number }}" >> "$GITHUB_ENV"
      - name: Build
        run: scripts/ci/build-release.sh
      - name: Pack app
        run: tar -cf dist/TimeTug.tar -C dist TimeTug.app
      - uses: actions/upload-artifact@v4
        with:
          name: beta-app
          path: dist/TimeTug.tar
          retention-days: 3
```

- [ ] **Step 3: `.github/workflows/beta-publish.yml`** (privileged; checks out the default branch only)

```yaml
# Signs and publishes the beta built by beta-build.yml. Runs from the DEFAULT branch: it never checks out
# or executes pull-request code; the downloaded app is treated as untrusted input. Version and build
# number are read back from the app's plist and validated, not taken from artifact metadata.
name: Beta publish

on:
  workflow_run:
    workflows: ['Beta build']
    types: [completed]

permissions:
  contents: write
  actions: read

concurrency:
  group: appcast
  cancel-in-progress: false

jobs:
  gate:
    if: >-
      github.event.workflow_run.conclusion == 'success' &&
      github.event.workflow_run.event == 'pull_request' &&
      github.event.workflow_run.head_repository.full_name == github.repository
    runs-on: ubuntu-latest
    env:
      GH_TOKEN: ${{ github.token }}
    steps:
      - uses: actions/checkout@v7
      - name: Wait for CI on the PR head
        run: scripts/ci/wait-for-ci.sh "${{ github.event.workflow_run.head_sha }}"

  publish:
    needs: gate
    runs-on: macos-26
    env:
      GH_TOKEN: ${{ github.token }}
    steps:
      - uses: actions/checkout@v7   # default branch: trusted scripts only
      - name: Download the built app
        uses: actions/download-artifact@v4
        with:
          name: beta-app
          run-id: ${{ github.event.workflow_run.id }}
          github-token: ${{ github.token }}
      - name: Unpack and read validated versions
        run: |
          mkdir -p dist && tar -C dist -xf TimeTug.tar
          PLIST=dist/TimeTug.app/Contents/Info.plist
          VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
          BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
          [[ "$BUILD" =~ ^[0-9]{12}$ ]] || { echo "::error::bad build number"; exit 1; }
          [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*([-+][0-9A-Za-z.-]+)?-beta\.[0-9]+\.[0-9]+$ ]] || { echo "::error::bad version"; exit 1; }
          echo "VERSION=$VERSION" >> "$GITHUB_ENV"
          echo "BUILD=$BUILD" >> "$GITHUB_ENV"
      - name: Sign with Developer ID (no notarization)
        env:
          MACOS_CERTIFICATE_P12_BASE64: ${{ secrets.MACOS_CERTIFICATE_P12_BASE64 }}
          MACOS_CERTIFICATE_PASSWORD: ${{ secrets.MACOS_CERTIFICATE_PASSWORD }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: scripts/release/sign-app.sh dist/TimeTug.app
      - name: Zip and EdDSA-sign
        env:
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
        run: |
          ZIP="dist/TimeTug-${VERSION}.zip"
          scripts/release/make-update-zip.sh dist/TimeTug.app "$ZIP"
          BIN="$(scripts/release/fetch-sparkle-tools.sh "$RUNNER_TEMP/sparkle")"
          KEY="$RUNNER_TEMP/sparkle.key"; umask 077
          printf '%s' "$SPARKLE_PRIVATE_KEY" > "$KEY"
          SIG="$("$BIN/sign_update" --ed-key-file "$KEY" "$ZIP")"; rm -f "$KEY"
          echo "SIGNATURE=$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$SIG")" >> "$GITHUB_ENV"
          echo "LENGTH=$(stat -f%z "$ZIP")" >> "$GITHUB_ENV"
          echo "ZIP=$ZIP" >> "$GITHUB_ENV"
      - name: Create draft prerelease
        run: |
          gh release create "beta-${BUILD}" "$ZIP" --draft --prerelease \
            --title "TimeTug ${VERSION}" --target "${{ github.event.workflow_run.head_sha }}" \
            --notes "Beta build from PR head ${{ github.event.workflow_run.head_sha }}."
      - name: Update appcast, then publish the release
        run: |
          URL="https://github.com/${GITHUB_REPOSITORY}/releases/download/beta-${BUILD}/$(basename "$ZIP")"
          git config --global user.name "github-actions[bot]"
          git config --global user.email "41898282+github-actions[bot]@users.noreply.github.com"
          PRUNED="$(scripts/release/publish-appcast.sh "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" \
            --keep-betas 5 -- \
            --title "TimeTug ${VERSION}" --version "$BUILD" --short "$VERSION" --url "$URL" \
            --length "$LENGTH" --signature "$SIGNATURE" --min-system 14.0 --channel beta)"
          gh release edit "beta-${BUILD}" --draft=false --prerelease
          for u in $PRUNED; do
            tag="$(sed -n 's#.*/download/\(beta-[0-9]*\)/.*#\1#p' <<<"$u")"
            [ -n "$tag" ] && gh release delete "$tag" --cleanup-tag --yes || true
          done
```

Betas publish automatically, with no environment approval. Because of that, keep `master` protected and limit who can push branches (see the ADR's accepted risk).

- [ ] **Step 4: Validate YAML and scripts**

Run: `python3 -c "import yaml,sys; [yaml.safe_load(open(f)) for f in ('.github/workflows/beta-build.yml','.github/workflows/beta-publish.yml')]; print('yaml ok')" && bash -n scripts/ci/wait-for-ci.sh && echo sh ok`
Expected: `yaml ok` and `sh ok`. If `actionlint` is installed, also run `actionlint .github/workflows/beta-*.yml`.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows scripts/ci/wait-for-ci.sh
git commit -m "ci: beta build (unprivileged) and beta publish (privileged) workflows

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: Stable release publishes to the appcast

**Files:**
- Modify: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: `compute-versions.sh stable`, `make-update-zip.sh`, `fetch-sparkle-tools.sh`, `publish-appcast.sh`.

- [ ] **Step 1: Stamp the timestamp build number.** Do NOT add a workflow-level concurrency group to `release.yml` (it would make every beta wait for a whole release and can drop queued runs); `publish-appcast.sh` already never force-pushes and re-applies its edit after a rejected push, so a release and a beta writing at once both land. Replace the step "Build Release app" with:

```yaml
      - name: Compute build number
        run: scripts/ci/compute-versions.sh stable "$TAG" >> "$GITHUB_ENV"
      - name: Build Release app
        run: scripts/ci/build-release.sh
```

(`APP_VERSION` and `BUILD_NUMBER` now come from the environment; `TAG` still drives the tag itself.)

- [ ] **Step 2: Add the Sparkle steps after "Sign and notarize DMG" and before "Verify DMG"**, all guarded by signing:

```yaml
      - name: Sparkle update zip and appcast (stable)
        if: steps.signing.outputs.has_signing == 'true'
        env:
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
        run: |
          VERSION="$(cat dist/version.txt)"
          ZIP="dist/TimeTug-${VERSION}.zip"
          scripts/release/make-update-zip.sh dist/TimeTug.app "$ZIP"
          BIN="$(scripts/release/fetch-sparkle-tools.sh "$RUNNER_TEMP/sparkle")"
          KEY="$RUNNER_TEMP/sparkle.key"; umask 077
          printf '%s' "$SPARKLE_PRIVATE_KEY" > "$KEY"
          SIG="$("$BIN/sign_update" --ed-key-file "$KEY" "$ZIP")"; rm -f "$KEY"
          echo "UPDATE_ZIP=$ZIP" >> "$GITHUB_ENV"
          echo "UPDATE_SIGNATURE=$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$SIG")" >> "$GITHUB_ENV"
          echo "UPDATE_LENGTH=$(stat -f%z "$ZIP")" >> "$GITHUB_ENV"
```

- [ ] **Step 3: Attach the zip to the signed release and update the appcast AFTER the release exists.** Extend "Publish signed release": add `"$UPDATE_ZIP"` to the `gh release create` file list, then append a new step:

```yaml
      - name: Add stable item to the appcast
        if: steps.signing.outputs.has_signing == 'true'
        run: |
          VERSION="$(cat dist/version.txt)"
          URL="https://github.com/${GITHUB_REPOSITORY}/releases/download/${TAG}/$(basename "$UPDATE_ZIP")"
          git config --global user.name "github-actions[bot]"
          git config --global user.email "41898282+github-actions[bot]@users.noreply.github.com"
          scripts/release/publish-appcast.sh "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" -- \
            --title "TimeTug ${VERSION}" --version "$BUILD_NUMBER" --short "$VERSION" --url "$URL" \
            --length "$UPDATE_LENGTH" --signature "$UPDATE_SIGNATURE" --min-system 14.0
```

Update the header comment of `release.yml` to say the signed path also publishes the Sparkle zip and stable appcast item, and that an unsigned release never enters the update feed.

- [ ] **Step 4: Validate**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml')); print('yaml ok')"`
Expected: `yaml ok`.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: release publishes the Sparkle zip and stable appcast item when signed

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 9: Documentation

**Files:**
- Modify: `docs/release.md`, `AGENTS.md` ("CI and releases"), `docs/manual-tests/macos-checklist.md`, spec (one line)
- Create: `docs/decisions/0011-sparkle-updates-and-beta-channel.md`

- [ ] **Step 1: ADR** `docs/decisions/0011-sparkle-updates-and-beta-channel.md`, in the format of ADR 0005 (Status, Context, Decision, Consequences), recording: Sparkle 2 pinned exactly (same version as `scripts/release/sparkle-version.txt`); one appcast with a `beta` channel on `gh-pages`; timestamp `CFBundleVersion` and why run numbers and hashes fail; Developer-ID-signed, non-notarized betas and why Gatekeeper does not intervene; the two-workflow beta pipeline and why (PR code must not run with keys); accepted risk: a same-repo branch author can cause a signed beta to ship, so protect `master` and restrict who can push branches; rejected: partial (non-bundle) updates, per-PR labels, `generate_appcast`.

- [ ] **Step 2: Rewrite `docs/release.md`.** Keep the DMG, signing-secret and local-test sections. Replace "Cut a release" and add: **Channels and versioning** (the display/build-number scheme from the spec), **How betas work** (what triggers them, the two workflows, retention of 5, users opt in under Settings > General > Software Update > Beta updates), **One-time setup** (below), **Publishing the stable update** (a signed tag release also updates the appcast; an unsigned one does not), **Troubleshooting** (appcast URL, `sign_update` key errors, why a user is not offered a beta).

One-time setup, to be written in the doc verbatim:
1. Generate keys: `scripts/release/fetch-sparkle-tools.sh /tmp/sparkle-tools && /tmp/sparkle-tools/bin/generate_keys` (public key goes in `project.yml` `SUPublicEDKey`; export the private key with `generate_keys -x sparkle.key`, store its contents as the `SPARKLE_PRIVATE_KEY` Actions secret, then delete the file).
2. `git switch --orphan gh-pages && git commit --allow-empty -m init && git push origin gh-pages`, then enable Pages (Settings > Pages > Deploy from a branch > `gh-pages` / root).
3. Secrets: `SPARKLE_PRIVATE_KEY`, plus the existing `MACOS_CERTIFICATE_P12_BASE64`, `MACOS_CERTIFICATE_PASSWORD`, `APPLE_TEAM_ID`.
4. Protect `master` and require the `release` environment reviewers.

- [ ] **Step 3: AGENTS.md.** In "CI and releases" add bullets for `beta-build.yml`/`beta-publish.yml`, the Sparkle scripts (`scripts/release/appcast.py`, `sign-app.sh`, `publish-appcast.sh`), the timestamp build-number rule, and a Gotcha that `SUFeedURL`/`SUPublicEDKey` live in `project.yml` `info.properties`. Add `UpdateController` to the layout notes and ADR 0011 to the list.

- [ ] **Step 4: Manual checklist** (`docs/manual-tests/macos-checklist.md`), new section "Updates":
  - Settings > General shows Software Update with the current version, Check for Updates, Automatic updates and Beta updates; the menu bar right-click menu has Check for Updates…
  - Against a test appcast (`SUFeedURL` overridden with `defaults write com.timetug.app SUFeedURL <url>`): a newer stable item is offered; a beta item is offered only with Beta updates on; turning it off and checking again offers only stable.
  - Installing an update relaunches the app and widgets still load (team-signed build).

- [x] **Step 5: Spec correction.** Already applied to the spec (`includeBetas` lives in `UserDefaults`); nothing to do.

- [ ] **Step 6: Commit**

```bash
git add docs AGENTS.md
git commit -m "docs: release process, ADR 0011 and checklist for Sparkle updates and betas

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 10: One-time setup and end-to-end verification (needs the owner)

These need credentials only the repo owner has. Each is a checkpoint, not code.

- [ ] **Step 1:** Do the four "One-time setup" items from `docs/release.md`.
- [ ] **Step 2:** Push the branch, open a PR, and confirm `Beta build` passes, then `Beta publish` creates a draft prerelease, updates `https://darkarena1.github.io/timetug/appcast.xml`, and publishes it.
- [ ] **Step 3:** In an installed TimeTug (a previous DMG build), turn on Beta updates, Check for Updates, and confirm the beta is offered, downloads and relaunches. Turn Beta updates off on a stable build and confirm nothing beta is offered.
- [ ] **Step 4:** Merge, tag `v0.x.0`, run the release, and confirm a stable item appears with a `sparkle:version` larger than every earlier beta.

---

## Self-Review (spec coverage)

| Spec requirement | Task |
|---|---|
| Sparkle 2 pinned exactly, new ADR | 4 (pin), 5, 9 |
| One appcast, `beta` channel via `allowedChannels(for:)` | 2, 5 |
| Timestamp `CFBundleVersion` via `BUILD_NUMBER`, no run-number fallback | 1 |
| Display version `<base>-beta.<PR>.<run>`; base from `CFBundleShortVersionString` | 1, 7 |
| `SUFeedURL`/`SUPublicEDKey` in `project.yml` `info.properties` | 5 |
| `UpdateController` behind a protocol, unit-tested | 5 |
| Settings section, Automatic and Beta rows, menu item, search | 6 |
| Two-workflow beta, no secrets in PR-code job, default-branch checkout, workflow_run field checks | 7 |
| Developer ID signing without notarization, Sparkle helpers signed inside-out, `sign-app.sh` split | 4 |
| Draft release, appcast, then publish; failure leaves draft | 7 |
| Beta publishes serialised by the `appcast` concurrency group; release and beta both retry without force-push | 3, 7 |
| Prune to 5 betas | 2, 3, 7 |
| Stable path only when signed; zip from the stapled app | 8 |
| Docs: `release.md`, AGENTS.md, ADR, checklist | 9 |
| One-time setup | 9, 10 |

Known judgment calls, flagged for the reviewer: `includeBetas` lives in `UserDefaults` rather than `SharedSettings` (spec corrected in Task 9); `wait-for-ci.sh` gates the publish on CI success so "latest green PR" holds; `scripts/release/appcast.py` replaces the spec's separate `update-appcast.sh` and `prune-betas.sh` (one Python script, two subcommands, same behavior).
