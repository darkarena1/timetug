# Architecture

Read `docs/superpowers/specs/2026-09-18-timetug-core-design.md` for the full design. This is the map.

## Modules
- `Packages/TimeTugCore`: pure Swift. `CalendarEvent` model, `CalendarSource` protocol, `CalendarStore`
  (merge/dedupe/last-good), duplicate rules, resolver, lessons and the adjudicator interface (ADR 0009), `TakeoverPolicy`, `TakeoverLedger` + `Scheduler`, `ConferenceLinkDetector`,
  `DayAgenda`, `TakeoverRequest`, `TakeoverSettings`. Note: `additionalCalendarKeys` tracks when a meeting
  appears on multiple opted-in calendars so takeover opt-in on any calendar counts.
- `Packages/EventKitSource`: Apple Calendar adapter. Only place EventKit is imported.
- `Packages/AppleIntelligenceInference`: Apple on-device model adapter for duplicate detection (macOS 26+, compile-guarded). Only place with Foundation Models imports.
- `Apps/macOS`: menu bar item, popover, overlay windows, settings, wiring (`AppCoordinator`).
  The optional global popup shortcut uses the KeyboardShortcuts package (ADR 0005), app layer only.

## Flow
EventKit -> `CalendarStore.refresh` (fetch window) -> `CalendarSnapshot` -> `Scheduler.next` -> one timer
-> `TakeoverRequest` -> `OverlayController`. `DayAgenda.make` feeds the popover and the status title.

## Adding a calendar source
Implement `CalendarSource` in a new package under `Packages/`, return only Core's model, throw
`SourceError` for permission/auth problems, and register the source in `AppCoordinator`. Never import
UI frameworks; never leak source-specific types.

## Adding a platform front end
Depend on `TimeTugCore` only. Decide for yourself whether a status bar exists and what it shows, how
the takeover looks, and where settings live.
