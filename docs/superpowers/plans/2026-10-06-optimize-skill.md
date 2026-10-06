# Optimize Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a shared `optimize` skill plus a Python library that finds consolidation and removal candidates in Swift, JavaScript/TypeScript, Python and React code, using Serena, Qdrant and native tools when present and built-in replacements when not.

**Architecture:** A language-neutral core (tree-sitter inventory, word-count reference counting, token/shingle clone detection, embedding similarity) with one thin adapter per language. Each capability has an ordered provider list (native tool, then built-in). `scan` is deterministic and read-only; the agent reads the ranked report and does the judgment steps through `SKILL.md`.

**Tech Stack:** Python 3.12, `uv`, `tree-sitter-language-pack`, `pathspec`, `pytest`; optional `fastembed`, `qdrant-client`, `numpy`.

**Spec:** `docs/superpowers/specs/2026-10-06-optimize-skill-design.md` (in the TimeTug repository).

## Where the code lives

`~/.agents` is not a git repository, so the skill is developed in its own repository at `~/Source/optimize-skill/` and symlinked into `~/.agents/skills/optimize` (and from there into `~/.claude/skills` and `~/.codex/skills`). This satisfies the spec's "lives in `~/.agents/skills/optimize/`" while keeping history. All task paths below are relative to `~/Source/optimize-skill/`. Every commit message ends with the trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

Run tests with `./run-tests.sh [pytest args]` (created in Task 1).

## Global Constraints

- Python `>=3.12`; core dependencies limited to `tree-sitter-language-pack` and `pathspec`. `fastembed`, `qdrant-client` and `numpy` are optional (semantic tier only).
- `scan` is read-only: it writes only to `.optimize/`, makes no network calls, and embeds locally.
- Languages in v1: Swift, JavaScript/TypeScript, Python, React/JSX.
- Candidate fields: `id`, `kind` (`clone | dead | semantic-dup | hotspot | single-use`), `language`, `locations`, `evidence`, `provider`, `confidence` (`high | medium | low`), `confirm`, `score`.
- Line numbers are 1-based in all output (Serena's are 0-based; `SKILL.md` says so).
- Files that look like they contain credentials are skipped and listed, never analysed.
- Default excludes: `dist/`, `node_modules/`, `.venv/`, build output, minified, lockfiles, generated code. Files over 500 KB are skipped.
- Two scans of the same tree produce byte-identical `report.json`; candidate ids are stable.
- Public API, entry points and anything reached by reflection or dynamic dispatch (`@objc`, command registries, framework decorators) go to the "review by hand" list and are never reported as dead.

## Review Focus

Failure modes the spec implies but a straightforward implementation would miss. Each has a test in the task that owns the code.

- A `.git` file pointing at a missing repository (the realm-of-darkness checkout) must fall back to a filesystem walk, not crash (Task 2).
- A source file that is binary, non-UTF-8, or syntactically broken must be skipped or tolerated, never abort the scan (Tasks 2, 3).
- Several unrelated types defining a method with the same name (`run`, `init`) must not be reported dead when one of them is called (Task 4).
- An empty project, or one with no supported source files, must produce an empty valid report and exit 0 (Task 10).
- Test classes and methods (XCTest, pytest, jest) are found by the framework by reflection and never look referenced; they must not be reported dead (Task 4). A scan of TimeTug without this rule reported 1,135 false "dead" symbols.
- Python's per-process string hash randomization must not leak into ids or ordering; ids use `sha1`/`crc32` only (Task 10 determinism test).

---

### Task 1: Repository scaffold and shared model

**Files:**
- Create: `pyproject.toml`, `run-tests.sh`, `.gitignore`, `lib/optimize/__init__.py`, `lib/optimize/model.py`
- Test: `tests/conftest.py`, `tests/test_model.py`

**Interfaces:**
- Produces: `Config`, `Location`, `Symbol`, `Candidate`, `stable_id(kind, *parts) -> str`, `canonical_json(obj) -> str` in `optimize.model`.

- [ ] **Step 1: Create the repository**

```bash
mkdir -p ~/Source/optimize-skill && cd ~/Source/optimize-skill && git init -q -b main
```

- [ ] **Step 2: Create the scaffold files**

**Create: `pyproject.toml`**

```toml
[project]
name = "optimize-skill"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = ["tree-sitter-language-pack", "pathspec"]

[project.optional-dependencies]
semantic = ["fastembed", "qdrant-client", "numpy"]
dev = ["pytest", "numpy"]

[tool.pytest.ini_options]
pythonpath = ["lib"]
testpaths = ["tests"]
```

**Create: `run-tests.sh`**

```bash
#!/usr/bin/env bash
cd "$(dirname "$0")" && exec uv run --python 3.12 --with pytest --with numpy --with tree-sitter-language-pack --with pathspec pytest -q "$@"
```

**Create: `.gitignore`**

```
__pycache__/
.pytest_cache/
.venv/
.optimize/
```

**Create: `lib/optimize/__init__.py`**

```python
__version__ = "0.1.0"
```

**Create: `tests/conftest.py`**

```python
import shutil
from pathlib import Path

import pytest

FIXTURES = Path(__file__).parent / "fixtures"


@pytest.fixture
def fixture_root(tmp_path):
    """Copy a fixture project into a temp dir (no git, so discovery uses the file walk)."""

    def make(name):
        dest = tmp_path / name
        if not dest.exists():
            shutil.copytree(FIXTURES / name, dest)
        return dest

    return make
```

- [ ] **Step 3: Write the failing test**

**Create: `tests/test_model.py`**

```python
from optimize.model import Candidate, Location, canonical_json, stable_id


def test_stable_id_is_deterministic_and_prefixed():
    assert stable_id("dead", "a.py", "f") == stable_id("dead", "a.py", "f")
    assert stable_id("dead", "a.py", "f").startswith("dead-")
    assert stable_id("clone", "x").startswith("dup-")
    assert stable_id("dead", "a") != stable_id("dead", "b")


def test_candidate_round_trip_rounds_floats():
    c = Candidate(
        id="dead-1",
        kind="dead",
        language="python",
        locations=[Location("a.py", 1, 3, "f")],
        evidence={"refs": 0, "similarity": 0.123456789},
        provider="p",
        confidence="medium",
        confirm=["zero-references"],
        score=0.5,
    )
    d = c.to_dict()
    assert d["evidence"]["similarity"] == 0.1235
    assert Candidate.from_dict(d).to_dict() == d


def test_location_overlap():
    a = Location("a.py", 1, 10)
    assert a.overlaps(Location("a.py", 10, 12))
    assert not a.overlaps(Location("a.py", 11, 12))
    assert not a.overlaps(Location("b.py", 1, 10))


def test_canonical_json_sorted_with_trailing_newline():
    text = canonical_json({"b": 1, "a": 2})
    assert text.index('"a"') < text.index('"b"')
    assert text.endswith("\n")
```

- [ ] **Step 4: Run test to verify it fails**

Run: `chmod +x run-tests.sh && ./run-tests.sh tests/test_model.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'optimize.model'`

- [ ] **Step 5: Write the implementation**

**Create: `lib/optimize/model.py`**

```python
"""Shared types, configuration and deterministic serialization."""
from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field
from typing import Any

KINDS = ("clone", "dead", "semantic-dup", "hotspot", "single-use")
CONFIDENCES = ("low", "medium", "high")
_PREFIX = {"clone": "dup", "dead": "dead", "semantic-dup": "sem", "hotspot": "hot", "single-use": "one"}


@dataclass(frozen=True)
class Config:
    min_clone_tokens: int = 50
    near_threshold: float = 0.8
    hotspot_complexity: int = 15
    single_use_max_tokens: int = 60
    semantic_threshold: float = 0.92
    semantic_max_symbols: int = 3000
    top_n: int = 25


def stable_id(kind: str, *parts: str) -> str:
    """Id derived only from content (sha1), never from Python's randomized hash()."""
    digest = hashlib.sha1("|".join((kind, *parts)).encode()).hexdigest()[:8]
    return f"{_PREFIX[kind]}-{digest}"


def _round(value: Any) -> Any:
    if isinstance(value, float):
        return round(value, 4)
    if isinstance(value, dict):
        return {k: _round(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_round(v) for v in value]
    return value


def canonical_json(obj: Any) -> str:
    return json.dumps(obj, sort_keys=True, indent=2, ensure_ascii=False) + "\n"


@dataclass(frozen=True)
class Location:
    path: str
    start: int
    end: int
    symbol: str | None = None

    def overlaps(self, other: "Location") -> bool:
        return self.path == other.path and self.start <= other.end and other.start <= self.end

    def to_dict(self) -> dict:
        return {"path": self.path, "start": self.start, "end": self.end, "symbol": self.symbol}

    @classmethod
    def from_dict(cls, d: dict) -> "Location":
        return cls(d["path"], d["start"], d["end"], d.get("symbol"))


@dataclass
class Symbol:
    name: str
    kind: str  # function | method | type
    language: str
    path: str
    start: int
    end: int
    tokens: int
    complexity: int
    norm_hash: str
    markers: list[str] = field(default_factory=list)
    qualname: str = ""
    seq: list[str] = field(default_factory=list, repr=False, compare=False)

    @property
    def label(self) -> str:
        return self.qualname or self.name

    @property
    def location(self) -> Location:
        return Location(self.path, self.start, self.end, self.label)


@dataclass
class Candidate:
    id: str
    kind: str
    language: str
    locations: list[Location]
    evidence: dict[str, Any]
    provider: str
    confidence: str
    confirm: list[str]
    score: float = 0.0

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "kind": self.kind,
            "language": self.language,
            "locations": [loc.to_dict() for loc in self.locations],
            "evidence": _round(self.evidence),
            "provider": self.provider,
            "confidence": self.confidence,
            "confirm": list(self.confirm),
            "score": round(self.score, 4),
        }

    @classmethod
    def from_dict(cls, d: dict) -> "Candidate":
        return cls(
            id=d["id"],
            kind=d["kind"],
            language=d["language"],
            locations=[Location.from_dict(x) for x in d["locations"]],
            evidence=d["evidence"],
            provider=d["provider"],
            confidence=d["confidence"],
            confirm=list(d["confirm"]),
            score=d.get("score", 0.0),
        )
```

- [ ] **Step 6: Run test to verify it passes**

Run: `./run-tests.sh tests/test_model.py`
Expected: 4 passed

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -q -m "Scaffold optimize skill library and shared model" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: File discovery

**Files:**
- Create: `lib/optimize/discover.py`
- Test: `tests/test_discover.py`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `LANGUAGE_BY_SUFFIX: dict[str, str]`, `SourceFile(path: str, abs: Path, language: str)`, `Discovery(root, files, via, skipped_secret, excluded)`, `discover(root, paths=None, languages=None) -> Discovery`.

- [ ] **Step 1: Write the failing test**

**Create: `tests/test_discover.py`**

```python
import subprocess

from optimize.discover import discover


def write(root, rel, text="x = 1\n"):
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(text, bytes):
        path.write_bytes(text)
    else:
        path.write_text(text)
    return path


def names(d):
    return {f.path for f in d.files}


def test_broken_git_pointer_falls_back_to_walk(tmp_path):
    # Mirrors the realm-of-darkness checkout: .git is a file pointing at a missing repository.
    (tmp_path / ".git").write_text("gitdir: /nonexistent/place/.git/worktrees/x\n")
    write(tmp_path, "a.py")
    write(tmp_path, "b.swift", "let a = 1\n")
    write(tmp_path, "node_modules/x.js", "var a\n")
    write(tmp_path, "dist/y.js", "var b\n")
    write(tmp_path, "ignored.py")
    write(tmp_path, ".gitignore", "ignored.py\n")
    d = discover(tmp_path)
    assert d.via == "walk"
    assert names(d) == {"a.py", "b.swift"}


def test_uses_git_when_it_works(tmp_path):
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    write(tmp_path, "tracked.py")
    write(tmp_path, "skip.py")
    write(tmp_path, ".gitignore", "skip.py\n")
    subprocess.run(["git", "add", "tracked.py", ".gitignore"], cwd=tmp_path, check=True)
    write(tmp_path, "untracked.py")
    d = discover(tmp_path)
    assert d.via == "git"
    assert names(d) == {"tracked.py", "untracked.py"}


def test_skips_binary_and_credential_files_but_keeps_odd_encodings(tmp_path):
    write(tmp_path, "bin.py", b"\x00\x01\xff")
    write(tmp_path, "latin.py", b"x = '\xff\xfe'\n")
    write(tmp_path, "leak.py", "api" + "_key = " + '"' + "a1b2c3d4e5f6g7h8" + '"' + "\n")
    write(tmp_path, "ok.py")
    d = discover(tmp_path)
    assert names(d) == {"latin.py", "ok.py"}
    assert d.skipped_secret == ["leak.py"]


def test_size_limit_ignore_file_minified_and_filters(tmp_path):
    write(tmp_path, "big.py", "x = 1\n" * 100_000)
    write(tmp_path, "lib/app.min.js", "var a=1\n")
    write(tmp_path, "gen/out.py")
    write(tmp_path, ".optimizeignore", "gen/\n")
    write(tmp_path, "src/a.py")
    write(tmp_path, "src/b.ts", "const a = 1\n")
    write(tmp_path, "other/c.py")
    d = discover(tmp_path)
    assert names(d) == {"src/a.py", "src/b.ts", "other/c.py"}
    assert d.excluded == 3  # big.py, app.min.js, gen/out.py
    assert names(discover(tmp_path, paths=["src"])) == {"src/a.py", "src/b.ts"}
    assert names(discover(tmp_path, languages=["typescript"])) == {"src/b.ts"}
    assert {f.language for f in discover(tmp_path).files} == {"python", "typescript"}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./run-tests.sh tests/test_discover.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'optimize.discover'`

- [ ] **Step 3: Write the implementation**

**Create: `lib/optimize/discover.py`**

```python
"""Find the source files to analyse: git when it works, a .gitignore-aware walk when it does not."""
from __future__ import annotations

import fnmatch
import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

import pathspec

LANGUAGE_BY_SUFFIX = {
    ".swift": "swift",
    ".js": "javascript",
    ".jsx": "javascript",
    ".mjs": "javascript",
    ".cjs": "javascript",
    ".ts": "typescript",
    ".tsx": "typescript",
    ".py": "python",
}
SKIP_DIRS = {
    ".git", "node_modules", ".venv", "venv", "__pycache__", "dist", "build", "target", ".next", "vendor",
    ".build", "Pods", "DerivedData", "Carthage", ".gradle", ".optimize", ".swiftpm", "coverage",
}
SKIP_NAME = re.compile(r"(\.min\.js$|\.d\.ts$|\.pb\.swift$|\.generated\.\w+$|^\.env)", re.I)
MAX_BYTES = 500_000
IGNORE_FILE = ".optimizeignore"  # fnmatch patterns on the repo-relative path; a trailing "/" skips a folder
# Files that look like they hold a credential are skipped (same rules as the index skill).
SECRET = re.compile(
    r"(sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|BEGIN [A-Z ]*PRIVATE KEY|"
    r"(password|passwd|secret|api_?key|token)\s*[=:]\s*['\"][^'\"\s$\\{}()]{8,}['\"]|"
    r"(?-i:Authorization):\s*(?:Bearer|Basic)\s+[A-Za-z0-9._~+/=-]{12,})",
    re.I,
)


@dataclass
class SourceFile:
    path: str  # repo-relative, posix
    abs: Path
    language: str


@dataclass
class Discovery:
    root: Path
    files: list[SourceFile]
    via: str  # "git" | "walk"
    skipped_secret: list[str]
    excluded: int  # source files skipped by name pattern, size, binary content or .optimizeignore


def _git_files(root: Path) -> list[Path] | None:
    r = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-co", "--exclude-standard"], capture_output=True, text=True
    )
    if r.returncode != 0:
        return None
    return [root / f for f in r.stdout.splitlines()]


def _gitignore_spec(lines: list[str]):
    for factory in ("gitignore", "gitwildmatch"):  # newer pathspec renamed the factory
        try:
            return pathspec.PathSpec.from_lines(factory, lines)
        except KeyError:
            continue
    return None


def _walk_files(root: Path) -> list[Path]:
    spec = None
    gitignore = root / ".gitignore"
    if gitignore.is_file():
        spec = _gitignore_spec(gitignore.read_text(errors="ignore").splitlines())
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        rel_dir = Path(dirpath).relative_to(root)
        dirnames[:] = sorted(
            d for d in dirnames
            if d not in SKIP_DIRS and not (spec and spec.match_file((rel_dir / d).as_posix() + "/"))
        )
        for name in sorted(filenames):
            rel = (rel_dir / name).as_posix()
            if spec and spec.match_file(rel):
                continue
            out.append(root / rel)
    return out


def _ignore_patterns(root: Path) -> list[str]:
    try:
        lines = (root / IGNORE_FILE).read_text().splitlines()
    except OSError:
        return []
    return [line.strip() for line in lines if line.strip() and not line.lstrip().startswith("#")]


def _ignored(rel: str, patterns: list[str]) -> bool:
    for pat in patterns:
        if pat.endswith("/"):
            if rel.startswith(pat):
                return True
        elif fnmatch.fnmatch(rel, pat):
            return True
    return False


def discover(root, paths=None, languages=None) -> Discovery:
    root = Path(root).resolve()
    listed = _git_files(root)
    via = "git"
    if listed is None:
        listed, via = _walk_files(root), "walk"
    ignore = _ignore_patterns(root)
    scopes = [p.strip("/") for p in (paths or [])]
    wanted = set(languages) if languages else None
    files: list[SourceFile] = []
    skipped_secret: list[str] = []
    excluded = 0
    for p in sorted(listed):
        try:
            rel_path = p.relative_to(root)
        except ValueError:
            continue
        language = LANGUAGE_BY_SUFFIX.get(p.suffix.lower())
        if language is None or (wanted and language not in wanted):
            continue
        rel = rel_path.as_posix()
        if SKIP_DIRS & set(rel_path.parts[:-1]):
            continue
        if scopes and not any(rel == s or rel.startswith(s + "/") for s in scopes):
            continue
        if SKIP_NAME.search(p.name) or _ignored(rel, ignore):
            excluded += 1
            continue
        try:
            if not p.is_file() or p.stat().st_size > MAX_BYTES:
                excluded += 1
                continue
            data = p.read_bytes()
        except OSError:
            continue
        if b"\0" in data:
            excluded += 1
            continue
        if SECRET.search(data.decode("utf-8", "ignore")):
            skipped_secret.append(rel)
            continue
        files.append(SourceFile(rel, p, language))
    return Discovery(root, files, via, skipped_secret, excluded)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./run-tests.sh tests/test_discover.py`
Expected: 4 passed

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -q -m "Add file discovery with git and filesystem-walk modes" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Language adapters, tokenizer and symbol inventory (with fixtures)

**Files:**
- Create: `lib/optimize/tokens.py`, `lib/optimize/adapters/__init__.py`, `lib/optimize/adapters/base.py`, `lib/optimize/adapters/python.py`, `lib/optimize/adapters/swift.py`, `lib/optimize/adapters/js_ts.py`, `lib/optimize/inventory.py`
- Create fixtures: `tests/fixtures/python/{durations.py,app.py}`, `tests/fixtures/swift/Sources/App/{Durations.swift,Controller.swift,main.swift}`, `tests/fixtures/js/src/{durations.js,index.js,types.ts,commands/pong.js}`, `tests/fixtures/react/src/{Cards.jsx,App.jsx}`
- Test: `tests/test_inventory.py`

**Interfaces:**
- Consumes: `Symbol` from Task 1; `SourceFile` and `LANGUAGE_BY_SUFFIX` from Task 2.
- Produces:
  - `normalize(text, keywords, line_comment) -> list[str]` in `optimize.tokens`.
  - `ADAPTERS: dict[str, Adapter]` in `optimize.adapters` (keys `swift`, `javascript`, `typescript`, `python`).
  - `is_test_path(path) -> bool` and `Inventory` with `symbols: list[Symbol]`, `words: Counter`, `defs: Counter`, `texts: dict[str, str]`, `totals: dict[str, dict]`, `parse_errors: list[str]`, `refs(sym) -> int`, `snippet(path, start, end) -> str`, `symbol_at(path, line) -> Symbol | None`.
  - `build_inventory(files: list[SourceFile]) -> Inventory`.
- Symbol `kind` is `function | method | type`. Symbol `markers` values: `decorated`, `framework-name`, `dynamic-dispatch`, `override`, `public-api`, `possible-witness`, `exported`, `registry-loaded`, `test-code`, `entry-point`, `special-name`.

- [ ] **Step 1: Create the fixture projects**

These fixtures contain planted cases used by Tasks 3-10: an exact renamed clone (`format_duration`/`render_elapsed` and equivalents), an unused function, a single-use wrapper, a high-complexity function, and look-alikes that must go to "review by hand".

**Create: `tests/fixtures/python/durations.py`**

```python
def format_duration(seconds):
    hours = seconds // 3600
    minutes = (seconds % 3600) // 60
    secs = seconds % 60
    if hours:
        return f"{hours}h {minutes}m {secs}s"
    if minutes:
        return f"{minutes}m {secs}s"
    return f"{secs}s"


def render_elapsed(total_seconds):
    h = total_seconds // 3600
    m = (total_seconds % 3600) // 60
    s = total_seconds % 60
    if h:
        return f"{h}h {m}m {s}s"
    if m:
        return f"{m}m {s}s"
    return f"{s}s"


def unused_helper(values):
    total = 0
    for value in values:
        total += value * 2
    return total
```

**Create: `tests/fixtures/python/app.py`**

```python
from durations import format_duration, render_elapsed


def only_called_once(seconds):
    return format_duration(seconds)


def branchy(a, b, c):
    if a > 1:
        return 1
    elif a > 0:
        return 2
    if b:
        for i in range(3):
            if i == c:
                return i
    while c:
        c -= 1
        if c == 5:
            break
    if a and b:
        return 3
    return 0


class App:
    def route(self, path):
        def wrap(fn):
            return fn

        return wrap


app = App()


@app.route("/health")
def health_endpoint():
    return "ok"


def main():
    print(only_called_once(5), render_elapsed(7), branchy(1, 2, 3))
```

**Create: `tests/fixtures/swift/Sources/App/Durations.swift`**

```swift
import Foundation

func formatDuration(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let secs = seconds % 60
    if hours > 0 {
        return "\(hours)h \(minutes)m \(secs)s"
    }
    if minutes > 0 {
        return "\(minutes)m \(secs)s"
    }
    return "\(secs)s"
}

func renderElapsed(_ total: Int) -> String {
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 {
        return "\(h)h \(m)m \(s)s"
    }
    if m > 0 {
        return "\(m)m \(s)s"
    }
    return "\(s)s"
}

func unusedHelper(_ values: [Int]) -> Int {
    var total = 0
    for value in values {
        total += value * 2
    }
    return total
}
```

**Create: `tests/fixtures/swift/Sources/App/Controller.swift`**

```swift
import AppKit

final class Controller: NSObject {
    @objc func menuAction(_ sender: Any?) {
        print("menu")
    }

    func onlyOnce(_ seconds: Int) -> String {
        return formatDuration(seconds)
    }

    func branchy(_ a: Int, _ b: Int, _ c: Int) -> Int {
        if a > 1 {
            return 1
        } else if a > 0 {
            return 2
        }
        if b > 0 {
            for i in 0..<3 {
                if i == c {
                    return i
                }
            }
        }
        var n = c
        while n > 0 {
            n -= 1
            if n == 5 {
                break
            }
        }
        guard a > b else {
            return 3
        }
        return 0
    }
}
```

**Create: `tests/fixtures/swift/Sources/App/main.swift`**

```swift
func wrapper(_ seconds: Int) -> String {
    return formatDuration(seconds)
}

print(wrapper(5), renderElapsed(7), Controller().branchy(1, 2, 3))
```

**Create: `tests/fixtures/js/src/durations.js`**

```javascript
export function formatDuration(seconds) {
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const secs = seconds % 60;
  if (hours > 0) {
    return `${hours}h ${minutes}m ${secs}s`;
  }
  if (minutes > 0) {
    return `${minutes}m ${secs}s`;
  }
  return `${secs}s`;
}

export function renderElapsed(total) {
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  if (h > 0) {
    return `${h}h ${m}m ${s}s`;
  }
  if (m > 0) {
    return `${m}m ${s}s`;
  }
  return `${s}s`;
}

function unusedHelper(values) {
  let total = 0;
  for (const value of values) {
    total += value * 2;
  }
  return total;
}

export function neverImported() {
  return 42;
}
```

**Create: `tests/fixtures/js/src/index.js`**

```javascript
import { formatDuration, renderElapsed } from './durations.js';

const onlyOnce = (seconds) => formatDuration(seconds);

function branchy(a, b, c) {
  if (a > 1) {
    return 1;
  } else if (a > 0) {
    return 2;
  }
  if (b) {
    for (let i = 0; i < 3; i++) {
      if (i === c) {
        return i;
      }
    }
  }
  while (c) {
    c -= 1;
    if (c === 5) {
      break;
    }
  }
  return a ? 3 : 0;
}

console.log(onlyOnce(5), renderElapsed(7), branchy(1, 2, 3));
```

**Create: `tests/fixtures/js/src/commands/pong.js`**

```javascript
export default async function pongCommand(interaction) {
  await interaction.reply('Pong!');
}
```

**Create: `tests/fixtures/js/src/types.ts`**

```typescript
function unusedTyped(a: number, b: number): number {
  const sum = a + b;
  return sum * 2;
}
```

**Create: `tests/fixtures/react/src/Cards.jsx`**

```jsx
import React from 'react';

export function UserCard({ user }) {
  return (
    <div className="card">
      <h2>{user.name}</h2>
      <p>{user.email}</p>
      <span>{user.role}</span>
    </div>
  );
}

export function AdminCard({ admin }) {
  return (
    <div className="card">
      <h2>{admin.name}</h2>
      <p>{admin.email}</p>
      <span>{admin.role}</span>
    </div>
  );
}

const Orphan = () => <div className="orphan">unused</div>;
```

**Create: `tests/fixtures/react/src/App.jsx`**

```jsx
import React from 'react';
import { UserCard, AdminCard } from './Cards';

export default function App() {
  return (
    <>
      <UserCard user={{}} />
      <AdminCard admin={{}} />
    </>
  );
}
```

- [ ] **Step 2: Write the failing test**

**Create: `tests/test_inventory.py`**

```python
from optimize.discover import discover
from optimize.inventory import build_inventory, is_test_path
from optimize.tokens import normalize


def inventory(fixture_root, name):
    root = fixture_root(name)
    return build_inventory(discover(root).files)


def by_label(inv):
    return {s.label: s for s in inv.symbols}


def test_normalize_renames_identifiers_but_keeps_keywords():
    kw = frozenset({"def", "return"})
    a = normalize("def foo(x):\n    return x + 1  # note", kw, "#")
    b = normalize("def bar(y):\n    return y + 2", kw, "#")
    assert a == b
    assert a[0] == "def" and "ID" in a and "NUM" in a


def test_python_symbols(fixture_root):
    syms = by_label(inventory(fixture_root, "python"))
    assert syms["format_duration"].kind == "function"
    assert syms["App.route"].kind == "method"
    assert syms["App"].kind == "type"
    assert "decorated" in syms["health_endpoint"].markers
    assert "entry-point" in syms["main"].markers
    assert syms["branchy"].complexity >= 8
    assert syms["format_duration"].norm_hash == syms["render_elapsed"].norm_hash
    assert syms["format_duration"].start == 1 and syms["format_duration"].end == 9


def test_swift_symbols(fixture_root):
    syms = by_label(inventory(fixture_root, "swift"))
    assert syms["formatDuration"].kind == "function"
    assert syms["formatDuration"].norm_hash == syms["renderElapsed"].norm_hash
    assert syms["Controller"].kind == "type"
    assert syms["Controller.menuAction"].kind == "method"
    assert "dynamic-dispatch" in syms["Controller.menuAction"].markers
    assert "possible-witness" in syms["Controller.onlyOnce"].markers
    assert syms["Controller.branchy"].complexity >= 8


def test_javascript_typescript_and_react_symbols(fixture_root):
    js = by_label(inventory(fixture_root, "js"))
    assert js["formatDuration"].kind == "function" and "exported" in js["formatDuration"].markers
    assert js["onlyOnce"].kind == "function"  # arrow function bound to a const
    assert "exported" not in js["unusedHelper"].markers
    assert "registry-loaded" in js["pongCommand"].markers
    assert js["unusedTyped"].language == "typescript"
    assert js["formatDuration"].norm_hash == js["renderElapsed"].norm_hash
    react = by_label(inventory(fixture_root, "react"))
    assert react["UserCard"].norm_hash == react["AdminCard"].norm_hash
    assert react["Orphan"].kind == "function"


def test_reference_counts_use_word_occurrences(fixture_root):
    inv = inventory(fixture_root, "python")
    syms = by_label(inv)
    assert inv.refs(syms["unused_helper"]) == 0
    assert inv.refs(syms["only_called_once"]) == 1
    assert inv.refs(syms["format_duration"]) >= 2


def test_symbol_at_returns_innermost(fixture_root):
    inv = inventory(fixture_root, "python")
    assert inv.symbol_at("app.py", 29).name == "wrap"
    assert inv.symbol_at("app.py", 1) is None


def test_test_files_are_marked_test_code(tmp_path):
    (tmp_path / "Tests").mkdir()
    (tmp_path / "Tests" / "ThingTests.swift").write_text("final class ThingTests {\n    func testIt() {}\n}\n")
    (tmp_path / "test_x.py").write_text("def helper():\n    pass\n")
    (tmp_path / "x.test.js").write_text("function spec() {}\n")
    inv = build_inventory(discover(tmp_path).files)
    assert inv.symbols and all("test-code" in s.markers for s in inv.symbols)
    assert is_test_path("Apps/macOS/Tests/A.swift") and not is_test_path("src/app.py")


def test_syntactically_broken_file_does_not_abort(fixture_root, tmp_path):
    root = fixture_root("python")
    (root / "bad.py").write_text("def (:\n  class ]]]\n@@@\n")
    inv = build_inventory(discover(root).files)
    assert any(s.name == "format_duration" for s in inv.symbols)
    assert inv.totals["python"]["files"] == 3
```

- [ ] **Step 3: Run test to verify it fails**

Run: `./run-tests.sh tests/test_inventory.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'optimize.tokens'`

- [ ] **Step 4: Write the tokenizer and adapter base**

**Create: `lib/optimize/tokens.py`**

```python
"""Language-aware token normalization used for clone detection and size metrics."""
from __future__ import annotations

import re

_STRING = r"\"(?:\\.|[^\"\\\n])*\"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`"
_TOKEN = re.compile(rf"({_STRING})|(\d[\w.]*)|([A-Za-z_]\w*)|(\S)")
_BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.S)
_LINE_COMMENT = {"//": re.compile(r"//[^\n]*"), "#": re.compile(r"#[^\n]*")}


