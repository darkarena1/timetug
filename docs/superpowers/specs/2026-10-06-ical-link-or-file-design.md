# Calendar connectors, Phase 6: iCal link or file connector

Status: design approved in brainstorming (2026-10-06); awaiting spec review. Phases 1 to 5 are merged; the API contract is in `docs/calendar-connectors-api.md`. The Phase 5 spec listed "No ICS subscription connector (the `ICalendar` product makes one cheap later)" as a non-goal; this phase builds it.

## Goal

Let a user add a calendar from an iCalendar feed to TimeTug without signing in to anything, in either of two ways:

1. **A link** (`webcal://`, `webcals://` or `https://`) that TimeTug re-reads on a timer, so changes show up.
2. **An `.ics` file** chosen from disk, read once and kept as a snapshot.

The motivating case is Meetup: its Your events page has an Add to calendar menu whose links are private feeds of the events the member has RSVP'd to. Meetup's API needs a paid Pro subscription, so the feed is the practical route. Checked on 2026-10-05: such a link answers `200 text/calendar` with no cookies, sends no `ETag` and says `no-store`, and holds a normal `VCALENDAR` with recurring events and a `VTIMEZONE`. The same connector serves any other service that publishes a feed link (a Google "secret address", an Outlook published calendar, Eventbrite, school or team calendars).

## Non-goals

- No writes, RSVP changes or alarms we create; a feed cannot take them (`canWrite = false`).
- No Meetup API, no Meetup-specific kind or host check. Meetup appears only as an example in the help text.
- No "watch this file" mode: a chosen file is a snapshot (see Decisions). It can be added later; the app is not sandboxed, so it needs no bookmarks.
- One feed per account. Another feed is another account.
- No `VTODO`, `VJOURNAL` or free/busy.

## Decisions

Made with the user during brainstorming:

- **One generic kind** (`icalsub`, shown as "iCal link or file"), not a generic kind plus a Meetup kind. The help text carries the Meetup steps.
- **Link or file in one sheet.** The credential sheet gets a Link / File segmented control (option B of the UI discussion); mixing a masked link field with a file button, or two entries in the "+" menu, were rejected.
- **A file is a one-time import** copied into app storage, labelled "Imported file (won't update)", refreshed by re-importing through the existing reauthorize flow. A live reference to the path was rejected for now: it adds a failure mode (moved or deleted file) for a case links already cover.
- **The link is a credential.** It is stored in the Keychain, shown masked, and never logged or put into an error message.

## Placement

| Package / target | New or changed |
|---|---|
| `CalendarCore` | `CredentialField.allowsFile` (new, defaults to `false`); `CalendarService.iCalSubscription` (`"icalsub"`) |
| `CalendarConnectors` → `Sources/ICalSubscription` (new target and library product; depends on `CalendarCore` and `ICalendar`; pure Swift, builds on Linux) | `ICalSubscriptionKind`, `FeedLocation` (input parsing), `ICalSubscriptionSource`, `FeedParser` (groups events by UID) |
| `CalendarConnectors` → `Tests/ICalSubscriptionTests` | see Testing |
| `CalendarTestSupport` | reused as is |
| App (`Apps/macOS`) | `CredentialSheet` Link / File control; `AppConnectors` registers the kind; Settings search keywords |
| Docs and site | API contract part 14, ADR 0018, `site/public/privacy.html`, `docs/PROGRESS.md` |

## The kind

| | |
|---|---|
| id | `icalsub` |
| display name | "iCal link or file" |
| platforms | all |
| authorization | `.password(fields: [feed])`, where `feed` is `CredentialField(key: "feed", label: "iCal link or file", isSecret: true, allowsFile: true)` |
| calendar `service` | `.iCalSubscription` |
| calendar `provider` | `.subscription` |

`credentialHelp` (via `CredentialPromptHelp`): "Paste an iCal link (webcal:// or https://) or choose an .ics file. A link keeps up to date; a file is read once. In Meetup, open Your events, choose Add to calendar, and copy any link in the menu." Link: "Open Meetup Your events", `https://www.meetup.com/your-events/`.

The field is a single text value. It holds either a link or a `file://` URL; the kind reads whichever it gets, so the library never knows about the open panel.

## Input handling (`FeedLocation`)

