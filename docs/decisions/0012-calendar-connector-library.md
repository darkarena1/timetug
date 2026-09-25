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
- The calendar list is remembered by the source: `calendars()` and each poll fetch it, `events(in:)` reuses it (one `calendarList` request per refresh instead of two). A calendar removed in between answers 404 or 403 and is skipped. A follow-up could poll `calendarList` with its own sync token to make polls cheaper still.

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

## OAuth in a system sheet

Sign-in runs in the system web-authentication sheet (`ASWebAuthenticationSession`, presented by `WebAuthenticationSessionPresenter` in `CalendarApple`) instead of the default browser, so it shares Safari sessions, passkeys and autofill and can close itself.

- **Loopback plus a 302, not a custom-scheme redirect.** Google's Desktop clients require a loopback redirect, so the OAuth redirect still hits the local listener. The listener answers it with a 302 to `timetug-oauth://done`; the sheet catches that scheme and dismisses. The scheme is only a completion signal and carries no authorization data.
- **Not a web view.** An embedded `WKWebView` is out: Google blocks embedded user agents, and it would lose Safari sessions and passkeys.
- **Fallback and cancel.** If the sheet cannot start, the flow opens the default browser and shows the plain "You're signed in" page. Cancelling the sheet ends the flow at once.

## Phase 3: write capabilities

Adds an optional write API to the library, implemented for Google and EventKit. Details and rationale are in `docs/superpowers/specs/2026-09-23-calendar-connectors-phase3-design.md`; the contract is `docs/calendar-connectors-api.md` part 10.

- **Opt-in by protocol.** `WritableCalendarSource: CalendarSource` is a separate protocol; a read-only connector implements nothing new. `capabilities.canWrite` is true exactly when a source conforms. Per-connector limits are capability fields (`writableFields`, `controlsNotifications`, `recurrenceScopes`, plus the existing `canEditAttendees` and `canRespondToInvite`); per-calendar limits stay `accessRole`. A write the connector cannot represent throws `WriteError.unsupported` before anything changes.
- **Patch-based updates.** `update` takes an `EventPatch` of changed fields, never a whole event, so data the library does not model is never overwritten. `EventPatch(from:to:)` remembers the original as `base`. A stale version is judged per field by the shared `PatchMerge`: only a real overlap with what the patch touches is a `WriteError.conflict`. A patch without a `base` conflicts on any stale version. A versioned write whose retry finds no version on the fresh event fails closed with `.conflict`; only a write that started unversioned retries unconditionally. `delete` ignores `ref.version` on both connectors (last-writer-wins).
- **Explicit notifications.** `NotifyPolicy` (`all`, `externalOnly`, `none`) is a required argument with no default.
- **Google `.thisAndFollowing`** is a truncation of the master's `RRULE` plus a new series (two calls, since Google has no such operation). The split reads and validates before its first write, the insert uses a client-chosen id so a lost reply can be looked up, and the master is restored only after a definite failure; otherwise the result is `WriteError.partial`. The new series starts at the occurrence's original slot with the master's length. Write results for a series (create with a rule, series-wide writes, the new series) are the master with `seriesID` set to its own id, so a `.thisInstance` write on that ref is refused instead of hitting the whole series. A recurrence change on one occurrence is `.unsupported(fields: [.recurrence])` on both connectors. Caveats: modified or cancelled instances after the split stay with the old series (a cancelled one may reappear in the new series, carried EXDATEs keep the old time of day, and whether a modified one shows twice is unverified until the live smoke test); `COUNT` arithmetic assumes the instances listing includes excluded occurrences (unverified); an add-on conference is dropped; and, on update, the truncation, the insert and any restore all carry the caller's `NotifyPolicy` (guests may get two messages; `.none` for silence; decided because external iTIP guests would otherwise keep the old series and also get the new one). `respond` with `.thisAndFollowing` is unsupported on Google. An `.allInSeries` time change is accepted only from the series' first occurrence, on Google and EventKit (an instance's date would otherwise move the whole series).
- **EventKit restrictions.** No attendee edits, no RSVP, no `visibility` or generated conference, no notification control (a `NotifyPolicy` other than `.all` is refused when other attendees exist), read-only calendars are `.forbidden`, and no calendar-default reminders (a nil draft list means no alarms). EventKit reads now fill `version`, `sourceID`, `seriesID` and `originalStart`. Several EventKit behaviors (shared `eventIdentifier`, `.futureEvents` on the first occurrence, `refresh()`, `lastModifiedDate` granularity) are unverified until the live spike is run.
- **Links stay local.** Provider-side metadata (Google `extendedProperties`, iCalendar `X-` properties, Graph extensions) is deferred; cross-calendar links, when TimeTug needs them, live in TimeTug's local store. A `metadata` field and capability can be added later without breaking this API.
- **Testing.** `WritableSourceConformance` runs against `FakeWritableSource` and, live and opt-in, against the real EventKit source; Google is covered by request-shape tests with the fake transport plus an opt-in live smoke test on the primary calendar. Live tests never run in CI.
