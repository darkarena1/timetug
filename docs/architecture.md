# Architecture

Read `docs/superpowers/specs/2026-09-18-timetug-core-design.md` for the full design. This is the map.

## Modules
- `Packages/TimeTugCore`: pure Swift; depends only on `CalendarCore`. `TimeTugCalendarEvent` model (wraps the library `CalendarEvent`, adds merge and display state), `CalendarSource` protocol, `CalendarStore`
  (merge/dedupe/last-good), duplicate rules, resolver, lessons and the adjudicator interface (ADR 0009), `TakeoverPolicy`, `TakeoverLedger` + `Scheduler`, `ConferenceLinkDetector`,
  `DayAgenda`, `TakeoverRequest`, `TakeoverSettings` (including `enabled`), `WidgetSnapshot` and `WidgetTimeline` (widget data and entry dates, ADR 0010). Note: `additionalCalendarKeys` tracks when a meeting
  appears on multiple opted-in calendars so takeover opt-in on any calendar counts.
- `Packages/EventKitSource`: Apple Calendar adapter. Only place EventKit is imported.
- `Packages/CalendarConnectors`: portable calendar connector library (ADR 0012), no external dependencies. Products: `CalendarCore` (model, `AllDay`, file-backed connection and sync-state stores), `CalendarOAuth` (PKCE, refresh provider, `SHA256Hashing` seam), `GoogleCalendar`, `CalendarTestSupport`. Google needs an OAuth client from a git-ignored xcconfig (see `AGENTS.md`).
- `Packages/CalendarBridge`: minimal glue. `EventMapper` wraps library events (drops cancelled, adds calendar info); `ConnectedSource` adapts a library source to Core and translates errors and changes.
- `Packages/CalendarApple`: Keychain credential store, loopback OAuth and `CryptoKitSHA256` for the library.
- `Packages/AppleIntelligenceInference`: Apple on-device model adapter for duplicate detection (macOS 26+, compile-guarded). Only place with Foundation Models imports.
- `Apps/macOS`: menu bar item, popover, overlay windows, settings, wiring (`AppCoordinator`).
- `Apps/macOS/Widgets`: WidgetKit extension (Next Up, Today, macOS 26 controls) that reads the app-written snapshot from the App Group; `Apps/macOS/Shared` holds the code compiled into both targets (ADR 0010).
  The optional global popup shortcut uses the KeyboardShortcuts package (ADR 0005), app layer only.

## Flow
EventKit -> `CalendarStore.refresh` (fetch window) -> `CalendarSnapshot` -> `Scheduler.next` -> one timer
-> `TakeoverRequest` -> `OverlayController`. `DayAgenda.make` feeds the popover and the status title.
App -> `WidgetSnapshot` -> group container (`agenda-snapshot.json`) -> widget timelines. Control Center intents write shared settings and post a Darwin notification; the app re-reads them.

## Adding a calendar source
Implement `CalendarSource` in a new package under `Packages/`, return only Core's model, throw
`SourceError` for permission/auth problems, and register the source in `AppCoordinator`. Never import
UI frameworks; never leak source-specific types.

## Adding a platform front end
Depend on `TimeTugCore` only. Decide for yourself whether a status bar exists and what it shows, how
the takeover looks, and where settings live.
