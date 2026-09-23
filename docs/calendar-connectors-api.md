# Calendar Connectors: API contract

Status: parts 1-9 and 11 describe the code on `master` after Phase 2.5; part 10 is the Phase 3 design and is marked **Proposed**.
The library is pre-1.0 and lives in this repository; it is meant to be extracted into its own repository once a
second provider (Microsoft, Phase 4) has proved the API is provider-neutral. Until then, anything here can change
with a matching change to this document.

## 1. What the suite is

A portable Swift library that lets a host application read (and, from Phase 3, write) calendars from several
providers behind one model, plus the small amount of host-specific glue TimeTug needs.

| Package / target | Role | Depends on | Platform notes |
|---|---|---|---|
| `CalendarConnectors` / `CalendarCore` | Model, source and connector protocols, stores, HTTP seam, change polling, all-day helpers | Foundation only | Portable; built on Linux in CI |
| `CalendarConnectors` / `CalendarOAuth` | OAuth 2.0 authorization-code + PKCE client, access-token cache | `CalendarCore` | Portable; no crypto dependency (pure-Swift SHA-256 default) |
| `CalendarConnectors` / `GoogleCalendar` | Google Calendar connector (REST v3) | `CalendarCore`, `CalendarOAuth` | Portable |
| `CalendarConnectors` / `CalendarTestSupport` | Fakes and conformance helpers for connector tests | `CalendarCore` | Test-only product |
| `CalendarApple` | Apple-only adapters: Keychain credentials, loopback and web-auth-session OAuth interaction, CryptoKit hashing | `CalendarCore`, `CalendarOAuth` | macOS |
| `EventKitSource` | Apple Calendar via EventKit as a connector | `CalendarCore` | macOS |
| `CalendarBridge` | Adapts a library source to TimeTug Core's own `CalendarSource` | `CalendarCore`, `TimeTugCore` | TimeTug only |

Layering rule: maximise generic, cross-platform code in `CalendarConnectors`. Anything OS-specific (Keychain,
Network.framework, EventKit, AuthenticationServices) lives in a separate adapter that implements a library
protocol, so another host can supply its own.

Dependency direction: `GoogleCalendar` → `CalendarOAuth` → `CalendarCore`; adapters and the bridge depend on
`CalendarCore`; nothing in `CalendarConnectors` depends on an adapter.

## 2. Conventions every part of the contract relies on

- **Concurrency.** All public types are `Sendable`; sources and stores are safe to call from any task. Swift 6
  language mode (the Apple adapters build in Swift 5 mode because of AppKit/Network types).
- **Errors.** Sources throw `SourceError` (part 3.6) and never leak provider or transport types. Cancellation
  surfaces as `CancellationError`.
- **Time.** Instants are `Date`. A timed event's `timeZone` is the zone it was authored in (informational for
  timed events).
- **All-day events (canonical form).** `isAllDay == true` ⇒ `timeZone` is non-nil, `start` is midnight of the
  first day in that zone, `end` is midnight of the day after the last day (exclusive). Days are interpreted in the
  event's own zone, not the device's. Connectors build and read this form only through the `AllDay` helpers, and
  their tests run fixtures through `AllDayConformance.violations`.
- **Identity.** A calendar is identified by `CalendarDescriptor.id` within its source. An event is identified by
  `(calendarID, eventID)` within its source (`CalendarEvent.id == "\(calendarID)/\(eventID)"`). A source is
  identified by `CalendarSource.id`. For network connectors `id == Connection.sourceID == "<kindID>-<connectionID>"`.
  EventKit is the documented exception: its source id is the constant `"eventkit"`, kept so previously stored
  calendar keys stay valid. Hosts always identify a source by `source.id`.
- **Secrets never live in the library.** Non-secret account data is a `Connection`; secrets go through a
  host-supplied `CredentialStore`. OAuth client identifiers are injected by the host from configuration that is
  not committed.
- **Polling, not push.** Change detection uses provider sync tokens on a timer. There are no webhooks or relay
  servers in the contract (the `supportsPush` capability is a seam only).

## 3. `CalendarCore`

### 3.1 Model

