import CalendarCore
import EventKit
import CoreLocation
import Foundation

/// Pure conversions for EventKit writes, kept free of `EKEventStore` so they are unit-testable.
enum EventKitWriteMapping {
    static func frequency(_ frequency: RecurrenceRule.Frequency) -> EKRecurrenceFrequency {
        switch frequency {
        case .daily, .secondly, .minutely, .hourly: .daily   // sub-daily rules are refused by `validate()` before this
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

    /// The inverse of `EventKitMapping.reminder(_:)`. EventKit can write an alarm relative to the start, at a date, or
    /// at a place, with an on-screen or sound alert; anything else (relative to the end, repeats, email or procedure
    /// alerts) is refused with `.unsupported(fields: [.reminders])`. The alert type is not settable directly: EventKit
    /// derives it from which of `soundName`, `emailAddress` and `url` is set.
    static func alarms(_ reminders: [Reminder]) throws -> [EKAlarm] {
        try reminders.map { reminder in
            guard reminder.repeatCount == 0 else { throw WriteError.unsupported(fields: [.reminders]) }
            let alarm: EKAlarm
            switch reminder.trigger {
            case .relative(let offset, .start): alarm = EKAlarm(relativeOffset: offset)
            case .relative(_, .end): throw WriteError.unsupported(fields: [.reminders])
            case .absolute(let date): alarm = EKAlarm(absoluteDate: date)
            case .location(let place, let proximity):
                alarm = EKAlarm(relativeOffset: 0)
                let location = EKStructuredLocation(title: place.title ?? "")
                if let latitude = place.latitude, let longitude = place.longitude {
                    location.geoLocation = CLLocation(latitude: latitude, longitude: longitude)
                }
                location.radius = place.radius ?? 0
                alarm.structuredLocation = location
                alarm.proximity = proximity == .enter ? .enter : .leave
            }
            switch reminder.type {
            case .display: break
            case .audio(let soundName): alarm.soundName = soundName ?? "Default"
            default: throw WriteError.unsupported(fields: [.reminders])
            }
            return alarm
        }
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

    /// The first candidate whose external identifier is `uid`; EventKit cannot search by it, so a create looks through
    /// the events around the draft's time.
    /// A cancelled copy stays in the store but is not a meeting the caller can see, so it never counts (as on Google).
    static func matchingIndex(uid: String, candidates: [(uid: String?, isCancelled: Bool)]) -> Int? {
        candidates.firstIndex { $0.uid == uid && !$0.isCancelled }
    }

    /// The window to search for a copy of a meeting: its own time, widened by a day either way (all-day events float).
    static func duplicateSearchWindow(for timing: EventTiming) -> DateInterval {
        DateInterval(start: timing.start.addingTimeInterval(-86_400), end: max(timing.end, timing.start.addingTimeInterval(1)).addingTimeInterval(86_400))
    }

    /// Whether a fetched event is the occurrence `ref` designates: same shared identifier (`seriesID`) and the same
    /// original slot.
    static func isOccurrence(_ ref: EventRef, eventIdentifier: String?, occurrenceDate: Date?) -> Bool {
        guard let seriesID = ref.seriesID, eventIdentifier == seriesID, let slot = occurrenceDate,
              let original = ref.originalStart else { return false }
        return abs(slot.timeIntervalSince(original)) < 1
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
