# Optimize skill: design

Date: 2026-10-06
Status: draft, awaiting review

## Purpose

LLM-generated code accumulates predictable bloat: near-duplicate helpers across files, one-use abstractions, redundant wrappers, dead code and defensive checks that cannot trigger. This design adds a shared `optimize` skill plus a Python library that finds those opportunities with deterministic methods first, and reserves the LLM for the judgment calls that need it.

Success means:

- a ranked, evidence-backed list of consolidation and removal candidates for a project;
- a before/after metrics check (`verify`) that shows whether a change helped;
- the same workflow works whether or not Serena, Qdrant or the language-native tools are installed, with lower confidence (stated in the report) when they are not.

## Scope

Languages in v1: **Swift, JavaScript/TypeScript, Python, React/JSX**. The motivating projects are TimeTug (Swift) and the Denver After Dark Discord bot repository (JS with a little TS; Python backend; React frontend).

Out of scope for v1: auto-applying changes without agent review, languages beyond the four, CI integration, a persistent database of past runs. The `.optimize/` files are the only state.

## Where it lives

- Shared skill: `~/.agents/skills/optimize/`, symlinked into `~/.claude/skills/optimize` and `~/.codex/skills/optimize` (one copy, per the shared rules).
- This spec and the implementation plan live in the TimeTug repository.

```
optimize/
├── SKILL.md                  # when to use it, workflow, hard rules
├── scripts/optimize.py       # CLI entry (uv script, PEP 723 dependencies)
├── lib/optimize/
│   ├── discover.py           # file listing and excludes
│   ├── detect.py             # capability probing (doctor)
│   ├── adapters/             # swift.py, js_ts.py, python.py
│   ├── providers/            # symbols, deadcode, clones, semantic (preferred + built-in)
│   ├── rank.py
│   ├── report.py
│   └── verify.py
└── tests/
```

## Architecture

One pipeline; each stage writes a file the next reads:

```
discover → inventory → detect → rank → report → (LLM judges) → verify
```

| Stage | Job | Output |
|---|---|---|
| discover | List source files, apply excludes | file list |
| inventory | Extract symbols and reference counts per language | `inventory.json` |
| detect | Clones, dead code, semantic clusters, complexity | `candidates.json` |
| rank | Score by removable size, confidence, churn × complexity | ordered candidates |
| report | Write `.optimize/report.md` and `report.json` | report |
| verify | Re-run metrics against a baseline, run the test command | pass/fail diff |

The first five stages use no LLM.

### File discovery

Use `git ls-files` when it works. Fall back to a `.gitignore`-aware filesystem walk when it does not (for example the realm-of-darkness checkout, whose `.git` file points at a missing worktree). Default excludes: `dist/`, `node_modules/`, `.venv/`, build output, minified files, lockfiles, generated code. The Discord bot's `dist/` is a build of `src/` and would double-count every function.

### Capabilities and providers

Each capability has an ordered list of providers. `optimize doctor` probes each and picks the first that works.

| Capability | Preferred | Built-in fallback |
|---|---|---|
| Symbols and references | Serena (agent side only), then native tool | tree-sitter plus ripgrep reference counting |
| Dead code | Periphery (Swift), `knip` (JS/TS), `vulture` (Python) | Symbols with zero references from the inventory |
| Clones | `jscpd` | Built-in token n-gram and AST-shape hash detector |
| Semantic similarity | Existing Qdrant collection | Local `fastembed` plus numpy cosine similarity |

Every candidate records the provider that found it and a confidence (`high`, `medium`, `low`). The report header lists the provider chosen for each capability so a degraded run is visible.

**Serena cannot be called from Python** (it is an MCP server). The library never depends on it. Each candidate carries a `confirm` list, and `SKILL.md` tells the agent to run those checks through Serena when available, or `rg` plus the build otherwise.

### Language adapters

One module per language. JSX is handled in the JS/TS adapter. An adapter supplies tree-sitter queries for symbols and references, the native-tool commands and output parsers, default excludes and test-command hints. Adding a language means adding one adapter.

## Candidate format

```json
{
  "id": "dup-3f9a1c",
  "kind": "clone | dead | semantic-dup | hotspot | single-use",
  "language": "swift",
  "locations": [{"path": "Sources/A.swift", "start": 40, "end": 72, "symbol": "formatDuration"}],
  "evidence": {"similarity": 0.94, "tokens": 118, "refs": 0, "complexity": 17, "churn_90d": 12},
  "provider": "builtin-clone",
  "confidence": "high",
  "confirm": ["zero-references"],
  "score": 0.81
}
```