def strip_comments(text: str, line_comment: str) -> str:
    if line_comment == "//":
        text = _BLOCK_COMMENT.sub(" ", text)
    return _LINE_COMMENT[line_comment].sub(" ", text)


def normalize(text: str, keywords: frozenset[str], line_comment: str) -> list[str]:
    """Strings -> STR, numbers -> NUM, non-keyword identifiers -> ID, everything else verbatim."""
    out: list[str] = []
    for m in _TOKEN.finditer(strip_comments(text, line_comment)):
        string, number, ident, punct = m.groups()
        if string:
            out.append("STR")
        elif number:
            out.append("NUM")
        elif ident:
            out.append(ident if ident in keywords else "ID")
        else:
            out.append(punct)
    return out
```

**Create: `lib/optimize/adapters/base.py`**

```python
"""Adapter contract: everything language-specific lives behind this."""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable

ENTRY_NAMES = frozenset({"main"})


@dataclass
class RawSymbol:
    name: str
    kind: str  # function | method | type
    node: object
    markers: list[str] = field(default_factory=list)
    qualname: str = ""


@dataclass(frozen=True)
class Adapter:
    name: str
    grammars: dict  # file suffix -> tree-sitter grammar name
    keywords: frozenset
    line_comment: str
    branch_nodes: frozenset
    registry_dirs: tuple
    extract: Callable  # (root_node, source_bytes) -> list[RawSymbol]
    native_dead: str | None
    test_hint: str


def node_text(node, src: bytes) -> str:
    return src[node.start_byte:node.end_byte].decode("utf-8", "ignore")
```

- [ ] **Step 5: Write the three adapters**

**Create: `lib/optimize/adapters/python.py`**

```python
from __future__ import annotations

import keyword

from .base import Adapter, RawSymbol, node_text

KEYWORDS = frozenset(keyword.kwlist) | {"match", "case", "self", "cls"}
BRANCH_NODES = frozenset({
    "if_statement", "elif_clause", "for_statement", "while_statement", "except_clause",
    "conditional_expression", "boolean_operator", "case_clause",
})


def extract(root, src: bytes) -> list[RawSymbol]:
    out: list[RawSymbol] = []

    def visit(node, scope, decorated):
        t = node.type
        if t == "decorated_definition":
            inner = node.child_by_field_name("definition")
            if inner is not None:
                visit(inner, scope, True)
            return
        if t in ("function_definition", "class_definition"):
            name_node = node.child_by_field_name("name")
            if name_node is not None:
                name = node_text(name_node, src)
                kind = "type" if t == "class_definition" else ("method" if scope and scope[-1][1] == "type" else "function")
                markers = []
                if decorated:
                    markers.append("decorated")
                if name.startswith("test_") or (name.startswith("__") and name.endswith("__")):
                    markers.append("framework-name")
                out.append(RawSymbol(name, kind, node, markers, ".".join([s[0] for s in scope] + [name])))
                for child in node.children:
                    visit(child, scope + [(name, kind)], False)
                return
        for child in node.children:
            visit(child, scope, False)

    visit(root, [], False)
    return out


ADAPTER = Adapter(
    name="python",
    grammars={".py": "python"},
    keywords=KEYWORDS,
    line_comment="#",
    branch_nodes=BRANCH_NODES,
    registry_dirs=("commands", "cogs", "events", "handlers", "routes", "migrations"),
    extract=extract,
    native_dead="vulture",
    test_hint="pytest",
)
```

**Create: `lib/optimize/adapters/swift.py`**

```python
from __future__ import annotations

import re

from .base import Adapter, RawSymbol, node_text

