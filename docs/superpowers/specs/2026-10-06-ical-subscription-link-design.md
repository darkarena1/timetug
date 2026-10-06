# Calendar connectors, Phase 6: iCal subscription link connector

Status: design approved in brainstorming (2026-10-06), revised the same day to links only; awaiting spec review. Phases 1 to 5 are merged; the API contract is in `docs/calendar-connectors-api.md`. The Phase 5 spec listed "No ICS subscription connector (the `ICalendar` product makes one cheap later)" as a non-goal; this phase builds it.

## Goal

Let a user add a calendar from an iCalendar subscription link to TimeTug without signing in to anything. The user pastes the link (`webcal://` or `https://`, with or without an `.ics` ending); TimeTug re-reads it on a timer so changes show up.

The motivating case is Meetup: its Your events page has an Add to calendar menu whose links are private feeds of the events the member has RSVP'd to. Meetup's API needs a paid Pro subscription, so the feed link is the practical route. Checked on 2026-10-05: such a link answers `200 text/calendar` with no cookies, sends no `ETag` and says `no-store`, and holds a normal `VCALENDAR` with recurring events and a `VTIMEZONE`. The same connector serves any other service that publishes a feed link (a Google "secret address", an Outlook published calendar, Eventbrite, school or team calendars).

## Non-goals

- **No file import.** A downloaded `.ics` is a one-time copy of what the subscription link serves, so it would go stale; the link is what stays current. (File import, with the text kept in the Keychain, was designed and then dropped on 2026-10-06.)
- No writes, RSVP changes or alarms we create; a feed cannot take them (`canWrite = false`).
- No Meetup API, no Meetup-specific kind or host check. Meetup appears only as an example in the help text.
- One feed per account. Another feed is another account.
- No `VTODO`, `VJOURNAL` or free/busy.

## Decisions

Made with the user during brainstorming:

- **One generic kind** (`icalsub`, shown as "iCal link"), not a generic kind plus a Meetup kind. The help text carries the Meetup steps.
- **Links only.** No file picker and no change to the credential sheet's layout: the kind is an ordinary one-field password-style kind, so the existing sheet already fits.
- **The link is a credential.** It is stored in the Keychain, shown masked, and never logged or put into an error message.

## Placement

| Package / target | New or changed |
|---|---|
| `CalendarCore` | `CalendarService.iCalSubscription` (`"icalsub"`) |
| `CalendarConnectors` → `Sources/ICalSubscription` (new target and library product; depends on `CalendarCore` and `ICalendar`; pure Swift, builds on Linux) | `ICalSubscriptionKind`, `FeedLocation` (input parsing), `ICalSubscriptionSource`, `FeedParser` (groups events by UID) |
| `CalendarConnectors` → `Tests/ICalSubscriptionTests` | see Testing |
| `CalendarTestSupport` | reused as is |
| App (`Apps/macOS`) | `AppConnectors` registers the kind; Settings search keywords |
| Docs and site | API contract part 14, ADR 0018, `site/public/privacy.html`, `docs/PROGRESS.md` |

## The kind

| | |
|---|---|
| id | `icalsub` |
| display name | "iCal link" |
| platforms | all |
| authorization | `.password(fields: [link])`, where `link` is `CredentialField(key: "link", label: "iCal link", isSecret: true)` |
| calendar `service` | `.iCalSubscription` |
| calendar `provider` | `.subscription` |

`credentialHelp` (via `CredentialPromptHelp`): "Paste a calendar subscription link (webcal:// or https://). Do not use a downloaded .ics file: it will not update. In Meetup, open Your events, choose Add to calendar, and copy any link in the menu." Link: "Open Meetup Your events", `https://www.meetup.com/your-events/`.

## Input handling (`FeedLocation`)

- Whitespace is trimmed. `webcal://` and `webcals://` become `https://`.
- `https://` is accepted, with or without an `.ics` ending. `http://` is refused except for `localhost`, `127.0.0.1` and `[::1]` (local test servers), the same rule as CalDAV. A URL with an embedded user name or password is refused.
- Anything else, including a `file://` URL or a path, is `SourceError.invalidResponse("enter an iCal link starting with https:// or webcal://")`.

## Sign-in

`authorize(using:credentials:)` prompts for the `link` field, parses it with `FeedLocation`, fetches it once, and requires the body to parse as a `VCALENDAR` (a feed with zero events is valid: a person may have no RSVPs yet). Nothing is stored until that succeeds.

- The URL goes to the `CredentialStore` under the key `link`. `Connection.config` holds only the host (for display). `displayName` is `"<calendar name> (<host>)"` where the calendar name is `X-WR-CALNAME` when present, else the host alone.
- **Reauthorize:** prompts again and replaces the stored link; the `connectionID` is kept so calendar keys and sync state stay valid. There is no "different account" check, since a feed has no identity beyond its content. This is also how a user recovers after the provider revokes or regenerates a link.

## Reads

`ICalSubscriptionSource` is a `PollingCalendarSource` and exposes one calendar:

- `id`: `"feed"`. `title`: `X-WR-CALNAME`, else the connection's display name. `colorHex`: `X-APPLE-CALENDAR-COLOR` or `COLOR` when valid, else nil.
- `provider = .subscription`, `kind = .subscribed`, `permissions = CalendarPermissions(canViewDetails: true, canEdit: false)`, `isDefault = false`, `accountName` the connection's display name, `timeZone` from `X-WR-TIMEZONE` when present.

