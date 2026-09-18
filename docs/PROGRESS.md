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
| 10 Takeover overlay | complete (build + 8 tests verified by controller; GUI checks pending user; DeepSeek Important on fireTest Join adjudicated not a defect, plan wording fixed) | cb9c4c5..d292e70 |
| 11 Settings window | complete (build + 8 tests verified; GUI checks pending user) | 0284da9..c47a1cd |
| 12 Docs, ADRs, manual checklist | complete (controller spot-checked ADR 0004 vs code and fixed one inaccuracy) | d332148..baff5d9 |
| 13 Brand assets + README | complete, review clean (GUI check pending user) | 06a64e7..46e175f |

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
- RESOLVED (user chose to fix; fixed in e4d7a09) (plan-mandated finding, Task 11): SettingsView launch-at-login toggle uses `try?` on SMAppService register/unregister, so failures are swallowed and the toggle can show a state that is not real. Suggested fix: on failure, revert the toggle to `SMAppService.mainApp.status == .enabled` and show a short message. Needs user decision (plan text mandates the current code).
- All 13 tasks done. Final whole-branch review (deepseek-v4-pro) in progress; result in .superpowers/sdd/final-review.md. Then: user to run docs/manual-tests/macos-checklist.md, decide the open question above, choose a LICENSE, and say whether to push to GitHub.
- Final whole-branch review (deepseek-v4-pro): no Critical; only Important = the launch-at-login toggle (same as the open question). Minors echoed: Google redirect unwrap gaps, CalendarEvent.id omits calendarID. Note: the review was thin (mostly restated known items), so a human/other-model pass on scheduling and timers is still worthwhile.
- 2026-09-18: launch-at-login fix done (e4d7a09); MIT license added (c5008a5); user chose local merge to master. Remaining for the user: run docs/manual-tests/macos-checklist.md, add a GitHub remote and push, decide artwork licensing.
