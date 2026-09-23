# Calendar connectors, Phase 3: write capabilities

Status: draft for review. Phases 1, 2 and 2.5 are merged (#16, #17, #18). This phase adds an optional, provider-neutral write API to the connector library, implements it for Google and EventKit, and leaves TimeTug's UI and Core untouched. The read-side contract is in `docs/calendar-connectors-api.md`; part 10 of that document is the summary of this spec and is updated when it lands.

## Goals

1. A source can *opt in* to writing by adopting `WritableCalendarSource`. Read-only connectors (any provider or feed that can be read but not written) implement nothing new and cannot be mistaken for writable.
2. The write API covers create, update, delete and respond-to-invite, with recurrence scopes (this instance, this and following, all in series) and an explicit attendee-notification policy.
3. Writes are safe against data we do not model: updates send only what changed, and a concurrent edit to an unrelated field never causes a spurious failure.
4. Google (REST) and EventKit implement the API. EventKit is the second implementation, so the API is proven not to be Google-shaped, and it is the connector that reports restricted capabilities (no attendee edits, no RSVP, no notification control).
5. Each connector declares exactly what it can write. Anything it cannot write is an error (`WriteError.unsupported`), never a silent partial write.

## Non-goals

- No TimeTug write UI, no Core or bridge changes beyond keeping existing tests green.
- No orchestration of linked events across calendars or accounts. Links, when TimeTug needs them, live in TimeTug's local store; the write API already supports the per-source calls that orchestration would make.
- No provider-side custom metadata (Google `extendedProperties`, iCalendar `X-` properties, Graph extensions). A `metadata` field and capability can be added later without breaking this API.
- No Microsoft or CalDAV connector (Phase 4 and later).
- No reading of a series' recurrence rule (reads still return expanded instances only). No moving an event between calendars. No editing an event's status, kind or provider-owned fields.
- No attendee editing or RSVP on EventKit (EventKit does not allow either).

## Decisions

Made with the user during brainstorming:

- **Opt-in by protocol.** `WritableCalendarSource: CalendarSource` is a separate protocol; callers check `source as? WritableCalendarSource`. Fine-grained limits are `capabilities` flags, and per-calendar limits are `CalendarDescriptor.accessRole`. (Rejected: write methods on `CalendarSource` throwing `.unsupported` by default; a connector-level static declaration on `ConnectorKind`.)
- **Scope: API + Google + EventKit.** No app-level write hook.
- **Recurrence: a structured RFC 5545 subset.** Rules outside the subset are rejected, not mangled.
- **Notifications: an explicit `NotifyPolicy` argument with no default**, so a caller cannot email attendees by accident.
- **Patch is the write primitive.** `update` takes an `EventPatch` of changed fields, never a whole event, because `CalendarEvent` deliberately carries fewer fields than a provider's event and a whole-event replace would delete the rest. A diff initializer and an `EventEdit` wrapper give callers the "mutate a copy" ergonomics.
- **Conflicts are field-level.** A stale version triggers a fetch and a three-way check on the fields the patch touches; only a real overlap is an error.
- **Provider metadata deferred; links stay local.**

## Placement

| Package | New or changed |
|---|---|
| `CalendarCore` | `WritableCalendarSource`, `EventDraft`, `EventPatch`, `EventEdit`, `EventRef`, `RecurrenceRule`, `RecurrenceScope`, `NotifyPolicy`, `WriteError`, the shared merge helper, `SourceCapabilities` additions (`writableFields`, `controlsNotifications`, `recurrenceScopes`), `CalendarEvent.sourceID` |
| `CalendarTestSupport` | `WritableSourceConformance`, `FakeWritableSource` |
| `GoogleCalendar` | write client and mapper, `GoogleCalendarSource: WritableCalendarSource`, `GoogleAPIClient.send` |
| `EventKitSource` | write mapping, `EventKitSource: WritableCalendarSource`, `version`, `sourceID`, `seriesID` and `originalStart` on read events |
| `CalendarBridge`, `TimeTugCore`, app | none (existing tests updated only where `CalendarEvent` equality now sees `sourceID`) |

Everything new in `CalendarCore` is pure Swift (Foundation only) so `core-linux` keeps building it.

## Capabilities

`SourceCapabilities` gains three fields, all defaulting to the read-only value so existing initializers and sources are unchanged:

```swift
var writableFields: Set<EventField> = []   // the fields create/update can write; drives validation and EventDraft(copying:for:)
var controlsNotifications: Bool = false    // honors NotifyPolicy (Google: sendUpdates); false = the server decides
var recurrenceScopes: Set<RecurrenceScope> = []   // scopes accepted for update/delete/respond on a series
```

Existing `canWrite`, `canEditAttendees` and `canRespondToInvite` keep their meaning. Invariants, enforced by the conformance suite: `capabilities.canWrite == (source is WritableCalendarSource)`; `canEditAttendees == writableFields.contains(.attendees)`; `writableFields` is empty and `recurrenceScopes` is empty unless `canWrite`; `canRespondToInvite` implies `canWrite`. Authoring a `RecurrenceRule` needs `.recurrence` in `writableFields`.

| | `canWrite` | `canEditAttendees` | `canRespondToInvite` | `writableFields` | `controlsNotifications` | `recurrenceScopes` |
|---|---|---|---|---|---|---|
| Google | true | true | true | all | true | all three |
| EventKit | true | false | false | all except `.attendees`, `.visibility`, `.conference` | false | all three (to verify, see Risks) |
| Read-only connector | false | false | false | empty | false | empty |

## API

```swift
public protocol WritableCalendarSource: CalendarSource {
    func create(_ draft: EventDraft, in calendarID: String, notify: NotifyPolicy) async throws -> CalendarEvent
    func update(_ ref: EventRef, _ patch: EventPatch, scope: RecurrenceScope, notify: NotifyPolicy) async throws -> CalendarEvent
    func delete(_ ref: EventRef, scope: RecurrenceScope, notify: NotifyPolicy) async throws
    func respond(to ref: EventRef, _ response: ResponseStatus, scope: RecurrenceScope, notify: NotifyPolicy) async throws -> CalendarEvent
}

public enum NotifyPolicy: Sendable { case all, externalOnly, none }
public enum RecurrenceScope: Sendable { case thisInstance, thisAndFollowing, allInSeries }
```

`respond` accepts `.accepted`, `.tentative` and `.declined`; `.needsAction` throws `.invalid`. `scope` is ignored when the ref is not part of a series.

**Return values.** Writes return the event in the provider's resulting form, including its new `version`, so calls can chain. `create` of a recurring event and a series-wide Google write return the series' first occurrence or master (Google's master resource has no `seriesID`); callers that need instances re-read. `delete` returns nothing.

### Errors

```swift
public enum EventField: Sendable, Hashable { case title, notes, location, timing, availability, visibility, reminders, attendees, recurrence, conference }

public enum WriteError: Error, Sendable, Equatable {
    case unsupported(fields: Set<EventField>)   // the connector cannot write these (or the operation)
    case conflict(fields: Set<EventField>)      // someone else changed a field this patch touches
    case notFound                               // the event or calendar is gone
    case forbidden(String?)                     // read-only calendar or no permission on this event
    case invalid(String)                        // malformed input (end before start, needsAction RSVP, ...)
    case partial(String)                        // a multi-step write stopped half way (Google .thisAndFollowing: series truncated, new series not created)
}

public enum ConferenceRequest: Sendable { case none, generate }   // on a draft
public enum ConferenceChange: Sendable { case generate, remove }  // on a patch
```

An unsupported *operation* is reported against the closest field: `respond` on a connector that cannot RSVP throws `.unsupported(fields: [.attendees])`. Authentication, network, rate-limit and server failures stay `SourceError`, thrown by the same methods. Validation (`invalid`, `unsupported`) happens before any network call or store mutation.

### `EventRef`

```swift
public struct EventRef: Hashable, Sendable {
    var calendarID: String
    var eventID: String
    var version: String?       // the version the caller last saw; used for optimistic locking
    var seriesID: String?      // set for an instance of a series
    var originalStart: Date?   // the occurrence's slot in its series (Google originalStartTime, EventKit occurrenceDate); differs from start for a moved occurrence
    init(_ event: CalendarEvent)
}
```

`originalStart` does two jobs: it identifies the occurrence when `eventID` is shared (EventKit) and it is the split point for `.thisAndFollowing`. A ref with a `seriesID` but no `originalStart` is `.invalid` for any scope other than `.allInSeries`.

`CalendarEvent` gains `sourceID: String?` (last initializer parameter, default nil), stamped by the source that produced it (`Connection.sourceID` for network connectors, `"eventkit"` for EventKit). It lets a host route an event to its account without a wrapper. `CalendarEvent.id` is unchanged by it; a host that holds several sources uses `event.sourceID` to find the right one.

### `EventDraft` (create)

```swift
public struct EventDraft: Sendable, Equatable {
    var title: String
    var notes: String?; var location: String?
    var timing: EventTiming
    var availability: Availability = .busy
    var visibility: Visibility = .default
    var reminders: [Reminder]?            // nil = the calendar's defaults; empty = none
    var attendees: [AttendeeDraft] = []
    var conference: ConferenceRequest = .none   // .none | .generate
    var recurrence: RecurrenceRule?
    init(copying event: CalendarEvent, for capabilities: SourceCapabilities)
}
public struct EventTiming: Sendable, Equatable {   // start, end, timeZone, isAllDay; canonical all-day form
    init(start: Date, end: Date, timeZone: TimeZone?, isAllDay: Bool)   // memberwise, never throws
    func validate() throws                                              // .invalid if end <= start or all-day without a zone; every write calls it before any request
}
public struct AttendeeDraft: Sendable, Equatable { var email: String; var name: String?; var role: AttendeeRole }
```

`EventDraft(copying:for:)` is the lenient path for copying an event to another calendar or account: it carries over only the fields in the target's `writableFields` and drops the rest (for example attendees, visibility and conference for EventKit). An empty `reminders` list on the source becomes `nil` (the target calendar's defaults), because reads cannot tell "defaults" from "none" (see Risks). Attachments, extended properties and colors are not modeled and are not copied. Direct writes are strict; only this constructor is best-effort.

### `EventPatch` (update)

```swift
public enum FieldUpdate<T: Sendable>: Sendable { case keep, set(T), clear }

public struct EventPatch: Sendable, Equatable {
    var title: String?                       // nil = keep
    var notes: FieldUpdate<String> = .keep
    var location: FieldUpdate<String> = .keep
    var timing: EventTiming?                 // time is one unit: start, end, zone and all-day together
    var availability: Availability?
    var visibility: Visibility?
    var reminders: FieldUpdate<[Reminder]> = .keep   // .clear = calendar defaults; .set([]) = none
    var attendees: AttendeeChanges?          // a delta, never a replacement list
    var recurrence: FieldUpdate<RecurrenceRule> = .keep
    var conference: ConferenceChange?        // .generate | .remove
    var touchedFields: Set<EventField> { get }
    var isEmpty: Bool { get }
    private(set) var base: CalendarEvent?        // the original the patch was diffed from; nil for a hand-built patch
    init(from original: CalendarEvent, to edited: CalendarEvent)   // non-throwing; sets `base`
}
public struct AttendeeChanges: Sendable, Equatable { var add: [AttendeeDraft]; var remove: [String] /* normalized emails */ }
```

`AttendeeChanges.add` upserts by email: an existing attendee keeps their response and takes the new name and role. An empty patch is a successful no-op that makes no request (a series is never split without a change to carry).

`base` is what makes field-level conflict handling possible: `update` receives only an `EventRef`, so the values the caller edited *from* travel inside the patch. A hand-built patch has no base and gets the strict behavior described under Conflict handling.

`EventPatch(from:to:)` compares `title`, `notes`, `location`, timing (`start`, `end`, `timeZone`, `isAllDay`), `availability`, `visibility`, `reminders` and `attendees` (by normalized email, so a changed role is an upsert; attendees without an email cannot be targeted and are ignored), plus removal of `conference`. It ignores provider-owned fields (`id`, `eventID`, `uid`, `calendarID`, `sourceID`, `organizer`, `status`, `kind`, `url`, `version`, `seriesID`, `originalStart`, `myResponse`, attendees' `response`, `isSelf`, `isOrganizer`), a changed or added `conference` (only `.generate` and `.remove` are writable) and `recurrence` (reads do not carry one). Callers who need to set a recurrence rule build the patch by hand.

### `EventEdit`

```swift
public struct EventEdit: Sendable {
    public let original: CalendarEvent
    public var event: CalendarEvent          // the working copy
    public var patch: EventPatch { EventPatch(from: original, to: event) }
    public var hasChanges: Bool { !patch.isEmpty }
}
```

Only callers that edit hold two copies; reads and widgets stay single-copy, and `CalendarEvent`'s `Hashable` behavior is unchanged apart from `sourceID`.

### `RecurrenceRule`

```swift
public struct RecurrenceRule: Hashable, Sendable {
    enum Frequency { case daily, weekly, monthly, yearly }
    enum Weekday { case monday, tuesday, wednesday, thursday, friday, saturday, sunday }
    struct WeekdayOccurrence: Hashable, Sendable { var weekday: Weekday; var ordinal: Int? }   // ordinal: ±1...±5, monthly/yearly only
    enum End: Hashable, Sendable { case never, count(Int), until(Date) }
    var frequency: Frequency
    var interval: Int = 1                     // >= 1
    var weekdays: [WeekdayOccurrence] = []
    var monthDays: [Int] = []                 // 1...31 or -31...-1
    var months: [Int] = []                    // 1...12
    var end: End = .never
    init(rrule: String) throws                // accepts an optional "RRULE:" prefix
    func rruleString(allDay: Bool, in zone: TimeZone?) -> String
}
```

`init(rrule:)` supports `FREQ` (daily to yearly), `INTERVAL`, `COUNT`, `UNTIL`, `BYDAY` (with ordinals), `BYMONTHDAY`, `BYMONTH` and `WKST` (accepted, must be the default). Everything else (`BYSETPOS`, `BYHOUR`, `BYYEARDAY`, `BYWEEKNO`, sub-daily frequencies, `COUNT` together with `UNTIL`) throws `WriteError.unsupported([.recurrence])`. `until` is an instant; `rruleString` renders it as a UTC date-time for timed events and as a date in `zone` for all-day events (Google requires `UNTIL` to have the same form as `DTSTART`). Validation (`interval >= 1`, ordinal only on monthly and yearly frequencies, ranges) runs in the throwing parse and in write validation.

EXDATE and RDATE are not authorable; removing one occurrence is `delete` with `.thisInstance`.

## Conflict handling (shared, in `CalendarCore`)

`PatchMerge` is a pure helper used by every connector that has a version to compare:

1. The connector sends the write with the ref's `version` (Google: `If-Match`; EventKit: compares `lastModifiedDate` before saving).
2. On a stale version it fetches the current event (`current`).
3. `PatchMerge.conflicts(patch, current)` returns the touched fields whose value in `current` differs from `patch.base` (timing fields compared as a unit; attendees compared by email set and per-email role). A patch with no `base` cannot be compared, so a stale version is `.conflict(fields: touchedFields)` immediately.
4. Non-empty result: throws `.conflict(fields: conflicting)`.
5. Empty result: the patch is re-applied on `current`'s version. If that write is stale again, go back to step 2 with the newer `current`, so a second concurrent edit is judged the same way. The loop runs at most three times; if the event is still changing, it throws `.conflict(fields: touchedFields)` (documented as "being edited concurrently").

Attendee changes and `respond` go through the same check: the connector fetches the current event, and if its version differs from `ref.version` it runs `PatchMerge` before applying the delta.

Series-wide Google writes (`.allInSeries`) have no usable version: an instance's etag does not cover the master. They send no `If-Match` and overwrite only the touched fields. This is documented behavior, not a bug.

## Google implementation

`GoogleAPIClient` gains `send(method:path:query:body:headers:)`, refactored out of `get` so the 401-refresh, rate-limit backoff and 5xx handling are shared (`get` becomes a thin wrapper). The client keeps its existing provider-level outcomes, so reads behave exactly as before: 410 stays `GoogleAPIError.gone` (the sync-token reset in `GoogleCalendarSource.poll` depends on it), 404 `.notFound`, a 403 `forbidden` reason `.forbidden`, and `insufficientPermissions` stays `SourceError.authExpired`. Two cases are added: 412 becomes `GoogleAPIError.preconditionFailed` and 400 becomes `GoogleAPIError.badRequest(reason)`. A write-mode flag additionally maps any other non-rate-limit 403 to `GoogleAPIError.forbidden`. Only the write layer translates these into `WriteError` (`gone` and `notFound` to `.notFound`, `forbidden` to `.forbidden`, `badRequest` to `.invalid`, `preconditionFailed` into the merge loop); nothing new escapes from a read method.

Write-side fetches (the pre-write GET for attendee edits and RSVP, and the master fetch for `.thisAndFollowing`) use no `fields` mask, so the full resource including `attendees(self)` and unmodeled fields is available.

| Operation | Request |
|---|---|
| create | `POST /calendars/{id}/events?sendUpdates=…`; adds `conferenceDataVersion=1` and `conferenceData.createRequest` (fresh `requestId`, `hangoutsMeet`) when a Meet link is requested |
| update | `PATCH /calendars/{id}/events/{eventId}` with only the touched fields, `If-Match`, `sendUpdates=…` |
| delete | `DELETE …/events/{eventId}?sendUpdates=…` |
| respond | `GET` the event, set the self attendee's `responseStatus`, `PATCH` the full `attendees` array with the fetched etag |

Field mapping: `summary`, `description`, `location`; `start` and `end` as `date` (all-day, exclusive end, through `AllDay`) or `dateTime` plus `timeZone`, always sent together, and always with a zone for recurring events; `availability` to `transparency` (`opaque`/`transparent`); `visibility` to `default/public/private/confidential`; `reminders` to `{useDefault: true}` when the draft's list is nil or a patch clears it, else `{useDefault: false, overrides: [{method: popup, minutes}]}`; `recurrence` to `["RRULE:…"]`. A `.clear` on notes or location sends JSON `null`.

**Attendees.** Google replaces the whole array on PATCH, so an attendee delta (and `respond`) first fetches the current event, runs the conflict check above if its etag differs from `ref.version`, applies the change and sends the full array with the fetched etag. That etag is safe to use because the delta is applied to the fresh copy. `respond` on an event where the user is not an attendee throws `.invalid`. A guest without permission to modify guests gets a 403, surfaced as `.forbidden`.

**Scopes.**

| Scope | update / respond | delete |
|---|---|---|
| `.thisInstance` | the instance id (each instance has its own id under `singleEvents`); `If-Match` with the instance etag | delete the instance id |
| `.allInSeries` | the master id (`recurringEventId`); no `If-Match` | delete the master id |
| `.thisAndFollowing` | see "Splitting a series" below | truncate the master's `RRULE` as described below |

**Splitting a series (`.thisAndFollowing`).**

1. Fetch the master (full resource) and the instance. The split point is the ref's `originalStart` (the slot in the series, not the possibly moved `start`).
2. Truncate the master's `RRULE` at the split: remove `COUNT` and `UNTIL` and set `UNTIL` to just before `originalStart`, as a date for all-day series and as a UTC date-time (`originalStart` minus one second) for timed series, since Google requires `UNTIL` to have the same form as `DTSTART`. Delete stops here.
3. Update only: insert a new series starting at the instance's current start. Its body is built from the full master resource with the patch applied, dropping output-only fields (`id`, `etag`, `iCalUID`, `htmlLink`, `created`, `updated`, `sequence`, `creator`, `organizer`, `recurringEventId`, `conferenceData`) and resetting guest responses; unmodeled fields such as color, attachments and extended properties carry over. If the master had a Meet link, the new series requests a new one (`createRequest`), so following instances do not lose their conference. Its time zone is the instance's `start.timeZone`, else the calendar's zone (Google requires one on recurring events). Its rule is the master's original rule, and for a `COUNT` rule the remaining count is `COUNT` minus the occurrences before the split, counted with `events.instances` (`showDeleted=true`, all pages, `timeMax` at the split), because an individually deleted occurrence still counts toward `COUNT`.
4. If the insert fails, restore the master's original `recurrence`; if that also fails, throw `WriteError.partial` (the series stays truncated, documented).

At the first instance, `.thisAndFollowing` is the same as `.allInSeries`. Modified or cancelled instances after the split point stay attached to the old series and are not carried over (documented). Truncation edits the raw `RRULE` string, so it works for rules outside the authorable subset.

`sendUpdates` maps `.all` to `all`, `.externalOnly` to `externalOnly` and `.none` to `none`. Our own writes show up as changes on the next poll and cause one extra refresh; no suppression is added.

Read-side additions: the mapper stamps `sourceID`; `version` (etag) is already mapped.

## EventKit implementation

`EventKitSource` adopts `WritableCalendarSource`. Reads now also fill `version` (`lastModifiedDate` as a fractional-epoch string), `sourceID`, and, for events that recur or are detached occurrences of a series, `seriesID` (the `eventIdentifier`) and `originalStart` (`occurrenceDate`). Today none of these three is set on EventKit reads, and without `seriesID` a recurring occurrence would look like a standalone event and scopes would be ignored.

- **Access.** All writes require full access (`.needsPermission` otherwise). A calendar whose `allowsContentModifications` is false gives `.forbidden`. An unknown calendar or event gives `.notFound`.
- **Strict validation.** Attendee changes, `respond`, a generated conference and `visibility` (EventKit has no such field) throw `.unsupported(fields:)` before anything is saved. A `NotifyPolicy` other than `.all` throws `.unsupported` when the event has other attendees; with no other attendees any policy is accepted and ignored.
- **Fields.** Title, notes, location, availability (`EKEventAvailability`), timing (all-day through the reverse of `EventKitMapping.canonicalAllDay`: the calendar dates in the draft's zone are rebuilt as device-local floating dates, consistent with the read side), reminders as `EKAlarm` relative offsets (a nil draft list gives no alarms, because EventKit has no calendar-default alarms; this is a documented deviation from the draft's "nil = defaults"), recurrence as `EKRecurrenceRule` (`EKRecurrenceDayOfWeek` carries ordinals; `EKRecurrenceEnd` carries count or until).
- **Locating an occurrence.** A non-recurring event is loaded by `eventIdentifier`. A recurring occurrence is found with a date-range predicate around the ref's `originalStart` and matched on `eventIdentifier` and `occurrenceDate`, because occurrences of one series share an identifier.
- **Scopes.** `.thisInstance` saves or removes with `.thisEvent`; `.thisAndFollowing` with `.futureEvents`; `.allInSeries` loads the series' first occurrence and saves with `.futureEvents`.
- **Versions.** The event is reloaded and `refresh()` is called before a write; a `nil` event or a `false` from `refresh()` (expected to mean the event was deleted; to verify) is `.notFound`. A `lastModifiedDate` that differs from `ref.version` runs the shared `PatchMerge` against the reloaded event.
- Mapping code (`EventKitWriteMapping`) is pure functions over plain values where possible so it is unit-testable; only the save path touches `EKEventStore`.

## Testing

- **`CalendarCore` (pure, Linux CI).** `EventPatch` construction and `EventPatch(from:to:)` (each field, ignored fields, attendee upserts and removals, empty patch); `FieldUpdate` semantics; `EventEdit`; `EventTiming` and `AttendeeDraft` validation; `RecurrenceRule` RRULE round trips for the supported subset and rejection of each unsupported key; `until` rendering for timed and all-day; `PatchMerge` (no overlap, overlap, repeated stale results re-judged each time and the three-attempt limit, no-base patches, timing as a unit, attendee compare); `EventDraft(copying:for:)` for each capability combination; capability-invariant checks.
- **`WritableSourceConformance` (in `CalendarTestSupport`).** Run against `FakeWritableSource` (an in-memory implementation) and against each real connector's fake backend: create then read back, update touches only patched fields, empty patch makes no write, stale version resolves or conflicts per `PatchMerge`, unsupported fields throw without partial writes, `canWrite` invariant, scopes limited to `recurrenceScopes`.
- **Google (fake transport).** For each operation and scope, assert method, path, query (`sendUpdates`, `conferenceDataVersion`), body JSON (only touched fields, `null` for clears, start and end together, `timeZone` on recurring), and headers (`If-Match`). Cover 412 then merge success, 412 then conflict, series-wide no-`If-Match`, attendee delta and RSVP flows (fetch then patch the full array), `.thisAndFollowing` (a `COUNT` rule with a deleted occurrence before the split, timed and all-day `UNTIL`, a moved occurrence, the full-resource insert body and Meet re-request, insert failure with rollback, rollback failure as `.partial`), reads still handling 410 as a sync-token reset after the `send` refactor, and the 400/403/404/410/429 error mappings.
- **EventKit.** Pure tests for recurrence and timing mapping, capability and strictness rules, and version strings. Save paths are covered by a gated manual smoke test.
- **Live smoke tests (manual, opt-in).** Google, through the user's Desktop OAuth client, and EventKit each create a scratch calendar and event, exercise create, update, RSVP where supported, a recurring series with each scope, and delete, then remove what they created. Neither touches existing events. They are documented in `docs/manual-tests/` and never run in CI.
- **Existing suites.** `CalendarBridgeTests`, `TimeTugCoreTests` and the app tests still pass; tests that compare events built by a source with hand-built events are updated for `sourceID`.

## Migration and compatibility

- All changes to shared types are additive with defaults: new `SourceCapabilities` fields, `CalendarEvent.sourceID` (nil by default). No persisted data changes (`Connection` and stores are untouched; `sourceID` on events is not persisted).
- Read-only behavior of every existing source is unchanged. A source that does not adopt `WritableCalendarSource` needs no code change.
- The OAuth scope `calendar.events` already covers Google writes, so existing accounts need no re-authorization.

## CI and docs

- No CI change: new `CalendarCore` code is covered by the existing `core-linux` job and the macOS jobs.
- Update `docs/calendar-connectors-api.md` (part 10 from Proposed to implemented, reconciled with this spec: `WriteError.forbidden`, `EventField` in error payloads), `docs/architecture.md` if it describes the sources, `docs/decisions/0012-calendar-connector-library.md` with a Phase 3 addendum, and `AGENTS.md` if it lists the library's capabilities.

## Risks and items to verify first

1. **EventKit identifiers and scopes.** Verify that occurrences of a series share `eventIdentifier`, that the predicate lookup finds the right occurrence, and that saving the first occurrence with `.futureEvents` edits the whole series. If `.allInSeries` cannot be done reliably, EventKit drops it from `recurrenceScopes` rather than approximating.
2. **Google PATCH behavior.** Verify with a live account: `If-Match` returns 412 on a stale etag for PATCH, an instance PATCH etag versus the master's, that `attendees` replacement preserves other guests' responses, and that recurring inserts require the zone on `start` and `end`.
3. **`.thisAndFollowing` on Google is two calls.** Rollback can fail, leaving a truncated series, and post-split exceptions are orphaned. Mitigation: documented behavior and the rollback path; the scope can be removed from Google's `recurrenceScopes` without an API change if the smoke test shows it is unreliable.
4. **EventKit `lastModifiedDate` granularity.** If two writes in the same second are indistinguishable, conflicts on EventKit are best-effort (documented); the Google path is exact.
5. **EventKit reads.** Verify `EKEvent.occurrenceDate` and `hasRecurrenceRules` give a reliable `seriesID` and `originalStart`, including for detached (moved) occurrences, that `EKObject.refresh()` returns false for a deleted event, and that negative `daysOfTheMonth` and `weekNumber` values are accepted by `EKRecurrenceRule`.
6. **Reminder defaults.** "Use the calendar's default reminders" and "no reminders" both read as an empty list, so a diff cannot tell them apart; patches that change reminders always set them explicitly, and copying an empty list means "defaults".

## Process

Per the standing rule, run the `deepseek-review` skill on this spec before the plan is written, and on the full diff (with the spec and tests) before the PR, verifying every Critical or Important finding against the repo. Implementation follows the same subagent-driven recipe as Phase 2.5, starting with the verification spikes above (items 1 and 2) so their results can adjust the plan before dependent code is written.
