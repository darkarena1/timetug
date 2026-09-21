# ADR 0012: Portable Calendar Connector Library

**Status:** Accepted

## Context

TimeTug reads calendars only through EventKit. Users also want to connect Google, Microsoft and CalDAV/iCloud accounts directly, with reads now and writes later, and the connectors should be reusable outside TimeTug. Google and Microsoft push notifications need a public HTTPS endpoint, which a desktop app does not have; iCloud has no third-party push at all. No Swift library maps across these providers.

## Decision

Build `Packages/CalendarConnectors` in this repository, extract it to its own repository after the Google connector has been used by TimeTug (Phase 2). It imports nothing from TimeTug; the package has no dependency on TimeTug packages, so the compiler enforces that.

- **Portable:** `CalendarCore` (model, `CalendarSource`, `ConnectorKind`, OAuth2 PKCE, `ChangeMonitor`) is pure Swift 6 and builds on Linux. No MSAL and no `GoogleAPIClientForREST`; networking goes through an injected `HTTPTransport`. The one dependency is `swift-crypto` (SHA-256 for PKCE).
- **The host app owns platform parts:** `CredentialStore` (Keychain on macOS), the browser and loopback redirect (`AuthorizationInteraction`), persistence of `Connection`s, and the OAuth client id/secret. EventKit stays in TimeTug as its own connector.
- **Naming:** the library's generic event is `CalendarEvent`; TimeTug's own event (with dedup fields) becomes `TimeTugCalendarEvent` in Phase 2.
- **Change detection:** poll using each provider's incremental sync token (Google `syncToken`, Graph delta, CalDAV sync-collection); `capabilities.syncKind`/`supportsPush` are the seam for a later webhook relay holding a websocket to the app. Google and Microsoft offer no persistent client connection.
- **Capabilities are per connector, not per provider:** iCloud via EventKit cannot invite or RSVP; via CalDAV (RFC 6638 server-side scheduling) it can.
- **Phases:** 1 library + read-only Google; 2 plug into TimeTug (Accounts pane, dynamic sources, Keychain); 3 write capabilities; 4 Microsoft.

## Google specifics

- OAuth for desktop apps uses a loopback redirect. Calendar scopes are "sensitive": while the Google Cloud project is in Testing only listed test users can sign in and refresh tokens expire after 7 days; a public release needs Google's OAuth verification.
- `syncToken` cannot be combined with `timeMin`/`timeMax` and requires `showDeleted=true`, so change detection lists whole calendars (field-minimal) only to obtain and advance tokens.

## Consequences

- Reads are provider-neutral; TimeTug maps `CalendarEvent` into `TimeTugCalendarEvent`.
- The first change check after connecting costs one field-minimal full listing per calendar; persisting sync tokens across launches (Phase 2) avoids repeating it.
- Extraction later is a `git subtree split`.

## Phase 2

TimeTug now uses the library. Decisions made while plugging it in:

- **Bridge package:** `Packages/CalendarBridge` maps library events to `TimeTugCalendarEvent` and adapts library sources to Core's source protocol. (Superseded by Phase 2.5: Core now depends on `CalendarCore`.) At the time `TimeTugCore` did not depend on the library: the library needs swift-crypto, which needs a newer toolchain than the `swift:6.0` image that proves Core's portability. Core gains only generic pieces (`CalendarStore.setSources`, `TakeoverSettings.removeCalendars`).
- **Layering:** anything generic (stores, all-day handling, conformance check) lives in `CalendarCore`; OS-specific code lives in `Packages/CalendarApple` (Keychain, loopback OAuth) and the `EventKitSource` adapter. The app composes them and owns UI and account state.
- **All-day rule:** a connector emits all-day events in the library's canonical form (`AllDay`); the bridge converts them to TimeTug's native all-day form so the same calendar date shows regardless of time zone. The bridge conversion is interim; Phase 2.5 removes it.
- **EventKit source id:** EventKit reports one constant source id for the Mac. Selections and status are keyed by `source.id`, never by the calendar's own source identifier.
- **Removal order** (`AccountsController.removeAccount`): the stored connection first (if that fails nothing else changes), then the source is dropped by reconciling, then the account's calendar selections, then its sync state, then its secrets, the last two best effort with an error message if the secret cannot be deleted. On launch an orphan sweep drops selections of account-based sources that no stored account owns, covering an interrupted removal.
- **Phase 2.5 goal:** a minimal bridge and a dependency-free `CalendarCore`, by moving OAuth into a separate `CalendarOAuth` product.

## Phase 2.5

Slims the bridge and removes the library's only dependency.

- **Core depends on `CalendarCore`.** This supersedes the Phase 2 note. `CalendarCore` has no dependencies and builds on `swift:6.0`, so Core stays portable. Core keeps its own `CalendarSource`, `SourceError` and `SourceStatus` and uses the library's `Attendee` and `ResponseStatus`.
- **No external dependencies in the library.** OAuth (PKCE, refresh provider) moved to a `CalendarOAuth` product. SHA-256 sits behind the `SHA256Hashing` seam with a pure-Swift default (`PureSwiftSHA256`); `CalendarApple` provides `CryptoKitSHA256`, injected in `AppConnectors.swift`. swift-crypto and the `Package.resolved` files that pinned only it are gone, so the Linux job runs on `swift:6.0` with Core.
- **Wrapper event.** `TimeTugCalendarEvent` wraps the library `CalendarEvent` instead of converting it, and stores the TimeTug-only fields (conference link, other attendee count, response status, merge and display state). The bridge is now `EventMapper` (wrap, drop cancelled, add calendar info) plus `ConnectedSource` (error and change translation).
- **All-day by calendar date.** An all-day event belongs to a day by its calendar date in the event's own zone (`allDayDates`, `covers`), never adjusted to the viewer's zone. A same-date range counts as one day. Because an event's date can differ from the viewer's day near midnight, `CalendarStore` widens the fetch window by 26 hours on each side for sources (`sourceQueryMargin`).
- **Accepted change.** The `id` and `contentKey` inputs of all-day events are now canonical instants. This changes keys only for all-day events in another zone; those never take over or merge, so nothing persisted is affected. Persisted formats of timed events are unchanged.
