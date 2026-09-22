# Sparkle release notes: rendered inline, not a linked GitHub page

Date: 2026-09-22. Status: approved.

## Problem
Sparkle's "Update Available" dialog loads `sparkle:releaseNotesLink` in a WKWebView. Both `release.yml`
and `beta.yml` point that link at the raw GitHub release page
(`https://github.com/<repo>/releases/tag/<tag>`), so the dialog shows the whole GitHub page — top nav,
sidebar, footer — squeezed into a small box, instead of just the notes.

## Decision
Stop linking to a GitHub page. At publish time, CI fetches the release body, renders it to HTML with
GitHub's markdown API, wraps it in a small styled standalone document, and embeds that HTML directly in
the appcast item's `<description>`. Sparkle renders `<description>` content as-is with no further network
fetch, so no GitHub chrome is ever loaded — the dialog shows exactly the notes, styled by us.

`sparkle:releaseNotesLink` is dropped entirely; `<description>` is the only source of notes going forward.

## Components

### `scripts/release/wrap-notes-html.py` (new)
Pure, stdin/stdout, unit-testable (no network). Reads already-rendered notes HTML (a fragment) from
stdin, wraps it in a minimal standalone HTML document with an inline `<style>` block: system font stack,
`prefers-color-scheme: dark` support, sensible margins and link color. If the input is empty or
whitespace-only, the body becomes "No release notes were provided for this update." instead of an empty
page. Prints the wrapped document to stdout.

### `scripts/release/appcast.py`
- `--notes-url` is removed.
- New optional `--notes-html-file PATH`: the file's contents (already-wrapped HTML) become the item's
  `<description>` text. ElementTree XML-escapes it when serializing (`<`, `>`, `&`), which is sufficient —
  Sparkle's XML parser decodes the text content back to the literal HTML string before rendering it, so no
  CDATA handling is needed.
- When `--notes-html-file` is not given, the item has neither `<description>` nor
  `sparkle:releaseNotesLink` (matches today's behavior for an item with no notes).

### `release.yml` / `beta.yml`
New step before "Add item to the appcast" / "Update appcast and prune old betas":
1. `BODY=$(gh api repos/$GITHUB_REPOSITORY/releases/tags/$TAG --jq .body)` — the release's markdown body
   (the release is already published by this point in both workflows).
2. Render to HTML via GitHub's markdown API in `gfm` mode with the repo as context (so `#123` / `@user`
   references resolve), authenticated with the job's existing `GH_TOKEN`:
   `jq -n --arg text "$BODY" --arg repo "$GITHUB_REPOSITORY" '{text:$text,mode:"gfm",context:$repo}' | gh api /markdown --input -`
3. Pipe that HTML through `wrap-notes-html.py` into a temp file.
4. Pass `--notes-html-file <temp file>` to `appcast.py add` instead of `--notes-url ...`.

Both workflows do the same fetch-render-wrap sequence; it is inlined in each workflow's existing shell
step rather than factored into a third shared script, matching how the rest of that step is already
per-workflow shell (AGENTS.md's "scripts hold logic, YAML wires them" rule is satisfied by
`wrap-notes-html.py` holding the only actual logic — the fetch/render lines are two `gh`/`jq` calls, not
logic worth extracting).

## Data flow
release body (markdown, from the published GitHub release)
→ GitHub `/markdown` render API (HTML fragment, gfm mode)
→ `wrap-notes-html.py` (standalone styled HTML document)
→ `appcast.py add --notes-html-file` (→ `<description>` in `appcast.xml` on `gh-pages`)
→ Sparkle renders `<description>` directly in the update dialog. No GitHub page is ever fetched by the app.

## Testing
- `scripts/release/tests/test_wrap_notes_html.py` (new, same subprocess-based pattern as
  `test_appcast.py`): passthrough of input HTML, the empty-input fallback message, presence of the
  `<style>` block.
- Extend `scripts/release/tests/test_appcast.py`: `--notes-html-file` populates `<description>` with the
  file's contents; an item built without it has neither `<description>` nor `sparkle:releaseNotesLink`;
  `--notes-url` is no longer accepted.
- The `gh api` fetch/render lines in the workflows are not unit-tested (no network in tests) — same
  boundary as the rest of `upload-release-assets.sh`.
- Manual verification: run a beta build, trigger "Check for Updates" in the app, confirm the dialog shows
  only the rendered notes (no GitHub chrome) in both light and dark mode. Add a step to
  `docs/manual-tests/macos-checklist.md` if that file already has a Sparkle-update check to extend.

## Out of scope
Changing how release notes are authored (still whatever the owner writes in the GitHub release, or
`--generate-notes` / the beta placeholder text). Styling parity with the app's own branding beyond a
clean system-font readable page. Caching/pre-rendering notes outside of CI at publish time.