- `id` is a hash of the kind plus the normalized code, stable across runs, so progress can be tracked and `verify` can match before and after.
- A clone group is one candidate with several `locations`.
- `confirm` states what the agent must check before acting (`zero-references`, `behavior-equivalent`).
- Line numbers are 1-based. Serena's are 0-based.
- `score` combines removable tokens, confidence, and churn × complexity. Weights live in one config block.

## Report

`.optimize/report.md` (full data in `report.json`):

1. Header: provider per capability, scanned file counts by language, what was excluded.
2. Summary table: candidate counts by kind and language, estimated removable lines or tokens (labeled an estimate).
3. Ranked candidates: top N (default 25) with id, locations, evidence, confidence and `confirm`.
4. Baseline metrics: total lines/tokens, clone ratio, dead-symbol count, mean complexity per language.

`optimize cluster <id>` emits a small packet for one candidate: snippets, direct callers, nearby tests and the other locations. It is small enough to give to an LLM or to the `deepseek-review` skill.

## CLI

```bash
O() { uv run --python 3.12 ~/.agents/skills/optimize/scripts/optimize.py "$@"; }
O doctor
O scan [--paths ...] [--lang ...]
O cluster <candidate-id>
O baseline
O verify
```

## LLM handoff and safety rules

The library decides what is similar, what has zero references, what is complex and how candidates rank. The LLM decides whether a cluster is one concept, what the canonical shape is, and whether a change could alter behavior. The LLM never re-derives a number the library produced; if it disagrees, it notes that in the report and does not silently override.

Per-candidate workflow (in `SKILL.md`):

1. `optimize cluster <id>`.
2. Run the `confirm` checks (Serena `find_referencing_symbols` if available, otherwise `rg` plus a build). A failed check ends the candidate with a note.
3. Check test coverage. If there is none, write characterization tests first, as a separate commit.
4. Propose the smallest change and state the behaviors it must preserve.
5. Optional refutation pass with the `deepseek-review` skill (its secrets scan applies; its findings are unverified).
6. Apply, preferring Serena symbol edits (`rename_symbol`, `replace_symbol_body`, `safe_delete_symbol`), otherwise `Edit`.
7. `optimize verify`. If tests fail or metrics did not improve, revert.

Hard rules:

- One refactor per commit, each individually revertible.
- Extract a shared helper only with three or more real call sites.
- Never remove error handling, validation or logging unless shown unreachable.
- Never act on `low` confidence candidates without an explicit confirm step.
- No optimization mixed into a feature or bug-fix change.
- Public API, entry points, and anything reached by reflection or dynamic dispatch (`@objc`, Discord command registries, dynamic `require`) is flagged `review-by-hand`, not offered for removal.
- Test code (XCTest, pytest, jest) is found by the test framework by reflection, so it is exempt from dead-code and single-use detection, and clones made entirely of test code are down-ranked.

Secrets: files that look like they contain credentials are skipped and listed (reusing the pattern set from the `index` skill). `scan` is read-only, writes only to `.optimize/` (added to `.gitignore` after asking), makes no network calls, and embeds locally.

## Testing

- **Fixtures:** one small project per language under `tests/fixtures/`, with planted cases: an exact clone, a renamed-variable clone, a semantic duplicate, an unused function, a function that only looks unused (reached via `@objc`, dynamic `require` or a command registry), a single-use wrapper, and a high-complexity function. Tests assert the expected candidates and that the look-alikes are `review-by-hand`.
- **Unit:** each detector, adapter query and parser (`pytest`).
- **Fallback parity:** each fixture once with native tools present and once absent. The built-in detectors must find the planted cases and the report must show lower confidence.
- **Capability detection:** `doctor` with providers stubbed in and out, Qdrant down, and a broken `.git`.
- **Determinism:** two scans of the same commit produce byte-identical `report.json` with stable ids.
- **Verify:** a known-good and a known-bad refactor on a fixture; `verify` passes one and fails the other.
- **Acceptance run:** before calling v1 done, scan TimeTug and the realm-of-darkness repository and review the top 25 candidates by hand. A mostly-wrong or mostly-obvious list means ranking or confidence needs work. The outcome is recorded in this spec's follow-ups.

## Follow-ups

None yet. The acceptance run adds entries here.