KEYWORDS = frozenset(
    "associatedtype class deinit enum extension fileprivate func import init inout internal let open operator "
    "private precedencegroup protocol public rethrows static struct subscript typealias var break case catch "
    "continue default defer do else fallthrough for guard if in repeat return throw switch where while Any as "
    "await false is nil super self Self throws true try async actor some any final override lazy mutating "
    "nonmutating weak unowned required convenience indirect optional dynamic".split()
)
BRANCH_NODES = frozenset({
    "if_statement", "guard_statement", "for_statement", "while_statement", "repeat_while_statement",
    "switch_entry", "catch_block", "ternary_expression",
})
DYNAMIC = re.compile(
    r"@(objc|objcMembers|IBAction|IBOutlet|IBInspectable|IBDesignable|main|NSApplicationMain|UIApplicationMain|"
    r"_cdecl|_silgen_name)\b"
)
TYPE_KEYWORDS = {"class", "struct", "enum", "actor", "extension"}
FUNC_NODES = ("function_declaration", "init_declaration")


def extract(root, src: bytes) -> list[RawSymbol]:
    out: list[RawSymbol] = []

    def modifiers(node) -> str:
        for c in node.children:
            if c.type == "modifiers":
                return node_text(c, src)
        return ""

    def markers_for(mods: str) -> list[str]:
        found = []
        if DYNAMIC.search(mods):
            found.append("dynamic-dispatch")
        if re.search(r"\boverride\b", mods):
            found.append("override")
        if re.search(r"\b(public|open)\b", mods):
            found.append("public-api")
        return found

    def visit(node, scope, conforming):
        t = node.type
        if t in ("class_declaration", "protocol_declaration"):
            keyword = "protocol" if t == "protocol_declaration" else next(
                (c.type for c in node.children if c.type in TYPE_KEYWORDS), "class"
            )
            name_node = node.child_by_field_name("name")
            name = node_text(name_node, src).strip() if name_node is not None else ""
            inherits = any(c.type == "inheritance_specifier" for c in node.children)
            if keyword != "extension" and name:
                out.append(RawSymbol(name, "type", node, markers_for(modifiers(node)), ".".join([s[0] for s in scope] + [name])))
            for child in node.children:
                visit(child, scope + [(name, "type")], inherits)
            return
        if t in FUNC_NODES:
            name_node = node.child_by_field_name("name")
            name = "init" if t == "init_declaration" else (node_text(name_node, src) if name_node is not None else "")
            if name:
                markers = markers_for(modifiers(node))
                in_type = bool(scope) and scope[-1][1] == "type"
                if in_type and conforming:
                    markers.append("possible-witness")
                out.append(RawSymbol(name, "method" if in_type else "function", node, markers, ".".join([s[0] for s in scope] + [name])))
            for child in node.children:
                visit(child, scope + [(name, "fn")], False)
            return
        for child in node.children:
            visit(child, scope, conforming)

    visit(root, [], False)
    return out


ADAPTER = Adapter(
    name="swift",
    grammars={".swift": "swift"},
    keywords=KEYWORDS,
    line_comment="//",
    branch_nodes=BRANCH_NODES,
    registry_dirs=(),
    extract=extract,
    native_dead="periphery",
    test_hint="swift test",
)
```

**Create: `lib/optimize/adapters/js_ts.py`**

```python
from __future__ import annotations

from .base import Adapter, RawSymbol, node_text

KEYWORDS = frozenset(
    "break case catch class const continue debugger default delete do else export extends finally for function if "
    "import in instanceof let new return super switch this throw try typeof var void while with yield async await "
    "of static get set true false null undefined interface type enum implements public private protected readonly "
    "abstract as from".split()
)
BRANCH_NODES = frozenset({
    "if_statement", "for_statement", "for_in_statement", "while_statement", "do_statement", "switch_case",
    "catch_clause", "ternary_expression",
})
FUNC_VALUES = {"arrow_function", "function_expression", "function", "generator_function"}
DECLS = {"function_declaration", "generator_function_declaration"}
CONTAINERS = {"lexical_declaration", "variable_declaration"}
REGISTRY_DIRS = ("commands", "events", "interactions", "handlers", "routes", "pages", "listeners")


def extract(root, src: bytes) -> list[RawSymbol]:
    out: list[RawSymbol] = []

    def name_of(node):
        n = node.child_by_field_name("name")
        return node_text(n, src) if n is not None else None

    def add(node, name, kind, scope, exported, extra=()):
        markers = (["exported"] if exported else []) + list(extra)
        out.append(RawSymbol(name, kind, node, markers, ".".join([s[0] for s in scope] + [name])))

    def visit(node, scope, exported):
        t = node.type
        if t == "export_statement":
            for c in node.children:
                visit(c, scope, True)
            return
        if t in DECLS:
            name = name_of(node)
            if name:
                add(node, name, "function", scope, exported)
                scope = scope + [(name, "fn")]
            for c in node.children:
                visit(c, scope, False)
            return
        if t == "class_declaration":
            name = name_of(node)
            if name:
                add(node, name, "type", scope, exported)
                scope = scope + [(name, "type")]
            for c in node.children:
                visit(c, scope, False)
            return
        if t == "method_definition":
            name = name_of(node)
            if name:
                add(node, name, "method", scope, False, ["framework-name"] if name == "constructor" else [])
                scope = scope + [(name, "fn")]
            for c in node.children:
                visit(c, scope, False)
            return
        if t == "variable_declarator":
            value = node.child_by_field_name("value")
            name_node = node.child_by_field_name("name")
            if value is not None and value.type in FUNC_VALUES and name_node is not None and name_node.type == "identifier":
                name = node_text(name_node, src)
                add(node, name, "function", scope, exported)
                scope = scope + [(name, "fn")]
            for c in node.children:
                visit(c, scope, False)
            return
        for c in node.children:
            visit(c, scope, exported if t in CONTAINERS else False)

    visit(root, [], False)
    return out


JS = Adapter(
    name="javascript",
    grammars={".js": "javascript", ".jsx": "javascript", ".mjs": "javascript", ".cjs": "javascript"},
    keywords=KEYWORDS,
    line_comment="//",
    branch_nodes=BRANCH_NODES,
    registry_dirs=REGISTRY_DIRS,
    extract=extract,
    native_dead="knip",
    test_hint="npm test",
)
TS = Adapter(
    name="typescript",
    grammars={".ts": "typescript", ".tsx": "tsx"},
    keywords=KEYWORDS,
    line_comment="//",
    branch_nodes=BRANCH_NODES,
    registry_dirs=REGISTRY_DIRS,
    extract=extract,
    native_dead="knip",
    test_hint="npm test",
)
```

- [ ] **Step 6: Write the registry and inventory**

**Create: `lib/optimize/adapters/__init__.py`**

```python
from .js_ts import JS, TS
from .python import ADAPTER as PYTHON
from .swift import ADAPTER as SWIFT

ADAPTERS = {"swift": SWIFT, "javascript": JS, "typescript": TS, "python": PYTHON}
```

**Create: `lib/optimize/inventory.py`**

```python
"""Symbol inventory: tree-sitter symbols, token metrics and textual reference counts."""
from __future__ import annotations

import hashlib
import re
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath

from .adapters import ADAPTERS
from .adapters.base import ENTRY_NAMES, node_text
from .model import Symbol
from .tokens import normalize

WORD = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_TEST_DIRS = {"test", "tests", "__tests__", "spec", "specs"}
_TEST_FILE = re.compile(r"(Tests?|Spec)\.swift$|\.(test|spec)\.[jt]sx?$|^test_.*\.py$|_test\.py$")
_parsers: dict = {}


def is_test_path(path: str) -> bool:
    """Test code is discovered by the test framework (XCTest, pytest, jest), not referenced by name."""
    parts = PurePosixPath(path).parts
    return bool({p.lower() for p in parts[:-1]} & _TEST_DIRS) or bool(_TEST_FILE.search(parts[-1]))


def get_parser(grammar: str):
    if grammar not in _parsers:
        try:
            from tree_sitter_language_pack import get_parser as gp

            _parsers[grammar] = gp(grammar)
        except Exception:
            _parsers[grammar] = None
    return _parsers[grammar]


@dataclass
class Inventory:
    symbols: list[Symbol] = field(default_factory=list)
    words: Counter = field(default_factory=Counter)
    defs: Counter = field(default_factory=Counter)
    texts: dict = field(default_factory=dict)
    totals: dict = field(default_factory=dict)
    parse_errors: list = field(default_factory=list)

    def refs(self, sym: Symbol) -> int:
        """Whole-word occurrences of the name anywhere (code, strings, comments) beyond its own definitions.
        Deliberately generous: it can only under-report dead code, never over-report it."""
        return max(0, self.words[sym.name] - self.defs[sym.name])

    def snippet(self, path: str, start: int, end: int) -> str:
        return "\n".join(self.texts[path].splitlines()[start - 1:end])

    def symbol_at(self, path: str, line: int) -> Symbol | None:
        best = None
        for s in self.symbols:
            if s.path == path and s.start <= line <= s.end:
                if best is None or (s.end - s.start) < (best.end - best.start):
                    best = s
        return best


def _complexity(node, branch_nodes) -> int:
    count, stack = 1, [node]
    while stack:
        n = stack.pop()
        if n.type in branch_nodes:
            count += 1
        stack.extend(n.children)
    return count


def build_inventory(files) -> Inventory:
    inv = Inventory()
    for f in files:
        adapter = ADAPTERS[f.language]
        data = f.abs.read_bytes()
        text = data.decode("utf-8", "ignore")
        inv.texts[f.path] = text
        inv.words.update(WORD.findall(text))
        totals = inv.totals.setdefault(f.language, {"files": 0, "lines": 0, "tokens": 0})
        totals["files"] += 1
        totals["lines"] += text.count("\n") + 1
        totals["tokens"] += len(normalize(text, adapter.keywords, adapter.line_comment))
        parser = get_parser(adapter.grammars[Path(f.path).suffix.lower()])
        if parser is None:
            inv.parse_errors.append(f.path)
            continue
        try:
            tree = parser.parse(data)
            raws = adapter.extract(tree.root_node, data)
        except Exception:
            inv.parse_errors.append(f.path)
            continue
        in_registry = bool(set(PurePosixPath(f.path).parent.parts) & set(adapter.registry_dirs))
        for raw in raws:
            seq = normalize(node_text(raw.node, data), adapter.keywords, adapter.line_comment)
            markers = list(raw.markers)
            if in_registry:
                markers.append("registry-loaded")
            if is_test_path(f.path):
                markers.append("test-code")
            if raw.name in ENTRY_NAMES:
                markers.append("entry-point")
            if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", raw.name):
                markers.append("special-name")
            inv.symbols.append(
                Symbol(
                    name=raw.name,
                    kind=raw.kind,
                    language=f.language,
                    path=f.path,
                    start=raw.node.start_point[0] + 1,
                    end=raw.node.end_point[0] + 1,
                    tokens=len(seq),
                    complexity=_complexity(raw.node, adapter.branch_nodes),
                    norm_hash=hashlib.sha1(" ".join(seq).encode()).hexdigest(),
                    markers=sorted(set(markers)),
                    qualname=raw.qualname,
                    seq=seq,
                )
            )
    for s in inv.symbols:
        inv.defs[s.name] += 1
    return inv
```

- [ ] **Step 7: Run test to verify it passes**

Run: `./run-tests.sh tests/test_inventory.py`
Expected: 7 passed. If a grammar node type or field name differs from what the adapters assume (the likely failures are Swift `declaration_kind`/`name` handling and JS `export_statement` children), print the tree with `get_parser(...).parse(src).root_node` for the failing fixture and adjust only the adapter's `extract`.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -q -m "Add language adapters, tokenizer and symbol inventory with fixtures" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Built-in dead-code, single-use and hotspot detectors

**Files:**
- Create: `lib/optimize/providers/__init__.py`, `lib/optimize/providers/deadcode.py`
- Test: `tests/test_deadcode.py`

**Interfaces:**
- Consumes: `Inventory`, `Config`, `Candidate`, `Location`, `stable_id`.
- Produces: `builtin_dead(inv, config) -> tuple[list[Candidate], list[Candidate], list[dict]]` returning `(dead, single_use, review_by_hand)`; `hotspots(inv, config) -> list[Candidate]`. Review entries are `{"path", "start", "symbol", "reasons", "refs"}`.

- [ ] **Step 1: Write the failing test**

**Create: `tests/test_deadcode.py`**

```python
from optimize.discover import discover
from optimize.inventory import build_inventory
from optimize.model import Config
from optimize.providers.deadcode import builtin_dead, hotspots

CFG = Config(hotspot_complexity=8)


def run(fixture_root, name):
    inv = build_inventory(discover(fixture_root(name)).files)
    return inv, *builtin_dead(inv, CFG)


def labels(cands):
    return {loc.symbol for c in cands for loc in c.locations}


def review_labels(review):
    return {r["symbol"] for r in review}


def test_python_dead_single_use_and_review(fixture_root):
    inv, dead, single, review = run(fixture_root, "python")
    assert "unused_helper" in labels(dead)
    assert all(c.provider == "builtin-zero-refs" and c.confidence == "medium" for c in dead)
    assert "only_called_once" in labels(single)
    assert {"health_endpoint", "main"} <= review_labels(review)
    assert "health_endpoint" not in labels(dead)


def test_swift_dead_and_review(fixture_root):
    inv, dead, single, review = run(fixture_root, "swift")
    assert "unusedHelper" in labels(dead)
    assert "wrapper" in labels(single)
    assert "Controller.menuAction" in review_labels(review)
    assert "Controller.menuAction" not in labels(dead)


def test_javascript_dead_and_review(fixture_root):
    inv, dead, single, review = run(fixture_root, "js")
    assert {"unusedHelper", "unusedTyped"} <= labels(dead)
    assert "onlyOnce" in labels(single)
    assert {"neverImported", "pongCommand"} <= review_labels(review)
    assert "neverImported" not in labels(dead)


def test_react_orphan_is_dead(fixture_root):
    inv, dead, single, review = run(fixture_root, "react")
    assert labels(dead) == {"Orphan"}


def test_hotspots(fixture_root):
    inv = build_inventory(discover(fixture_root("python")).files)
    hot = hotspots(inv, CFG)
    assert labels(hot) == {"branchy"}
    assert hot[0].kind == "hotspot" and hot[0].evidence["complexity"] >= 8


def test_shared_method_names_are_not_dead_when_one_is_called(tmp_path):
    (tmp_path / "m.py").write_text(
        "class A:\n    def run(self):\n        return 1\n\n\nclass B:\n    def run(self):\n        return 2\n\n\nA().run()\n"
    )
    inv = build_inventory(discover(tmp_path).files)
    dead, single, review = builtin_dead(inv, CFG)
    assert "A.run" not in labels(dead) and "B.run" not in labels(dead)


def test_test_code_is_never_dead_or_reviewed(tmp_path):
    (tmp_path / "Tests").mkdir()
    (tmp_path / "Tests" / "ThingTests.swift").write_text("final class ThingTests {\n    func testIt() {}\n}\n")
    inv = build_inventory(discover(tmp_path).files)
    assert builtin_dead(inv, CFG) == ([], [], [])


def test_candidate_ids_are_stable(fixture_root):
    a = run(fixture_root, "python")[1]
    b = run(fixture_root, "python")[1]
    assert [c.id for c in a] == [c.id for c in b]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./run-tests.sh tests/test_deadcode.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'optimize.providers'`

- [ ] **Step 3: Write the implementation**

**Create: `lib/optimize/providers/__init__.py`**

```python
```

**Create: `lib/optimize/providers/deadcode.py`**

```python
"""Built-in provider: zero-reference symbols, single-use wrappers and complexity hotspots."""
from __future__ import annotations

from ..inventory import Inventory
from ..model import Candidate, Config, stable_id

FUNCTION_KINDS = ("function", "method")


def builtin_dead(inv: Inventory, config: Config):
    """Return (dead, single_use, review_by_hand).

    A symbol is dead only when its name never appears anywhere else in the scanned source (generous word
    counting). Anything with a marker (framework decorator, @objc, exported, registry-loaded, entry point...)
    is reported for manual review instead and never offered for removal."""
    dead, single, review = [], [], []
    for s in inv.symbols:
        if s.kind not in ("function", "method", "type") or "test-code" in s.markers:
            continue  # test frameworks find tests by reflection, so they never look referenced
        refs = inv.refs(s)
        if refs == 0:
            if s.markers:
                review.append({"path": s.path, "start": s.start, "symbol": s.label, "reasons": sorted(set(s.markers)), "refs": 0})
                continue
            dead.append(Candidate(
                id=stable_id("dead", s.path, s.label, s.norm_hash),
                kind="dead",
                language=s.language,
                locations=[s.location],
                evidence={"name": s.name, "refs": 0, "tokens": s.tokens, "removable_tokens": s.tokens, "complexity": s.complexity},
                provider="builtin-zero-refs",
                confidence="medium",
                confirm=["zero-references"],
            ))
        elif refs == 1 and s.kind in FUNCTION_KINDS and not s.markers and s.tokens <= config.single_use_max_tokens:
            single.append(Candidate(
                id=stable_id("single-use", s.path, s.label, s.norm_hash),
                kind="single-use",
                language=s.language,
                locations=[s.location],
                evidence={"name": s.name, "refs": 1, "tokens": s.tokens, "complexity": s.complexity},
                provider="builtin-zero-refs",
                confidence="low",
                confirm=["single-caller", "behavior-equivalent"],
            ))
    return dead, single, review


