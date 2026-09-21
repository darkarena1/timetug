# Calendar connectors, Phase 2.5: a minimal bridge

Status: draft for review. Phases 1 and 2 are merged (#16, #17, `ef212ec`). This phase shrinks `CalendarBridge` to what is genuinely TimeTug-specific, by letting `TimeTugCore` use the library's native event, times and all-day form directly.

## Goals

1. `TimeTugCore` depends on `CalendarCore` and uses the library's `CalendarEvent`, `Attendee` and `ResponseStatus` directly. No per-refresh conversion of times, dates or attendees.
2. `CalendarCore` and the whole `CalendarConnectors` package have no external dependencies, so `core-linux` (`swift:6.0`) keeps building Core.
3. All-day events are handled by calendar date, zone-aware, in Core's agenda, widget snapshot, popup rows and takeover policy.
4. The bridge keeps only: wrapping events with `sourceID`, dropping cancelled events, mapping `CalendarDescriptor` to `CalendarInfo`, and translating change and error types.

## Non-goals

- No change to persisted data: ledger and lesson keys of timed events, settings keys and the widget snapshot schema stay as they are (all-day keys may change for other-zone events; see the wrapper section).
- No write capabilities (Phase 3), no Microsoft (Phase 4), no injection of the Google OAuth client into CI builds (separate small PR).
- Core keeps its own `CalendarSource` protocol, `SourceError` and `SourceStatus`; it does not adopt the library's change stream.

## Decisions

- **All-day day membership is by calendar date** (chosen by the user). An all-day event belongs to the user's local day D when any date in `AllDay.dates(start:end:in: event.timeZone)` equals D. A Tokyo "Sep 21" event shows on Sep 21 for every viewer.
- **Wrapper with forwarding accessors** (chosen by the user), not explicit `.event.` access and not a generic side-table design.
- **Core adopts the library's value types** (`Attendee`, `ResponseStatus`) and keeps its own source seam.
- **Crypto behind a protocol** (proposed by the user): the library ships a pure-Swift SHA-256 default; a host may inject its own. This replaces swift-crypto.

## Packages and dependencies

`Packages/CalendarConnectors` stays one package with these products, no external dependencies, tools version 6.0:

| Product | Contents | Depends on |
|---|---|---|
| `CalendarCore` | model, `CalendarSource` and friends, `HTTPTransport`, `AllDay`, `Connection` and stores, `ChangeMonitor`, `CredentialStore` | nothing |
| `CalendarOAuth` (new) | `OAuthConfig`, `OAuthClient`, `OAuthTokens`, `AuthorizationError`, `AccessTokenProvider`, `PKCE`, `SHA256Hashing`, default SHA-256 | `CalendarCore` |
| `GoogleCalendar` | Google connector | `CalendarCore`, `CalendarOAuth` |
| `CalendarTestSupport` | fakes, `AllDayConformance` | `CalendarCore` |

`OAuth.swift`, `AccessTokenProvider.swift` and `PKCE.swift` move from `CalendarCore` to `CalendarOAuth`; they gain `import CalendarCore` (for `SourceError`, `HTTPRequest`, `HTTPResponse`, `HTTPTransport`) and `PKCE.swift` drops `import Crypto`. Their tests move to a new `CalendarOAuthTests` target depending on `CalendarOAuth`, `CalendarCore` and `CalendarTestSupport` (for `FakeTransport`). Only `GoogleCalendar` uses these types today. The `swift-crypto` dependency and its pin are removed from the manifest.

`SHA256Hashing` is `Sendable` with `func sha256(_ data: Data) -> Data`. `PKCE.challenge(for:hasher:)` takes a hasher defaulting to the built-in `PureSwiftSHA256`, and `GoogleConnectorKind.init` takes a `hasher` parameter with the same default and passes it to PKCE (`OAuthClient` itself never hashes). The default is checked against the NIST short-message vectors and the RFC 7636 appendix B example. `CalendarApple` adds a CryptoKit-backed `CryptoKitSHA256` (Apple platforms need no extra dependency); the app injects it. A Linux host can wrap swift-crypto itself. Randomness for verifiers and state stays `SystemRandomNumberGenerator`.

Dependency graph afterwards: `TimeTugCore -> CalendarCore`; `CalendarBridge -> TimeTugCore, CalendarCore`; `EventKitSource, CalendarApple -> CalendarCore` (`CalendarApple` also `CalendarOAuth`); `GoogleCalendar -> CalendarCore, CalendarOAuth`. The library still imports nothing from TimeTug.

## The event wrapper

`TimeTugCalendarEvent` becomes:

```
struct TimeTugCalendarEvent { var event: CalendarCore.CalendarEvent; var sourceID: String
    var additionalCalendarKeys, mergedMembers, mergeProvenance, displayStart }
```

- Forwarding accessors (get and set where Core mutates them): `title`, `start`, `end`, `isAllDay`, `timeZone`, `location`, `notes`, `url`, `calendarID`.
- Three fields stay stored and settable on the wrapper, initialised from the library event, because Core writes them after construction: `conferenceURL` (from `event.conference?.url`; `CalendarStore.makeSnapshot` fills it with `ConferenceLinkDetector` when nil, and `DuplicateResolver` sets the best link on merged events; the detector yields only a URL, not a `ConferenceProvider`), `otherAttendeeCount` (non-self attendee count) and `responseStatus` (`event.myResponse ?? self-attendee response`, an optional library `ResponseStatus`: `nil` replaces Core's `.unknown` and `needsAction` replaces `.pending`). The merge step raises the last two to the best value across a group. The library event is never modified.
- Computed from the library event: `sourceEventID` (`event.eventID`), `externalUID` (`event.uid`), `attendees` (non-self attendees) and `organizerEmail` (organizer's email unless self).
- `id`, `contentKey`, `calendarKey`, `allCalendarKeys`, `allContentKeys` and `isSameMeeting` keep their exact current formulas, computed from the forwarded `start`/`end`. For timed events the inputs are unchanged, so the takeover ledger and dedup lessons stay compatible (a test pins them). For all-day events the inputs are now the event's own canonical instants instead of the bridge's device-local midnights, so their keys change when the event's zone differs from the device's. This is accepted: all-day events never take over, and dedup never merges them (`DuplicateRules.decide` returns `.separate(.allDay)` for any pair involving one; only an exact `contentKey` match, which needs identical titles and instants, precedes that check). `start` and `end` for a merged event still follow today's merge rule (`start` is the tug time, `displayStart` the shown range).
- Core's `Attendee` and `ResponseStatus` are deleted. The library's `Attendee.init` already trims and lowercases, so `DuplicateRules.emails` drops its `normalizedEmail` step; connectors hand over plain addresses (`EventKitSource` already strips `mailto:` through its own `EventKitMapping.email(fromMailto:)`). `SourceError`, `SourceStatus` and Core's `CalendarSource` (wrapped events, `changes() -> AsyncStream<Void>`) stay, as does `CalendarInfo`.

## Bridge and all-day

- `ConnectedSource` wraps `event` with `sourceID`, drops `.cancelled` events, maps descriptors to `CalendarInfo`, and translates `SourceError` and the change stream exactly as it does now.
- `EventMapper` loses its interim all-day conversion and its attendee/response mapping; it reduces to the two mappings above.
- Core gains a small helper on the wrapper: `allDayDates` (first date and exclusive end date in the event's own zone) and `covers(_ date: CalendarDate)`. `DayAgenda.make`, `WidgetSnapshot` (all-day inclusion, computed with the passed-in `calendar`) and `CalendarStore` (the raw filter) use it; `DuplicateRules` is unchanged (it still excludes all-day events). `CalendarDate` gains `Comparable` in `CalendarCore` for these comparisons. The popup row model needs no change: it only labels all-day rows. `TakeoverPolicy` still returns false for all-day events.
- `DayAgenda` treats an all-day event as on day D by `covers`; timed events keep instant overlap. An all-day item's `state` also comes from dates: `.past` when its last covered date is before today, otherwise `.current`; it is never `.upcoming` (an all-day event covering tomorrow only is not on today's agenda), and `next` still ignores all-day events. Time is still passed in; Core never calls `Date()`.
- **Fetch window.** `CalendarStore.fetchWindow` and the raw filter are instant-based over one local day, so an all-day event in a zone more than a day away from the viewer could be missed. Sources are queried with the window widened by 26 hours (the largest zone spread) on each side, and the raw filter keeps timed events by the unchanged instant test and all-day events by `covers` for any date within the local window. `DayAgenda` and the widget still decide what is shown.
- `WidgetSnapshot` keeps its own DTO. For all-day events it emits local-midnight instants for the day range built once at snapshot time from the covered dates, so the snapshot schema and the widget code do not change.
- `EventKitSource` already stamps floating all-day events with the device zone and emits them canonically (`EventKitMapping.canonicalAllDay`), so it needs no change; it is re-read every refresh, so travelling never leaves stale zones.
- `AllDay.startOfDay(_:in:)` and `AllDay.dates` stay in the library; only the bridge's reverse conversion is deleted.

## Testing

Tests come first, per repo rule (Swift Testing in packages, XCTest in the app).

- `CalendarOAuthTests`: NIST SHA-256 vectors including empty, multi-block and one-million-`a` inputs; the RFC 7636 example verifier and challenge; an injected hasher is the one used; existing OAuth, token-refresh and PKCE tests move unchanged.
- Wrapper tests: forwarding and setters, the settable `conferenceURL`, computed fields, `id`, `contentKey` and `isSameMeeting` unchanged for timed events against fixed expected strings.
- All-day tests: Tokyo event for a US viewer, multi-day event, spring-forward-gap zone, local date rollover at midnight, in `DayAgenda`, `WidgetSnapshot` and the popup row model; an all-day event whose zone is more than 24 hours from the viewer's is fetched and shown on its own date; a Tokyo all-day event viewed in Los Angeles is `.current`, not `.past`, on that date; a floating EventKit all-day event passes `AllDayConformance`.
- Existing Core, dedup, takeover and app tests get mechanical updates; the bridge tests shrink to wrapping, cancelled filtering and change/error translation.
- Gate: `swift test` for every package, the app tests, and the persisted-key regression tests pass before the PR.

## Migration and compatibility

- No persisted format changes. The ledger and lesson keys derive from the unchanged `contentKey`/`id` formulas; a test pins them.
- Call sites that change with the type move, to list in the plan: `CalendarStore.makeSnapshot` and `DuplicateResolver` (`conferenceURL` writes), `DuplicateRules.emails` (`normalizedEmail`), `EventKitSource` (library attendees), the app's popup row model, coordinator and tests, and the widget target (Core now links `CalendarCore`; check `Apps/macOS/project.yml` for both the app and `TimeTugWidgets` targets).
- The work is one PR from `claude/calendar-phase2-5-slim-bridge` off up-to-date `master`, in small commits: (1) `CalendarOAuth` split and hasher, dependency removal; (2) Core depends on `CalendarCore`, wrapper and value-type adoption; (3) zone-aware all-day and EventKit stamping; (4) bridge shrink; (5) CI, ADR and docs.

## CI and docs

- `core-linux` (`swift:6.0`) tests `TimeTugCore` and `CalendarConnectors`; `connectors-linux` (`swift:6.2`) is removed once that passes, or kept only if it still adds coverage.
- ADR 0012 gets a Phase 2.5 section (supersedes the Phase 2 note that Core cannot depend on the library, and records the crypto seam). `AGENTS.md`, `docs/architecture.md` and the CI comments are updated.

## Risks

- Swift 6 concurrency: `SHA256Hashing` and `PureSwiftSHA256` must be `Sendable`; the wrapper stays a value type.
- The wrapper's forwarding setters must not change merge behavior; the dedup and store tests pin it.
- A pure-Swift SHA-256 must be correct: the vector tests guard it, and its only use is a public PKCE challenge.
