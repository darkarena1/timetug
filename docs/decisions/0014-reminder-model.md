# ADR 0014: Reminder model

**Status:** Accepted

## Context

`Reminder` was only `minutesBefore`. Providers say more: EventKit has absolute-time alarms, alarms tied to a place (arrive or leave), the alert type (on screen, sound, email) and, on iCalendar, alarms relative to the end and repeats. Google has the method (popup or email) and whether a reminder is the calendar's default (`useDefault`). Reads could not tell "the calendar's defaults" from "no reminders".

## Decision

- One uniform shape closely modeled on `EKAlarm`: `trigger` (`.relative(offset:to:)` from the start or end, `.absolute(Date)`, `.location(StructuredLocation, proximity)`; mutually exclusive, so a reminder cannot be both absolute and location-based), `type` (`.display`, `.audio`, `.email`, `.procedure`, `.other`), `repeatCount`/`repeatInterval` (iCalendar REPEAT and DURATION) and `isCalendarDefault`.
- The library reports every reminder and never filters, merges or schedules. The consumer decides which to honor and when to show them; location, travel time and traffic are platform concerns. Pure helpers (`fireDate`, `minutesBefore`) do arithmetic only.
- `StructuredLocation` has plain values (no CoreLocation) so the library stays portable; coordinates exist only for location reminders. An event's own location remains the provider's text.
- Providers: Google `overrides` map to start-relative `.display` (popup) or `.email(address: nil)` reminders and `useDefault` resolves to the calendar's `defaultReminders` with `isCalendarDefault == true`; EventKit maps `EKAlarm` directly (a location alarm with no coordinates keeps its title; radius 0 is nil). Microsoft Graph (later): `isReminderOn` gives one `.display` reminder at `-minutes`, else `[]`.
- Writes accept the common denominator; anything a provider cannot store throws `.unsupported(fields: [.reminders])` before any change. Google: start-relative popup or owner email, 0 to 40320 minutes, at most 5. EventKit: start-relative, absolute and location triggers, with a display or sound alert (the alert type is derived from which related value is set, so email and procedure are refused).
- Patches and merges compare reminders as a set of write identities (trigger, type, repeat), ignoring order and `isCalendarDefault`.
- Deferred: a `VALARM` reader and writer (arrives with a CalDAV connector, one place with a round-trip test), and snooze and acknowledged state.
