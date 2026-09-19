# Widgets and Control Center controls: design

Date: 2026-09-19. Status: approved in conversation, awaiting written-spec review.

## Goal
Add two desktop widgets (Next Up, Today) and three Control Center toggles (Skip All Day Events, Use Intelligence, Disable Tug). Disable Tug is also a setting in Settings.

## Decisions
- **Data source:** the app writes an agenda snapshot; widgets only read it. Widgets therefore match the popover exactly (merging, dedup, all-day filtering, Apple Intelligence) and need no calendar permission of their own. Rejected: the widget reading EventKit itself (second permission prompt, would duplicate or skip dedup logic).
- **Sharing:** App Group `YYA6ZKMD36.com.timetug.shared` (team-prefixed, so Developer ID builds need no provisioning profile for it). Team ID `YYA6ZKMD36` is a public identifier.
- **Disable Tug** turns off takeover and the pre-meeting popup only. Menu bar item, popover and widgets keep showing the agenda.
- **Platforms:** app stays on macOS 14. Widgets work on macOS 14+. Controls need macOS 26 and are `#available`-guarded.

## Shared state
- `agenda-snapshot.json` in the group container: merged events for today plus the next few days (Next Up needs to roll past midnight), written by the app.
- Shared `UserDefaults` suite (`YYA6ZKMD36.com.timetug.shared`) with three booleans: `skipAllDay`, `useIntelligence`, `disableTug`.
- `SettingsStore` reads and writes those three through the suite. On first launch it migrates existing values (`takeoverSettings.v1` `skipAllDayEvents`, `dedupInference.v1`) into the suite, once. Existing Settings toggles bind to the same values.
- The app observes the suite (KVO on the three keys) so a toggle flipped in Control Center, which runs in the extension process, applies immediately: reschedule takeover, re-run dedup, refresh the snapshot.

## Core (TimeTugCore, pure Swift, tests first)
- `WidgetSnapshot`: Codable, platform-neutral model of the events widgets need (id, title, start, end, isAllDay, calendar colour key, join URL, merged flag) plus `generatedAt`. Core has no display strings.
- `WidgetTimeline.entries(snapshot:, now:, limit:)`: pure function returning the instants at which a widget's content changes (each event start and end after `now`, and day boundaries) and the state at each. Drives the rolling Next Up behaviour; `now` is always passed in.
- `TakeoverSettings.disabled` (default false, decoded with `decodeIfPresent`). `TakeoverPolicy` and `Scheduler` produce no takeover while it is set; the agenda is unaffected.
- All-day filtering already exists (`TakeoverSettings.skipAllDayEvents`, applied in `DayAgenda`); the snapshot is built from the filtered agenda.

## Widget extension (`TimeTugWidgets` target)
- **Next Up** (small, medium): current or next event with a countdown; medium adds the events after it as a rolling list. The timeline advances at each event start/end. Tapping opens the join link when there is one, else the popover.
- **Today** (medium, large): today's meetings in order; past dimmed, current highlighted; "nothing today" empty state.
- Missing or stale snapshot renders a "Open TimeTug to refresh" placeholder rather than wrong data. Disabled or unauthorised states are handled the same way.
- **Controls** (macOS 26): three `ControlWidgetToggle`s, each backed by a `SetValueIntent` writing the shared suite: Skip All Day Events, Use Intelligence, Disable Tug.

## App changes
- `AppCoordinator` writes the snapshot and calls `WidgetCenter.reloadAllTimelines()` after each calendar refresh and each setting change. Write is atomic; failures are logged, not fatal.
- Settings: add "Disable Tug" toggle (General or Tug Rules pane; implementation picks the better fit), register it in `SettingsSearch`. Use Intelligence stays labelled Beta and unavailable where inference is unavailable; the control reflects that (disabled/off with explanatory value text).
- Menu bar/popover unchanged except that a disabled Tug is indicated (small state in the status menu; exact affordance decided in the plan).

## Build, signing, CI
- `project.yml`: new `TimeTugWidgets` app-extension target embedded in TimeTug; `DEVELOPMENT_TEAM: YYA6ZKMD36`; app group entitlement on both targets; the extension is sandboxed (required). The app keeps ad-hoc signing for local/CI builds where no cert exists; the group ID is still team-prefixed.
- `scripts/release/sign-and-notarize.sh` and CI scripts: sign the embedded `.appex` (inside-out) before the app, then notarize. DMG verification checks the appex is present.
- ADR 0010: App Group + snapshot design. Update `AGENTS.md`, `docs/architecture.md`, README, `docs/manual-tests/macos-checklist.md`.

## Testing
- Core: Swift Testing for `WidgetSnapshot` round-trip, `WidgetTimeline` (rolling, midnight, empty, overlap), `TakeoverSettings.disabled` decoding and takeover suppression.
- App: settings migration, snapshot writer, suite-to-store observation.
- Manual (checklist): add each widget, verify rolling advance, toggle each control from Control Center and confirm the app reacts, run on a signed build.

## Risks
- Extension loading on ad-hoc signed local builds may be flaky; verify with a Developer-ID-signed build.
- Snapshot goes stale if the app is not running; timeline entries are precomputed to the snapshot horizon so display stays correct until then.
- Controls cannot be built or exercised on macOS < 26; they are compile-guarded.
