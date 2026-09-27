#!/usr/bin/env bash
# Prints the test commands a change needs: the packages it touches, every package and the app that depend
# on them (from the Package.swift manifests and Apps/macOS/project.yml), and the tests of changed scripts.
#
# Usage: scripts/dev/affected-tests.sh [--base <ref>] [--run] [path...]
#   path    repo-relative or absolute. Without paths: everything changed since the merge base with <ref>
#           (default origin/master, else master), including staged, unstaged and untracked files.
#   --run   run the commands in order and stop at the first failure.
# Commands are printed one per line, relative to the repository root, dependencies first.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$PWD"
base="" run=0 paths=()
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="${2:?--base needs a ref}"; shift 2 ;;
    --run) run=1; shift ;;
    -h | --help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) paths+=("${1#"$ROOT"/}"); shift ;;
  esac
done

has() { case " $1 " in *" $2 "*) return 0 ;; esac; return 1; }
if [ ${#paths[@]} -gt 0 ]; then
  changed="$(printf '%s\n' "${paths[@]}")"
  since=HEAD
else
  if [ -z "$base" ]; then
    base=master; git rev-parse -q --verify origin/master >/dev/null && base=origin/master
  fi
  since="$(git merge-base HEAD "$base")"
  changed="$({ git diff --name-only --no-renames "$since"; git ls-files --others --exclude-standard; } | sort -u)"
fi

packages=""
for m in Packages/*/Package.swift; do packages="$packages $(basename "$(dirname "$m")")"; done
deps_of() { grep -oE '\.package\(path:[[:space:]]*"\.\./[^"]+"' "Packages/$1/Package.swift" | sed -E 's#.*"\.\./([^"]+)"#\1#' || true; }
app_deps="$(grep -oE 'path:[[:space:]]*\.\./\.\./Packages/[A-Za-z0-9_]+' Apps/macOS/project.yml | sed 's#.*/##' | tr '\n' ' ' || true)"

direct="" app=0 regen=0 arch=0 scripts=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    Packages/*/*)
      p="${f#Packages/}"; p="${p%%/*}"
      has "$packages" "$p" && direct="$direct $p"
      case "$f" in *.swift) arch=1 ;; esac ;;
    Apps/macOS/*)
      app=1
      case "$f" in *.swift) arch=1 ;; esac
      # XcodeGen globs the sources, so added, removed and renamed files need a regenerated project.
      if [ "$f" = Apps/macOS/project.yml ] || [ ! -e "$f" ] || ! git cat-file -e "$since:$f" 2>/dev/null; then regen=1; fi ;;
    .github/workflows/*) scripts+=(scripts/ci/tests/test-workflows.sh) ;;
    scripts/*/*)
      d="${f#scripts/}"; d="scripts/${d%%/*}/tests"
      for t in "$d"/test-*.sh "$d"/test_*.py; do [ -e "$t" ] && scripts+=("$t"); done ;;
  esac
done <<< "$changed"

# Everything that depends on a changed package, directly or not.
affected="$direct"
grew=1
while [ "$grew" = 1 ]; do
  grew=0
  for p in $packages; do
    has "$affected" "$p" && continue
    for d in $(deps_of "$p"); do has "$affected" "$d" && { affected="$affected $p"; grew=1; break; }; done
  done
done
for d in $app_deps; do has "$affected" "$d" && app=1; done
[ -d Apps/macOS/TimeTug.xcodeproj ] || regen=1

cmds=()
[ "$arch" = 1 ] && cmds+=(scripts/ci/check-architecture.sh)
done_pkgs="" progress=1
while [ "$progress" = 1 ]; do   # dependencies first
  progress=0
  for p in $packages; do
    has "$affected" "$p" && ! has "$done_pkgs" "$p" || continue
    ready=1
    for d in $(deps_of "$p"); do has "$affected" "$d" && ! has "$done_pkgs" "$d" && ready=0; done
    [ "$ready" = 1 ] || continue
    done_pkgs="$done_pkgs $p"; progress=1
    cmds+=("swift test --package-path Packages/$p")
  done
done
if [ "$app" = 1 ]; then
  [ "$regen" = 1 ] && cmds+=("xcodegen generate --spec Apps/macOS/project.yml")
  cmds+=("xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test")
fi
seen=" "
for t in ${scripts[@]+"${scripts[@]}"}; do
  has "$seen" "$t" && continue
  seen="$seen$t "
  case "$t" in *.py) cmds+=("python3 $t") ;; *) cmds+=("$t") ;; esac
done

if [ ${#cmds[@]} = 0 ]; then
  echo "No tests affected ($(grep -c . <<< "$changed" || true) changed file(s))." >&2
  exit 0
fi
if [ "$run" = 0 ]; then printf '%s\n' "${cmds[@]}"; exit 0; fi
for c in "${cmds[@]}"; do
  echo "==> $c" >&2
  bash -c "$c" || { s=$?; echo "FAILED ($s): $c" >&2; exit "$s"; }
done