- Whitespace is trimmed. `webcal://` and `webcals://` become `https://`.
- `https://` is accepted. `http://` is refused except for `localhost`, `127.0.0.1` and `[::1]` (local test servers), the same rule as CalDAV. A URL with embedded user name or password is refused (enter nothing in the address that belongs in a credential).
- `file://` URLs must be absolute and point at a regular file.
- Anything else is `SourceError.invalidResponse("enter an iCal link starting with https:// or webcal://, or choose a file")`.

## Sign-in

`authorize(using:credentials:)` prompts for the `feed` field, parses it with `FeedLocation`, loads the content once, and requires it to parse as a `VCALENDAR` with at least one calendar component (a feed with zero events is valid: a person may have no RSVPs yet). Nothing is stored until that succeeds.

- **Link:** the URL goes to the `CredentialStore` under the key `feed`. `Connection.config` holds only `mode = "link"` and the host (for display). `displayName` is `"<calendar name> (<host>)"` where the calendar name is `X-WR-CALNAME` when present, else the host alone.
- **File:** the file's bytes (UTF-8 text) go to `SyncStateStore` under the scope `snapshot`. They are not credentials, and `SyncStateStore.removeAll` already runs when an account is removed, so the snapshot goes with the account. `Connection.config` holds `mode = "file"` and the file name. `displayName` is `"<calendar name> (<file name>)"`. The size cap below applies. This reuses an existing store rather than adding a new one; the cost is that `FileSyncStateStore` rewrites its whole JSON file on a change, which for a snapshot of a few hundred kilobytes at most is acceptable. If snapshots prove large, a dedicated blob store is the follow-up.
- **Reauthorize:** prompts again. A link replaces the stored link; a file replaces the snapshot. The mode may change (link to file or back); the `connectionID` is kept so calendar keys and sync state stay valid. There is no "different account" check, since a feed has no identity beyond its content.

## Reads

`ICalSubscriptionSource` is a `PollingCalendarSource` and exposes one calendar:

- `id`: `"feed"`. `title`: `X-WR-CALNAME`, else the connection's display name. `colorHex`: `X-APPLE-CALENDAR-COLOR` or `COLOR` when valid, else nil.
- `provider = .subscription`, `kind = .subscribed`, `permissions = CalendarPermissions(canViewDetails: true, canEdit: false)`, `isDefault = false`, `accountName` the connection's display name, `timeZone` from `X-WR-TIMEZONE` when present.

**Events.** A feed is one `VCALENDAR` holding many events, while `EventResource` expects one UID per resource (a master plus its overrides). `FeedParser` parses the text once, groups the `VEVENT`s by `UID` (an event without a `UID` gets a synthetic one from a digest of its `DTSTART` and `SUMMARY`, stable across reads), builds one `EventResource` per group that shares the calendar's `VTIMEZONE`s, and calls `EventReader.events(in:overlapping:context:)` for each. The `resourceName` is the percent-encoded UID, so `eventID` stays stable and unique within the feed. `selfAddresses` is empty, so `participation` is not a provided field. Cancelled events are returned with `status == .cancelled`, as for the other connectors.

**Fetch rules (links).**

- `GET` with `Accept: text/calendar`, following redirects, but only to `https` (a redirect to `http` or to a `file` scheme is `SourceError.invalidResponse`).
- The body is capped at 10 MB (`SourceError.invalidResponse("the feed is too large")`).
- Status mapping: 200 reads; 401, 403, 404 and 410 map to `SourceError.authExpired`, because for a private link "gone" usually means the link was revoked or regenerated, and the app then asks for a new one (a temporary 404 from a provider can cause one needless prompt, which is accepted); 429 and 5xx map to `SourceError.server(status:)`.
- Caching: the parsed feed is kept in memory with its fetch time. `events(in:)` reuses it while it is younger than the poll interval, so opening the popup does not trigger a request. A conditional request is used when the server gave an `ETag` or `Last-Modified`.
- Errors never include the URL: the message names the host at most.

## Change detection

15-minute poll (injectable, as for the other connectors). Each poll refetches the feed (or sends the conditional request) and compares a SHA-256 digest of the body with the stored one (`SyncStateStore` scope `digest`); a difference returns `.eventsChanged(calendarIDs: ["feed"])`. The first call establishes the baseline and returns nil. A 401/403/404/410 finishes `changes()` with `.sourceFailed`/`authExpired`. A file account never polls the network (`syncKind = .none`; `checkForChanges` returns nil).

## Capabilities

