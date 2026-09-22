import CalendarCore
import CoreGraphics
import EventKit
import Foundation

/// Pure conversions used by `EventKitSource`, kept free of `EKEventStore` so they are unit-testable.
enum EventKitMapping {
    static func kind(_ type: EKCalendarType) -> CalendarKind {
        switch type {
        case .birthday: .birthdays
        case .subscription: .subscribed
        default: .standard
        }
    }


    /// EventKit reports all-day events as floating device-local dates whose `endDate` is normally the end of the
    /// last day (23:59:59). Returns the library's canonical form: start-of-day of the first day and the start of
    /// the day after the last, in `calendar`'s zone. `end <= start` covers one day; an `end` already at a
    /// midnight after `start` is taken as exclusive.
    static func canonicalAllDay(start: Date, end: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let first = calendar.startOfDay(for: start)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: first) ?? first.addingTimeInterval(86_400)
        if end <= start { return (first, nextDay) }
        let endDay = calendar.startOfDay(for: end)
        if end == endDay { return (first, max(endDay, nextDay)) }
        let after = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay.addingTimeInterval(86_400)
        return (first, max(after, nextDay))
    }

    /// nil for statuses the library has no value for (unknown, delegated, in process, ...).
    static func response(_ status: EKParticipantStatus) -> ResponseStatus? {
        switch status {
        case .accepted: .accepted
        case .tentative: .tentative
        case .declined: .declined
        case .pending: .needsAction
        default: nil
        }
    }

    static func role(_ participant: EKParticipant) -> AttendeeRole {
        if participant.participantType == .resource || participant.participantType == .room { return .resource }
        return participant.participantRole == .optional ? .optional : .required
    }

    static func email(fromMailto urlString: String?) -> String? {
        guard let urlString, urlString.lowercased().hasPrefix("mailto:") else { return nil }
        let rest = String(urlString.dropFirst("mailto:".count))
        let address = rest.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
        let trimmed = address?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    static func hex(from color: CGColor?) -> String? {
        guard let color, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let c = color.converted(to: space, intent: .defaultIntent, options: nil),
              let comps = c.components, comps.count >= 3 else { return nil }
        let v = comps.prefix(3).map { Int((min(max($0, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", v[0], v[1], v[2])
    }
}
