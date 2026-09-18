# ADR 0002: Core, Source, and App Module Boundaries

**Status:** Accepted

## Context

The app integrates multiple calendar sources and must evolve to support Google Calendar, iCloud, and Exchange in the future. Dependencies must be testable, independently replaceable, and isolate platform-specific code from reusable logic.

## Decision

Organize into three layers:
- **Core** (`Packages/TimeTugCore`): Pure Swift, no AppKit/SwiftUI/EventKit imports. Defines the `CalendarSource` protocol and all business logic (scheduling, policy, merging, link detection). Returns only Core's normalized `CalendarEvent` model.
- **Sources** (e.g., `Packages/EventKitSource`): Implement `CalendarSource` for a specific backend. May import platform frameworks but no UI. Sources contain no display logic or settings storage.
- **App** (`Apps/macOS`): The composition root. Owns the UI, wires sources into the store, configures credential storage, and renders settings. The only place that instantiates sources and knows which exist at runtime.

Dependency direction: `Apps/macOS -> EventKitSource -> TimeTugCore`. Core imports nothing else.

Rejected alternative: Shared source configuration UI in the source package itself would couple sources to UI frameworks, prevent headless testing, and limit future iOS/CLI frontends.

## Consequences

**Advantages:**
- Core is testable with fake sources and an injected clock; no system framework mocks needed.
- Sources can fail independently without affecting others (last-known events still fire takeowers).
- Each platform frontend (iOS, CLI, Windows) imports only `TimeTugCore` and implements its own `AppCoordinator` equivalent.
- Runtime plugin loading becomes possible later: a source need not be compiled in.

**Trade-off:** Up-front cost to define `CalendarSource` protocol carefully. Mitigation: protocol is small (5 methods) and driven by real sources (EventKit, Google Meet API, Exchange EWS).

No credential storage yet lives in sources; the app owns `UserDefaults` and future secure storage, keyed by `sourceID`.