`canWrite = false`, `canEditAttendees = false`, `canRespondToInvite = false`, `syncKind = .token` for links (`.none` for files), `supportsPush = false`. `providedFields`: `series`, `uidScope` (`.global`, an iCalendar UID), `provider`, `calendarTimeZone`. A field is declared only if every event the connector returns fills it; `ProvidedFieldsConformance` checks the declaration. `visibility`, `availability` and `reminders` are not declared: a feed may or may not carry `CLASS`, `TRANSP` or `VALARM`, so they stay optional (`nil` means the source does not say).

## App wiring

- `AppConnectors.makeRegistry` registers `ICalSubscriptionKind()`. No client id, so no CI secret and no local configuration.
- `CredentialSheet`: a field with `allowsFile == true` renders a **Link / File** segmented control above its input.
  - **Link** shows the masked field (`SecureField`), as for any secret.
  - **File** shows a drop zone ("Drop an .ics file here, or Choose file…") and a standard open panel limited to `.ics` and `.ical` types. After a choice it shows the file name and an ✕ to clear it.
  - The field's value is the link text in Link mode and the chosen file's `file://` URL in File mode. Switching mode clears the value. Sign In enables when the active mode has a value (`isComplete` is unchanged).
  - The drop zone also accepts a file dropped anywhere on the sheet while File mode is active, and switches to File mode if a file is dropped while Link mode is showing.
- `AccountsPane` labels a file account "Imported file (won't update)" under its name. Re-importing is the existing "Sign in again" action on the account.
- `SettingsSearch` keywords: "ical", "ics", "webcal", "feed", "subscription", "meetup".

## Security and privacy

- The link is sent only to the host it names, over HTTPS, and is never logged or placed in an error or a crash report. Request logs omit the URL's path and query.
- The link is held in the Keychain through the existing `CredentialStore`. The snapshot and digest live in the app's support folder, like other sync state. Calendar contents are read in memory only, as for every other connector.
- The privacy policy gets a new bullet: what the feed connector reads (the feed's events, titles, times, places, descriptions and links), what is stored (the link in the Keychain, or the imported file's text in app storage, and a digest to spot changes), that a link is a private address anyone holding it could read, that the user can revoke it at the provider, and that nothing is ever written back. The summary of "what we store" (the account list) gains the feed type and host.

## Testing

1. **`FeedLocation`:** `webcal` and `webcals` mapping, `https` accepted, `http` refused (and allowed for loopback), embedded credentials refused, `file://` accepted only for absolute regular files, and junk text refused.
2. **`FeedParser`:** a scrubbed fixture shaped like a real Meetup feed (two events, a recurring one with an `RRULE`, one `VTIMEZONE`, an event page `URL`), built from structure only with invented data; a feed with two events sharing a time zone; a feed with no events; an event without a `UID`; a recurring event with an override; all-day events through `AllDayConformance`; `ProvidedFieldsConformance`.
3. **`ICalSubscriptionSource` over `FakeTransport`:** the first fetch and poll baseline, a changed digest, an unchanged feed, conditional request when `ETag` is present, 401/403/404/410 mapped to `authExpired`, 429 and 5xx to `server`, redirect to `http` refused, oversized body refused, a body that is not a calendar refused at sign-in, and that no thrown error or description contains the URL (a test greps the error text for the secret path).
4. **File mode:** the snapshot round-trips through an in-memory `SyncStateStore`; a file account never touches the transport; reauthorize with a new file replaces the snapshot and keeps the `connectionID`; mode switch both ways.
5. **Linux:** the `core-linux` job builds and tests `ICalSubscription`.
6. **App tests:** the registry contains `icalsub` and its help has a link; `CredentialSheet` Link / File value rules (mode switch clears the value, `isComplete` follows the active mode); `AccountsPane` label for a file account.
7. **Live (opt-in, never in CI):** `TIMETUG_LIVE_ICALSUB=1` reads a feed link from the git-ignored `~/.config/timetug/icalsub-live` (one line), loads it through the real transport, and prints counts and field coverage only, never the link or event text.

## Risks and follow-ups

- **A revoked or regenerated Meetup link** shows as `authExpired`; the user pastes the new link. This is the intended recovery.
- **`SyncStateStore` as a snapshot home** is a pragmatic reuse; revisit if imported files are large.
- **Duplicate events** are handled by the existing UID duplicate merge; Meetup UIDs are Meetup's own, so a Meetup event that was also added to Google will not merge (different UIDs), which is accepted.
- **Follow-ups, not in this phase:** a "watch this file" mode, a Meetup preset with a host check if people paste wrong links often, and a dedicated blob store.
