import CalendarCore
import EventKit
import Foundation

/// Pure conversions for EventKit writes, kept free of `EKEventStore` so they are unit-testable.
enum EventKitWriteMapping {
    static func frequency(_ frequency: RecurrenceRule.Frequency) -> EKRecurrenceFrequency {
        switch frequency {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        }
    }

    static func weekday(_ weekday: RecurrenceRule.Weekday) -> EKWeekday {
        switch weekday {
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        case .sunday: .sunday
        }
    }

    static func recurrenceRule(_ rule: RecurrenceRule) -> EKRecurrenceRule {
        let days = rule.weekdays.map { EKRecurrenceDayOfWeek(dayOfTheWeek: weekday($0.weekday), weekNumber: $0.ordinal ?? 0) }
        let end: EKRecurrenceEnd?
        switch rule.end {
        case .never: end = nil
        case .count(let count): end = EKRecurrenceEnd(occurrenceCount: count)
        case .until(let date): end = EKRecurrenceEnd(end: date)
        }
        return EKRecurrenceRule(
            recurrenceWith: frequency(rule.frequency), interval: rule.interval,
            daysOfTheWeek: days.isEmpty ? nil : days,
            daysOfTheMonth: rule.monthDays.isEmpty ? nil : rule.monthDays.map { NSNumber(value: $0) },
            monthsOfTheYear: rule.months.isEmpty ? nil : rule.months.map { NSNumber(value: $0) },
            weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: end)
    }

    /// Floating-point arithmetic so an absurd `minutesBefore` cannot trap on `Int` overflow.
    static func alarms(_ reminders: [Reminder]) -> [EKAlarm] {
        reminders.map { EKAlarm(relativeOffset: -(Double($0.minutesBefore) * 60)) }
    }

    /// `.thisInstance` saves one occurrence; both other scopes save the occurrence and everything after it (for
    /// `.allInSeries` the caller starts from the series' first occurrence).
    static func span(for scope: RecurrenceScope) -> EKSpan {
        scope == .thisInstance ? .thisEvent : .futureEvents
    }

    /// Where to look for an occurrence whose slot is `slot`. A date-range predicate matches an occurrence's ACTUAL
    /// dates, and an occurrence can be moved far from its slot, so the window is a year either way (EventKit
    /// searches at most four years at a time).
    static func occurrenceSearchWindow(around slot: Date) -> DateInterval {
        DateInterval(start: slot.addingTimeInterval(-366 * 86_400), end: slot.addingTimeInterval(367 * 86_400))
    }

    /// EventKit has no etag; the modification date is the version.
    static func version(_ modified: Date?) -> String? {
        modified.map { String($0.timeIntervalSince1970) }
    }

    /// EventKit cannot control notifications (the server decides), so anything but `.all` is refused when other
    /// attendees would be affected. With no other attendees every policy is accepted and ignored.
    static func checkNotify(_ policy: NotifyPolicy, hasOtherAttendees: Bool) throws {
        if policy != .all && hasOtherAttendees { throw WriteError.unsupported(fields: [.attendees]) }
    }

    /// EventKit stores all-day events as floating device-local dates whose end is the end of the last day (the shape
    /// `EventKitMapping.canonicalAllDay` reads). Rebuilds the calendar dates of `timing` (in its own zone) in
    /// `calendar`'s zone. nil when the timing has no zone. Always covers at least one day.
    static func floatingAllDay(_ timing: EventTiming, calendar: Calendar) -> (start: Date, end: Date)? {
        guard let zone = timing.timeZone else { return nil }
        let days = AllDay.dates(start: timing.start, end: timing.end, in: zone)
        let lastDay = max(days.first, days.endExclusive.adding(days: -1))
        guard let first = AllDay.startOfDay(days.first, in: calendar.timeZone),
              let last = AllDay.startOfDay(lastDay, in: calendar.timeZone),
              let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: last)
        else { return nil }
        return (first, end)
    }
}
