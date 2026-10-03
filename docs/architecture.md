# Architecture

This is the current module map. The [2026-09-18 core design](superpowers/specs/2026-09-18-timetug-core-design.md) records original rationale; later ADRs and code supersede changed details.

## Modules
- `Packages/TimeTugCore`: pure Swift; depends only on `CalendarCore`. `TimeTugCalendarEvent` model (wraps the library `CalendarEvent`, adds merge and display state), `CalendarSource` protocol, `CalendarStore`
  (merge/dedupe/last-good), duplicate rules, resolver, lessons and the adjudicator interface (ADR 0009), `TakeoverPolicy`, `TakeoverLedger` + `Scheduler`,
  `DayAgenda`, `TakeoverRequest`, `TakeoverSettings` (including `enabled`), `WidgetSnapshot` and `WidgetTimeline` (widget data and entry dates, ADR 0010). Note: `additionalCalendarKeys` tracks when a meeting
  appears on multiple opted-in calendars so takeover opt-in on any calendar counts.
- `Packages/EventKitSource`: Apple Calendar adapter. Only place EventKit is imported.
- `Packages/CalendarConnectors`: portable calendar connector library (ADR 0012), no external dependencies. Products: `CalendarCore` (model, `AllDay`, `ConferenceDetector`, `JoinURLPolicy`, file-backed connection and sync-state stores, optional write API), `CalendarOAuth` (PKCE, refresh provider, `SHA256Hashing` seam), `GoogleCalendar`, `MicrosoftCalendar`, `CalendarTestSupport`. The app supplies Google and Microsoft OAuth configuration from git-ignored xcconfigs (see [operations](development/runbooks/operations.md)). Microsoft retains `Calendars.ReadWrite` and `Calendars.ReadWrite.Shared` access and writable capabilities.
- `Packages/CalendarBridge`: minimal glue. `EventMapper` wraps library events (drops cancelled, adds calendar info); `ConnectedSource` adapts a library source to Core and translates errors and changes.
- `Packages/CalendarApple`: Keychain credential store, loopback OAuth and `CryptoKitSHA256` for the library.
- `Packages/AppleIntelligenceInference`: Apple on-device model adapter for duplicate detection (macOS 26+, compile-guarded). Only place with Foundation Models imports.
- `Apps/macOS`: menu bar item, popover, overlay windows, settings, wiring (`AppCoordinator`).
- `Apps/macOS/Widgets`: WidgetKit extension (Next Up, Today, macOS 26 controls) that reads the app-written snapshot from the App Group; `Apps/macOS/Shared` holds the code compiled into both targets (ADR 0010).
  The optional global popup shortcut uses the KeyboardShortcuts package (ADR 0005), app layer only.

## Flow
EventKit, Google and Microsoft -> `CalendarBridge.ConnectedSource` -> `CalendarStore.refresh` (fetch window) -> `CalendarSnapshot` -> `Scheduler.next` -> one timer
-> `TakeoverRequest` -> `OverlayController`. `DayAgenda.make` feeds the popover and the status title.
App -> `WidgetSnapshot` -> group container (`agenda-snapshot.json`) -> widget timelines. Control Center intents write shared settings and post a Darwin notification; the app re-reads them.

## Adding a calendar source
Implement the library's `CalendarSource` and `ConnectorKind` in `Packages/CalendarConnectors` (except Apple Calendar, which uses `EventKitSource`). Use `CalendarCore` models and errors; add `WritableCalendarSource` only for supported writes. Map the source through `CalendarBridge.ConnectedSource` and register its connector kind in `Apps/macOS/Sources/AppConnectors.swift`. The app supplies credentials, OAuth interaction and source configuration UI. Never import UI frameworks into the connector library or leak provider types into Core. A new package also needs its allowed dependencies and import rules in `scripts/ci/check-architecture.sh`, which fails until it has them.

## Adding a platform front end
Depend on `TimeTugCore` only. Decide for yourself whether a status bar exists and what it shows, how
the takeover looks, and where settings live.
