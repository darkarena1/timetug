# ADR 0016: iCalendar and recurrence expansion in the library

**Status:** Accepted

## Context

CalDAV (RFC 4791) stores each event as a whole iCalendar resource: the series master with its `RRULE`, `RDATE` and
`EXDATE`, plus one `VEVENT` per changed occurrence. Google and Microsoft expand a series on the server; a CalDAV server
may (`<C:expand>`), but support is uneven and an expanded answer drops the master and the rule, which series reads and
splits need. ADR 0015 said the library does no expansion because every provider did it. iCloud through EventKit was
also considered and rejected: it is not portable and cannot invite or reply (ADR 0012).

## Decision

- **The library expands recurrence itself.** `RecurrenceRule.instances(anchor:timeZone:isAllDay:before:limit:skipTo:)`
  expands one rule in the series' zone (wall-clock times, DST gaps moved forward, repeated times take the first);
  `RecurrenceSet.occurrences(anchor:duration:timeZone:isAllDay:overlapping:limit:)` combines rules, `RDATE` and `EXDATE`
  for a window. Limits: 5000 emitted instances per resource per query, 200,000 periods per rule; a series that started
  years ago fast-forwards to the window instead of counting from its start (except with `COUNT`). A rule the library
  cannot read shows the first occurrence only.
- **`ICalendar` is its own product,** depending only on `CalendarCore`: a byte-level parser and a serializer (75-octet
  folding that never splits a UTF-8 character), a component tree that keeps unknown properties and parameters, time zone
  resolution (IANA, Windows and Mozilla-prefixed names, `VTIMEZONE` rule matching, then a fixed offset) and `VTIMEZONE`
  output, and the `VEVENT` ↔ `CalendarEvent`, `VALARM` ↔ `Reminder` and attendee mappings. A write edits the stored tree in
  place, so properties TimeTug does not model survive.
- **`CalDAVCalendar`** depends on `CalendarCore` and `ICalendar` and parses XML with `XMLParser` (`FoundationXML` on Linux).

## Consequences

- One connector serves iCloud and any other CalDAV server, and a future ICS subscription connector can reuse `ICalendar`.
- Expansion bugs are now ours: the expander is tested against every RFC 5545 section 3.8.5.3 example, DST changes and
  all-day series, and the conformance suites run against a fake CalDAV server.
- The library still has no external dependencies and builds on Linux.
- A whole-series edit changes only the master resource. An occurrence that has its own override keeps its own values and
  attendees.
- Moving a timed series from one occurrence shifts it by absolute seconds (`SeriesEditor.shift`), so across a DST change
  the local wall-clock time of the shifted occurrences can differ by an hour from the one the caller chose.