**Events.** A feed is one `VCALENDAR` holding many events, while `EventResource` expects one UID per resource (a master plus its overrides). `FeedParser` parses the text once, groups the `VEVENT`s by `UID` (an event without a `UID` gets a synthetic one from a digest of its `DTSTART` and `SUMMARY`, stable across reads), builds one `EventResource` per group that shares the calendar's `VTIMEZONE`s, and calls `EventReader.events(in:overlapping:context:)` for each. The `resourceName` is the percent-encoded UID, so `eventID` stays stable and unique within the feed. `selfAddresses` is empty, so `participation` is not a provided field. Cancelled events are returned with `status == .cancelled`, as for the other connectors.

**Fetch rules.**

- `GET` with `Accept: text/calendar`, following redirects, but only to `https` (a redirect to `http` or any other scheme is `SourceError.invalidResponse`).
- The body is capped at 10 MB (`SourceError.invalidResponse("the feed is too large")`).
- Status mapping: 200 reads; 401, 403, 404 and 410 map to `SourceError.authExpired`, because for a private link "gone" usually means the link was revoked or regenerated, and the app then asks for a new one (a temporary 404 from a provider can cause one needless prompt, which is accepted); 429 and 5xx map to `SourceError.server(status:)`.
- Caching: the parsed feed is kept in memory with its fetch time. `events(in:)` reuses it while it is younger than the poll interval, so opening the popup does not trigger a request. A conditional request is used when the server gave an `ETag` or `Last-Modified`.
- Errors never include the URL: the message names the host at most.

## Change detection

15-minute poll (injectable, as for the other connectors). Each poll refetches the feed (or sends the conditional request) and compares a SHA-256 digest of the body with the stored one (`SyncStateStore` scope `digest`); a difference returns `.eventsChanged(calendarIDs: ["feed"])`. The first call establishes the baseline and returns nil. A 401/403/404/410 finishes `changes()` with `.sourceFailed`/`authExpired`.

## Capabilities

`canWrite = false`, `canEditAttendees = false`, `canRespondToInvite = false`, `syncKind = .token`, `supportsPush = false`. `providedFields`: `series`, `uidScope` (`.global`, an iCalendar UID), `provider`, `calendarTimeZone`. A field is declared only if every event the connector returns fills it; `ProvidedFieldsConformance` checks the declaration. `visibility`, `availability` and `reminders` are not declared: a feed may or may not carry `CLASS`, `TRANSP` or `VALARM`, so they stay optional (`nil` means the source does not say).

## App wiring

- `AppConnectors.makeRegistry` registers `ICalSubscriptionKind()`. No client id, so no CI secret and no local configuration.
- The existing `CredentialSheet` renders the one masked field and the kind's help text and link; no sheet change is needed.
- `SettingsSearch` keywords: "ical", "ics", "webcal", "feed", "subscription", "meetup".

## Security and privacy

- The link is sent only to the host it names, over HTTPS, and is never logged or placed in an error or a crash report. Request logs omit the URL's path and query.
- The link is held in the Keychain through the existing `CredentialStore`. Only the change-detection digest lives in the app's support folder, like other sync state. Calendar contents are read in memory only, as for every other connector.
- The privacy policy gets a new bullet: what the feed connector reads (the feed's events, titles, times, places, descriptions and links), what is stored (the link in the Keychain, and a digest to spot changes), that a link is a private address anyone holding it could read, that the user can revoke it at the provider, and that nothing is ever written back. The summary of "what we store" (the account list) gains the feed type and host.

## Testing

1. **`FeedLocation`:** `webcal` and `webcals` mapping, `https` accepted with and without an `.ics` ending, `http` refused (and allowed for loopback), embedded credentials refused, and `file://`, a path and junk text refused.
2. **`FeedParser`:** a scrubbed fixture shaped like a real Meetup feed (two events, a recurring one with an `RRULE`, one `VTIMEZONE`, an event page `URL`), built from structure only with invented data; a feed with two events sharing a time zone; a feed with no events; an event without a `UID`; a recurring event with an override; all-day events through `AllDayConformance`; `ProvidedFieldsConformance`.
3. **`ICalSubscriptionSource` over `FakeTransport`:** the first fetch and poll baseline, a changed digest, an unchanged feed, conditional request when `ETag` is present, 401/403/404/410 mapped to `authExpired`, 429 and 5xx to `server`, redirect to `http` refused, oversized body refused, a body that is not a calendar refused at sign-in, reauthorize keeping the `connectionID`, and that no thrown error or description contains the URL (a test greps the error text for the secret path).
4. **Linux:** the `core-linux` job builds and tests `ICalSubscription`.
5. **App tests:** the registry contains `icalsub` and its help has a link.
6. **Live (opt-in, never in CI):** `TIMETUG_LIVE_ICALSUB=1` reads a feed link from the git-ignored `~/.config/timetug/icalsub-live` (one line), loads it through the real transport, and prints counts and field coverage only, never the link or event text.

## Risks and follow-ups

- **A revoked or regenerated link** shows as `authExpired`; the user pastes the new link. This is the intended recovery.
- **A downloaded `.ics` pasted as a path** is refused with a message pointing at subscription links; the help text says why.
- **Duplicate events** are handled by the existing UID duplicate merge; Meetup UIDs are Meetup's own, so a Meetup event that was also added to Google will not merge (different UIDs), which is accepted.
- **Follow-ups, not in this phase:** a Meetup preset with a host check if people paste wrong links often, and file import if a real need appears.