def hotspots(inv: Inventory, config: Config):
    out = []
    for s in inv.symbols:
        if s.kind in FUNCTION_KINDS and s.complexity >= config.hotspot_complexity:
            out.append(Candidate(
                id=stable_id("hotspot", s.path, s.label, s.norm_hash),
                kind="hotspot",
                language=s.language,
                locations=[s.location],
                evidence={"name": s.name, "complexity": s.complexity, "tokens": s.tokens},
                provider="builtin-complexity",
                confidence="high",
                confirm=["behavior-equivalent"],
            ))
    return out
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./run-tests.sh tests/test_deadcode.py`
Expected: 7 passed

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -q -m "Add built-in dead-code, single-use and hotspot detectors" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Built-in clone detector

**Files:**
- Create: `lib/optimize/providers/grouping.py`, `lib/optimize/providers/clones.py`
- Test: `tests/test_clones.py`

**Interfaces:**
- Consumes: `Inventory`, `Config`, `Candidate`, `stable_id`.
- Produces: `group_edges(n, edges) -> list[tuple[list[int], float]]` in `grouping`; `builtin_clones(inv, config) -> list[Candidate]` in `clones`.

- [ ] **Step 1: Write the failing test**

**Create: `tests/test_clones.py`**

```python
from optimize.discover import discover
from optimize.inventory import build_inventory
from optimize.model import Config
from optimize.providers.clones import builtin_clones
from optimize.providers.grouping import group_edges

CFG = Config(min_clone_tokens=30)

BASE = """def {name}(items, limit):
    result = []
    total = 0
    for item in items:
        if item is None:
            continue
        if item.size > limit:
            result.append(item.name)
        elif item.size == limit:
            result.insert(0, item.name)
        total += item.size{extra}
    while total > limit:
        total -= 1
        result.pop()
    if not result:
        return None
    return sorted(result), total
"""


def test_group_edges_merges_chains_and_tracks_min_similarity():
    groups = group_edges(5, [(0, 1, 1.0), (1, 2, 0.85), (3, 4, 0.9)])
    assert groups == [([0, 1, 2], 0.85), ([3, 4], 0.9)] or groups == [([3, 4], 0.9), ([0, 1, 2], 0.85)]


def clones(fixture_root, name):
    inv = build_inventory(discover(fixture_root(name)).files)
    return builtin_clones(inv, CFG)


def test_exact_renamed_clones_in_every_language(fixture_root):
    expected = {
        "python": {"format_duration", "render_elapsed"},
        "swift": {"formatDuration", "renderElapsed"},
        "js": {"formatDuration", "renderElapsed"},
        "react": {"UserCard", "AdminCard"},
    }
    for name, symbols in expected.items():
        found = [c for c in clones(fixture_root, name) if {loc.symbol for loc in c.locations} == symbols]
        assert len(found) == 1, name
        c = found[0]
        assert c.kind == "clone" and c.confidence == "high" and c.evidence["similarity"] == 1.0
        assert c.evidence["removable_tokens"] > 0 and c.provider == "builtin-token-clones"


def test_near_clone_is_found_with_lower_confidence(tmp_path):
    (tmp_path / "a.py").write_text(BASE.format(name="first", extra=""))
    (tmp_path / "b.py").write_text(BASE.format(name="second", extra="\n        item.seen = True"))
    inv = build_inventory(discover(tmp_path).files)
    found = builtin_clones(inv, CFG)
    assert len(found) == 1
    assert 0.8 <= found[0].evidence["similarity"] < 1.0
    assert found[0].confidence in ("medium", "low")


def test_unrelated_functions_and_small_functions_are_not_clones(tmp_path):
    (tmp_path / "a.py").write_text(BASE.format(name="first", extra=""))
    (tmp_path / "b.py").write_text("def other(x):\n    return [i * 2 for i in range(x) if i % 3 == 0 and i > 4]\n")
    (tmp_path / "c.py").write_text("def tiny(x):\n    return x\n\n\ndef tiny2(y):\n    return y\n")
    inv = build_inventory(discover(tmp_path).files)
    assert builtin_clones(inv, CFG) == []


def test_clones_among_test_files_are_flagged_as_test_code(tmp_path):
    only_tests, only_prod = tmp_path / "a", tmp_path / "b"
    (only_tests / "tests").mkdir(parents=True)
    only_prod.mkdir()
    (only_tests / "tests" / "test_a.py").write_text(BASE.format(name="test_first", extra=""))
    (only_tests / "tests" / "test_b.py").write_text(BASE.format(name="test_second", extra=""))
    (only_prod / "x.py").write_text(BASE.format(name="one", extra=""))
    (only_prod / "y.py").write_text(BASE.format(name="two", extra=""))
    flagged = builtin_clones(build_inventory(discover(only_tests).files), CFG)
    plain = builtin_clones(build_inventory(discover(only_prod).files), CFG)
    assert [c.evidence["test_code"] for c in flagged] == [True]
    assert [c.evidence["test_code"] for c in plain] == [False]


def test_clone_ids_are_stable_across_runs(fixture_root):
    a = [c.id for c in clones(fixture_root, "python")]
    b = [c.id for c in clones(fixture_root, "python")]
    assert a == b and a
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./run-tests.sh tests/test_clones.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'optimize.providers.clones'`

- [ ] **Step 3: Write the implementation**

**Create: `lib/optimize/providers/grouping.py`**

```python
from __future__ import annotations

from collections import defaultdict


def group_edges(n: int, edges):
    """Union (a, b, similarity) edges into groups. Returns [(sorted member indexes, minimum similarity)]."""
    parent = list(range(n))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for a, b, _ in edges:
        parent[find(a)] = find(b)
    members: dict[int, set] = defaultdict(set)
    sims: dict[int, float] = {}
    for a, b, s in edges:
        r = find(a)
        members[r].update((a, b))
        sims[r] = min(sims.get(r, 1.0), s)
    return [(sorted(m), sims[r]) for r, m in sorted(members.items())]
```

**Create: `lib/optimize/providers/clones.py`**

```python
"""Built-in clone detector: exact (renamed) clones by normalized hash, near clones by shingle similarity."""
from __future__ import annotations

import zlib
from collections import defaultdict

from ..inventory import Inventory
from ..model import Candidate, Config, Symbol, stable_id
from .grouping import group_edges

SHINGLE = 5
SKETCH = 32
MAX_BUCKET = 50


def _shingles(seq: list[str]) -> set[int]:
    if len(seq) < SHINGLE:
        return {zlib.crc32(" ".join(seq).encode())}
    return {zlib.crc32(" ".join(seq[i:i + SHINGLE]).encode()) for i in range(len(seq) - SHINGLE + 1)}


def _overlap(a: Symbol, b: Symbol) -> bool:
    return a.path == b.path and a.start <= b.end and b.start <= a.end


def builtin_clones(inv: Inventory, config: Config) -> list[Candidate]:
    by_language: dict[str, list[Symbol]] = defaultdict(list)
    for s in inv.symbols:
        if s.kind in ("function", "method") and s.tokens >= config.min_clone_tokens:
            by_language[s.language].append(s)
    out: list[Candidate] = []
    for language in sorted(by_language):
        syms = sorted(by_language[language], key=lambda s: (s.path, s.start))
        edges: list[tuple[int, int, float]] = []
        by_hash: dict[str, list[int]] = defaultdict(list)
        for i, s in enumerate(syms):
            by_hash[s.norm_hash].append(i)
        for idxs in by_hash.values():
            for a, b in zip(idxs, idxs[1:]):
                if not _overlap(syms[a], syms[b]):
                    edges.append((a, b, 1.0))
        sets = [_shingles(s.seq) for s in syms]
        buckets: dict[int, list[int]] = defaultdict(list)
        for i, st in enumerate(sets):
            for h in sorted(st)[:SKETCH]:
                buckets[h].append(i)
        seen: set[tuple[int, int]] = set()
        for members in buckets.values():
            if len(members) > MAX_BUCKET:
                continue
            for x in range(len(members)):
                for y in range(x + 1, len(members)):
                    a, b = members[x], members[y]
                    if (a, b) in seen:
                        continue
                    seen.add((a, b))
                    if syms[a].norm_hash == syms[b].norm_hash or _overlap(syms[a], syms[b]):
                        continue
                    jaccard = len(sets[a] & sets[b]) / len(sets[a] | sets[b])
                    if jaccard >= config.near_threshold:
                        edges.append((a, b, jaccard))
        for members, sim in group_edges(len(syms), edges):
            group = [syms[i] for i in members]
            tokens = [s.tokens for s in group]
            out.append(Candidate(
                id=stable_id("clone", *sorted(f"{s.path}:{s.label}:{s.norm_hash}" for s in group)),
                kind="clone",
                language=language,
                locations=[s.location for s in group],
                evidence={
                    "similarity": sim,
                    "tokens": max(tokens),
                    "removable_tokens": sum(tokens) - max(tokens),
                    "members": len(group),
                    "test_code": all("test-code" in s.markers for s in group),
                },
                provider="builtin-token-clones",
                confidence="high" if sim == 1.0 else ("medium" if sim >= 0.9 else "low"),
                confirm=["behavior-equivalent"],
            ))
    return out
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./run-tests.sh tests/test_clones.py`
Expected: 4 passed

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -q -m "Add built-in clone detector" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Native tool providers (vulture, knip, Periphery, jscpd)

**Files:**
- Create: `lib/optimize/providers/native.py`
- Test: `tests/test_native.py`

**Interfaces:**
- Consumes: `Candidate`, `Config`, `Location`, `stable_id`, `LANGUAGE_BY_SUFFIX`.
- Produces: `NATIVE_DEAD: dict[str, str]` (language -> tool); `parse_vulture(text, root)`, `parse_knip(text, root)`, `parse_periphery(text, root)`, `parse_jscpd(report: dict, root)` each returning `list[Candidate]`; `run_tool(argv, cwd, timeout=900)`; `run_dead(tool, root) -> tuple[list[Candidate] | None, str | None]`; `run_jscpd(root, config) -> tuple[list[Candidate] | None, str | None]`. Native dead candidates carry `evidence["name"]`.

None of these tools is installed on the development machine, so the parsers are tested against sample output and the exact formats are re-checked against real tools in Task 12.

- [ ] **Step 1: Write the failing test**

**Create: `tests/test_native.py`**

```python
import json
import subprocess
from pathlib import Path

from optimize.model import Config
from optimize.providers import native

ROOT = Path("/tmp/proj")


def test_parse_vulture_keeps_functions_classes_methods_only():
    text = (
        "app.py:10: unused function 'old' (60% confidence)\n"
        "app.py:20: unused import 'os' (90% confidence)\n"
        "app.py:30: unused variable 'x' (60% confidence)\n"
        "app.py:40: unreachable code after 'return' (100% confidence)\n"
        "app.py:50: unused class 'Gone' (60% confidence)\n"
    )
    cands = native.parse_vulture(text, ROOT)
    assert [c.evidence["name"] for c in cands] == ["old", "Gone"]
    assert cands[0].locations[0].path == "app.py" and cands[0].locations[0].start == 10
    assert cands[0].provider == "vulture" and cands[0].confidence == "medium" and cands[0].kind == "dead"


def test_parse_periphery_relativizes_paths_and_keeps_declarations():
    items = [
        {"kind": "function.free", "name": "oldFunc()", "location": "/tmp/proj/Sources/A.swift:12:6", "hints": ["unused"]},
        {"kind": "var.instance", "name": "x", "location": "/tmp/proj/Sources/A.swift:20:9", "hints": ["unused"]},
        {"kind": "struct", "name": "Old", "location": "/tmp/proj/Sources/B.swift:3:8", "hints": ["unused"]},
        {"kind": "function.free", "name": "assignOnly()", "location": "/tmp/proj/Sources/C.swift:1:1", "hints": ["assignOnlyProperty"]},
    ]
    cands = native.parse_periphery(json.dumps(items), ROOT)
    assert [(c.evidence["name"], c.locations[0].path, c.locations[0].start) for c in cands] == [
        ("oldFunc", "Sources/A.swift", 12),
        ("Old", "Sources/B.swift", 3),
    ]
    assert all(c.provider == "periphery" and c.confidence == "high" and c.language == "swift" for c in cands)


def test_parse_knip_files_exports_and_types():
    data = {
        "files": ["src/unused.js"],
        "issues": [{
            "file": "src/a.js",
            "exports": [{"name": "old", "line": 4, "col": 17, "pos": 80}],
            "types": [{"name": "T", "line": 9, "col": 1, "pos": 2}],
        }],
    }
    cands = native.parse_knip(json.dumps(data), ROOT)
    assert [(c.locations[0].path, c.locations[0].start, c.evidence.get("name")) for c in cands] == [
        ("src/unused.js", 1, None),
        ("src/a.js", 4, "old"),
        ("src/a.js", 9, "T"),
    ]
    assert all(c.provider == "knip" and c.language == "javascript" for c in cands)


def test_parse_jscpd_pairs_become_clone_candidates():
    report = {"duplicates": [{
        "format": "javascript", "lines": 12, "tokens": 90,
        "firstFile": {"name": "src/a.js", "start": 3, "end": 15},
        "secondFile": {"name": "src/b.js", "start": 7, "end": 19},
    }]}
    cands = native.parse_jscpd(report, ROOT)
    assert len(cands) == 1
    c = cands[0]
    assert c.kind == "clone" and c.provider == "jscpd" and c.language == "javascript"
    assert [(loc.path, loc.start, loc.end) for loc in c.locations] == [("src/a.js", 3, 15), ("src/b.js", 7, 19)]
    assert c.evidence["tokens"] == 90 and c.evidence["removable_tokens"] == 90


def fake_run(stdout="", returncode=0, stderr=""):
    def runner(argv, cwd, timeout=900):
        return subprocess.CompletedProcess(argv, returncode, stdout, stderr), None

    return runner


def test_run_dead_parses_tool_output(monkeypatch):
    monkeypatch.setattr(native, "run_tool", fake_run("app.py:10: unused function 'old' (60% confidence)\n", 3))
    cands, err = native.run_dead("vulture", ROOT)
    assert err is None and len(cands) == 1


def test_run_dead_reports_failure_so_the_pipeline_can_fall_back(monkeypatch):
    monkeypatch.setattr(native, "run_tool", lambda argv, cwd, timeout=900: (None, "vulture failed: boom"))
    cands, err = native.run_dead("vulture", ROOT)
    assert cands is None and "boom" in err
    monkeypatch.setattr(native, "run_tool", fake_run("not json at all", 2, "periphery: no project found"))
    cands, err = native.run_dead("periphery", ROOT)
    assert cands is None and "periphery" in err


def test_native_dead_mapping():
    assert native.NATIVE_DEAD == {"swift": "periphery", "python": "vulture", "javascript": "knip", "typescript": "knip"}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./run-tests.sh tests/test_native.py`
Expected: FAIL with `ImportError: cannot import name 'native'`

- [ ] **Step 3: Write the implementation**

**Create: `lib/optimize/providers/native.py`**

```python
"""Adapters for native analysis tools. Each parser is pure; run_* functions shell out and never raise."""
from __future__ import annotations

import json
import re
import subprocess
import tempfile
from pathlib import Path

from ..discover import LANGUAGE_BY_SUFFIX
from ..model import Candidate, Config, Location, stable_id

NATIVE_DEAD = {"swift": "periphery", "python": "vulture", "javascript": "knip", "typescript": "knip"}
_VULTURE = re.compile(r"^(?P<path>.+?):(?P<line>\d+): unused (?P<what>[a-z ]+?) '(?P<name>[^']+)' \((?P<pct>\d+)% confidence\)$")
_VULTURE_KINDS = {"function", "class", "method", "property"}
_PERIPHERY_KINDS = ("function", "class", "struct", "enum", "protocol")


def _rel(path: str, root: Path) -> str:
    p = Path(path)
    if p.is_absolute():
        try:
            return p.relative_to(root).as_posix()
        except ValueError:
            return p.as_posix()
    return p.as_posix()


def _language(path: str) -> str:
    return LANGUAGE_BY_SUFFIX.get(Path(path).suffix.lower(), "unknown")


def _dead(path, line, name, provider, confidence, extra=None) -> Candidate:
    evidence = {"refs": 0, "unused_file": False}
    if name:
        evidence["name"] = name
    evidence.update(extra or {})
    return Candidate(
        id=stable_id("dead", path, str(name), str(line)),
        kind="dead",
        language=_language(path),
        locations=[Location(path, line, line, name)],
        evidence=evidence,
        provider=provider,
        confidence=confidence,
        confirm=["zero-references"],
    )


def parse_vulture(text: str, root: Path) -> list[Candidate]:
    out = []
    for line in text.splitlines():
        m = _VULTURE.match(line.strip())
        if not m or m["what"] not in _VULTURE_KINDS:
            continue
        confidence = "high" if int(m["pct"]) >= 90 else "medium"
        out.append(_dead(_rel(m["path"], root), int(m["line"]), m["name"], "vulture", confidence))
    return out


def parse_periphery(text: str, root: Path) -> list[Candidate]:
    out = []
    for item in json.loads(text):
        if "unused" not in item.get("hints", []) or not str(item.get("kind", "")).startswith(_PERIPHERY_KINDS):
            continue
        path, line, _ = (item["location"].rsplit(":", 2) + ["0", "0"])[:3] if item["location"].count(":") >= 2 else (item["location"], "1", "0")
        name = item["name"].split("(")[0]
        out.append(_dead(_rel(path, root), int(line), name, "periphery", "high"))
    return out