```swift
public struct CalendarDescriptor: Hashable, Sendable, Identifiable {
    var id: String; var title: String
    private(set) var colorHex: String?   // "#RRGGBB" uppercase, or nil if unknown/invalid
    var accessRole: AccessRole           // owner, writer, reader, freeBusyReader
    var isPrimary: Bool; var timeZone: TimeZone?
    var accountName: String?             // the owning account, e.g. the signed-in email
    var kind: CalendarKind               // standard, subscribed, birthdays
    static func normalizedHex(_:) -> String?   // "#RGB" | "#RRGGBB" | "RRGGBB" → "#RRGGBB"
}
```

`CalendarEvent` (the one generic event type; TimeTug's own wrapper is `TimeTugCalendarEvent`):

| Field | Type | Contract |
|---|---|---|
| `eventID` | `String` | Unique within its calendar; a recurring instance has its own id (see part 11 for EventKit) |
| `id` | `String` (computed) | `"\(calendarID)/\(eventID)"`, unique within a source |
| `uid` | `String?` | iCalendar UID (Google `iCalUID`); stable across copies of the same meeting |
| `calendarID` | `String` | Owning calendar |
| `title` | `String` | Non-optional; a connector substitutes its own placeholder for an untitled event ("(No title)" today) |
| `notes`, `location` | `String?` | |
| `start`, `end` | `Date` | See the all-day convention; `end` is exclusive |
| `timeZone` | `TimeZone?` | Non-nil whenever `isAllDay` |
| `isAllDay` | `Bool` | |
| `status` | `EventStatus` | `confirmed`, `tentative`, `cancelled` |
| `availability` | `Availability` | `busy`, `free` |
| `visibility` | `Visibility` | `default`, `publicEvent`, `privateEvent`, `confidential` |
| `kind` | `EventKind` | `standard`, `focusTime`, `outOfOffice`, `workingLocation`, `birthday`, `other` |
| `seriesID`, `originalStart` | `String?`, `Date?` | Set on an instance of a recurring series |
| `attendees` | `[Attendee]` | `name?`, `email?` (trimmed, lowercased), `role` (`required/optional/resource`), `response`, `isSelf`, `isOrganizer` |
| `organizer` | `Attendee?` | |
| `conference` | `ConferenceInfo?` | `url` + `provider` (`meet/teams/zoom/other`) |
| `reminders` | `[Reminder]` | `minutesBefore`; empty means none *or* provider defaults (not distinguished today) |
| `url` | `URL?` | Link to the event in the provider's UI |
| `version` | `String?` | Opaque provider version (Google etag); used for optimistic writes in Phase 3 |
| `myResponse` | `ResponseStatus?` | The account owner's own response, when the provider says |

Reads return recurring events already expanded into instances. No read path returns a recurrence rule.

### 3.2 Sources

```swift
public protocol CalendarSource: Sendable {
    var id: String { get }
    var displayName: String { get }
    var capabilities: SourceCapabilities { get }
    func calendars() async throws -> [CalendarDescriptor]
    /// Events of every visible calendar of the account that overlap `interval`.
    func events(in interval: DateInterval) async throws -> [CalendarEvent]
    func changes() -> AsyncStream<CalendarChange>
}

public protocol PollingCalendarSource: CalendarSource {
    /// One cheap incremental check. Returns the change since the last call, or nil for none.
    /// The first call establishes the baseline and returns nil.
    func checkForChanges() async throws -> CalendarChange?
}
```

Guarantees:

- `events(in:)` returns events sorted by start (then id) for network connectors, excluding calendars the account
  can no longer read. Cancelled events may be present in the model (`status == .cancelled`); consumers such as the
  bridge drop them.
- A source is read-only unless it also conforms to `WritableCalendarSource` (Phase 3, part 10).

### 3.3 Capabilities

```swift
public struct SourceCapabilities: Equatable, Sendable {
    var canWrite: Bool              // false today for every source
    var canEditAttendees: Bool
    var canRespondToInvite: Bool
    var providesConference: Bool
    var syncKind: SyncKind          // .none, .token, .notification
    var supportsPush: Bool
}
```

Capabilities are what a source *can* do, declared per connector; the per-calendar `accessRole` says which of its
calendars are writable. Current values: Google = `providesConference`, `.token`; EventKit = `.notification`.

### 3.4 Changes

```swift
public enum CalendarChange: Equatable, Sendable {
    case calendarsChanged                      // reload calendars AND events; event changes in the same check are not reported separately
    case eventsChanged(calendarIDs: Set<String>?)   // nil = scope unknown
    case sourceFailed(SourceError)             // terminal: the stream finishes after this (e.g. .authExpired)
}
```

`ChangeMonitor` (public struct) turns a `PollingCalendarSource.checkForChanges()` into `changes()`:
default interval 60 s, exponential backoff on failures capped at 900 s, sleeping through an injectable `Sleeper`.
Polling starts when the stream is created and stops when the consuming task is cancelled or the stream finishes;
dropping the stream without cancelling does not stop it. Use one subscriber per source.

### 3.5 Connecting

```swift
public struct Connection: Codable, Hashable, Sendable, Identifiable {
    var kindID: String; var connectionID: ConnectionID   // ConnectionID = String
    var displayName: String; var config: [String: String] // non-secret
    var sourceID: String { "\(kindID)-\(connectionID)" }  // every consumer must use this helper
}

public protocol ConnectorKind: Sendable {                 // registered once per provider
    var id: String { get }; var displayName: String { get }
    var supportedPlatforms: Platform { get }              // OptionSet: macOS, iOS, linux, windows
    var authorization: AuthorizationMethod { get }        // .oauth, .password(fields:), .system
    func authorize(using: any AuthorizationInteraction, credentials: any CredentialStore) async throws -> Connection
    func reauthorize(_: Connection, using: any AuthorizationInteraction, credentials: any CredentialStore) async throws -> Connection
    func makeSource(for: Connection, credentials: any CredentialStore, syncState: any SyncStateStore) throws -> any CalendarSource
}
```

- `authorize` stores secrets only after sign-in fully succeeds, under a fresh `ConnectionID`; a failure leaves
  nothing stored.
- `reauthorize` keeps the `connectionID` (so `sourceID`, calendar keys and sync state stay valid), replaces the
  secrets, and throws `SourceError.invalidResponse` if the user signs in as a different account.
- `ConnectorRegistry` (`register`, `kind(id:)`, `kinds(for: Platform)` sorted by id) is the host's lookup.

Host-supplied seams:

```swift
public protocol CredentialStore: Sendable {   // keyed secrets per connection (Google: ["refresh_token": …])
    func secrets(for:) async throws -> [String: String]?
    func setSecrets(_:for:) async throws
    func removeSecrets(for:) async throws
}
public protocol SyncStateStore: Sendable {    // per-connection, per-scope tokens; absent = full sync
    func token(for:scope:) async -> String?
    func setToken(_:for:scope:) async
    func removeAll(for:) async
}
public protocol AuthorizationInteraction: Sendable {   // the only OS/UI-specific part of sign-in
    func beginOAuthRedirect() async throws -> any OAuthRedirectSession
    func promptCredentials(_ fields: [CredentialField]) async throws -> [String: String]
}
public protocol OAuthRedirectSession: Sendable {
    var redirectURI: URL { get }
    func authorize(at authorizationURL: URL) async throws -> URL   // opens the URL, waits, returns the redirect
    func close() async
}
```

Shipped implementations in `CalendarCore`: `InMemoryCredentialStore`, `InMemorySyncStateStore` (actors),
`FileConnectionStore` (JSON list of `Connection`; a missing file loads as empty, an unreadable file is never
overwritten and throws `FileStoreError.unreadable` on write), `FileSyncStateStore` (one JSON file; unreadable ⇒
"no tokens", so sources re-bootstrap).

### 3.6 Errors

```swift
public enum SourceError: Error, Sendable, Equatable {
    case authExpired                    // re-authorize
    case network(String)
    case rateLimited(retryAfter: TimeInterval?)
    case server(status: Int)
    case invalidResponse(String)
    case needsPermission                // OS/user has not granted access to a local store; never thrown by network connectors
}
```

Provider-specific outcomes (404, 410, per-calendar 403) are handled inside the connector and never escape as
provider types.

### 3.7 HTTP seam

`HTTPTransport.send(_:)` returns any HTTP response including 4xx/5xx and throws `SourceError.network` for
transport failures. `URLSessionTransport` is the default (`FoundationNetworking` on Linux); tests use
`FakeTransport`. `HTTPRequest` and `HTTPResponse` are plain value types (response header names are lowercased).

### 3.8 All-day helpers

`CalendarDate` (`year, month, day`, `adding(days:)`, `Comparable`) and `AllDay` (`startOfDay`, `date(of:in:)`,
`canonical(first:endExclusive:in:)`, `dates(start:end:in:)`, `endExclusive(afterLast:)`) are the only sanctioned way
to convert between provider all-day dates and the canonical instants.

## 4. `CalendarOAuth`

- `OAuthConfig`: authorization and token endpoints, client id, optional client secret (a desktop client's secret is
  not confidential but the token endpoint still requires it), scopes, extra authorization parameters.
- `OAuthClient(config:transport:now:)`: `authorizationURL(redirectURI:state:codeChallenge:)` (always PKCE `S256`),
  `authorizationCode(from:expectedState:)` (throws `AuthorizationError.stateMismatch`, `.cancelled` for
  `access_denied`, `.missingCode`), `exchange(code:verifier:redirectURI:)`, and `refresh(refreshToken:)`, which
  throws `SourceError.authExpired` on `invalid_grant`.
- `AccessTokenProvider` (actor): `accessToken()` returns a cached token or refreshes 60 s before expiry; concurrent
  callers share one in-flight refresh; a rotated refresh token is written back to the `CredentialStore` (re-reading
  first so other keys are not overwritten); `invalidate()` after a 401.
- `PKCE`: verifier generation and `challenge(for:hasher:)`. `SHA256Hashing` is a one-method protocol; the library
  ships `PureSwiftSHA256` (NIST-vector tested, used only on a public verifier) so `CalendarCore` and its dependents
  need no crypto package; hosts may inject `CryptoKitSHA256` (from `CalendarApple`) or their own.

## 5. `GoogleCalendar`

Public surface: `GoogleOAuthConfig(clientID:clientSecret:)`, `GoogleConnectorKind(config:transport:now:sleep:pollInterval:hasher:)`,
and the `CalendarSource` returned by `makeSource` (id `google-<connectionID>`).

- **Kind:** id `google`, display name "Google", all platforms, `.oauth`. Scopes
  `calendar.events` and `calendar.calendarlist.readonly` (the events scope already covers Phase 3 writes, so no
  re-consent is needed). Authorization requests `access_type=offline` and `prompt=consent` so a refresh token is issued.
- **Connection:** `displayName` and `config["email"]` are the primary calendar's id (lowercased); sign-in throws
  `invalidResponse` if no refresh token or no primary calendar comes back.
- **Reads:** `calendarList` (paged, `showHidden=false`, `minAccessRole=freeBusyReader`), then per calendar
  `events.list` with `singleEvents=true`, the requested window, paging and a restricted `fields` mask. All-day `date`
  values are converted to the canonical form. A calendar that returns 404 or a plain `forbidden` 403 is skipped.
- **Change detection:** one sync token per calendar plus a token for the set of calendars. Google forbids combining a
  sync token with a time window, so a token is bootstrapped from one minimal listing. A changed calendar set yields
  `.calendarsChanged`; changed events yield `.eventsChanged(calendarIDs:)`; HTTP 410 drops the token, re-bootstraps
  and reports a change.
- **HTTP behaviour:** 401 refreshes the token once, then `.authExpired`; 403 `insufficientPermissions` is
  `.authExpired`; 429 and rate-limit 403 retry up to three times honoring `Retry-After` (else jittered exponential
  backoff) and then throw `.rateLimited`; 5xx throws `.server`; anything else is `.invalidResponse`.
- **Capabilities:** `providesConference`, `.token` sync.

## 6. `CalendarApple` (macOS adapters)

| Type | Implements | Purpose |
|---|---|---|
| `KeychainCredentialStore(service:)` | `CredentialStore` | Secrets in the macOS Keychain |
| `LoopbackAuthorizationInteraction` | `AuthorizationInteraction` | OAuth through a 127.0.0.1 ephemeral-port listener; `openURL` and an optional `AuthorizationPresenting` are host-supplied; times out after 300 s; errors in `LoopbackError` |
| `WebAuthenticationSessionPresenter` | `AuthorizationPresenting` | Shows the sign-in page in an `ASWebAuthenticationSession` sheet that closes itself |
| `CryptoKitSHA256` | `SHA256Hashing` | Hardware-backed hashing for PKCE |

## 7. `EventKitSource`

- `EventKitSource` (`CalendarSource`, id `"eventkit"`, display name "Apple Calendar"): `requestAccess()` prompts for
  full calendar access; every read requires it and otherwise throws `.needsPermission`. Calendars map
  `allowsContentModifications` to `accessRole` `.writer` / `.reader` and EventKit's calendar types to `CalendarKind`.
  All-day events are normalised from EventKit's floating device-local dates to the canonical form in the device zone.
  `changes()` yields `.calendarsChanged` on every `EKEventStoreChanged`.
- `EventKitConnectorKind` (`.system` authorization, macOS only): `authorize` requests access and returns the
  synthesised `Connection` (`kindID: "eventkit"`, `connectionID: "this-mac"`); hosts do not persist it, and
  `makeSource` returns the shared source.
- Capabilities: no conference links, `.notification` sync, read-only until Phase 3.

## 8. `CalendarBridge` (TimeTug only)

Core defines its own `CalendarSource` (`calendars() -> [CalendarInfo]`, `events(in:) -> [TimeTugCalendarEvent]`,
`changes() -> AsyncStream<Void>`) and never sees library types.

- `ConnectedSource` wraps any library source. It maps calendars to `CalendarInfo`, events to `TimeTugCalendarEvent`
  (dropping cancelled ones), forwards every library change (including `.sourceFailed`) as a `Void` yield, and translates
  `needsPermission` and `authExpired` to Core's `SourceError`. Cancelling the consumer cancels the inner stream.
- `TimeTugCalendarEvent { event, sourceID, conferenceURL, otherAttendeeCount, responseStatus, merge state… }` carries the
  library event as is. Its `id` also appends the start time, because recurring events share a source event id but
  differ in start.

## 9. Rules for implementing a connector

1. Conform to `CalendarSource`; add `PollingCalendarSource` and use `ChangeMonitor` when the provider has a cheap
   incremental check.
2. Throw only `SourceError`; map provider errors inside the module.
3. Emit canonical all-day events and run your mapper fixtures through `AllDayConformance`.
4. Set `id` to `Connection.sourceID` (unless a documented compatibility reason applies) and keep it stable across
   `reauthorize`.
5. Declare `capabilities` honestly; `calendars()` must set `accessRole` per calendar.
6. Keep secrets in the injected `CredentialStore` and persist nothing during a failed `authorize`.
7. Test against `FakeTransport` (network) or pure mappers (local stores); no test may need a real account.

## 10. Proposed: write capabilities (Phase 3)

Status: **Proposed**. This part summarizes `docs/superpowers/specs/2026-09-23-calendar-connectors-phase3-design.md`,
which is authoritative for signatures and behavior; update this part when Phase 3 lands.

**Opt-in.** Writing is an optional, separate protocol. A read-only connector never implements it.

```swift
public protocol WritableCalendarSource: CalendarSource {
    func create(_ draft: EventDraft, in calendarID: String, notify: NotifyPolicy) async throws -> CalendarEvent
    func update(_ ref: EventRef, _ patch: EventPatch, scope: RecurrenceScope, notify: NotifyPolicy) async throws -> CalendarEvent
    func delete(_ ref: EventRef, scope: RecurrenceScope, notify: NotifyPolicy) async throws
    func respond(to ref: EventRef, _ response: ResponseStatus, scope: RecurrenceScope, notify: NotifyPolicy) async throws -> CalendarEvent
}
```

**Three levels of "can I write?"**
1. Conformance to `WritableCalendarSource` (checked by callers with `as?`). Invariant: `capabilities.canWrite` is true
   exactly when the source conforms; a conformance test enforces it.
2. `capabilities` gains `canWriteRecurrence`, `controlsNotifications` and `recurrenceScopes: Set<RecurrenceScope>`
   alongside the existing `canEditAttendees` and `canRespondToInvite`.
3. `CalendarDescriptor.accessRole` per calendar.

**Unsupported means an error, never a partial write.** A write that touches something the connector cannot represent
throws `WriteError.unsupported`, naming the fields.

```swift
public enum NotifyPolicy: Sendable { case all, externalOnly, none }        // required argument, no default
public enum RecurrenceScope: Sendable { case thisInstance, thisAndFollowing, allInSeries }  // ignored for non-series events
public enum EventField: Sendable, Hashable { case title, notes, location, timing, availability, visibility, reminders, attendees, recurrence, conference }
public enum WriteError: Error, Sendable, Equatable {
    case unsupported(fields: Set<EventField>), conflict(fields: Set<EventField>), notFound, forbidden(String?), invalid(String)
}   // forbidden = read-only calendar or no permission on the event; auth, network, rate-limit and 5xx stay SourceError
public struct EventRef: Hashable, Sendable {
    var calendarID: String; var eventID: String
    var version: String?; var seriesID: String?; var instanceStart: Date?
    init(_ event: CalendarEvent)
}
```

`CalendarEvent` gains an optional `sourceID`, stamped by the source that produced it, so an event can be routed to its
account without a host wrapper. `CalendarEvent.id` is unchanged.

**Models.**
- `EventDraft` (create): title, notes, location, start/end/timeZone/isAllDay in the canonical form, availability,
  visibility, reminders (`nil` = calendar defaults, empty = none), attendee drafts (`email`, `name?`, `role`),
  conference request (`none` or `generate`), optional `RecurrenceRule`. `EventDraft(copying: event, for: capabilities)`
  carries over what the target can represent and drops the rest (best-effort copy across calendars or accounts).
- `EventPatch` (update): each field is `FieldUpdate<T>` = `.keep` (default), `.set(value)` or `.clear`. Time is one unit
  (`EventTiming`: start, end, zone, all-day). Attendees are a delta (`AttendeeChanges(add:remove:)`), never a replacement
  list. `EventPatch(from: original, to: edited)` computes the minimal patch from two events and ignores provider-owned
  fields (`id`, `uid`, `organizer`, `status`, `url`, `seriesID`, `myResponse`, attendee responses).
- `EventEdit { let original: CalendarEvent; var event: CalendarEvent }` with `patch` and `hasChanges` for callers that
  want tracked edits.
- `RecurrenceRule`: frequency (daily/weekly/monthly/yearly), interval, weekdays with optional ordinal, month days,
  months, and end (`.never`, `.count(n)`, `.until(date)`), with `init(rrule:)` and `rruleString`. Anything outside this
  RFC 5545 subset throws `WriteError.unsupported`. EXDATE and RDATE are not authorable; removing one occurrence is a
  `delete` with `.thisInstance`.

**Conflicts.** A write sends `If-Match: original.version` where the provider supports it (Google etag) or compares
`lastModifiedDate` (EventKit). On a stale version the shared merge helper fetches the current event and compares only
the fields the patch touches against the original: if none differ, the patch is re-applied once on the fresh version;
otherwise it throws `WriteError.conflict(fields:)`.

**Provider mapping.**

| Operation | Google | EventKit |
|---|---|---|
| create | `POST …/events?sendUpdates=…` (`conferenceDataVersion=1` for a generated Meet link) | `EKEvent` save |
| update | `PATCH` of changed fields only, `If-Match`; attendee changes fetch the current event and send the full array | mutate and save |
| delete | `DELETE …?sendUpdates=…` | `remove` with span |
| respond | patch own attendee's `responseStatus` | `unsupported` |
| `.thisInstance` | instance id (own etag) | `.thisEvent` |
| `.allInSeries` | master id (its etag differs from the instance's, so the instance `version` cannot lock it) | first occurrence with `.futureEvents` (to be verified) |
| `.thisAndFollowing` | delete truncates the master's RRULE `UNTIL`; update truncates then inserts a new series (two calls, best-effort rollback) | `.futureEvents` |

EventKit's declared capabilities: writes yes, recurrence yes, all three scopes, attendee edits no, RSVP no, notification
control no (a `NotifyPolicy` of `.none` or `.externalOnly` throws `.unsupported` when the event has other attendees).

**Out of scope for Phase 3:** TimeTug write UI, cross-calendar link orchestration (kept in TimeTug's local store, not in
provider metadata; a `metadata` field and capability can be added later without breaking this API), Microsoft, CalDAV.

## 11. Known gaps

- **EventKit event ids.** The read model promises a per-instance `eventID`, but EventKit's `eventIdentifier` is, to our
  knowledge, shared by every occurrence of a series (TimeTug's wrapper id already appends the start time for this
  reason). To verify in the Phase 3 plan; writes need `EventRef.instanceStart` either way.
- **Reminder defaults.** A provider's "use default reminders" and "no reminders" both read as an empty list.
- **Google OAuth client in release builds.** The client id and secret are injected from git-ignored configuration; CI
  injection for release builds is a separate follow-up.
- **No CalDAV or Microsoft connector yet.** They are the next providers; their `AuthorizationMethod` cases (`.password`,
  `.oauth`) are already in the contract.
