# Implementation progress log

Plan: `docs/superpowers/plans/2026-09-18-timetug-core-app.md` (12 tasks, subagent-driven).
Branch: `feature/core-app`. To resume: read this file and `git log`, then continue at the first task not marked complete.

| Task | Status | Commits |
|---|---|---|
| 1 Scaffold + Core model | complete, review clean | fbcfdb2..37c62e8 |
| 2 ConferenceLinkDetector | complete, review clean + hardening fix | 86eda30..85ee751 |
| 3 TakeoverPolicy | complete, review clean | a92ec5e..749d9c9 |
| 4 Ledger, Scheduler, TakeoverRequest | complete (DeepSeek Critical was a false positive, verified: no typo, 41/41 pass) | 7413e39..e3bf990 |
| 5 CalendarStore | complete (+ dedupe-merge fix so opt-in/links survive; re-review Importants were about the controller-ordered fix, adjudicated not defects) | 461ca02..cb44e8c |
| 6 DayAgenda | complete, review clean (Core package done: 63 tests) | 3e61801..f656bd1 |
| 7 EventKitSource | complete, review clean (build-only verification) | 8ee011c..399524c |
| 8 macOS shell + coordinator | complete (build + 8 app tests verified by controller; GUI checks pending user) | 4a3bf7a..a920ac8 |
| 9 Dropdown popover | complete, review clean (GUI check pending user) | c017000..f484b0a |

## Notes
- 2026-09-18: brand artwork added by the user (`artwork/`, `Apps/macOS/Resources/Assets.xcassets`, `docs/ARTWORK_USAGE.md`); plan Task 13 covers wiring it in plus README. `artwork/Source` boards and menu bar PNG exports were intentionally not committed (still in ~/Downloads/TimeTugAssets).
- Repo is to be published as a public GitHub project. No push has been done; no LICENSE chosen yet (ask the user).
- DeepSeek is used for task reviews via a Haiku relay subagent (no secrets ever sent). Implementers run on Claude.
- Minor findings (for final review): `CalendarSource.displayName` is source metadata, arguably a display string in Core; `CalendarEvent.id` omits calendarID (collision speculative); test helpers force-unwrap.
- Task 2 leftover minors: Google redirect unwrap ignores bare google.com and /url/; regex rebuilt per call (perf).
- Reviewer calibration: DeepSeek flash hallucinated a test typo in Task 4 (verified false). Verify any Critical/Important finding against the repo before acting.
- Design change in Task 5: CalendarEvent.additionalCalendarKeys/allCalendarKeys; TakeoverPolicy opt-in passes if ANY calendar of a merged meeting is opted in; DayAgenda (Task 6) hides a merged meeting only if all its calendars are hidden (plan already updated).
- Task 5 minors: sourceNames uniqueKeysWithValues traps on duplicate source ids; dedupe key uses raw doubles. Task 6 minors: force-unwrapped day arithmetic in DayAgenda.make.
- Manual/visual verification steps (Tasks 8-11, checklist in docs/manual-tests) cannot be done by subagents: they build and run unit tests only; the user must do the manual checks.
- Task 8: plan test inputs 300s->299s (compact(300) is "5m"); fireTest() is added in Task 10 not Task 8; DeepSeek flagged both, adjudicated not defects.