def parse_knip(text: str, root: Path) -> list[Candidate]:
    data = json.loads(text)
    out = []
    for path in data.get("files", []):
        out.append(_dead(_rel(path, root), 1, None, "knip", "high", {"unused_file": True}))
    for issue in data.get("issues", []):
        path = _rel(issue["file"], root)
        for key in ("exports", "types", "classMembers", "enumMembers"):
            for entry in issue.get(key, []):
                out.append(_dead(path, int(entry.get("line", 1)), entry["name"], "knip", "high"))
    return out


def parse_jscpd(report: dict, root: Path) -> list[Candidate]:
    out = []
    for dup in report.get("duplicates", []):
        locs = [
            Location(_rel(dup[key]["name"], root), int(dup[key]["start"]), int(dup[key]["end"]))
            for key in ("firstFile", "secondFile")
        ]
        tokens = int(dup.get("tokens", 0))
        out.append(Candidate(
            id=stable_id("clone", *[f"{loc.path}:{loc.start}:{loc.end}" for loc in locs]),
            kind="clone",
            language=_language(locs[0].path),
            locations=locs,
            evidence={"tokens": tokens, "removable_tokens": tokens, "lines": int(dup.get("lines", 0)), "members": 2},
            provider="jscpd",
            confidence="medium",
            confirm=["behavior-equivalent"],
        ))
    return out


def run_tool(argv, cwd, timeout=900):
    try:
        return subprocess.run(argv, cwd=cwd, capture_output=True, text=True, timeout=timeout), None
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, f"{argv[0]} failed: {e}"


_DEAD_COMMANDS = {
    "vulture": (["vulture", ".", "--min-confidence", "60"], parse_vulture),
    "knip": (["knip", "--reporter", "json"], parse_knip),
    "periphery": (["periphery", "scan", "--format", "json", "--quiet"], parse_periphery),
}


def run_dead(tool: str, root: Path):
    argv, parser = _DEAD_COMMANDS[tool]
    result, err = run_tool(argv, root)
    if result is None:
        return None, err
    try:
        return parser(result.stdout, root), None
    except (ValueError, KeyError, TypeError):
        detail = (result.stderr or result.stdout).strip().splitlines()
        return None, f"{tool} produced no usable output (exit {result.returncode}): {detail[0] if detail else 'empty'}"


def run_jscpd(root: Path, config: Config):
    with tempfile.TemporaryDirectory() as out:
        argv = [
            "jscpd", ".", "--reporters", "json", "--output", out, "--silent",
            "--min-tokens", str(config.min_clone_tokens),
            "--ignore", "**/node_modules/**,**/dist/**,**/build/**,**/.venv/**,**/.optimize/**",
            "--format", "swift,javascript,typescript,jsx,tsx,python",
        ]
        result, err = run_tool(argv, root)
        if result is None:
            return None, err
        report = Path(out) / "jscpd-report.json"
        try:
            return parse_jscpd(json.loads(report.read_text()), root), None
        except (OSError, ValueError, KeyError):
            return None, f"jscpd produced no report (exit {result.returncode})"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./run-tests.sh tests/test_native.py`
Expected: 7 passed

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -q -m "Add native tool providers (vulture, knip, Periphery, jscpd)" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Semantic similarity providers (Qdrant and local embeddings)

**Files:**
- Create: `lib/optimize/providers/semantic.py`
- Test: `tests/test_semantic.py`

**Interfaces:**
- Consumes: `Inventory`, `Config`, `Candidate`, `Location`, `stable_id`, `group_edges`, `LANGUAGE_BY_SUFFIX`.
- Produces: `MODEL`, `VEC`, `URL`; `collection_name(root) -> str`; `find_pairs(vectors, threshold) -> list[tuple[int, int, float]]`; `fastembed_embed(texts) -> list[list[float]]`; `local_semantic(inv, config, embed=None) -> list[Candidate]`; `qdrant_semantic(root, config, allowed_paths, client=None) -> tuple[list[Candidate] | None, str | None]`.

- [ ] **Step 1: Write the failing test**

**Create: `tests/test_semantic.py`**

```python
from pathlib import Path

import pytest

np = pytest.importorskip("numpy")

from optimize.discover import discover  # noqa: E402
from optimize.inventory import build_inventory  # noqa: E402
from optimize.model import Config  # noqa: E402
from optimize.providers import semantic  # noqa: E402

CFG = Config(min_clone_tokens=20, semantic_threshold=0.9)


def test_find_pairs_uses_cosine_similarity():
    pairs = semantic.find_pairs([[1, 0], [0.99, 0.1], [0, 1]], 0.9)
    assert [(i, j) for i, j, _ in pairs] == [(0, 1)]
    assert semantic.find_pairs([], 0.9) == []


def test_collection_name_matches_index_skill_convention(tmp_path):
    name = semantic.collection_name(tmp_path)
    assert name.startswith(f"proj-{tmp_path.name}-") and name.endswith("-jc2")


def test_local_semantic_groups_similar_symbols_but_skips_exact_clones(fixture_root):
    inv = build_inventory(discover(fixture_root("python")).files)

    def embed(texts):
        # format_duration and unused_helper "mean" the same thing; everything else is unrelated.
        return [[1.0, 0.0] if ("format_duration" in t or "unused_helper" in t) else [0.0, 1.0] for t in texts]

    found = semantic.local_semantic(inv, CFG, embed=embed)
    labels = [{loc.symbol for loc in c.locations} for c in found]
    assert {"format_duration", "unused_helper"} in labels
    assert all(c.kind == "semantic-dup" and c.provider == "local-fastembed" for c in found)
    # render_elapsed has the same normalized hash as format_duration, so it is a clone, not a semantic dup.
    assert not any({"format_duration", "render_elapsed"} <= s for s in labels)


class Point:
    def __init__(self, vec, path, start, end):
        self.vector = {semantic.VEC: vec}
        self.payload = {"path": path, "start_line": start, "end_line": end}


class FakeClient:
    def __init__(self, points, exists=True):
        self.points, self.exists = points, exists

    def collection_exists(self, name):
        return self.exists

    def scroll(self, name, limit, offset=None, with_payload=None, with_vectors=None):
        return self.points, None


def test_qdrant_semantic_pairs_chunks_across_files(tmp_path):
    pts = [
        Point([1.0, 0.0], "a.py", 1, 50),
        Point([0.99, 0.05], "b.py", 10, 60),
        Point([1.0, 0.0], "a.py", 40, 90),  # overlaps the first chunk in the same file: ignored
        Point([0.0, 1.0], "c.py", 1, 50),
        Point([1.0, 0.0], "notes.md", 1, 50),  # not an allowed source file
    ]
    found, err = semantic.qdrant_semantic(tmp_path, CFG, {"a.py", "b.py", "c.py"}, client=FakeClient(pts))
    assert err is None
    paths = [sorted(loc.path for loc in c.locations) for c in found]
    assert ["a.py", "b.py"] in paths
    assert all(c.provider == "qdrant" and c.confidence == "low" for c in found)


def test_qdrant_semantic_reports_missing_collection(tmp_path):
    found, err = semantic.qdrant_semantic(tmp_path, CFG, set(), client=FakeClient([], exists=False))
    assert found is None and "no collection" in err
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./run-tests.sh tests/test_semantic.py`
Expected: FAIL with `ImportError: cannot import name 'semantic'`

- [ ] **Step 3: Write the implementation**

**Create: `lib/optimize/providers/semantic.py`**

```python
"""Semantic-duplicate providers: an existing Qdrant index when there is one, local embeddings otherwise."""
from __future__ import annotations

import hashlib
import re
from pathlib import Path

from ..discover import LANGUAGE_BY_SUFFIX
from ..inventory import Inventory
from ..model import Candidate, Config, Location, stable_id
from .grouping import group_edges

URL = "http://localhost:6333"
MODEL = "jinaai/jina-embeddings-v2-base-code"  # same model as the index skill
VEC = "fast-jina-embeddings-v2-base-code"
MODEL_TAG = "jc2"
MAX_POINTS = 8000


def collection_name(root) -> str:
    """Matches the index skill's naming so an existing collection is found."""
    root = Path(root).resolve()
    safe = re.sub(r"[^A-Za-z0-9_-]", "-", root.name)
    return f"proj-{safe}-{hashlib.sha1(str(root).encode()).hexdigest()[:6]}-{MODEL_TAG}"


def find_pairs(vectors, threshold: float):
    import numpy as np

    m = np.asarray(vectors, dtype="float32")
    if m.size == 0:
        return []
    norms = np.linalg.norm(m, axis=1, keepdims=True)
    norms[norms == 0] = 1
    m = m / norms
    pairs = []
    for i in range(len(m) - 1):
        sims = m[i + 1:] @ m[i]
        for off in np.nonzero(sims >= threshold)[0]:
            pairs.append((i, i + 1 + int(off), float(sims[off])))
    return pairs


def fastembed_embed(texts):
    from fastembed import TextEmbedding

    return [v.tolist() for v in TextEmbedding(MODEL).embed(texts, batch_size=16)]


def _confidence(sim: float) -> str:
    return "medium" if sim >= 0.95 else "low"


def local_semantic(inv: Inventory, config: Config, embed=None) -> list[Candidate]:
    syms = [s for s in inv.symbols if s.kind in ("function", "method") and s.tokens >= config.min_clone_tokens]
    syms.sort(key=lambda s: (-s.tokens, s.path, s.start))
    syms = sorted(syms[: config.semantic_max_symbols], key=lambda s: (s.path, s.start))
    if len(syms) < 2:
        return []
    vectors = (embed or fastembed_embed)([inv.snippet(s.path, s.start, s.end) for s in syms])
    edges = [
        (i, j, sim)
        for i, j, sim in find_pairs(vectors, config.semantic_threshold)
        if syms[i].norm_hash != syms[j].norm_hash and not syms[i].location.overlaps(syms[j].location)
    ]
    out = []
    for members, sim in group_edges(len(syms), edges):
        group = [syms[i] for i in members]
        tokens = [s.tokens for s in group]
        out.append(Candidate(
            id=stable_id("semantic-dup", *sorted(f"{s.path}:{s.label}:{s.norm_hash}" for s in group)),
            kind="semantic-dup",
            language=group[0].language,
            locations=[s.location for s in group],
            evidence={"similarity": sim, "tokens": max(tokens), "removable_tokens": sum(tokens) - max(tokens), "members": len(group)},
            provider="local-fastembed",
            confidence=_confidence(sim),
            confirm=["behavior-equivalent"],
        ))
    return out


def qdrant_semantic(root, config: Config, allowed_paths, client=None):
    """Pair up chunks of the project's existing index. Returns (candidates | None, reason)."""
    root = Path(root).resolve()
    name = collection_name(root)
    try:
        if client is None:
            from qdrant_client import QdrantClient

            client = QdrantClient(url=URL, timeout=30)
        if not client.collection_exists(name):
            return None, f"qdrant: no collection {name} (run the index skill first)"
        points, offset = [], None
        while True:
            batch, offset = client.scroll(name, limit=500, offset=offset, with_payload=["path", "start_line", "end_line"], with_vectors=[VEC])
            points.extend(batch)
            if offset is None or len(points) >= MAX_POINTS:
                break
    except Exception as e:  # unreachable server, missing client library, API change
        return None, f"qdrant unavailable: {e}"
    chunks, vectors = [], []
    for pt in points:
        path = pt.payload["path"]
        if path not in allowed_paths or Path(path).suffix.lower() not in LANGUAGE_BY_SUFFIX:
            continue
        vec = pt.vector[VEC] if isinstance(pt.vector, dict) else pt.vector
        chunks.append(Location(path, pt.payload["start_line"], pt.payload["end_line"]))
        vectors.append(vec)
    edges = [
        (i, j, sim)
        for i, j, sim in find_pairs(vectors, config.semantic_threshold)
        if not chunks[i].overlaps(chunks[j])
    ]
    out = []
    for members, sim in group_edges(len(chunks), edges):
        group: list[Location] = []
        for i in members:  # transitive grouping can pull in overlapping chunks of one file; keep the first of each
            if not any(chunks[i].overlaps(kept) for kept in group):
                group.append(chunks[i])
        if len(group) < 2:
            continue
        out.append(Candidate(
            id=stable_id("semantic-dup", *sorted(f"{c.path}:{c.start}:{c.end}" for c in group)),
            kind="semantic-dup",
            language=LANGUAGE_BY_SUFFIX[Path(group[0].path).suffix.lower()],
            locations=group,
            evidence={"similarity": sim, "lines": max(c.end - c.start + 1 for c in group), "members": len(group)},
            provider="qdrant",
            confidence="low",
            confirm=["behavior-equivalent"],
        ))
    return out, None
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./run-tests.sh tests/test_semantic.py`
Expected: 5 passed

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -q -m "Add Qdrant and local-embedding semantic providers" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Capability detection (`doctor`) and churn

**Files:**
- Create: `lib/optimize/detect.py`, `lib/optimize/churn.py`
- Test: `tests/test_detect.py`

**Interfaces:**
- Consumes: `NATIVE_DEAD` from Task 6; `collection_name`, `URL` from Task 7.
- Produces:
  - `doctor(root, languages, use_native=True, use_semantic=True, qdrant_client=None, embed=None) -> dict` with keys `git`, `capabilities`. `capabilities` has `symbols`, `deadcode` (per language), `clones`, `semantic`, each `{"chosen": str, "options": [{"name","available","detail","agent_side"}]}` (`deadcode` maps language -> that shape).
  - `churn(root, days=90) -> dict[str, int]` (empty when git is unavailable).

- [ ] **Step 1: Write the failing test**

**Create: `tests/test_detect.py`**

```python
import subprocess

from optimize import detect
from optimize.churn import churn


def stub(monkeypatch, tools=(), modules=()):
    monkeypatch.setattr(detect.shutil, "which", lambda name: f"/bin/{name}" if name in tools else None)
    monkeypatch.setattr(detect, "_has_module", lambda name: name in modules)


def test_everything_missing_falls_back_to_builtins(tmp_path, monkeypatch):
    stub(monkeypatch)
    info = detect.doctor(tmp_path, ["swift", "python"])
    caps = info["capabilities"]
    assert caps["symbols"]["chosen"] == "tree-sitter+word-count"
    assert caps["deadcode"]["swift"]["chosen"] == "builtin-zero-refs"
    assert caps["deadcode"]["python"]["chosen"] == "builtin-zero-refs"
    assert caps["clones"]["chosen"] == "builtin-token-clones"
    assert caps["semantic"]["chosen"] == "none"
    serena = next(o for o in caps["symbols"]["options"] if o["name"] == "serena")
    assert serena["agent_side"] is True and serena["available"] is False


def test_native_tools_are_chosen_when_present_and_usable(tmp_path, monkeypatch):
    stub(monkeypatch, tools={"vulture", "periphery", "knip", "jscpd"})
    (tmp_path / "package.json").write_text("{}")
    info = detect.doctor(tmp_path, ["swift", "python", "javascript"])
    caps = info["capabilities"]
    assert caps["deadcode"]["python"]["chosen"] == "vulture"
    assert caps["deadcode"]["javascript"]["chosen"] == "knip"
    assert caps["clones"]["chosen"] == "jscpd"
    # Periphery is installed but the project has no Swift project to scan.
    assert caps["deadcode"]["swift"]["chosen"] == "builtin-zero-refs"
    periphery = next(o for o in caps["deadcode"]["swift"]["options"] if o["name"] == "periphery")
    assert periphery["available"] is False and "project" in periphery["detail"]
    (tmp_path / "Package.swift").write_text("// swift-tools-version:5.9\n")
    assert detect.doctor(tmp_path, ["swift"])["capabilities"]["deadcode"]["swift"]["chosen"] == "periphery"


def test_flags_disable_native_and_semantic(tmp_path, monkeypatch):
    stub(monkeypatch, tools={"vulture", "jscpd"}, modules={"fastembed", "numpy"})
    info = detect.doctor(tmp_path, ["python"], use_native=False, use_semantic=False)
    assert info["capabilities"]["deadcode"]["python"]["chosen"] == "builtin-zero-refs"
    assert info["capabilities"]["clones"]["chosen"] == "builtin-token-clones"
    assert info["capabilities"]["semantic"]["chosen"] == "none"


def test_semantic_prefers_existing_qdrant_collection_then_local(tmp_path, monkeypatch):
    stub(monkeypatch, modules={"fastembed", "numpy", "qdrant_client"})

    class Client:
        def __init__(self, exists):
            self.exists = exists

        def collection_exists(self, name):
            return self.exists

    assert detect.doctor(tmp_path, ["python"], qdrant_client=Client(True))["capabilities"]["semantic"]["chosen"] == "qdrant"
    assert detect.doctor(tmp_path, ["python"], qdrant_client=Client(False))["capabilities"]["semantic"]["chosen"] == "local-fastembed"


def test_git_state_reports_broken_checkout(tmp_path, monkeypatch):
    stub(monkeypatch)
    (tmp_path / ".git").write_text("gitdir: /nonexistent\n")
    assert "walk" in detect.doctor(tmp_path, [])["git"]


