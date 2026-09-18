# ADR 0003: Current-Day Display Window with Lead+Buffer Fetch

**Status:** Accepted

## Context

The dropdown shows today's events. However, meetings scheduled after midnight (e.g., 12:05 AM) with a lead time (e.g., 10 minutes) must fire their overlay *before* midnight (11:55 PM) so the user gets warning. The fetch window must extend far enough that the scheduler always has future events queued.

## Decision

- **Display window:** Current local calendar day only. A 12:05 AM meeting appears in the dropdown only when inside its lead-time window (before midnight), not again after the day rolls over.
- **Fetch window:** Local midnight today through next local midnight + lead time + 5-minute buffer (named `CalendarStore.fetchBuffer = 300`). The buffer ensures that edge cases (e.g., slow refresh, clock skew) do not leave a meeting unscheduled.
- **Duplicate merging:** When the same meeting (by lowercased title, start, end) appears on multiple opted-in calendars, keep one entry. Record all calendar keys in `additionalCalendarKeys` so takeover opt-in on *any* calendar counts.
- **Fired-ledger pruning:** At midnight, prune the fired-ledger by event end time (not wholesale). A 11:55 PM takeover for a 12:05 AM meeting does not repeat after rollover because the event ends after the prune threshold.

Rejected alternative: A sliding 24-hour window would complicate midnight transitions and calendar caching; current-day is simpler and matches user expectations.

## Consequences

**Advantages:**
- Simple display semantics: the popover always shows today's events.
- Fetch window is predictable and independent of lead-time changes (only added at app start/settings change).
- Edge cases like sleep/wake or timezone changes trigger a full re-fetch; no stale state persists past midnight.

**Trade-off:** Display window is fixed to one day; may widen later if multi-day view is requested. The constant `displayWindow = 1` lives in `CalendarStore`; changing it is a single-line edit if the need arises.
