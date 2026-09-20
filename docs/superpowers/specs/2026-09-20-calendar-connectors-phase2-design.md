# Calendar connectors, Phase 2: plug the library into TimeTug

Status: draft for review. Phase 1 (the portable `Packages/CalendarConnectors` library with a read-only Google connector) is merged (#16, `51f9a6d`). This phase makes TimeTug use it: Google accounts appear in Settings, their calendars feed the same store and dedup as Apple Calendar, and EventKit itself moves onto the library's abstraction. Roadmap and earlier decisions: `docs/superpowers/specs/2026-09-20-calendar-connectors-phase1-design.md` and ADR `docs/decisions/0012-calendar-connector-library.md`.

## Goals

1. Add and remove Google Calendar accounts from a new **Accounts** tab in Settings (standard `+` / `−`, several accounts of one kind allowed).
2. Apple Calendar (EventKit) stays available, appears as one pinned row in the same tab with an enable checkbox, and is built on the library's `CalendarSource` / `ConnectorKind` abstraction like every other source.
3. The Calendars tab lists calendars from every enabled account; removing an account also removes that account's Tug and visibility selections, which live in Core's `TakeoverSettings`.
4. Google data refreshes through the library's sync-token polling; changes reach the menu bar within about a minute.

## Non-goals

Write support (Phase 3), Microsoft (Phase 4), CalDAV/iCloud-direct, webhook push, iOS, any UI beyond the Accounts pane and the existing Calendars tab. Shipping a Google OAuth client inside release builds is a separate follow-up (see "OAuth client configuration").

## Global constraints

- `TimeTugCore` stays pure Swift 6 with no Apple-only imports and **no dependency on `CalendarConnectors`** (swift-crypto needs Swift 6.2, which would break the `core-linux` job on `swift:6.0`).
- `CalendarCore` and `GoogleCalendar` stay free of Apple-only imports; the only library API change is adding one error case (below).
- `EventKitSource` and the app remain Swift 5 language mode; `CalendarBridge` is Swift 6 mode (it depends on `TimeTugCore`).
- Stored calendar selections are `sourceID/calendarID` strings and must keep working: EventKit's source id stays `"eventkit"`.
- New `Codable` fields use `decodeIfPresent` with defaults. Every Core/bridge behavior gets a Swift Testing test first; app tests are XCTest.
- All-day events are dates: connectors emit the library's canonical form, the bridge alone converts to TimeTug's device-local form, and no other code compensates for provider or zone differences.
- No secrets in the repository: OAuth client values come from a git-ignored xcconfig; user credentials live only in the Keychain.
- Merges to `master` ship a beta build, so the work lands only through a pull request with CI green.

## Architecture

```
TimeTugCore (pure)            CalendarCore / GoogleCalendar (portable library)
   CalendarSource (Void)  <---  CalendarBridge  --->  CalendarSource (CalendarChange)
   TimeTugCalendarEvent          mapper + adapter       CalendarEvent, CalendarDescriptor
        ^                              ^                          ^
        |                              |                          |
     CalendarStore            Apps/macOS (composition root)   EventKitSource (Mac-only kind + source)
                                AccountStore, Keychain, OAuth loopback, reconciler, Accounts pane
```

**New package `Packages/CalendarBridge`** (Swift 6, depends on `TimeTugCore` and the library's `CalendarCore`). It is the only code that knows both vocabularies:

- `EventMapper`: library `CalendarEvent` to `TimeTugCalendarEvent`; library `CalendarDescriptor` to Core `CalendarInfo`.
- `ConnectedSource`: wraps `any CalendarCore.CalendarSource` and conforms to Core's `CalendarSource`. It translates errors and the change stream (below).

`EventKitSource` drops its dependency on `TimeTugCore` and depends on `CalendarCore` instead.

## Step 0: rename (first commit, mechanical)

Rename TimeTug's `CalendarEvent` to `TimeTugCalendarEvent` (about 120 references in ~38 files across `TimeTugCore`, `EventKitSource`, `AppleIntelligenceInference`, `Apps/macOS`, `docs/` and `AGENTS.md`). Move the type from `Model/CalendarEvent.swift` to `Model/TimeTugCalendarEvent.swift`, leaving `CalendarInfo` and `ResponseStatus` in place. The type is not `Codable`, so no persisted data changes. The commit changes names only; the existing Core and app test suites must pass unchanged except for the name.

## TimeTugCore changes

- `CalendarStore.setSources(_ sources: [any CalendarSource])` replaces the fixed `sources` array with mutable state. Sources that disappear drop their cached events, calendars and status. `refresh` and `makeSnapshot` read the current set; `sourceNames` come from it. `init(sources:)` stays for tests and startup. `CalendarStore` is a reentrant actor, so `setSources` can run while a `refresh` is suspended in its task group. `setSources` therefore bumps a generation counter, and `refresh` discards the results of any source that is no longer in the current set (or whose generation changed) instead of writing them back. `makeSnapshot` also filters `statuses` to the current sources, so a removed or disabled source never leaves a ghost status or stale events behind (an EventKit toggle off and on again starts empty until its next refresh).
- `TakeoverSettings.removeCalendars(forSourceID:)` removes every entry of `takeoverCalendarKeys` and `hiddenCalendarKeys` that starts with `"<sourceID>/"`. The prefix includes the slash so `google-1` never matches `google-10`. Tests come first.

## Library change

Add `SourceError.needsPermission` to `CalendarCore`: the OS or user has not granted access to a local data store (EventKit). It is a new case in an existing enum; no existing behavior changes, and Google never throws it. `GoogleCalendar` tests are unaffected.

## EventKit as a connector

`EventKitSource` (still one class, still `EKEventStore` inside) conforms to the library's `CalendarSource`:

- `id` is the constant `"eventkit"`, because existing stored keys begin with `eventkit/` and EventKit is a singleton. This deliberately differs from `Connection.sourceID` (which would be `eventkit-this-mac`). To keep one rule for all kinds, **the app and the reconciler identify every source by the built source's `id`, never by computing `Connection.sourceID`**; for Google the two are identical (a test asserts it), for EventKit only `source.id` is used. The exception is documented at the definition.
- `calendars()` returns `CalendarDescriptor` (id = `calendarIdentifier`, title, sRGB hex color, `accountName` = the owning macOS account title).
- `events(in:)` returns library `CalendarEvent`: `eventID` = `eventIdentifier ?? calendarItemIdentifier`; `uid` = `calendarItemExternalIdentifier`; attendees carry `isSelf` (from `isCurrentUser`), `response`, name, and email from the `mailto:` URL; `organizer` likewise; `myResponse` from the current user's participant status; timed events pass `startDate`/`endDate` through; **all-day events are normalized to the library's canonical form** (see "All-day events" below). `title` keeps today's rule, `event.title ?? "(No title)"`: only nil is substituted, so an empty title stays empty and stored merge and separation decisions (which are keyed by `contentKey`) keep matching.
- `capabilities`: read-only, `syncKind: .notification`, no conference detection (TimeTug's `ConferenceLinkDetector` continues to run in the store).
- `changes()` yields `.calendarsChanged` on `EKEventStoreChanged`, which the library defines as "reload calendars and events".
- Missing access throws `SourceError.needsPermission`.

`EventKitConnectorKind: ConnectorKind` (`id: "eventkit"`, `supportedPlatforms: .macOS`, `authorization: .system`):

- `authorize` calls `requestFullAccessToEvents()` and throws `needsPermission` when denied; it never uses the `AuthorizationInteraction` or the `CredentialStore`. It returns a synthesized `Connection(kindID: "eventkit", connectionID: "this-mac", displayName: "Apple Calendar")`, which the app does not persist (EventKit is a setting, not an account).
- `reauthorize` behaves as `authorize`. When access was previously denied, macOS will not prompt again, so the UI offers "Open System Settings" instead.
- `makeSource` returns the `EventKitSource`.

## All-day events: one form per layer

An all-day event is a run of calendar *dates*, not instants, and providers encode it differently. To keep TimeTug's main path (day bucketing, "skip all-day", widgets, the popup) identical for every source, each layer has exactly one form and conversion happens only at the boundaries:

1. **Native** (provider-specific): Google sends `date` strings and the calendar's time zone; EventKit sends floating device-local dates with an `endDate` that is typically the last day's end (23:59:59), not the next midnight; other providers will differ again.
2. **Canonical** (the library contract, already in Phase 1): `start` is midnight of the first day **in `timeZone`**, `end` is midnight after the last day (exclusive), `timeZone` is non-nil. Every connector's job is to map its native form into this, so nothing above the connector needs to know provider quirks.
3. **TimeTug native** (`TimeTugCalendarEvent`, documented on the type): `start` is the **device-local** midnight of the first day, `end` the device-local midnight after the last day (exclusive). All-day events in TimeTug are dates in the user's own calendar, so they fall on the same day the user sees in their calendar app, regardless of the source's zone.

Conversions:

- **Connector, native to canonical.** Google already does this (`GoogleEventMapper`: `date` parsed in the calendar's zone, exclusive end). The EventKit connector treats EventKit's all-day dates as floating: it takes the device-local calendar days of `startDate` and of the last covered day, and emits canonical instants with `timeZone = .current`. The last covered day is the day of `endDate`, except when `endDate` is exactly a local midnight after `startDate` (already exclusive); a zero-length event (`end <= start`) covers one day. `EKEvent.timeZone` is ignored for all-day events (floating semantics).
- **Bridge, canonical to TimeTug native.** `EventMapper` reads the year, month and day of `start` and of `end` in the event's `timeZone`, and rebuilds midnight instants of those same dates in the injected device `Calendar` (default `.current`, the same calendar `CalendarStore` uses). The rebuild uses the start of day of that date so a zone whose midnight does not exist on a DST day still yields a valid instant. When `timeZone` equals the device zone this is the identity, so the common case is unchanged.

Consequences to accept: existing EventKit all-day events change `end` from about 23:59:59 to the next midnight. All-day events never take part in duplicate merging (the `.allDay` rule) and never trigger a takeover, and `DayAgenda` selects by overlap, so behavior is unchanged; a test pins that. Multi-day all-day events keep appearing on every covered day.

## Bridge behavior

**Mapping** (`TimeTugCalendarEvent`), the same for every source so Google and Apple events dedup against each other:

| TimeTug field | From library event |
|---|---|
| `sourceEventID`, `calendarID`, `title` | `eventID`, `calendarID`, `title` unchanged (each source decides its own placeholder; the bridge never rewrites titles, so `contentKey` is stable) |
| `sourceID` | the source's `id` |
| `start`, `end` | timed events: same instants. All-day events: converted to TimeTug's native all-day form (see "All-day events") |
| `isAllDay` | same |
| `responseStatus` | `myResponse`, else the self attendee's `response`; `needsAction` becomes `.pending`; none becomes `.unknown` |
| `attendees` | non-self attendees as TimeTug `Attendee(name:email:)` |
| `otherAttendeeCount` | count of non-self attendees |
| `organizerEmail` | organizer's email unless the organizer is self |
| `externalUID` | `uid` |
| `conferenceURL` | `conference?.url` (else the store's link detector runs as today) |
| `location`, `notes`, `url` | same |

Events with `status == .cancelled` are dropped. The library's `Attendee` and `ResponseStatus` share names with Core's, so the mapper qualifies them (`CalendarCore.Attendee`). `CalendarDescriptor` to `CalendarInfo`: `sourceID` = the source id, `calendarID` = `id`, plus title, `accountName`, `colorHex`.

**Errors.** `ConnectedSource` throws Core's `SourceError.needsPermission` for the library's `needsPermission` and `SourceError.authExpired` for `authExpired`; anything else propagates and `CalendarStore` records it as `.failing`.

**Changes.** `changes()` maps the library stream to Core's `AsyncStream<Void>`: every `CalendarChange` yields once. `.sourceFailed` also yields, so the next refresh surfaces the failure status ("Sign in again") instead of leaving stale data quietly. Cancelling the consumer ends the library stream.

## App (Apps/macOS)

**Persistence and platform services**

- `AccountStore`: an actor holding `[Connection]` in `accounts.json` under Application Support, injectable file URL and atomic writes, following `LedgerStore` conventions. EventKit is never stored here.
- `KeychainCredentialStore: CredentialStore`: `kSecClassGenericPassword`, service `com.timetug.app.credentials` (injectable for tests), account = `connectionID`, value = JSON of the secrets map.
- `FileSyncStateStore: SyncStateStore`: an actor over `sync-state.json` in Application Support, injectable URL, atomic writes. A missing or unreadable file means "no tokens", so the library does a full bootstrap.
- `OAuthInteraction: AuthorizationInteraction`: `beginOAuthRedirect()` starts an `NWListener` on `127.0.0.1` with an ephemeral port and returns a session whose `redirectURI` is `http://127.0.0.1:<port>`; `authorize(at:)` opens the URL with `NSWorkspace`, answers the first request with a small "You can close this window" page, and returns the received URL; it times out after 5 minutes and `close()` cancels the listener. `promptCredentials` throws (unused until CalDAV). The app has no sandbox entitlement, so the listener and Keychain need no new entitlements.
- `ConnectorRegistry` is built at launch with `GoogleConnectorKind` (when a client is configured) and `EventKitConnectorKind`.

**Reconciler.** A testable type, `SourceReconciler`, owns "which sources exist": given the persisted connections, the EventKit enabled flag and the registry, it builds a `[String: ConnectedSource]` keyed by source id, diffs against the running set, and reports additions and removals. `AppCoordinator` calls it at launch and after any account or toggle change, then calls `store.setSources(_:)`, starts a change-listening task for each added source (each `for await _ in source.changes() { await refresh() }`) and cancels the tasks of removed sources. The existing periodic refresh remains. The old direct EventKit access request and `eventKit.changes()` loop are replaced by this path. A failing `makeSource` for one account leaves it out of the set and records a status for the pane instead of stopping the others. `SourceReconciler` also has `rebuild(sourceID:)`, used after a successful re-sign-in: it builds a fresh source for the same id, replaces the old instance in the running set, and restarts that source's listener task. This is required because the library ends a source's change stream after `.sourceFailed` (expired auth), so a rebuilt source with an unchanged id would otherwise never poll again. The reconciler tracks source instances, not just ids, and a test covers "expired auth, re-sign-in, edits arrive again".

**Settings**

- `SettingsPane.accounts` (after General; icon `person.crop.circle`; also indexed in `SettingsSearch`).
- `AccountsPane` and a small view model. A list with a pinned first row "Apple Calendar (this Mac)" and an enable checkbox (not removable); then one row per Google account with its email, status (connected; "Sign in again"; error text) and, for permission problems, an "Open System Settings" link. Below the list, the standard `+` and `−` controls.
  - `+` lists the registered, platform-valid connector kinds excluding `.system` ones (just Google now; `AuthorizationMethod` is not `Equatable`, so test with `if case .system = kind.authorization`). Selecting Google runs `authorize` in a task, shows "Waiting for browser..." with Cancel, then persists the `Connection` and reconciles. Signing in as an account that is already added (same kind and display name) is rejected with a message.
  - `−` (never available for the EventKit row) asks: "Remove <email>? Its calendars will no longer appear and their Tug and visibility choices are forgotten." On confirm, in this order, so an interruption never leaves a half-removed account that looks alive: (1) stop and remove the source; (2) delete the stored `Connection` (the record that the account exists); (3) call `removeCalendars(forSourceID:)` on the persisted settings; (4) best-effort delete its Keychain secrets and sync state, reporting a Keychain failure without undoing the removal. Every step is idempotent, so repeating `−` after a crash or error is safe. As a backstop, launch runs an orphan sweep: it drops stored selection keys whose source id belongs to an account-based kind (`google-...`) but matches no stored connection. The sweep is skipped when `accounts.json` could not be read (a corrupt file must not wipe selections) and never touches `eventkit/...` keys. EventKit never goes through `removeCalendars`: the checkbox only changes the enabled flag.
  - "Sign in again" runs `reauthorize` (same `connectionID`, so selections and sync state survive) and calls `reconciler.rebuild(sourceID:)`.
  - The EventKit checkbox is persisted as `eventKitEnabled.v1` in `SettingsStore` (default `true`, so existing users see no change). Turning it off removes the source and hides its calendars but **keeps** their stored selections, so turning it back on is lossless; it does not revoke the system permission. Turning it on runs `authorize` (prompting if undetermined).
- The Calendars tab needs no structural change: it groups by `accountName`, so Google calendars appear under the account's email and disabled or removed sources contribute nothing.

## OAuth client configuration

The Google Desktop OAuth client ID and secret are read from `Info.plist` keys filled by a git-ignored `Apps/macOS/Config/GoogleOAuth.xcconfig` (optionally included, following the `Local.xcconfig` pattern). When they are absent (CI, fresh checkouts), Google is not registered and the `+` menu has no Google entry; everything else works, so CI and beta builds are unaffected. The Desktop-client "secret" is not confidential but is still kept out of source control. Live testing needs the Google Cloud project described in ADR 0012 (Calendar API enabled; sensitive scopes, so in Testing mode only listed test users, with 7-day refresh tokens; public release needs Google's OAuth verification). **Open item for after this phase:** how release and beta workflows receive the client values (GitHub secrets into the build).

## Testing

- **Core (Swift Testing):** `setSources` add/remove drops cache, statuses and names, including a `setSources` that runs while a `refresh` is suspended (a fake source that blocks) so nothing is written back and no ghost status remains; `removeCalendars(forSourceID:)` including the `google-1` / `google-10` prefix case and untouched other sources.
- **Bridge (Swift Testing, fake library source):** mapper table above (all-day in the device zone is the identity; all-day from a calendar in another zone, for example Tokyo events on a New York device and the reverse, lands on the same dates locally; multi-day; a DST-day zone; self/other attendees, organizer-is-self, response fallback and `needsAction`, cancelled dropped, titles passed through unchanged including empty, conference URL); adapter error translation; change-stream mapping including `.sourceFailed`; cancellation ends the stream. A parity fixture checks that an EventKit-shaped event and a Google-shaped event for the same meeting map to values the existing dedup treats as one meeting (same `externalUID`, title and times).
- **EventKitSource:** the pure helpers (participant status to response, color to hex, and the all-day normalization taking plain dates and a calendar: one-day event ending 23:59:59, multi-day ending 23:59:59, end already at midnight, zero-length, DST day) get Swift Testing tests; the package must still build. The `EKEventStore` paths are covered by the manual checklist.
- **Library:** one test for `needsPermission`; the 81 existing tests keep passing.
- **App (XCTest):** `AccountStore` round trip, missing and corrupt file; `FileSyncStateStore`; `KeychainCredentialStore` with a per-run unique service name and cleanup; `SourceReconciler` add, remove, EventKit toggle, failing `makeSource`, `rebuild` restarting the listener, and identical keying by `source.id` for Google; removal order and idempotence with a store that throws at each step; the launch orphan sweep (including the unreadable-file and `eventkit/` cases); Accounts view-model add/remove/duplicate/re-sign-in using a fake `ConnectorKind` and interaction.
- **Manual (`docs/manual-tests/macos-checklist.md`, needs the Google client):** add a Google account (calendars appear under the email); add a second; toggle EventKit off and on (calendars hide and return, selections intact); `−` an account (calendars and Tug choices vanish, Keychain item gone); relaunch reconnects silently; revoke access on the Google account page and see "Sign in again", then fix it in place; edit an event in Google and see it in the menu bar within about a minute; deny Calendar access in System Settings and see the EventKit row explain it; the same meeting via both EventKit and direct Google merges into one.
- **CI:** the `core` job also runs `swift test` for `CalendarBridge` and builds `EventKitSource`; the `app` job builds and tests the app with the new package references in `project.yml`. `core-linux` is unchanged (Core does not depend on the library).

## Risks

- **Duplicate meetings.** A Google calendar also added in macOS appears twice. The existing dedup should merge them through `externalUID` (`iCalUID` vs `calendarItemExternalIdentifier`); the parity test and manual check cover it, and users can turn EventKit off.
- **EventKit regression.** The conversion touches a working source. The mapping rules are unchanged, pure pieces are tested, and the manual checklist exercises permission grant, denial and live edits.
- **Token expiry in Testing mode.** Google refresh tokens last 7 days for unverified apps, so test accounts will show "Sign in again" weekly until the app is verified.
- **Loopback listener.** A firewall prompt or a blocked port fails the sign-in with a clear error and Cancel; the listener always closes.

## Commit sequence (one PR)

1. Rename `CalendarEvent` to `TimeTugCalendarEvent` (mechanical).
2. Core: `setSources`, `removeCalendars(forSourceID:)`.
3. Library: `SourceError.needsPermission`.
4. `CalendarBridge` package (mapper, adapter) with tests.
5. `EventKitSource` conversion and `EventKitConnectorKind`.
6. App services: `AccountStore`, Keychain, sync state, `OAuthInteraction`, OAuth config plumbing.
7. `SourceReconciler` and `AppCoordinator` wiring.
8. Accounts pane, `SettingsPane.accounts`, search entries, view model.
9. Docs: ADR 0012 update, `architecture.md`, `AGENTS.md` (layout, test commands, CI), manual checklist.
