# Implementation progress log

Plan: `docs/superpowers/plans/2026-09-18-timetug-core-app.md` (12 tasks, subagent-driven).
Branch: `feature/core-app`. To resume: read this file and `git log`, then continue at the first task not marked complete.

| Task | Status | Commits |
|---|---|---|
| 1 Scaffold + Core model | complete, review clean | fbcfdb2..37c62e8 |
| 2 ConferenceLinkDetector | complete, review clean + hardening fix | 86eda30..85ee751 |

## Notes
- 2026-09-18: brand artwork added by the user (`artwork/`, `Apps/macOS/Resources/Assets.xcassets`, `docs/ARTWORK_USAGE.md`); plan Task 13 covers wiring it in plus README. `artwork/Source` boards and menu bar PNG exports were intentionally not committed (still in ~/Downloads/TimeTugAssets).
- Repo is to be published as a public GitHub project. No push has been done; no LICENSE chosen yet (ask the user).
- DeepSeek is used for task reviews via a Haiku relay subagent (no secrets ever sent). Implementers run on Claude.
- Minor findings (for final review): `CalendarSource.displayName` is source metadata, arguably a display string in Core; `CalendarEvent.id` omits calendarID (collision speculative); test helpers force-unwrap.
- Task 2 leftover minors: Google redirect unwrap ignores bare google.com and /url/; regex rebuilt per call (perf).
