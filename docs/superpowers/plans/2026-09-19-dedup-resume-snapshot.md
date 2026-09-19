# Dedup feature: resume snapshot (written 2026-09-19, mid-session)

Read this first if a session ran out of tokens. Branch: `claude/calendar-dedup-ai-inference-c8b0f2` (worktree `.claude/worktrees/calendar-dedup-ai-inference-c8b0f2`). PR: https://github.com/darkarena1/timetug/pull/6 (OPEN, do NOT merge until the user has tested it from Xcode and says so). Specs and history: `docs/superpowers/specs/2026-09-19-calendar-dedup-inference-design.md`, ADR 0009, `docs/PROGRESS.md`, plan `docs/superpowers/plans/2026-09-19-calendar-dedup-inference.md`. Scratch ledger and briefs (git-ignored): `.superpowers/sdd/` (`progress.md`, `fixA-brief.md`, `fixB-brief.md`, reports).

## State of the branch
- All 12 plan tasks done and reviewed; final whole-branch review + 3 fix passes done; CI on PR #6 was green (app, core, core-linux, dmg) before the later commits below.
- Post-PR commits from the user's manual test (in order): `1c8384d` (Fix A, see below), then Fix B in progress (may or may not be committed; check `git log` / `git status`).
- Fix A DONE (1c8384d). Fix B DONE (7929860, 89ff2f3, df371d6, 9c981a9). Fix C DONE (da52f4e, 7a0bd36, plus the docs commit that follows).
- Fix D DONE (9188d2a, 4b3a98b, 8603ba1, plus the docs commit that follows): expandable merged-events list, tooltip, per-member split (`CalendarStore.separate`).
- Fix E DONE (eebf8e5, 64d5130, plus the docs commit that follows): identical copies listed once ("×N"), `separate(_ members:, from:, now:)`, actions renamed "Split off" (row) and "Unmerge all" (card).
- Fix F DONE (d1221b2, plus the docs commit that follows): identical-only merged groups present as a plain event (no "N copies merged", no list, no Unmerge all).
- Last known counts: Core 210, AppleIntelligenceInference 11, app 142.
- Next: push, watch CI on PR #6, user re-tests in Xcode. PR #6 stays open; never merge without the user's explicit go-ahead.

## The user's test finding and fixes
Real data: three identical "Mando (X1102)'s Upcoming Appointment" (13:00-13:30, same location) on three calendars all named "O'Bryan Shared" (Exchange, Gmail, Cloud accounts) plus a bare placeholder "Mando Spem Collection" 12:45-13:45 (Test Calendar, Gmail). The model answered same, same, different for Spem vs the three identical copies; the old resolver joined Spem to two copies and left the third exact duplicate as its own card.
- **Fix A (done, commit `1c8384d`)**: exact/rule/user merges happen first with NO size cap; model verdicts are votes between groups (same must outnumber soft different votes; at most 4 clusters per result group); hard blocks (rules-separate, user "different" lessons) always block.
- **Fix B (in progress, agent brief `.superpowers/sdd/fixB-brief.md`)**: (1) resolver split into three literal phases: identical items -> other rules + user corrections -> model verdicts; (2) merged event DISPLAYS the longer copy's span (`CalendarEvent.displayStart`, `shownStart`); tug time = start of the copy carrying a conference link, else the longer copy's start (user decision); (3) popup rows/overlay details use the shown span while countdown/scheduler follow the tug start; docs + manual-test entry.
- **Fix C (queued, not started)**: make the model consistent (user approved items 1 and 2 of my recommendation):
  1. Judge each GROUP pair once (representative = richest copy of each group; ties earliest) instead of once per copy, so identical copies get one verdict and cannot disagree (also 3x fewer model calls). The request fingerprint must not depend on which identical copy is the representative: drop `calendarKey` from the fingerprint (keep titles, times, location, notes prefix, emails, attendee count). A cached `same` merges the group pair, `different` blocks it (soft), `unsure` does nothing; pending requests deduped; hard blocks still prevent requests.
  2. Prompt changes (AppleIntelligenceInference `PromptBuilder`, and Core `AdjudicationRequest` gets structured facts, no display strings in Core): drop account names from the prompt (keep the calendar title only if useful); add rule-computed facts (start offset minutes, end offset minutes, overlap, which detail fields each side has, "no conflicting details found"); instructions say a missing detail (no location/attendees) is not a mismatch and different lengths (travel/prep) are normal; add 2-3 short worked examples (e.g. "Scott: Doctor" bare vs "Intermountain Health" with location => same; "Kristin: Logan Dance" vs "Scott: Doctor" => different). Update PromptBuilder tests (no "@", no account names, facts lines present, examples present).
  Not now (later, only if flips persist): evidence-first structured output with a stored reason (also a "why merged" tooltip), and a fixture harness that runs real cases N times on a Mac with Apple Intelligence to measure self-consistency.

## How to resume
1. `git log --oneline -8` and `git status --short`; check `.superpowers/sdd/progress.md` and any `fixB-report.md` / `fixC-*` files.
2. If Fix B is not committed: read `fixB-brief.md`, finish it test-first (Core: `swift test --package-path Packages/TimeTugCore`; app: `xcodegen generate --spec Apps/macOS/project.yml && xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test`).
3. Then do Fix C (above), test-first, then a short review pass, then push (`git push`) so PR #6 updates and check CI (`gh pr checks 6`).
4. Tell the user to re-test in Xcode: open `Apps/macOS/TimeTug.xcodeproj` from the worktree after `xcodegen generate --spec Apps/macOS/project.yml`; branch `claude/calendar-dedup-ai-inference-c8b0f2`; Settings > Calendars toggle (Beta, off by default).
5. Never merge PR #6 without the user's explicit go-ahead.

## Decisions made with the user (do not relitigate)
- Inference opt-in, default OFF, Beta badge; rules-only when no on-device model. Only on-device engines.
- Vetoes (conflicting location or conference link) run BEFORE shared-attendee and same-location merges.
- Merge badges: "Merged with <engine>" (model), "Merged manually" (user), none for rule merges. Unmerge/merge corrections become lessons.
- Merged meeting shows the longer copy's range; no-link tug at the longer copy's start; with a link, tug at that copy's start.
- Approved: the three-step mental model (identical -> rules -> inference) and spanning all accounts/calendars with no cap on certain duplicates.

## Still unverified (needs a person)
Popup/Settings UI visuals, Foundation Models quality and self-consistency on device, real EventKit attendee emails/UIDs, EventKit never supplies structured conference links (so the conflicting-link veto only covers recognised providers in the real app).
