# ADR 0015: Recurrence model

**Status:** Accepted

## Context

An instance only knew its series id and original start; no source exposed the rule, so a consumer could not show "every 2nd Tuesday". EventKit's `EKRecurrenceRule` is the reference API but has known gaps: nothing more frequent than daily, no extra or skipped dates (`RDATE`/`EXDATE`), parts it cannot represent are dropped silently, no raw rule text, no list of cancelled occurrences. The Phase 3 write API already had a write-side `RecurrenceRule` and `RecurrenceScope`.

## Decision

- **The series owns the rule; instances stay parented to it** through `CalendarEvent.series` (`SeriesInfo`). The rule is fetched on demand through `SeriesSource.series(id:calendarID:)`, so `events(in:)` stays cheap. A source declares `ProvidedField.recurrenceRules` exactly when it conforms.
- **One rule type for reading and writing.** `RecurrenceRule` follows RFC 5545 fully: every frequency (`SECONDLY` to `YEARLY`), `WKST`, `BYDAY` (ordinals up to 53 when read), `BYMONTHDAY`, `BYMONTH`, `BYYEARDAY`, `BYWEEKNO`, `BYSETPOS`, `BYHOUR`, `BYMINUTE`, `BYSECOND`, and `unrecognizedParts` for `X-` parts and future extensions, kept in order. Parsing and rendering live in that one type, so they cannot drift.
- **Reading never fails for an unusual rule.** The parser throws `RecurrenceParseError.malformed` only for text that is not a rule (`INTERVAL=0`, `COUNT` with `UNTIL`, an unknown `FREQ`, an out-of-range value, a duplicate part). Whether a writer can store the rule is `validate()`'s job: sub-daily frequencies, the extra parts, a non-Monday week start and unrecognized parts throw `WriteError.unsupported(fields: [.recurrence])` ("rejected, not mangled"). Floating `UNTIL` values are read in the series' zone.
- **`RecurrenceSet`** holds a series' rules with `extraDates` (RDATE) and `excludedDates` (EXDATE). nil means the source cannot say (EventKit), `[]` means none. Lines the library does not model (`EXRULE`, `VALUE=PERIOD`, a zone it cannot resolve such as a Windows name, a malformed rule) stay in `unparsed`, verbatim, so a write does not lose them. Dates are parsed and formatted with Gregorian calendar components, never a locale-dependent formatter, so behavior is identical on Linux. There is no rule expansion: providers expand occurrences on read.
- **Edit scopes** are `RecurrenceScope` (this instance, this and following, all in series). EXDATE and RDATE are not authorable through `EventPatch`.
- **Google** reads the master's `recurrence` lines and anchor time. **EventKit** maps `EKRecurrenceRule` with a pure function (day of week 1 is Sunday, `weekNumber` 0 is no position, first day 0 is the default); its extra and skipped dates are nil.
- **A write fix found on the way:** setting a series' rule replaced Google's whole `recurrence` array, which also holds EXDATE and RDATE lines, so cancelled occurrences came back. A series-wide set now keeps every line that is not a rule.
