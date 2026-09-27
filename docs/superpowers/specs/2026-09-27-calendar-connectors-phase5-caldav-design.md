# Calendar connectors, Phase 5: CalDAV and iCloud connector

Status: design approved in brainstorming (2026-09-27); not yet implemented. Phases 1 to 4 are merged (#16, #17, #18, #32, #38, #40). This phase adds a generic CalDAV connector to the connector library, with iCloud as a preset, at full parity with Google and Microsoft (read, change detection, writes, RSVP, series), and plugs it into TimeTug's Accounts tab. The API contract is in `docs/calendar-connectors-api.md`; part 11 lists "No CalDAV connector yet", which this phase closes. ADR 0012 already chose CalDAV for iCloud because, unlike EventKit, it can invite and RSVP (RFC 6638 server-side scheduling).

## Goals

1. Sign in to iCloud with an Apple ID and an app-specific password, and to any other CalDAV server (Fastmail, Nextcloud, ...) with a server URL, username and password, and read their calendars and events like any other source.
2. Poll for changes cheaply with `sync-collection` (RFC 6578), falling back to `getctag`.
3. Write: create, update, delete, respond to invites, with all three recurrence scopes and attendees, through the Phase 3 `WritableCalendarSource` API.
4. Read a series' recurrence rules (`SeriesSource`).
5. Keep the library layering rule: every new target is pure Swift with no external dependencies and builds on Linux; OS-specific code stays in `CalendarApple` and the app.

## Non-goals

- No webhook or push (CalDAV has none that is portable; polling was chosen for every provider).
- No conference link generation (CalDAV has no such service). Links in events are still detected by `ConferenceDetector`.
- No VTODO (reminders lists), no VJOURNAL, no free/busy queries, no calendar sharing or creation of calendars.
- No moving events between calendars, no attachments (`ATTACH` is preserved on round-trip, not modeled).
- No server-side expansion (`<C:expand>`); expansion is client-side (see Decisions).
- No ICS subscription connector (the `ICalendar` product makes one cheap later).
- No control over scheduling emails in this phase (`controlsNotifications = false`, see Writes).

## Decisions

Made with the user during brainstorming:

- **Generic CalDAV with an iCloud preset**, one implementation. Two `ConnectorKind`s so the "+" menu shows "iCloud" and "Other CalDAV" as separate entries.
- **Full parity with Google and Microsoft in one phase.**
- **Client-side engine (approach A):** a reusable iCalendar codec, a recurrence expander in `CalendarCore`, and a WebDAV client. Rejected: server-side `<C:expand>` (uneven server support, and expanded results lose the master and rule that `SeriesSource` and splits need, so both paths would be needed); iCloud through EventKit only (not portable, no invite/RSVP).
- **`ICalendar` is its own library product**, reusable by a future ICS subscription connector and by library users.
- **Generic credential sheet** in the app, built from the kind's `[CredentialField]`, reusable by any password connector.
- **`controlsNotifications = false`** until the live test shows iCloud honors `SCHEDULE-AGENT=CLIENT`; emailing someone when the caller asked for no email is the failure to avoid.
- **Optimistic locking with real ETags:** every write is a whole-resource PUT with `If-Match`; a 412 re-reads and runs `PatchMerge` per field.

## Placement

| Package / target | New or changed |
|---|---|
| `CalendarCore` | `RecurrenceSet.occurrences(of:in:limit:)` (the expander), `CalendarService.calDAV` (one static constant), the optional `CredentialPromptHelp` protocol (see Sign-in), and `WindowsTimeZones` moved here from `MicrosoftCalendar` (see `VTIMEZONE`) |
| `CalendarConnectors` → `Sources/ICalendar` (new target and library product; depends only on `CalendarCore`) | content-line parser and writer, component tree (`ICalendarComponent`, `ICalendarProperty`), `VTIMEZONE` resolver, `VEVENT` ↔ `CalendarEvent` mapper, `VALARM` ↔ `Reminder` mapper, patch applier that edits a component tree in place |
| `CalendarConnectors` → `Sources/CalDAVCalendar` (new target and library product; depends on `CalendarCore` and `ICalendar`; `FoundationXML` on Linux) | `WebDAVClient`, `DAVXML` (multistatus parsing and request bodies), `CalDAVDiscovery`, `CalDAVConnectorKind`, `ICloudConnectorKind`, `CalDAVAccount` (shared config), `CalDAVCalendarSource` (`+Sync`, `+Write`, `+Split`, `+Series`) |
| `CalendarConnectors` → `Tests` | `ICalendarTests`, recurrence expander tests in `CalendarCoreTests`, `CalDAVCalendarTests` with an in-memory fake CalDAV server behind `FakeTransport` |
| `CalendarTestSupport` | reused as is (`WritableSourceConformance`, `AllDayConformance`, `ProvidedFieldsConformance`) |
| `CalendarApple` | iCloud live smoke test only (credentials go through the existing Keychain `CredentialStore`) |
| App (`Apps/macOS`) | `CredentialSheet` (SwiftUI), the retry loop in `AccountsController`, both kinds registered in `AppConnectors.makeRegistry`, Settings search keywords |

The two kinds share `CalDAVAccount` and `CalDAVCalendarSource`; they differ only in fields, server URL, display name and provider.

| | `ICloudConnectorKind` | `CalDAVConnectorKind` |
|---|---|---|
| id | `icloud` | `caldav` |
| display name | "iCloud" | "Other CalDAV" |
| platforms | all | all |
| authorization | `.password(fields: [appleID, appPassword(secret)])` | `.password(fields: [serverURL, username, password(secret)])` |
| server | fixed `https://caldav.icloud.com` | entered by the user |
| calendar `provider` | `.iCloud` | `.calDAV` |
| calendar `service` | `.calDAV` | `.calDAV` |

## Sign-in

- `authorize(using:credentials:)` calls `interaction.promptCredentials(fields)`, trims whitespace from non-secret fields, and runs discovery with the result. Nothing is stored until discovery succeeds.
- **Discovery:** `PROPFIND` on `<server>/.well-known/caldav` (RFC 6764), following redirects under the rules in Security; then `PROPFIND current-user-principal`; then `PROPFIND calendar-home-set` and `calendar-user-address-set` on the principal. If `.well-known` is missing (404), the server URL itself is tried as the context path. A 401 at any step is `SourceError.authExpired`.
- **Connection:** `connectionID` is a new UUID. `displayName` is the Apple ID for iCloud and `username@host` otherwise. `config` holds `serverURL`, `principalURL` and `homeURL`. The Keychain entry holds the username and the password under the keys `username` and `password`.
- **Reauthorize:** prompts again with the non-secret fields prefilled from `config` (see App wiring), runs discovery, and throws `SourceError.invalidResponse` if the principal URL differs (a different account); otherwise replaces the stored secrets and keeps the `connectionID`.
- **Help text:** kinds may adopt a small optional protocol `CredentialPromptHelp` (in `CalendarCore`: `var credentialHelp: (text: String, url: URL?)? { get }`) so the sheet can explain app-specific passwords and link to Apple's page. The iCloud kind adopts it; `AuthorizationMethod` and `CredentialField` are unchanged.

## Security

- Basic auth is sent only over HTTPS. For "Other CalDAV" an `http://` server URL is refused at sign-in, except `localhost` and `127.0.0.1` (local test servers).
- Credentials are sent only to the configured server's host or its subdomains (iCloud moves an account to a partition host such as `pNN-caldav.icloud.com`, a subdomain of `icloud.com`; the allowed suffix for iCloud is `icloud.com`). `WebDAVClient` follows redirects itself (up to 5) and attaches credentials per request; a redirect or an `href` that resolves to any other host is `SourceError.invalidResponse`, never followed with the password.
- The password is never logged. Request logs leave out the `Authorization` header; response bodies are logged only at debug level and never include request headers.

## Reads

### Calendars

`PROPFIND` depth 1 on the calendar home for `resourcetype`, `displayname`, `supported-calendar-component-set`, `current-user-privilege-set`, `calendar-timezone`, `apple:calendar-color`, `getctag`, `sync-token`, and `schedule-default-calendar-URL` on the principal.

- Kept: collections whose resource type includes `calendar` and whose component set includes `VEVENT` (a missing set means all components). Skipped: VTODO-only lists, the scheduling inbox and outbox, iCloud notification collections.
- `id`: the collection path relative to the home URL (stable across partition-host moves).
- `title` from `displayname` (falling back to the last path segment); colour from `apple:calendar-color` (`#RRGGBBAA` trimmed to `#RRGGBB`).
- `permissions`: `canEdit` = `write` or `write-content` privilege; `canViewDetails` = `read` privilege (a `read-free-busy`-only calendar is `false`); `canShare` and `canViewPrivate` are filled (`false` unless the privilege set says otherwise) so `permissionDetails` holds.
- `timeZone` from `calendar-timezone` through the `VTIMEZONE` resolver.
- `isDefault`: true for the collection named by `schedule-default-calendar-URL`, false for the rest, nil when the server does not say.
- `kind`: `.subscribed` for iCloud subscribed collections (`calendarserver:subscribed` resource type), `.standard` otherwise.
- `accountName`: the connection's display name. `service = .calDAV`; `provider` per kind.

### Events

`REPORT calendar-query` per visible calendar with a `time-range` filter on `VEVENT` over the requested interval, asking for `getetag` and `calendar-data`. One resource holds one `UID`: a master (with `RRULE`/`RDATE`/`EXDATE`, or none) plus zero or more overrides carrying `RECURRENCE-ID`. A resource with overrides but no master (an invite to single occurrences) is valid; each override is shown on its own.

**Identity**
- `seriesID` = the resource name (last path segment, e.g. `4F2A….ics`) for a recurring resource; nil otherwise.
- `eventID` = the resource name for a non-recurring event; for an occurrence, the resource name + `#` + the original start in UTC basic format (`20260927T150000Z`; all-day: `20260927`).
- `uid` = `UID`, `uidScope = .global`, so the existing duplicate merge matches iCloud-via-CalDAV with iCloud-via-EventKit and with copies in Google or Microsoft.
- `version` = the resource ETag (shared by every occurrence of a resource; every write is a whole-resource PUT, so this is the right lock).
- `series = .occurrence(seriesID:originalStart:)` for occurrences.

**Expansion** (`RecurrenceSet.occurrences(of:in:limit:)`)
- Expands `RRULE` (every frequency and BY-part the parser accepts, `COUNT`, `UNTIL`, `WKST`, `BYSETPOS`), adds `RDATE`, removes `EXDATE`, in the master's own time zone on wall-clock time so DST shifts are correct; all-day by calendar date.
- An override replaces the occurrence whose original start equals its `RECURRENCE-ID`; an override moved into the window from outside is included because the whole resource is returned whenever any instance overlaps. The query window gets the same margin `CalendarStore` already applies.
- A hard limit (default 5000 instances per resource per query) stops runaway rules; hitting it logs once and returns what was expanded.
- A rule the parser keeps as `unparsed` cannot be expanded: the master's first occurrence and the overrides are shown, and a test pins this.

**Field mapping**

| iCalendar | `CalendarEvent` |
|---|---|
| `SUMMARY`, `DESCRIPTION`, `LOCATION` | `title`, `notes`, `location` |
| `DTSTART`/`DTEND`/`DURATION`, `VALUE=DATE` | `start`, `end`, `timeZone`, `isAllDay` (all-day through `AllDay` in the event's zone; floating times in the calendar's zone) |
| `STATUS` | `status` (a `CANCELLED` event is returned; the bridge drops it as today) |
| `TRANSP` | `availability` (`OPAQUE` busy, `TRANSPARENT` free) |
| `CLASS` | `visibility` (`PUBLIC`, `PRIVATE`, `CONFIDENTIAL`; absent is `.default`) |
| `ORGANIZER`, `ATTENDEE` (`CN`, `ROLE`, `PARTSTAT`, `CUTYPE`) | `organizer`, `attendees`; email through `CalendarUserAddress.email(from:)`; `isSelf` by matching the principal's `calendar-user-address-set`; `CUTYPE=RESOURCE`/`ROOM` is `.resource` |
| `VALARM` (`TRIGGER` relative or absolute, `ACTION`, `REPEAT`/`DURATION`, Apple proximity) | `reminders` (the `VALARM` reader ADR 0014 deferred to this connector) |
| `URL`, `X-APPLE-STRUCTURED-LOCATION` | `url`, structured location |
| `LAST-MODIFIED`, `CREATED` | `lastModified`, `created` |

Conference links come from the shared `ConferenceDetector` (location, URL, notes). `participation` is derived from the self attendee as the other connectors do.

**Provided fields:** `visibility`, `availability`, `reminders`, `series`, `participation`, `version`, `uidScope`, `recurrenceRules`, `permissionDetails`, `provider`, `calendarTimeZone`. `lastModified` and `created` are declared only if the live test shows iCloud always sends them; `ProvidedFieldsConformance` checks whatever is declared. `isDefault` is not declared (servers may not say).

### `VTIMEZONE`

A `TZID` that `TimeZone(identifier:)` knows is used directly. Otherwise the resolver maps known Windows and Outlook names (through `WindowsTimeZones`, moved from `MicrosoftCalendar` to `CalendarCore` so both connectors share it) and, failing that, matches the component's `STANDARD`/`DAYLIGHT` offsets and rules against the system zones for the event's year; the last fallback is a fixed-offset zone from the `STANDARD` offset. Writes always emit IANA `TZID`s with a `VTIMEZONE` generated from `TimeZone` transitions around the event.

## Change detection

`CalDAVCalendarSource` is a `PollingCalendarSource`, polled at the same interval as the other connectors.

1. `PROPFIND` depth 1 on the home for `getctag` and `sync-token`. A calendar added or removed (or a changed display property) returns `.calendarsChanged`.
2. For each calendar whose token or ctag changed, `REPORT sync-collection` (RFC 6578) from its stored token (kept in `SyncStateStore` under scope `calendar:<id>`); any change returns `.eventsChanged(calendarIDs:)`.
3. An invalid token (the `valid-sync-token` precondition, 403 or 409) re-baselines that calendar and reports it changed.
4. A server that does not support `sync-collection` (no `sync-token` property) falls back to the ctag alone.
5. The first call establishes the baseline and returns nil. A 401 is `.authExpired` and finishes the `changes()` stream with `.sourceFailed`.

## Series

`series(id:calendarID:)` GETs the resource and returns the master's `RRULE`, `RDATE` and `EXDATE` as `CalendarSeries` (through `RecurrenceSet(iCalendarLines:timeZone:isAllDay:)`). An unknown id or a resource without a recurring master throws `SourceError.notFound`.

## Writes

`CalDAVCalendarSource` is a `WritableCalendarSource` and a `SeriesSource`.

**Capabilities**
- `canWrite = true`. `canEditAttendees` and `canRespondToInvite` are true when the server's `DAV:` response header lists `calendar-auto-schedule` (iCloud does), false otherwise.
- `writableFields`: title, notes, location, timing, availability, visibility, reminders, attendees, recurrence. `conference` is not writable; `ConferenceRequest.generate` or `ConferenceChange.generate` throws `WriteError.unsupported([.conference])`. `ConferenceChange.remove` is also unsupported (links live in free text).
- `recurrenceScopes`: all three. `controlsNotifications = false`.
- Reminders accepted: start- or end-relative and absolute triggers with a display alert (sound where the model has one). Anything else throws `.unsupported([.reminders])` before any request.

**Mechanics.** Every write GETs the resource (or uses the copy just read when the ETag matches), applies the patch to the parsed component tree, and PUTs the whole resource with `If-Match: <etag>`. Properties the model does not cover (`X-` properties, `ATTACH`, Apple-specific ones, unknown parameters) are kept as they were. On **412** the connector re-reads the resource and runs `PatchMerge` against `patch.base`: no overlapping field retries once with the fresh ETag; an overlap throws `WriteError.conflict(fields)`. 403 is `WriteError.forbidden`, 404/410 `WriteError.notFound`, 507 `SourceError.server(status:)`.

**create** PUTs `<calendar>/<new UUID>.ics` with `If-None-Match: *`, using the draft's `uid` or a new UUID. If the draft has a `uid`, a `calendar-query` with a `UID` text-match filter runs first; a hit throws `WriteError.alreadyExists(stored)` and writes nothing. A 412 on the PUT (a name clash) retries once with a new name. Returns the event read back from the response ETag and the written body.

**update**
- `thisInstance`: adds an override `VEVENT` with `RECURRENCE-ID` equal to the original start (copying the master's properties), or edits the existing override.
- `allInSeries`: edits the master. When the patch moves the series start by a delta, each override's `RECURRENCE-ID` and each `EXDATE` shift by the same delta so they keep matching; an override whose own time had been changed keeps its time. When the patch changes the rule, overrides and `EXDATE`s that no longer match an occurrence of the new rule are dropped.
- `thisAndFollowing` (split): (1) PUT the original resource with the master's rule truncated by `UNTIL` just before the split occurrence, and overrides and `EXDATE`s at or after it removed; (2) PUT a new resource with a new UID starting at the split occurrence with the patch applied, carrying the removed overrides and `EXDATE`s (shifted if the start moved). Unlike Google, later exceptions move with the new series because they live in the same resource. If step 2 fails after step 1, the connector restores the original resource body (unconditionally, even if the caller was cancelled) and rethrows; if the restore fails too the result is `WriteError.partial` naming both errors. Splitting on the first occurrence is an `allInSeries` update.

**delete**
- `thisInstance`: adds an `EXDATE` for the original start and removes any override for it.
- `thisAndFollowing`: truncates the rule with `UNTIL` and removes later overrides and `EXDATE`s; on the first occurrence it is `allInSeries`.
- `allInSeries` (or a non-recurring event): `DELETE` with `If-Match`.

**respond** sets our own `ATTENDEE`'s `PARTSTAT` (matched by `calendar-user-address-set`) on the master for `allInSeries`, on a new or existing override for `thisInstance`, and on the new series after a split for `thisAndFollowing`; then PUTs. The server sends the iTIP `REPLY` (RFC 6638 implicit scheduling). `.needsAction` throws `WriteError.invalid`. No self attendee throws `WriteError.unsupported([.attendees])`.

**Notifications.** With implicit scheduling the server emails attendees on every organizer change and the organizer on every reply; `NotifyPolicy` is accepted and ignored (`controlsNotifications = false`, as the contract allows). The live smoke test records whether iCloud honors `SCHEDULE-AGENT=CLIENT`; if it does, a later change can honor `.none` and flip the capability.

## App wiring

- `AppConnectors.makeRegistry` always registers `ICloudConnectorKind` and `CalDAVConnectorKind` (no client id, so no CI secret and no local configuration).
- `CredentialSheet` (new SwiftUI view) renders one `TextField` per non-secret field and one `SecureField` per secret field, with the kind's `CredentialPromptHelp` text and link below, and Cancel / Sign In. Sign In is disabled while any field is empty. Cancel throws `CancellationError` from `promptCredentials`.
- `AccountsController` supplies the `promptCredentials` closure to `LoopbackAuthorizationInteraction` and presents the sheet. On a sign-in failure other than cancellation it runs `authorize` again with the non-secret fields prefilled and the error shown at the top of the sheet ("Apple ID or app-specific password was not accepted." for `.authExpired`; the described error otherwise). The retry loop is app-only; the library contract does not change.
- `SettingsSearch` keywords gain "caldav", "fastmail", "nextcloud" ("icloud" is already there).

## Prerequisites (the user)

- For the live smoke test: an iCloud app-specific password (appleid.apple.com → Sign-In and Security → App-Specific Passwords) in the git-ignored `~/.config/timetug/icloud-live` (two lines, Apple ID then password), and a test calendar in that account named `TimeTug Live Test`.

## Testing

1. **`ICalendar`:** round-trip fixtures (RFC 5545 examples and scrubbed iCloud exports) preserve unknown properties and parameters; line folding at 75 octets including multi-byte characters; text escaping; `VTIMEZONE` resolution (IANA, Windows names, rule matching, fixed-offset fallback); `VALARM` reader and writer round-trip (ADR 0014's pending test); `VEVENT` ↔ `CalendarEvent` mapping for every row of the table above.
2. **Expander (`CalendarCoreTests`):** every example in RFC 5545 section 3.8.5.3; DST forward and back for a daily 01:30 and 02:30 rule; all-day; `RDATE`/`EXDATE`; `COUNT` with a window starting mid-series; the instance limit; the unparsed fallback.
3. **`CalDAVCalendarTests`:** an in-memory fake CalDAV server behind `FakeTransport` (PROPFIND, `calendar-query`, `sync-collection`, GET, PUT with `If-Match`/`If-None-Match`, DELETE, ETags, sync tokens, injectable 401/403/412/507). `WritableSourceConformance`, `AllDayConformance` and `ProvidedFieldsConformance` run against it. Request-shape and parsing tests use recorded iCloud multistatus XML. Discovery tests cover `.well-known` redirects, a partition host, and a redirect to a foreign host (refused). Split, restore-on-failure and `.partial` are covered with injected failures.
4. **Linux:** the `core-linux` job builds and tests `ICalendar` and `CalDAVCalendar` (proves `FoundationXML` works).
5. **Live (opt-in, never in CI):** `TIMETUG_LIVE_ICLOUD=1 swift test --package-path Packages/CalendarApple --filter iCloud` signs in with `~/.config/timetug/icloud-live`, never prints the credentials, and prints `LIVE` lines to paste into "Live findings".

## Risks (verify in the live test)

- `sync-collection` on iCloud: supported, and how an invalid token is reported.
- Whether iCloud always sends `LAST-MODIFIED` and `CREATED` (decides the provided fields).
- Whether iCloud honors `SCHEDULE-AGENT=CLIENT` (decides a future `controlsNotifications`).
- The partition host and redirect chain from `caldav.icloud.com`.
- How subscribed calendars appear (resource type, privileges).
- How iCloud treats the split: the truncated master and the new resource both show correctly in Calendar.app, and moved overrides survive.
- Whether iCloud rewrites the body on PUT (so the ETag in the response is not the body we sent); if so, writes read back with a GET.

## Manual checklist (the user, in the app, with the real account)

- [ ] Settings > Accounts > + shows "iCloud" and "Other CalDAV".
- [ ] iCloud sign-in with a wrong password reopens the sheet with the Apple ID kept and the error shown; with an app-specific password it adds the account and lists its calendars (reminders lists absent).
- [ ] An iCloud meeting also visible through Apple Calendar appears once in the popup (merged by UID).
- [ ] An event added in Calendar.app on iCloud appears in TimeTug within one poll.
- [ ] Revoking the app-specific password shows "Sign in again"; signing in again keeps the calendar choices.
- [ ] Removing the account removes its Keychain item.

## Live findings

(To be filled from the live smoke test's `LIVE` lines.)

## Open questions

None from brainstorming.