def test_churn_counts_commits_per_file_and_tolerates_no_git(tmp_path):
    assert churn(tmp_path) == {}
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    for message in ("one", "two"):
        (tmp_path / "a.py").write_text(message)
        subprocess.run(["git", "add", "a.py"], cwd=tmp_path, check=True)
        subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", message], cwd=tmp_path, check=True)
    assert churn(tmp_path) == {"a.py": 2}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./run-tests.sh tests/test_detect.py`
Expected: FAIL with `ImportError: cannot import name 'detect'`

- [ ] **Step 3: Write the implementation**

**Create: `lib/optimize/churn.py`**

```python
from __future__ import annotations

import subprocess
from collections import Counter
from pathlib import Path


def churn(root, days: int = 90) -> dict[str, int]:
    """Commits touching each file in the last `days` days; empty when git is unavailable."""
    r = subprocess.run(
        ["git", "-C", str(Path(root)), "log", f"--since={days}.days", "--name-only", "--pretty=format:"],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        return {}
    return dict(Counter(line for line in r.stdout.splitlines() if line.strip()))
```

**Create: `lib/optimize/detect.py`**

```python
"""Capability probing: which provider will run for each capability, and why."""
from __future__ import annotations

import importlib.util
import shutil
import subprocess
from dataclasses import asdict, dataclass
from pathlib import Path

from .providers.native import NATIVE_DEAD
from .providers.semantic import URL, collection_name


@dataclass
class Option:
    name: str
    available: bool
    detail: str = ""
    agent_side: bool = False


def _has_module(name: str) -> bool:
    try:
        return importlib.util.find_spec(name) is not None
    except (ImportError, ValueError):
        return False


def _choose(options: list[Option]) -> str:
    for o in options:
        if o.available and not o.agent_side:
            return o.name
    return "none"


def _pack(options: list[Option]) -> dict:
    return {"chosen": _choose(options), "options": [asdict(o) for o in options]}


def _tool_option(tool: str, root: Path, enabled: bool) -> Option:
    if not enabled:
        return Option(tool, False, "native tools disabled by flag")
    path = shutil.which(tool)
    if not path:
        return Option(tool, False, "not installed")
    if tool == "periphery" and not (
        (root / ".periphery.yml").exists() or (root / "Package.swift").exists() or any(root.glob("*.xcodeproj"))
    ):
        return Option(tool, False, "installed, but the root has no .periphery.yml, Package.swift or Xcode project")
    if tool == "knip" and not (root / "package.json").exists():
        return Option(tool, False, "installed, but the root has no package.json")
    return Option(tool, True, path)


def _qdrant_option(root: Path, client) -> Option:
    if client is None:
        if not _has_module("qdrant_client"):
            return Option("qdrant", False, "qdrant-client not installed")
        try:
            from qdrant_client import QdrantClient

            client = QdrantClient(url=URL, timeout=2)
        except Exception as e:
            return Option("qdrant", False, f"unreachable: {e}")
    name = collection_name(root)
    try:
        exists = client.collection_exists(name)
    except Exception as e:
        return Option("qdrant", False, f"unreachable: {e}")
    return Option("qdrant", bool(exists), f"collection {name}" if exists else f"no collection {name} (run the index skill)")


def _git_state(root: Path) -> str:
    r = subprocess.run(["git", "-C", str(root), "rev-parse", "--is-inside-work-tree"], capture_output=True, text=True)
    return "ok" if r.returncode == 0 else "unavailable (filesystem walk is used; churn is empty)"


def doctor(root, languages, use_native=True, use_semantic=True, qdrant_client=None, embed=None) -> dict:
    root = Path(root).resolve()
    caps = {
        "symbols": _pack([
            Option("serena", False, "agent-side MCP server: SKILL.md uses it to confirm and apply candidates", agent_side=True),
            Option("tree-sitter+word-count", True, "built in"),
        ]),
        "deadcode": {},
    }
    for lang in sorted(languages):
        options = []
        if lang in NATIVE_DEAD:
            options.append(_tool_option(NATIVE_DEAD[lang], root, use_native))
        options.append(Option("builtin-zero-refs", True, "tree-sitter symbols + whole-word counts"))
        caps["deadcode"][lang] = _pack(options)
    caps["clones"] = _pack([
        _tool_option("jscpd", root, use_native),
        Option("builtin-token-clones", True, "normalized-token hash + shingle similarity"),
    ])
    if use_semantic:
        local_ok = embed is not None or (_has_module("fastembed") and _has_module("numpy"))
        semantic = [
            _qdrant_option(root, qdrant_client),
            Option("local-fastembed", local_ok, "fastembed + numpy" if local_ok else "fastembed/numpy not installed"),
        ]
    else:
        semantic = [Option("qdrant", False, "semantic tier disabled by flag"), Option("local-fastembed", False, "semantic tier disabled by flag")]
    caps["semantic"] = _pack(semantic)
    return {"git": _git_state(root), "capabilities": caps}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./run-tests.sh tests/test_detect.py`
Expected: 6 passed

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -q -m "Add capability detection and churn" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Ranking, report and metrics

**Files:**
- Create: `lib/optimize/rank.py`, `lib/optimize/report.py`
- Test: `tests/test_report.py`

**Interfaces:**
- Consumes: `Candidate`, `Config`, `Inventory`, `Discovery`, `canonical_json`.
- Produces:
  - `enrich(cands, inv, churn_map) -> list[Candidate]`, `dedupe(cands) -> list[Candidate]`, `rank(cands, churn_map, inv) -> list[Candidate]` (enriched, deduped, scored, sorted) in `optimize.rank`; `WEIGHTS` dict.
  - `compute_metrics(inv, cands) -> dict` with keys `total_tokens`, `clone_tokens`, `dead_symbols`, `hotspots`, `mean_complexity`, `by_language`.
  - `build_report(disc, inv, info, cands, review, notes, config) -> dict`; `render_markdown(report, top_n) -> str` in `optimize.report`.

- [ ] **Step 1: Write the failing test**

**Create: `tests/test_report.py`**

```python
from optimize.discover import discover
from optimize.inventory import build_inventory
from optimize.model import Candidate, Config, Location
from optimize.providers.clones import builtin_clones
from optimize.providers.deadcode import builtin_dead, hotspots
from optimize.rank import WEIGHTS, dedupe, enrich, rank, score
from optimize.report import build_report, compute_metrics, render_markdown

CFG = Config(min_clone_tokens=30, hotspot_complexity=8)


def candidates(fixture_root, name="python"):
    disc = discover(fixture_root(name))
    inv = build_inventory(disc.files)
    dead, single, review = builtin_dead(inv, CFG)
    cands = builtin_clones(inv, CFG) + dead + single + hotspots(inv, CFG)
    return disc, inv, cands, review


def make(kind, path, start, end, **evidence):
    return Candidate(id=f"{kind}-{path}{start}", kind=kind, language="python", locations=[Location(path, start, end)],
                     evidence=evidence, provider="p", confidence="medium", confirm=[])


def test_weights_are_one_config_block():
    assert set(WEIGHTS) == {"size", "confidence", "hotspot"} and abs(sum(WEIGHTS.values()) - 1.0) < 1e-9


def test_duplicated_test_code_scores_below_the_same_duplication_in_production_code():
    prod = make("clone", "src/a.py", 1, 20, removable_tokens=400)
    tests = make("clone", "tests/a.py", 1, 20, removable_tokens=400, test_code=True)
    assert score(prod) > score(tests)


def test_dedupe_drops_semantic_and_single_use_overlapping_clones_or_dead():
    clone = make("clone", "a.py", 1, 20, removable_tokens=100)
    sem = make("semantic-dup", "a.py", 5, 10)
    one = make("single-use", "b.py", 1, 5)
    far = make("semantic-dup", "c.py", 1, 5)
    kept = dedupe([clone, sem, one, far])
    assert [c.kind for c in kept] == ["clone", "single-use", "semantic-dup"]
    assert {c.locations[0].path for c in kept} == {"a.py", "b.py", "c.py"}


def test_enrich_expands_native_single_line_locations_to_symbols(fixture_root):
    disc, inv, cands, review = candidates(fixture_root)
    line = next(s.start for s in inv.symbols if s.name == "unused_helper")
    native = Candidate(id="dead-n", kind="dead", language="python", locations=[Location("durations.py", line, line, "unused_helper")],
                       evidence={"name": "unused_helper"}, provider="vulture", confidence="medium", confirm=["zero-references"])
    out = enrich([native], inv, {"durations.py": 4})[0]
    assert out.locations[0].end > line and out.evidence["tokens"] > 0 and out.evidence["churn_90d"] == 4


def test_rank_orders_by_score_then_id_and_is_deterministic(fixture_root):
    disc, inv, cands, review = candidates(fixture_root)
    a = rank(list(cands), {}, inv)
    b = rank(list(reversed(cands)), {}, inv)
    assert [c.id for c in a] == [c.id for c in b]
    assert [c.score for c in a] == sorted((c.score for c in a), reverse=True)
    assert a[0].kind in ("clone", "dead")


def test_metrics_and_report_shape(fixture_root):
    disc, inv, cands, review = candidates(fixture_root)
    ranked = rank(cands, {}, inv)
    m = compute_metrics(inv, ranked)
    assert m["dead_symbols"] >= 1 and m["clone_tokens"] > 0 and m["hotspots"] == 1
    assert m["by_language"]["python"]["files"] == 2 and m["total_tokens"] > 0
    info = {"git": "ok", "capabilities": {"symbols": {"chosen": "tree-sitter+word-count", "options": []}, "deadcode": {"python": {"chosen": "builtin-zero-refs", "options": []}}, "clones": {"chosen": "builtin-token-clones", "options": []}, "semantic": {"chosen": "none", "options": []}}}
    report = build_report(disc, inv, info, ranked, review, ["a note"], CFG)
    assert report["header"]["providers"]["clones"] == "builtin-token-clones"
    assert report["header"]["providers"]["deadcode"] == {"python": "builtin-zero-refs"}
    assert report["header"]["files"]["python"] == 2 and report["header"]["notes"] == ["a note"]
    assert report["summary"]["by_kind"]["clone"] == 1 and report["summary"]["review_by_hand"] == len(review)
    assert len(report["candidates"]) == len(ranked)
    md = render_markdown(report, 25)
    for needle in ("# Optimize report", "builtin-token-clones", "## Review by hand", "## Baseline metrics", ranked[0].id):
        assert needle in md
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./run-tests.sh tests/test_report.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'optimize.rank'`

- [ ] **Step 3: Write the implementation**

**Create: `lib/optimize/rank.py`**

```python
"""Enrich candidates with inventory/churn evidence, drop redundant ones, score and order them."""
from __future__ import annotations

from collections import defaultdict

from .inventory import Inventory
from .model import Candidate, Location

# One config block: the weights of the three score components (sum to 1).
WEIGHTS = {"size": 0.5, "confidence": 0.3, "hotspot": 0.2}
CONFIDENCE_SCORE = {"low": 0.3, "medium": 0.65, "high": 1.0}


def enrich(cands: list[Candidate], inv: Inventory, churn_map: dict) -> list[Candidate]:
    for c in cands:
        locations, max_complexity = [], 0
        for loc in c.locations:
            sym = inv.symbol_at(loc.path, loc.start)
            if sym is not None and loc.start == loc.end and sym.name == c.evidence.get("name"):
                loc = Location(loc.path, sym.start, sym.end, sym.label)
                c.evidence.setdefault("tokens", sym.tokens)
                c.evidence.setdefault("removable_tokens", sym.tokens)
            if sym is not None:
                max_complexity = max(max_complexity, sym.complexity)
            locations.append(loc)
        c.locations = locations
        c.evidence["max_complexity"] = max_complexity
        c.evidence["churn_90d"] = sum(churn_map.get(p, 0) for p in {loc.path for loc in locations})
    return cands


def dedupe(cands: list[Candidate]) -> list[Candidate]:
    """A semantic-dup or single-use finding that overlaps a clone or dead finding adds nothing."""
    primary: dict[str, list[Location]] = defaultdict(list)
    for c in cands:
        if c.kind in ("clone", "dead"):
            for loc in c.locations:
                primary[loc.path].append(loc)
    kept = []
    for c in cands:
        if c.kind in ("semantic-dup", "single-use") and any(
            loc.overlaps(other) for loc in c.locations for other in primary.get(loc.path, [])
        ):
            continue
        kept.append(c)
    return kept


def score(c: Candidate) -> float:
    size = min(c.evidence.get("removable_tokens", 0) / 500, 1.0) * (0.5 if c.evidence.get("test_code") else 1.0)
    hot = min(c.evidence.get("churn_90d", 0) / 20, 1.0) * 0.5 + min(c.evidence.get("max_complexity", 0) / 30, 1.0) * 0.5
    return round(WEIGHTS["size"] * size + WEIGHTS["confidence"] * CONFIDENCE_SCORE[c.confidence] + WEIGHTS["hotspot"] * hot, 4)


def rank(cands: list[Candidate], churn_map: dict, inv: Inventory) -> list[Candidate]:
    out = dedupe(enrich(cands, inv, churn_map))
    for c in out:
        c.score = score(c)
    return sorted(out, key=lambda c: (-c.score, c.id))
```

**Create: `lib/optimize/report.py`**

```python
"""Report assembly (deterministic: no timestamps, sorted keys) and markdown rendering."""
from __future__ import annotations

from collections import Counter

from .discover import Discovery
from .inventory import Inventory
from .model import Candidate, Config


def compute_metrics(inv: Inventory, cands: list[Candidate]) -> dict:
    funcs = [s for s in inv.symbols if s.kind in ("function", "method")]
    mean = round(sum(s.complexity for s in funcs) / len(funcs), 2) if funcs else 0.0
    return {
        "total_tokens": sum(t["tokens"] for t in inv.totals.values()),
        "clone_tokens": sum(c.evidence.get("removable_tokens", 0) for c in cands if c.kind == "clone"),
        "dead_symbols": sum(1 for c in cands if c.kind == "dead"),
        "hotspots": sum(1 for c in cands if c.kind == "hotspot"),
        "mean_complexity": mean,
        "by_language": {lang: dict(t) for lang, t in sorted(inv.totals.items())},
    }


def build_report(disc: Discovery, inv: Inventory, info: dict, cands: list[Candidate], review: list[dict], notes: list[str], config: Config) -> dict:
    caps = info["capabilities"]
    providers = {
        "symbols": caps["symbols"]["chosen"],
        "deadcode": {lang: v["chosen"] for lang, v in sorted(caps["deadcode"].items())},
        "clones": caps["clones"]["chosen"],
        "semantic": caps["semantic"]["chosen"],
    }
    by_kind = Counter(c.kind for c in cands)
    by_language = Counter(c.language for c in cands)
    return {
        "version": 1,
        "header": {
            "discovery": disc.via,
            "git": info["git"],
            "providers": providers,
            "files": {lang: t["files"] for lang, t in sorted(inv.totals.items())},
            "excluded_files": disc.excluded,
            "skipped_secret": sorted(disc.skipped_secret),
            "parse_errors": sorted(inv.parse_errors),
            "notes": list(notes),
        },
        "summary": {
            "by_kind": dict(sorted(by_kind.items())),
            "by_language": dict(sorted(by_language.items())),
            "review_by_hand": len(review),
            "estimated_removable_tokens": sum(c.evidence.get("removable_tokens", 0) for c in cands if c.kind in ("clone", "dead")),
        },
        "metrics": compute_metrics(inv, cands),
        "candidates": [c.to_dict() for c in cands],
        "review_by_hand": sorted(review, key=lambda r: (r["path"], r["start"])),
    }


def render_markdown(report: dict, top_n: int) -> str:
    h, s, m = report["header"], report["summary"], report["metrics"]
    lines = ["# Optimize report", "", "## Providers", ""]
    p = h["providers"]
    lines += [f"- symbols: {p['symbols']}", f"- clones: {p['clones']}", f"- semantic: {p['semantic']}"]
    lines += [f"- dead code ({lang}): {name}" for lang, name in p["deadcode"].items()]
    lines += ["", f"Files discovered via {h['discovery']} (git: {h['git']}). "
              + ", ".join(f"{lang}: {n}" for lang, n in h["files"].items())
              + f". Excluded: {h['excluded_files']}."]
    for label, key in (("Skipped (look like credentials)", "skipped_secret"), ("Parse errors", "parse_errors"), ("Notes", "notes")):
        if h[key]:
            lines += ["", f"{label}:"] + [f"- {x}" for x in h[key]]
    lines += ["", "## Summary", "", "| kind | count |", "|---|---|"]
    lines += [f"| {k} | {v} |" for k, v in s["by_kind"].items()]
    lines += ["", f"Estimated removable tokens (clones + dead code, an estimate): {s['estimated_removable_tokens']}. "
              f"Review by hand: {s['review_by_hand']}.", "", f"## Candidates (top {top_n})", ""]
    for i, c in enumerate(report["candidates"][:top_n], 1):
        locs = "; ".join(f"{loc['path']}:{loc['start']}-{loc['end']}" + (f" ({loc['symbol']})" if loc["symbol"] else "") for loc in c["locations"])
        lines += [
            f"### {i}. {c['id']} - {c['kind']} ({c['confidence']}, score {c['score']})",
            f"- where: {locs}",
            f"- evidence: {', '.join(f'{k}={v}' for k, v in sorted(c['evidence'].items()))}",
            f"- provider: {c['provider']}; confirm: {', '.join(c['confirm']) or 'nothing'}",
            "",
        ]
    lines += ["## Review by hand", "", "Public API, entry points and dynamically reached symbols with no references. Not offered for removal.", ""]
    lines += [f"- {r['path']}:{r['start']} {r['symbol']} ({', '.join(r['reasons'])})" for r in report["review_by_hand"]] or ["- none"]
    lines += ["", "## Baseline metrics", "",
              f"- total tokens: {m['total_tokens']}", f"- clone tokens: {m['clone_tokens']}", f"- dead symbols: {m['dead_symbols']}",
              f"- hotspots: {m['hotspots']}", f"- mean complexity: {m['mean_complexity']}"]
    lines += [f"- {lang}: {t['files']} files, {t['lines']} lines, {t['tokens']} tokens" for lang, t in m["by_language"].items()]
    return "\n".join(lines) + "\n"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./run-tests.sh tests/test_report.py`
Expected: 5 passed

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -q -m "Add ranking, metrics and report rendering" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Pipeline, verify, cluster packet and CLI

**Files:**
- Create: `lib/optimize/pipeline.py`, `lib/optimize/verify.py`, `lib/optimize/cluster.py`, `lib/optimize/cli.py`, `scripts/optimize.py`
- Test: `tests/test_pipeline.py`, `tests/test_cli.py`

**Interfaces:**
- Consumes: everything from Tasks 1-9.
- Produces:
  - `ScanResult(report: dict, candidates: list[Candidate], inventory: Inventory, review: list[dict])`; `run_scan(root, config=Config(), paths=None, languages=None, use_native=True, use_semantic=True, embed=None, qdrant_client=None) -> ScanResult` in `optimize.pipeline`.
  - `compare(base: dict, now: dict) -> dict` (`improved`, `worse`) and `run_tests(cmd, cwd) -> tuple[bool, str]` in `optimize.verify`.
  - `build_packet(root, out_dir, cand_id, max_lines=80) -> str` in `optimize.cluster`.
  - `main(argv=None) -> int` in `optimize.cli` with subcommands `doctor`, `scan`, `cluster`, `baseline`, `verify`.

- [ ] **Step 1: Write the failing pipeline test (fixtures, fallback parity, review focus)**

**Create: `tests/test_pipeline.py`**

```python
import json
import subprocess

import pytest

from optimize import detect
from optimize.model import Config
from optimize.pipeline import run_scan
from optimize.providers import native

CFG = Config(min_clone_tokens=30, hotspot_complexity=8)


def scan(root, **kw):
    return run_scan(root, CFG, use_semantic=False, **kw)


def symbols(result, kind):
    return {loc.symbol for c in result.candidates if c.kind == kind for loc in c.locations}


EXPECTED = {
    "python": {"dead": {"unused_helper"}, "single-use": {"only_called_once"}, "hotspot": {"branchy"},
               "clone": {"format_duration", "render_elapsed"}, "review": {"health_endpoint"}},
    "swift": {"dead": {"unusedHelper"}, "single-use": {"wrapper"}, "hotspot": {"Controller.branchy"},
              "clone": {"formatDuration", "renderElapsed"}, "review": {"Controller.menuAction"}},
    "js": {"dead": {"unusedHelper", "unusedTyped"}, "single-use": {"onlyOnce"}, "hotspot": {"branchy"},
           "clone": {"formatDuration", "renderElapsed"}, "review": {"neverImported", "pongCommand"}},
    "react": {"dead": {"Orphan"}, "clone": {"UserCard", "AdminCard"}},
}


@pytest.mark.parametrize("name", sorted(EXPECTED))
def test_planted_cases_are_found_in_every_language(fixture_root, name):
    result = scan(fixture_root(name), use_native=False)
    want = EXPECTED[name]
    for kind in ("dead", "single-use", "hotspot"):
        if kind in want:
            assert want[kind] <= symbols(result, kind), (name, kind)
    clone_sets = [{loc.symbol for loc in c.locations} for c in result.candidates if c.kind == "clone"]
    assert want["clone"] in clone_sets
    if "review" in want:
        assert want["review"] <= {r["symbol"] for r in result.review}
        assert not (want["review"] & symbols(result, "dead"))
    assert result.report["header"]["providers"]["clones"] == "builtin-token-clones"


def test_native_present_vs_absent_changes_provider_and_confidence(fixture_root, monkeypatch):
    root = fixture_root("swift")
    (root / "Package.swift").write_text("// swift-tools-version:5.9\n")
    monkeypatch.setattr(detect.shutil, "which", lambda name: None)
    absent = scan(root, use_native=True)
    dead_absent = next(c for c in absent.candidates if c.kind == "dead")
    assert dead_absent.provider == "builtin-zero-refs" and dead_absent.confidence == "medium"
    assert absent.report["header"]["providers"]["deadcode"]["swift"] == "builtin-zero-refs"

    monkeypatch.setattr(detect.shutil, "which", lambda name: "/bin/periphery" if name == "periphery" else None)
    line = next(i for i, l in enumerate((root / "Sources/App/Durations.swift").read_text().splitlines(), 1) if l.startswith("func unusedHelper"))
    output = json.dumps([{"kind": "function.free", "name": "unusedHelper(_:)", "location": f"{root.resolve()}/Sources/App/Durations.swift:{line}:6", "hints": ["unused"]}])
    monkeypatch.setattr(native, "run_tool", lambda argv, cwd, timeout=900: (subprocess.CompletedProcess(argv, 0, output, ""), None))
    present = scan(root, use_native=True)
    dead = [c for c in present.candidates if c.kind == "dead"]
    assert [c.provider for c in dead] == ["periphery"] and dead[0].confidence == "high"
    assert dead[0].locations[0].end > line  # expanded to the whole function by enrich()
    assert present.report["header"]["providers"]["deadcode"]["swift"] == "periphery"


def test_native_failure_falls_back_and_says_so(fixture_root, monkeypatch):
    root = fixture_root("swift")
    (root / "Package.swift").write_text("// swift-tools-version:5.9\n")
    monkeypatch.setattr(detect.shutil, "which", lambda name: "/bin/periphery" if name == "periphery" else None)
    monkeypatch.setattr(native, "run_tool", lambda argv, cwd, timeout=900: (None, "periphery failed: boom"))
    result = scan(root, use_native=True)
    assert "unusedHelper" in symbols(result, "dead")
    assert "fallback" in result.report["header"]["providers"]["deadcode"]["swift"]
    assert any("boom" in n for n in result.report["header"]["notes"])


def test_empty_project_gives_empty_valid_report(tmp_path):
    result = scan(tmp_path)
    assert result.candidates == [] and result.report["metrics"]["total_tokens"] == 0
    assert result.report["header"]["files"] == {}


def test_broken_git_pointer_still_scans(fixture_root):
    root = fixture_root("python")
    (root / ".git").write_text("gitdir: /nonexistent\n")
    result = scan(root)
    assert result.report["header"]["discovery"] == "walk"
    assert "unused_helper" in symbols(result, "dead")


def test_local_semantic_tier_runs_with_an_injected_embedder(fixture_root):
    pytest.importorskip("numpy")
    root = fixture_root("python")
    # branchy and main "mean the same thing" to the fake embedder. Neither is a clone or dead code, so ranking keeps the finding.
    embed = lambda texts: [[1.0, 0.0] if ("def branchy" in t or "def main" in t) else [0.0, 1.0] for t in texts]
    cfg = Config(min_clone_tokens=20, hotspot_complexity=8, semantic_threshold=0.9)
    result = run_scan(root, cfg, embed=embed)
    assert result.report["header"]["providers"]["semantic"] == "local-fastembed"
    assert {"branchy", "main"} in [{loc.symbol for loc in c.locations} for c in result.candidates if c.kind == "semantic-dup"]
```

- [ ] **Step 2: Write the failing CLI/verify test**

**Create: `tests/test_cli.py`**

```python
import json
import os
import subprocess
import sys
from pathlib import Path

from optimize import cli
from optimize.verify import compare

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "optimize.py"
FLAGS = ["--no-native", "--no-semantic", "--min-clone-tokens", "30", "--hotspot-complexity", "8"]


def scan_args(root):
    return ["scan", "--root", str(root), *FLAGS]


def test_scan_writes_all_outputs(fixture_root, capsys):
    root = fixture_root("python")
    assert cli.main(scan_args(root)) == 0
    out = root / ".optimize"
    for name in ("report.json", "report.md", "candidates.json", "inventory.json"):
        assert (out / name).exists(), name
    report = json.loads((out / "report.json").read_text())
    assert {"clone", "dead", "single-use", "hotspot"} <= {c["kind"] for c in report["candidates"]}
    assert "Optimize report" in (out / "report.md").read_text()
    assert "report.md" in capsys.readouterr().out


def test_scan_is_deterministic_across_processes_and_hash_seeds(fixture_root):
    root = fixture_root("js")
    texts = []
    for seed in ("1", "2"):
        env = {**os.environ, "PYTHONHASHSEED": seed, "PYTHONPATH": str(SCRIPT.parent.parent / "lib")}
        subprocess.run([sys.executable, str(SCRIPT), *scan_args(root)], check=True, env=env, capture_output=True)
        texts.append((root / ".optimize" / "report.json").read_bytes())
    assert texts[0] == texts[1]


def test_add_gitignore_flag_appends_once(fixture_root):
    root = fixture_root("python")
    assert cli.main([*scan_args(root), "--add-gitignore"]) == 0
    assert cli.main([*scan_args(root), "--add-gitignore"]) == 0
    assert (root / ".gitignore").read_text().splitlines().count(".optimize/") == 1


def test_doctor_prints_json(fixture_root, capsys):
    root = fixture_root("python")
    assert cli.main(["doctor", "--root", str(root), "--no-native", "--no-semantic"]) == 0
    info = json.loads(capsys.readouterr().out)
    assert info["capabilities"]["clones"]["chosen"] == "builtin-token-clones"


def test_cluster_packet_for_a_dead_candidate(fixture_root, capsys):
    root = fixture_root("python")
    cli.main(scan_args(root))
    capsys.readouterr()
    cands = json.loads((root / ".optimize" / "candidates.json").read_text())
    dead = next(c for c in cands if c["kind"] == "dead")
    assert cli.main(["cluster", dead["id"], "--root", str(root)]) == 0
    packet = capsys.readouterr().out
    assert "def unused_helper" in packet and "zero-references" in packet
    assert cli.main(["cluster", "dead-nope", "--root", str(root)]) != 0


def test_compare_flags_improvement_and_regression():
    base = {"total_tokens": 100, "clone_tokens": 10, "dead_symbols": 2, "hotspots": 1, "mean_complexity": 3.0}
    better = {**base, "total_tokens": 80, "dead_symbols": 1}
    worse = {**base, "dead_symbols": 3}
    flat = dict(base)
    assert compare(base, better) == {"improved": ["total_tokens", "dead_symbols"], "worse": []}
    assert compare(base, worse)["worse"] == ["dead_symbols"]
    assert compare(base, flat) == {"improved": [], "worse": []}


def test_verify_passes_a_good_refactor_and_fails_bad_ones(fixture_root):
    root = fixture_root("python")
    assert cli.main(["baseline", "--root", str(root), *FLAGS]) == 0
    verify = ["verify", "--root", str(root), *FLAGS]
    assert cli.main([*verify, "--test-cmd", "true"]) == 1  # nothing changed: no improvement

    durations = root / "durations.py"
    original = durations.read_text()
    durations.write_text(original.split("\n\n\ndef unused_helper")[0] + "\n")  # good: delete the dead function
    assert cli.main([*verify, "--test-cmd", "true"]) == 0
    assert cli.main([*verify, "--test-cmd", "false"]) == 1  # improved, but the tests fail

    durations.write_text(original + "\n\ndef another_unused(x):\n    return x * 3 + 1\n")  # bad: more dead code
    assert cli.main([*verify, "--test-cmd", "true"]) == 1


def test_verify_without_baseline_is_an_error(fixture_root):
    assert cli.main(["verify", "--root", str(fixture_root("python")), *FLAGS]) == 2


def test_empty_project_scan_exits_zero(tmp_path):
    assert cli.main(scan_args(tmp_path)) == 0
    assert json.loads((tmp_path / ".optimize" / "report.json").read_text())["candidates"] == []
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `./run-tests.sh tests/test_pipeline.py tests/test_cli.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'optimize.pipeline'` (and `optimize.cli`)

- [ ] **Step 4: Write the pipeline**

**Create: `lib/optimize/pipeline.py`**

```python
"""The deterministic scan: discover -> inventory -> detect -> rank -> report."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .churn import churn
from .detect import doctor
from .discover import discover
from .inventory import Inventory, build_inventory
from .model import Candidate, Config
from .providers import native
from .providers.clones import builtin_clones
from .providers.deadcode import builtin_dead, hotspots
from .providers.semantic import local_semantic, qdrant_semantic
from .rank import rank
from .report import build_report

BUILTIN_DEAD = "builtin-zero-refs"


@dataclass
class ScanResult:
    report: dict
    candidates: list[Candidate]
    inventory: Inventory
    review: list[dict]


def run_scan(root, config: Config = Config(), paths=None, languages=None, use_native=True, use_semantic=True, embed=None, qdrant_client=None) -> ScanResult:
    root = Path(root).resolve()
    disc = discover(root, paths, languages)
    inv = build_inventory(disc.files)
    languages_present = sorted(inv.totals)
    info = doctor(root, languages_present, use_native=use_native, use_semantic=use_semantic, qdrant_client=qdrant_client, embed=embed)
    caps = info["capabilities"]
    notes: list[str] = []
    cands: list[Candidate] = []

    builtin_dead_cands, single_use, review = builtin_dead(inv, config)
    native_langs: dict[str, list[str]] = {}
    for lang in languages_present:
        chosen = caps["deadcode"][lang]["chosen"]
        if chosen == BUILTIN_DEAD:
            cands += [c for c in builtin_dead_cands if c.language == lang]
        else:
            native_langs.setdefault(chosen, []).append(lang)
    for tool, langs in sorted(native_langs.items()):
        found, err = native.run_dead(tool, root)
        if found is None:
            notes.append(err)
            for lang in langs:
                caps["deadcode"][lang]["chosen"] = f"{BUILTIN_DEAD} (fallback: {tool} failed)"
                cands += [c for c in builtin_dead_cands if c.language == lang]
        else:
            cands += [c for c in found if c.language in langs]

    clones = None
    if caps["clones"]["chosen"] == "jscpd":
        clones, err = native.run_jscpd(root, config)
        if clones is None:
            notes.append(err)
            caps["clones"]["chosen"] = "builtin-token-clones (fallback: jscpd failed)"
    cands += clones if clones is not None else builtin_clones(inv, config)
    cands += single_use + hotspots(inv, config)

    options = {o["name"]: o["available"] for o in caps["semantic"]["options"]}
    semantic, chosen = None, "none"
    if options.get("qdrant"):
        semantic, err = qdrant_semantic(root, config, {f.path for f in disc.files}, client=qdrant_client)
        chosen = "qdrant"
        if semantic is None:
            notes.append(err)
    if semantic is None and options.get("local-fastembed"):
        try:
            semantic, chosen = local_semantic(inv, config, embed=embed), "local-fastembed"
        except Exception as e:
            notes.append(f"local-fastembed failed: {e}")
    if semantic is None:
        chosen = "none"
    caps["semantic"]["chosen"] = chosen
    cands += semantic or []

    ranked = rank(cands, churn(root), inv)
    report = build_report(disc, inv, info, ranked, review, notes, config)
    return ScanResult(report, ranked, inv, review)
```

- [ ] **Step 5: Write verify, cluster and the CLI**

**Create: `lib/optimize/verify.py`**

```python
from __future__ import annotations

import subprocess

IMPROVEMENT_METRICS = ("total_tokens", "clone_tokens", "dead_symbols", "hotspots", "mean_complexity")
REGRESSION_METRICS = ("clone_tokens", "dead_symbols", "hotspots")


def compare(base: dict, now: dict) -> dict:
    """improved: any size/smell metric went down. worse: a smell metric went up."""
    return {
        "improved": [m for m in IMPROVEMENT_METRICS if now[m] < base[m]],
        "worse": [m for m in REGRESSION_METRICS if now[m] > base[m]],
    }


def run_tests(cmd: str, cwd) -> tuple[bool, str]:
    r = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True)
    tail = "\n".join((r.stdout + r.stderr).strip().splitlines()[-15:])
    return r.returncode == 0, tail
```

**Create: `lib/optimize/cluster.py`**

```python
"""Small, self-contained packet for one candidate: snippets, callers, nearby tests, other locations."""
from __future__ import annotations

import json
import re
from pathlib import Path

from .discover import discover
from .model import Candidate


def build_packet(root, out_dir, cand_id: str, max_lines: int = 80) -> str:
    root = Path(root).resolve()
    data = json.loads((Path(out_dir) / "candidates.json").read_text())
    match = next((c for c in data if c["id"] == cand_id), None)
    if match is None:
        raise KeyError(cand_id)
    cand = Candidate.from_dict(match)
    lines = [
        f"# {cand.id}: {cand.kind} ({cand.confidence}, provider {cand.provider})",
        "",
        "Confirm before acting: " + (", ".join(cand.confirm) or "nothing"),
        "Evidence: " + json.dumps(cand.evidence, sort_keys=True),
        "",
    ]
    for loc in cand.locations:
        text = (root / loc.path).read_text(errors="ignore").splitlines()
        snippet = text[loc.start - 1: min(loc.end, loc.start - 1 + max_lines)]
        lines += [f"## {loc.path}:{loc.start}-{loc.end} {loc.symbol or ''}".rstrip(), "```", *snippet, "```", ""]
    names = {loc.symbol.split(".")[-1] for loc in cand.locations if loc.symbol}
    if names:
        pattern = re.compile(r"\b(" + "|".join(re.escape(n) for n in sorted(names)) + r")\b")
        callers, tests = [], []
        for f in discover(root).files:
            for i, line in enumerate(f.abs.read_text(errors="ignore").splitlines(), 1):
                if not pattern.search(line) or any(loc.path == f.path and loc.start <= i <= loc.end for loc in cand.locations):
                    continue
                entry = f"{f.path}:{i}: {line.strip()[:120]}"
                (tests if "test" in f.path.lower() else callers).append(entry)
        lines += ["## Callers (first 10)", *(callers[:10] or ["none found"]), "", "## Nearby tests (first 10)", *(tests[:10] or ["none found"])]
    return "\n".join(lines) + "\n"
```

**Create: `lib/optimize/cli.py`**

```python
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .cluster import build_packet
from .detect import doctor
from .discover import discover
from .model import Config, canonical_json
from .pipeline import run_scan
from .report import render_markdown
from .verify import compare, run_tests


def _add_scan_args(p):
    p.add_argument("--root", default=".")
    p.add_argument("--paths", nargs="*")
    p.add_argument("--lang", nargs="*", dest="languages")
    p.add_argument("--no-native", action="store_true")
    p.add_argument("--no-semantic", action="store_true")
    p.add_argument("--min-clone-tokens", type=int, default=Config.min_clone_tokens)
    p.add_argument("--hotspot-complexity", type=int, default=Config.hotspot_complexity)
    p.add_argument("--top-n", type=int, default=Config.top_n)


def _scan(a):
    config = Config(min_clone_tokens=a.min_clone_tokens, hotspot_complexity=a.hotspot_complexity, top_n=a.top_n)
    return run_scan(Path(a.root), config, a.paths, a.languages, use_native=not a.no_native, use_semantic=not a.no_semantic), config


def _out(a) -> Path:
    return Path(a.root).resolve() / ".optimize"


def _write(out: Path, result, config) -> None:
    out.mkdir(exist_ok=True)
    (out / "report.json").write_text(canonical_json(result.report))
    (out / "report.md").write_text(render_markdown(result.report, config.top_n))
    (out / "candidates.json").write_text(canonical_json([c.to_dict() for c in result.candidates]))
    inventory = [
        {k: v for k, v in vars(s).items() if k != "seq"} for s in result.inventory.symbols
    ]
    (out / "inventory.json").write_text(canonical_json(inventory))


def cmd_doctor(a) -> int:
    root = Path(a.root).resolve()
    langs = sorted({f.language for f in discover(root).files})
    print(json.dumps(doctor(root, langs, use_native=not a.no_native, use_semantic=not a.no_semantic), indent=2))
    return 0


def cmd_scan(a) -> int:
    result, config = _scan(a)
    out = _out(a)
    _write(out, result, config)
    if a.add_gitignore:
        gi = Path(a.root).resolve() / ".gitignore"
        existing = gi.read_text().splitlines() if gi.exists() else []
        if ".optimize/" not in existing:
            gi.write_text("\n".join(existing + [".optimize/"]) + "\n")
    s, h = result.report["summary"], result.report["header"]
    print(f"Providers: {json.dumps(h['providers'])}")
    print(f"Candidates: {json.dumps(s['by_kind'])}; review by hand: {s['review_by_hand']}")
    print(f"Report: {out / 'report.md'}")
    return 0


def cmd_cluster(a) -> int:
    try:
        print(build_packet(a.root, _out(a), a.id), end="")
    except (KeyError, OSError):
        print(f"No candidate {a.id}; run `scan` first.", file=sys.stderr)
        return 1
    return 0


def cmd_baseline(a) -> int:
    result, config = _scan(a)
    out = _out(a)
    _write(out, result, config)
    (out / "baseline.json").write_text(canonical_json(result.report["metrics"]))
    print(f"Baseline saved: {out / 'baseline.json'}")
    return 0


def cmd_verify(a) -> int:
    baseline = _out(a) / "baseline.json"
    if not baseline.exists():
        print("No baseline; run `baseline` before making changes.", file=sys.stderr)
        return 2
    result, config = _scan(a)
    _write(_out(a), result, config)
    verdict = compare(json.loads(baseline.read_text()), result.report["metrics"])
    if a.test_cmd:
        tests_ok, tail = run_tests(a.test_cmd, Path(a.root).resolve())
        print(f"Tests: {'pass' if tests_ok else 'FAIL'}" + ("" if tests_ok else f"\n{tail}"))
    else:
        tests_ok = True
        print("Tests: skipped (no --test-cmd); pass the project's test command to make this a real gate")
    print(f"Improved: {', '.join(verdict['improved']) or 'nothing'}")
    print(f"Worse: {', '.join(verdict['worse']) or 'nothing'}")
    ok = tests_ok and bool(verdict["improved"]) and not verdict["worse"]
    print("VERIFY: ok" if ok else "VERIFY: revert or rework this change")
    return 0 if ok else 1


def main(argv=None) -> int:
    sys.setrecursionlimit(5000)
    parser = argparse.ArgumentParser(prog="optimize")
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("doctor")
    p.add_argument("--root", default=".")
    p.add_argument("--no-native", action="store_true")
    p.add_argument("--no-semantic", action="store_true")
    p.set_defaults(fn=cmd_doctor)
    p = sub.add_parser("scan")
    _add_scan_args(p)
    p.add_argument("--add-gitignore", action="store_true")
    p.set_defaults(fn=cmd_scan)
    p = sub.add_parser("cluster")
    p.add_argument("id")
    p.add_argument("--root", default=".")
    p.set_defaults(fn=cmd_cluster)
    p = sub.add_parser("baseline")
    _add_scan_args(p)
    p.set_defaults(fn=cmd_baseline)
    p = sub.add_parser("verify")
    _add_scan_args(p)
    p.add_argument("--test-cmd")
    p.set_defaults(fn=cmd_verify)
    a = parser.parse_args(argv)
    return a.fn(a)
```

**Create: `scripts/optimize.py`**

```python
#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = ["tree-sitter-language-pack", "pathspec"]
# ///
"""Entry point: uv run --python 3.12 scripts/optimize.py <doctor|scan|cluster|baseline|verify> ..."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))

from optimize.cli import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `./run-tests.sh`
Expected: all tests pass (the full suite). If `test_verify_passes_a_good_refactor_and_fails_bad_ones` fails because deleting `unused_helper` leaves a trailing blank line that changes nothing measurable, check that `dead_symbols` dropped from 1 to 0 in `.optimize/report.json`; that is the improvement signal.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -q -m "Add scan pipeline, verify, cluster packet and CLI" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 11: SKILL.md and installation

**Files:**
- Create: `SKILL.md`

**Interfaces:**
- Consumes: the CLI from Task 10.
- Produces: the installed skill at `~/.agents/skills/optimize` (symlink to the repository) and links in `~/.claude/skills` and `~/.codex/skills`.

- [ ] **Step 1: Write SKILL.md**

**Create: `SKILL.md`**

````markdown
---
name: optimize
description: Use when asked to find and reduce bloat in a codebase, especially LLM-generated code: duplicate or near-duplicate functions, unused code, one-use wrappers, over-complex functions, or "organize/minimize/clean up/optimize this code". Covers Swift, JavaScript/TypeScript, Python and React. Runs a deterministic scan that ranks candidates, then guides a verified, one-refactor-at-a-time cleanup.
---

# Optimize

A deterministic scan finds and ranks candidates. You judge them and apply changes. The library decides what is similar, what has zero references and what is complex. You decide whether a cluster is one concept, what the canonical shape is, and whether a change could alter behavior. Never re-derive a number the scan produced; if you disagree with one, say so in your notes instead of silently overriding it.

```bash
O() { uv run --python 3.12 ~/.agents/skills/optimize/scripts/optimize.py "$@"; }
# With the semantic tier (local embeddings, Qdrant client): same command plus the extras.
OS() { uv run --python 3.12 --with fastembed --with qdrant-client --with numpy ~/.agents/skills/optimize/scripts/optimize.py "$@"; }
```

Run from the project root (or pass `--root`). Line numbers in all output are 1-based; Serena's are 0-based, so add 1 when comparing.

## Workflow

1. `O doctor`. Tell the user which provider each capability will use. Native tools (Periphery, knip, vulture, jscpd) and Qdrant make results more precise; without them the built-in tiers run and the report says so.
2. `O scan` (use `OS scan` when the user wants the semantic tier). Add `--add-gitignore` after asking the user whether `.optimize/` should be ignored. Then `O baseline` before touching any code.
3. Read `.optimize/report.md`. Work candidates one at a time, highest score first.
4. For each candidate: `O cluster <id>` gives the snippets, callers and nearby tests.
5. Run the candidate's `confirm` checks:
   - `zero-references`: with Serena, `find_referencing_symbols`; without it, `rg -w <name>` plus a build. Cross-check with one text search when completeness matters.
   - `single-caller`: confirm there is exactly one real caller.
   - `behavior-equivalent`: the cluster's members must do the same thing, including edge cases. Compare the code, do not assume.
   A failed check ends the candidate; note why and move on.
6. Check test coverage of the affected code. If there is none, write characterization tests first, as their own commit.
7. Propose the smallest change that works and state which behaviors it must preserve.
8. Optional: refute it with the `deepseek-review` skill (its secrets scan applies; treat findings as unverified).
9. Apply. With Serena, use `rename_symbol`, `replace_symbol_body`, `safe_delete_symbol`. Without it, use `Edit` and the project's build.
10. `O verify --test-cmd "<the project's test command>"` (for example `swift test`, `npm test`, `pytest`). If it prints `VERIFY: revert or rework this change`, undo the change. One refactor per commit.

## Hard rules

- One refactor per commit, each individually revertible.
- Extract a shared helper only with three or more real call sites. Two similar functions can be coincidence.
- Never remove error handling, validation or logging unless shown unreachable.
- Never act on a `low` confidence candidate without completing its `confirm` checks.
- Do not mix optimization into a feature or bug-fix change.
- Anything in the report's "Review by hand" section (public API, entry points, `@objc`, command registries, framework decorators, protocol witnesses) is never removed on the scan's say-so. Decide it by hand, with the user.
- Native tools are optional. If a provider falls back, the report header says so; treat lower-confidence results accordingly.

## Safety

`scan` is read-only: it writes only `.optimize/`, makes no network calls and embeds locally. Files that look like they contain credentials are skipped and listed in the report; tell the user which. Never send scan output or source to an external service unless the user asks, and never send anything the credential check skipped.

## What the candidate kinds mean

- `clone`: structurally identical or near-identical functions (renamed variables). `behavior-equivalent` must be checked. Clones that are all test code are down-ranked (`test_code` in the evidence): repeated test setup is often deliberate.
- `dead`: no references anywhere in the scanned source. Dynamic dispatch and exports are filtered to "Review by hand"; test code is exempt (test frameworks find it by reflection).
- `single-use`: a small function with exactly one caller; an inlining candidate.
- `semantic-dup`: similar by embedding, not by text; the weakest evidence.
- `hotspot`: high cyclomatic complexity; a refactoring target, not a deletion.
````

- [ ] **Step 2: Install the symlinks**

```bash
ln -sfn ~/Source/optimize-skill ~/.agents/skills/optimize
ln -sfn ~/.agents/skills/optimize ~/.claude/skills/optimize
mkdir -p ~/.codex/skills && ln -sfn ~/.agents/skills/optimize ~/.codex/skills/optimize
ls -l ~/.agents/skills/optimize ~/.claude/skills/optimize ~/.codex/skills/optimize
```
Expected: three symlinks resolving to `~/Source/optimize-skill`.

- [ ] **Step 3: Smoke-test the installed entry point on a fixture**

```bash
O() { uv run --python 3.12 ~/.agents/skills/optimize/scripts/optimize.py "$@"; }
cd ~/Source/optimize-skill/tests/fixtures/python && O doctor --no-semantic | head -20 && O scan --no-semantic --min-clone-tokens 30 --hotspot-complexity 8 && rm -rf .optimize
```
Expected: `doctor` prints JSON with `"chosen": "builtin-token-clones"` (no native tools installed); `scan` prints the providers line, candidate counts including `clone`, `dead`, `single-use` and `hotspot`, and a report path.

- [ ] **Step 4: Commit**

```bash
cd ~/Source/optimize-skill && git add -A && git commit -q -m "Add SKILL.md" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Acceptance run on real projects

This task needs human judgment; it is the spec's final gate, not a unit test. It also verifies the native-tool output formats, which Tasks 6 could only test against samples.

**Files:**
- Modify: `docs/superpowers/specs/2026-10-06-optimize-skill-design.md` (in the TimeTug repository; append to "Follow-ups")

Feasibility baseline (a prototype of this plan's code run on TimeTug before the plan was finalized): the scan takes about 3 seconds on ~310 Swift files; with test code exempt it found 0 dead symbols, 84 clone groups, 25 hotspots and 18 single-use wrappers. Real examples to look for: `checkForChanges` duplicated between `GoogleCalendarSource` and `MicrosoftCalendarSource`, `normalizedHex` duplicated in `Model.swift` and `CalendarInfo.swift`, and `expectWriteError` defined in three test helper files. Use these as a sanity check that the final run still finds them.

- [ ] **Step 1: Scan TimeTug (Swift)**

```bash
O() { uv run --python 3.12 ~/.agents/skills/optimize/scripts/optimize.py "$@"; }
cd ~/Source/timetug && O doctor && O scan --add-gitignore
```
Read `.optimize/report.md`. For the top 25 candidates, open each location and record: real finding (would act), obvious/noise, or wrong. Also note anything in "Review by hand" that should have been a candidate and vice versa.

- [ ] **Step 2: Scan the Discord bot and backend repository**

```bash
cd ~/Source/realm-of-darkness-kcbn-upstream && O doctor && O scan --paths discord_bots/src backend frontend/src
```
`discord_bots/dist` is a build of `src` and must not appear in the report; if it does, extend `SKIP_DIRS` or the project's `.optimizeignore`. The broken `.git` pointer means `doctor` should report discovery via `walk`.

- [ ] **Step 3: Install and check one native tool per language, if available**

If the user agrees to install any of them (`brew install periphery`, `pipx install vulture`, `npm i -g knip jscpd`), rerun `O doctor` and `O scan`, and compare the native tool's findings against the built-in ones for the same project. Compare the real tool output to the sample formats in `tests/test_native.py`; fix any parser that does not match and add the real sample as a test.

- [ ] **Step 4: Decide**

If most of the top 25 are noise, or real dead code or clones are missed, fix ranking or confidence (weights are in `lib/optimize/rank.py`), rerun, and repeat. Do not call v1 done until the top results are mostly real.

- [ ] **Step 5: Record the outcome in the spec and commit**

Append to the spec's `## Follow-ups` section: the date, the two projects scanned, how many of the top 25 were real, the false-positive patterns found, and any native-tool format corrections. Commit on the TimeTug branch:

```bash
cd ~/Source/timetug/.claude/worktrees/app-updates-release-workflow-148fcf && git add docs/superpowers/specs/2026-10-06-optimize-skill-design.md && git commit -q -m "Record optimize skill acceptance run" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Self-review

**Spec coverage.**
- Pipeline stages: discover (Task 2), inventory (3), detect (4-8), rank (9), report (9), verify (10).
- Provider tiers: symbols, dead code, clones, semantic with built-in fallbacks (Tasks 3-8, 10).
- Serena stays agent-side: `confirm` fields (Tasks 4-6) and SKILL.md workflow (Task 11).
- Language adapters, one per language: Swift, JS/TS (JSX), Python (Task 3).
- Candidate format and stable ids (Task 1, 4-5, 10).
- Report with provider header, summary, ranked list, baseline metrics (Task 9).
- `cluster` packet (Task 10).
- Hard rules including review-by-hand and credential skipping (Tasks 2, 4, 11).
- Testing: fixtures with planted cases (Task 3), unit tests (all), fallback parity (Task 10), capability detection including a broken `.git` (Tasks 2, 8, 10), determinism (Task 10), verify good/bad (Task 10), acceptance run (Task 12).

**Deliberate clarifications of the spec.**
- Exported and `public` symbols with zero references go to "Review by hand" (as the spec requires) and are listed with their zero-reference count, so unused exports remain visible. They are not emitted as dead candidates.
- The `excluded` count covers only source files skipped by name pattern, size, binary content or `.optimizeignore`; whole directories pruned by `SKIP_DIRS` are not counted.
- When a native provider fails at run time, the scan falls back to the built-in provider for those languages and records the reason in the report notes, rather than aborting.
- Test code (XCTest, pytest, jest, by path convention) is exempt from dead-code and single-use detection and its clones are down-ranked. Found by running a prototype on TimeTug, where it removed 1,135 false positives. This refines the spec's "reflection or dynamic dispatch" rule.
- The Qdrant tier compares index chunks (about 50 lines), not symbols, so its candidates are always `low` confidence.

**Placeholders.** None; every code step shows full content. The Task 10 note about `tests/test_pipeline.py` is explicit about which lines change.

**Type consistency.** `Symbol.label`/`.location`, `Candidate.evidence["name"]` (used by `enrich` for native candidates), `Inventory.refs/snippet/symbol_at`, `doctor(...)` result shape and `ScanResult` match across Tasks 3-10.
