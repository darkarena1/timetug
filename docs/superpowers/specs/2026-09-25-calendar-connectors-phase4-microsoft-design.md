# Calendar connectors, Phase 4: Microsoft (Outlook) connector

Status: design, approved in brainstorming (2026-09-25). Phases 1, 2, 2.5 and 3 are merged (#16, #17, #18, #32, #38). This phase adds a Microsoft Graph connector to the connector library with full parity with Google (read, change detection, writes, series) and plugs it into TimeTug's Accounts tab. The API contract is in `docs/calendar-connectors-api.md`; its Phase 4 note ("until a second provider has proved the API is provider-neutral") is what this phase closes.

## Goals

1. Sign in with a Microsoft account (personal Outlook.com/Hotmail/Live, or work/school Microsoft 365) and read its calendars and events like any other source.
2. Poll for changes cheaply with Graph delta queries, so the app refreshes when something changes without fetching everything.
3. Write: create, update, delete, respond to invites, with recurrence scopes, attendees and Teams links, through the Phase 3 `WritableCalendarSource` API.
4. Read a series' recurrence rule (`SeriesSource`).
5. Keep the library layering rule: the connector is pure Swift with no external dependencies and builds on Linux; OS-specific code stays in `CalendarApple` and the app.

## Non-goals

- No webhook push (Graph subscriptions need a public endpoint; polling was chosen for every provider).
- No MSAL and no Microsoft SDK. The connector is a small REST client over the library's `HTTPTransport`.
- No free/busy-only calendars beyond what `permissions.canViewDetails` already expresses.
- No shipping the Microsoft client id in beta and release builds beyond wiring the CI injection (see "App wiring").
- No moving events between calendars, no Graph extensions or open-type metadata, no attachments.
- No CalDAV or iCloud-direct connector (a later phase).

## Decisions

Made with the user during brainstorming:

- **Scope: full parity with Google.** Reads, delta sync, writes, `SeriesSource`.
- **Accounts: work/school and personal**, authority `common`. Work tenants other than the registering one need admin consent while the app has no verified publisher; the connector surfaces that as a sign-in error, it does not work around it.
- **Change detection: `calendarView/delta` over a rolling window**, re-baselined before it ages out. (Rejected: fetch-and-hash each poll, wasteful; `lastModifiedDateTime` filter, misses deletions.)
- **Public client, PKCE, no secret.** `OAuthConfig.clientSecret` is already optional.
- **Optimistic locking by read-before-write plus `PatchMerge`**, not `If-Match` (Graph's ETag support on events is not dependable).

## Placement

| Package | New or changed |
|---|---|
| `CalendarCore` | `CalendarService.microsoft` (one static constant) and the `controlsNotifications` doc comment (see Writes); nothing else |
| `CalendarConnectors` (`Sources/MicrosoftCalendar`, new target and library product) | `MicrosoftConnectorKind`, `MicrosoftOAuthConfig`, `MicrosoftCalendarSource` (`+Write`, `+Series`), `GraphAPIClient`, `GraphDTOs`, `GraphEventMapper`, `GraphWriteMapper`, `GraphRecurrenceMapper`, `WindowsTimeZones` |
| `CalendarTestSupport` | reused as is (`WritableSourceConformance`, `AllDayConformance`, `ProvidedFieldsConformance`) |
| `CalendarApple` | loopback redirect host option for Microsoft (see Risk 1); Microsoft live smoke test |
| `Apps/macOS` | `MicrosoftOAuthSettings`, `AppConnectors` registration, `project.yml` and `Signing.xcconfig` keys, Accounts tab entry, `scripts/dev/link-signing.sh` and CI helper |
| `TimeTugCore`, `CalendarBridge` | none |

Everything in `MicrosoftCalendar` uses only Foundation and the library, like `GoogleCalendar`.

## Sign-in

`MicrosoftConnectorKind` mirrors `GoogleConnectorKind`.

- `kindID = "microsoft"`, `displayName = "Microsoft"` (the Accounts tab may show "Outlook" as the subtitle), `authorization = .oauth`, all four platforms.
- Endpoints: `https://login.microsoftonline.com/common/oauth2/v2.0/authorize` and `.../token`.
- Scopes: `offline_access`, `User.Read`, `MailboxSettings.Read`, `Calendars.ReadWrite`, `Calendars.ReadWrite.Shared`. `.Shared` gives parity with Google's calendar list (shared and delegated calendars); `MailboxSettings.Read` is for the account's time zone (see Time zones). None needs admin consent by itself. Consent is another matter for work and school accounts: an app registered without a verified publisher (a Microsoft Cloud Partner Program step, out of scope) cannot get user consent in other organizations' tenants, so a work account outside the registering tenant needs its admin to approve the app. Personal accounts and the registering tenant are unaffected. The connector reports the resulting sign-in error as is.
- `MicrosoftOAuthConfig` holds the client id only. Extra auth parameter: `prompt=select_account`, so a user with several Microsoft accounts is not silently signed in as the wrong one.
- After the code exchange, `GET /me?$select=mail,userPrincipalName,displayName` gives the account identity. The connection's `config["email"]` is `mail` if present, else `userPrincipalName`, lowercased, and `displayName` is that address. `reauthorize` throws `SourceError.invalidResponse("signed in as a different account")` when the identity differs, exactly like Google, and stores secrets only after sign-in succeeds.
- Secrets: `["refresh_token": ...]` through `AccessTokenProvider`. Microsoft rotates refresh tokens; `AccessTokenProvider` already writes a rotated one back to the store, so no change is needed there. `invalid_grant` becomes `SourceError.authExpired`; work tenants may also return `interaction_required`, which maps to `authExpired` too.

## Reads

Base URL `https://graph.microsoft.com/v1.0`. `GraphAPIClient` mirrors `GoogleAPIClient`: bearer token from `AccessTokenProvider`, paging through `@odata.nextLink`, `429` and `503` retry honoring `Retry-After` (through the injected sleeper), and a typed `GraphAPIError` (`notFound`, `forbidden`, `gone`, `badRequest`, `conflict`, `precondition`, `throttled`, `server`) with a `sourceError` translation.

Every request sends `Prefer: IdType="ImmutableId"` so ids survive folder moves. Event reads also send `Prefer: outlook.timezone="<account zone>"` (see Time zones).

**Time zones.** Graph reports times as a `dateTime` plus a `timeZone`, and returns UTC unless the request names a zone with `Prefer: outlook.timezone`. The zone an event was scheduled in is only available as `originalStartTimeZone`. The library needs a zone at two levels: per event (`CalendarEvent.timeZone`) and per calendar (`CalendarDescriptor.timeZone`, which anchors all-day dates). The connector uses the account's mailbox zone as the calendar zone:

- `GET /me/mailboxSettings/timeZone` (scope `MailboxSettings.Read`) gives the account's default zone, a Windows name such as `Pacific Standard Time` or an IANA name. `WindowsTimeZones` (a bidirectional table, Windows to IANA and back, pure Swift, no ICU dependency) turns it into a `TimeZone`. A missing scope, a 403, a failed request or a name not in the table falls back to `UTC`, so `CalendarDescriptor.timeZone` is never nil. The zone is read on each `calendars()` call (one small request), since the user can change it, and the source remembers it for `events(in:)`.
- Every calendar in the account gets that zone. A shared calendar owned by someone in another zone is still described in the account's zone; that only affects where an all-day event falls on the calendar grid, not any timed instant.
- Reads send `Prefer: outlook.timezone` set to the account zone's raw name (or `UTC` after a fallback), so `dateTime` values are in the account zone and an all-day event falls on the date the user sees in Outlook. Instants are computed from `dateTime` plus that zone, never from a bare local string.
- `CalendarEvent.timeZone`: for a timed event, `originalStartTimeZone` mapped through the table (the zone it was scheduled in, so the event displays as its organizer meant it), else the account zone; for an all-day event, the account zone.

**Calendars.** `GET /me/calendars` (owned and shared). Mapping: `id`, `name`, `hexColor` (Graph's `color` enum is the fallback), `isDefaultCalendar` to `isDefault`, `canEdit`, `canShare`, `canViewPrivateItems` to `CalendarPermissions`, `owner.address` or the account email to `accountName`, `provider = .microsoft`, `service = .microsoft`, `supportedAvailabilities = [.busy, .free, .tentative, .unavailable]` (Graph's `showAs`: free, tentative, busy, oof, workingElsewhere; `workingElsewhere` reads as `.free`). `timeZone` is the account's mailbox zone (see Time zones). `defaultReminders` is nil: Graph's calendar resource has no reminder defaults (reminders live on events).

**Events.** `GET /me/calendars/{id}/calendarView?startDateTime&endDateTime&$top=100`, paged. Occurrences come expanded. One task per calendar, results merged and sorted like Google. A calendar that answers 404 or 403 is skipped. Items with `isCancelled == true` are dropped.

`GraphEventMapper` maps:

| Library field | Graph |
|---|---|
| `eventID` | `id` (immutable) |
| `uid`, `uidScope` | `iCalUId`, `.global` |
| `title`, `notes`, `location` | `subject`, `body` (text; HTML stripped by the existing detector helpers), `location.displayName` |
| `start`, `end`, `timeZone` | `start`/`end` `dateTime` interpreted in the zone the response names (the account zone, because of the `Prefer` header); `timeZone` as in Time zones |
| `isAllDay` | `isAllDay`, converted to the library's canonical all-day form with the `AllDay` helper (exclusive end, calendar date in the event's zone); must pass `AllDayConformance` |
| `status` | `isCancelled` cancelled; `showAs == tentative` is availability, not status; everything else confirmed |
| `availability` | `showAs` |
| `visibility` | `sensitivity`: normal default, personal/private private, confidential confidential |
| `kind` | standard (Graph has no focus/OOO event type; `showAs == oof` stays availability) |
| `series` | `type`: `seriesMaster` and `singleInstance` not recurring at the instance level; `occurrence`/`exception` give `.occurrence(seriesID: seriesMasterId, originalStart: originalStart in originalStartTimeZone)` |
| `attendees`, `organizer` | `attendees[].emailAddress`, `type` (required/optional/resource), `status.response`; organizer from `organizer`; `isSelf` by matching the account email |
| `participation` | `.invited(response)` from `responseStatus.response` when the account is an attendee and not the organizer, else `.notInvited` |
| `reminders` | `isReminderOn` and `reminderMinutesBeforeStart` (relative, start-anchored, `.display`) |
| `conferences` | `onlineMeeting.joinUrl` as a structured Teams conference; the `ConferenceDetector` scan of location, body and URL remains the fallback |
| `version` | `changeKey` |
| `lastModified`, `created` | `lastModifiedDateTime`, `createdDateTime` |
| `url` | `webLink` |

Declared `providedFields`: `.kind`, `.visibility`, `.availability`, `.reminders`, `.series`, `.participation`, `.structuredConference`, `.version`, `.lastModified`, `.created`, `.uidScope`, `.recurrenceRules` (see Series), `.isDefault`, `.calendarTimeZone`, `.provider`, `.supportedAvailabilities`, `.permissionDetails`. Google's list minus `.defaultReminders`, which Graph does not supply.

## Change detection

`checkForChanges()` follows the Google source's structure with Graph's delta.

- Per calendar id, the `SyncStateStore` scope holds a `deltaLink` and the window it was baselined on, encoded together as `"<baselineDate>|<deltaLink>"` (the store is string-only).
- **Baseline:** `GET /me/calendars/{id}/calendarView/delta?startDateTime=now-30d&endDateTime=now+365d` with `Prefer: odata.maxpagesize=200`, walking `@odata.nextLink` to the last page, discarding items and keeping `@odata.deltaLink`.
- **Poll:** `GET` the stored `deltaLink`, walk to the last page, count items (including `@removed` ones), and store the new `deltaLink`. Any item means the calendar changed. Items that fail to parse still count.
- **Re-baseline:** after polling, when the baseline is older than 14 days (so the window always keeps at least 16 days back and 350 days ahead), fetch a fresh baseline. A re-baseline discards the items it lists, so an edit made between the poll and the fresh baseline would otherwise never be reported; the re-baseline therefore reports `.eventsChanged` for that calendar, like the `410` path (one extra refresh every 14 days). A `410 Gone` or invalid-token answer also triggers a re-baseline, reported the same way, because changes may have been missed.
- The calendar set is tracked as for Google (`_calendars` scope): a changed set reports `.calendarsChanged`, and tokens for removed calendars are dropped.
- The first call establishes baselines and returns nil.
- `capabilities.syncKind = .token`, `supportsPush = false`. The source is a `PollingCalendarSource` driven by `ChangeMonitor`.

## Series

`MicrosoftCalendarSource` conforms to `SeriesSource` and declares `.recurrenceRules`.

`GraphRecurrenceMapper` converts Graph's `patternedRecurrence` to and from `RecurrenceRule`:

| Graph pattern | RecurrenceRule |
|---|---|
| `daily` + `interval` | `DAILY;INTERVAL` |
| `weekly` + `daysOfWeek` + `firstDayOfWeek` | `WEEKLY;BYDAY;WKST` |
| `absoluteMonthly` + `dayOfMonth` | `MONTHLY;BYMONTHDAY` |
| `relativeMonthly` + `daysOfWeek` + `index` | `MONTHLY;BYDAY` with ordinal (first=1 ... fourth=4, last=-1) |
| `absoluteYearly` + `month` + `dayOfMonth` | `YEARLY;BYMONTH;BYMONTHDAY` |
| `relativeYearly` + `month` + `daysOfWeek` + `index` | `YEARLY;BYMONTH;BYDAY` with ordinal |

Range: `noEnd` is never, `numbered` is `COUNT`, `endDate` is `UNTIL` (end of that date in the recurrence zone).

Writing accepts only what Graph can express and throws `WriteError.unsupported(fields: [.recurrence])` otherwise (never mangles): ordinals other than 1...4 and -1, more than one month day, a yearly rule with several months, and any `unrecognizedParts`. A non-Monday `weekStart` is writable, because Graph's `firstDayOfWeek` carries it. Reading never throws for a rule Graph produced.

`series(id:calendarID:)` fetches the master (`GET /me/events/{id}` with the immutable id) and returns its rule and start. A 404, or a master that is not a series (`type` is not `seriesMaster`, or `recurrence` is absent), throws `SourceError.notFound`. Exceptions and cancelled occurrences (`RecurrenceSet` exdates): Graph's `exceptionOccurrences` navigation is beta-only, so the connector derives them by comparing the rule's expansion with the `calendarView` over the known window; outside that window exdates may be missing. Risk 3.

## Writes

`MicrosoftCalendarSource: WritableCalendarSource` (`+Write` extension), with `GraphWriteMapper` translating `EventDraft` and `EventPatch` to Graph JSON.

**Capabilities.** `canWrite`, `canEditAttendees` and `canRespondToInvite` true; `writableFields` all fields; `recurrenceScopes` all three; `controlsNotifications = false`. Graph has no `sendUpdates`: it emails attendees when the organizer creates, updates or cancels. The library's contract for `controlsNotifications == false` is "the server decides", the same as EventKit, so `NotifyPolicy` is accepted and ignored on create, update and delete (Graph emails attendees whatever the caller asks; Risk 4 records what each account type actually does). The one exception is `respond`, which passes `sendResponse: false` when `notify == .none` and `true` otherwise. Delete is always a plain `DELETE`. The exception is recorded in the doc comment on `SourceCapabilities.controlsNotifications` ("false means the server decides for create, update and delete; a connector may still honor the policy for a response to an invite"), the only change to `SourceTypes.swift`.

**Create.** With a draft `uid`, look up `iCalUId eq '<uid>'` on the target calendar first; a hit throws `.alreadyExists(storedCopy)` and writes nothing. Otherwise `POST /me/calendars/{id}/events`. A recurring draft carries `recurrence` (rule mapped as above, `range.startDate` from the draft start in its zone).

**Update.** Read the current event, run `PatchMerge` against `EventPatch.base` to detect a field-level conflict (`WriteError.conflict(fields:)`), then send only the changed fields with `PATCH`. Timing patches send `start` and `end` as local `dateTime` values with the event's zone written as a Windows name (from the reverse table; a zone with no Windows entry is sent as UTC with the instant converted); an all-day event sends midnight dateTimes in the account zone with `isAllDay: true`. Attendee patches send the full attendee list (Graph replaces it). Conference: `generate` sets `isOnlineMeeting: true` and `onlineMeetingProvider: "teamsForBusiness"`; `remove` sets `isOnlineMeeting: false`.

**Scope handling.**

| Scope | Target |
|---|---|
| not in a series | the event id |
| `.thisInstance` | the occurrence's id (from `calendarView`); Graph turns it into an exception. `EventRef.originalStart` identifies the slot when only the master id is known (look the occurrence up by `originalStart` in `calendarView`) |
| `.allInSeries` | `seriesMasterId` |
| `.thisAndFollowing` | a split at the series' first occurrence is the same as `.allInSeries` and is handled as that. Otherwise emulated: rewrite the master's recurrence range to end before the split (a `numbered` range becomes `endDate`, using count arithmetic over the instances before the split), then create a new series from the split point carrying the master's fields plus the patch. The new series keeps the master's pattern; its range is `noEnd` for `noEnd`, the same `endDate` for `endDate`, and for `numbered` the *remaining* count (original count minus the instances before the split), so the total stays the same. Failure between the two steps throws `WriteError.partial` after restoring the master's original range (best effort, restore failures reported in the message), as Google does. |

**Delete.** `DELETE` on the same targets. `.thisInstance` deletes the occurrence, which Graph records as a cancelled exception.

**Respond.** `POST /me/events/{id}/accept`, `tentativelyAccept` or `decline` with `{ "sendResponse": <bool> }`; `.needsAction` throws `.invalid`. Scope handling as above (`.allInSeries` targets the master). The result is the re-read event.

**Errors.** `GraphAPIError` maps to `WriteError` as Google's does: 404 and `410` to `.notFound`, 403 to `.forbidden`, 400 to `.invalid`, and 412/409 to `SourceError.invalidResponse` (no `If-Match` is sent, so they are unexpected).

## App wiring

- `MicrosoftOAuthSettings` (like `GoogleOAuthSettings`) reads `TimeTugMicrosoftClientID` from Info.plist; without it Microsoft is not offered and everything else works.
- `Signing.xcconfig` includes a git-ignored `MicrosoftOAuth.xcconfig` (`MICROSOFT_OAUTH_CLIENT_ID`); `scripts/dev/link-signing.sh` links it from `~/.config/timetug/microsoft-oauth.xcconfig`; `project.yml` injects `TimeTugMicrosoftClientID`.
- `AppConnectors.makeRegistry` registers `MicrosoftConnectorKind` when the config is present, with `CryptoKitSHA256`.
- The Accounts tab already lists registered kinds; no new UI beyond the kind's name and icon. Re-authorize and remove flows are the existing ones.
- CI: `scripts/ci/microsoft-oauth-config.sh` mirrors the Google helper for `MICROSOFT_OAUTH_CLIENT_ID` (one variable; a public client id is not a secret but stays out of git), used by `build-release.sh` and the beta and release workflows. Adding the repository variable is the user's step.

## Prerequisites (the user)

An Azure app registration (Microsoft Entra, "App registrations"), with:

- Supported account types: accounts in any organizational directory and personal Microsoft accounts.
- Platform: "Mobile and desktop applications" with redirect URI `http://localhost` (Microsoft ignores the port for loopback redirects).
- "Allow public client flows": yes.
- API permissions (delegated): `offline_access`, `User.Read`, `MailboxSettings.Read`, `Calendars.ReadWrite`, `Calendars.ReadWrite.Shared`.
- The Application (client) id goes in `~/.config/timetug/microsoft-oauth.xcconfig` as `MICROSOFT_OAUTH_CLIENT_ID = ...`.

For live testing: one personal Outlook.com account and, ideally, one Microsoft 365 work account.

## Testing

- **Library unit tests** on `FakeTransport`, in a new `MicrosoftCalendarTests` target: sign-in and re-authorize (identity, wrong account, cancel, refresh-token rotation), the API client (paging, retry, error translation), the mailbox zone lookup (Windows name, IANA name, unknown name, 403, failure: each ends in a zone, UTC on failure), `GraphEventMapper` fixtures (timed with and without `originalStartTimeZone`, all-day in the account zone and in UTC, cancelled, occurrence and exception, attendees and self, Teams, reminders), `WindowsTimeZones`, `GraphRecurrenceMapper` round trips over every pattern and the unsupported writes, delta baseline, poll, removal, re-baseline after 14 days, `410`, and calendar-set changes.
- **Conformance:** `AllDayConformance`, `ProvidedFieldsConformance` and `WritableSourceConformance` against a stubbed transport, as for Google; write tests for create (including `.alreadyExists`), update (merge, conflict), delete, respond and every scope, and for `.thisAndFollowing` including numbered-range arithmetic, split at the first occurrence, and the partial-failure rollback.
- **App tests:** `MicrosoftOAuthSettingsTests` (missing, placeholder and valid values) and the `AppConnectorsTests` registry cases.
- **Live smoke** (`TIMETUG_LIVE_MICROSOFT=1`, in `CalendarApple` tests like the Google one): the risks below, recorded in a "Live findings" section added to this spec when it is run. Needs the user's client id and an account to sign in with.
- `core-linux` still builds `CalendarCore` and now `MicrosoftCalendar`.

## Risks (verify in the live spike)

1. **Loopback redirect host.** The current loopback session builds `http://127.0.0.1:<port>`. Microsoft's registration takes `http://localhost` and ignores the port; whether `127.0.0.1` is matched at runtime must be confirmed. If not, the session gets a redirect-host option so the authorization URL uses `http://localhost:<port>` while the listener still binds the loopback interface (and, if `localhost` resolves to `::1` first in the browser, also binds IPv6).
2. **Time zones.** Confirm `Prefer: outlook.timezone` accepts the raw mailbox name (Windows or IANA), that all-day events land on the right date in it, that `originalStartTimeZone` is present on events created elsewhere (Outlook web, iPhone, an invite from another tenant), that writes accept the zone names the connector sends (Windows names are the safe form; IANA names are used only if the live run shows Graph accepts them), and that the table covers the zones seen in the wild.
3. **Exdates.** Confirm what `RecurrenceSet` can recover for moved and cancelled occurrences on v1.0, and document the window limit if it applies.
4. **Notifications on create, update and delete**, and whether personal accounts and work accounts behave the same.
5. **Teams generation** for personal accounts (`teamsForBusiness` versus consumer providers) and the `onlineMeeting` field shape returned.
6. **Delta window behavior:** that a `deltaLink` keeps working across 14 days and reports `@removed` for cancelled occurrences.
7. **Delegated and shared calendars** appear in `/me/calendars` with `.Shared` consent and are readable and (where permitted) writable.
8. **Refresh-token rotation:** confirm live that a connection keeps working across several refreshes (the write-back exists; this checks Microsoft's behavior against it).

## Open questions

None. Anything the live spike contradicts is recorded in a "Live findings" section and the affected section is corrected.
