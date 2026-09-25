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

    /// `.notSupported` (birthday and subscribed calendars) is nil: EventKit does not say.
    static func availability(_ availability: EKEventAvailability) -> Availability? {
        switch availability {
        case .busy: .busy
        case .free: .free
        case .tentative: .tentative
        case .unavailable: .unavailable
        default: nil
        }
    }

    /// The account type gives the provider; the account title is user-editable and is never read. A `.calDAV`
    /// account may really be iCloud, Google or another host: EventKit presents it as CalDAV and so do we.
    static func provider(sourceType: EKSourceType?, calendarType: EKCalendarType) -> CalendarProvider? {
        if calendarType == .birthday || calendarType == .subscription { return .subscription }
        switch sourceType {
        case .local?: return .local
        case .exchange?: return .microsoft
        case .mobileMe?: return .iCloud
        case .calDAV?: return .calDAV
        case .subscribed?, .birthdays?: return .subscription
        default: return nil
        }
    }

    /// Exchange's object id is not an iCalendar UID (it only matches copies from the same store); everything else that
    /// EventKit carries keeps the real UID. nil when the provider is unknown.
    static func uidScope(provider: CalendarProvider?) -> UIDScope? {
        guard let provider else { return nil }
        return provider == .microsoft ? .provider : .global
    }

    /// The availability values a calendar accepts; an empty mask means it does not track availability.
    static func supportedAvailabilities(_ mask: EKCalendarEventAvailabilityMask) -> Set<Availability> {
        var result: Set<Availability> = []
        if mask.contains(.busy) { result.insert(.busy) }
        if mask.contains(.free) { result.insert(.free) }
        if mask.contains(.tentative) { result.insert(.tentative) }
        if mask.contains(.unavailable) { result.insert(.unavailable) }
        return result
    }

    static func eventAvailability(_ availability: Availability) -> EKEventAvailability {
        switch availability {
        case .busy: .busy
        case .free: .free
        case .tentative: .tentative
        case .unavailable: .unavailable
        }
    }

    /// EventKit has one default calendar across all accounts: true for it, false for its siblings in the same
    /// account, nil for calendars in other accounts (they have a default EventKit does not tell us).
    static func isDefault(calendarID: String, calendarSourceID: String?, defaultCalendarID: String?, defaultSourceID: String?) -> Bool? {
        guard let defaultCalendarID else { return nil }
        if calendarID == defaultCalendarID { return true }
        if let calendarSourceID, calendarSourceID == defaultSourceID { return false }
        return nil
    }

    /// Instances of a series (and a detached, moved one) are occurrences; the series id is the raw shared identifier.
    static func series(isOccurrence: Bool, identifier: String, occurrenceDate: Date?) -> SeriesInfo {
        isOccurrence ? .occurrence(seriesID: identifier, originalStart: occurrenceDate) : .notRecurring
    }

    /// `selfStatus` is the current user's attendee status, nil when they are not among the attendees. An unknown
    /// status (delegated, in process) still means invited and awaiting a reply. An organizer who is the user with no
    /// attendee entry (an event with no guests) counts as accepted.
    static func participation(selfStatus: EKParticipantStatus?, organizerIsCurrentUser: Bool) -> Participation {
        if let selfStatus { return .invited(response(selfStatus) ?? .needsAction) }
        return organizerIsCurrentUser ? .invited(.accepted) : .notInvited
    }

    /// Only alarms relative to the start are read for now (the rich reminder model arrives with the next commit).
    static func reminder(_ alarm: EKAlarm) -> Reminder? {
        guard alarm.absoluteDate == nil, alarm.relativeOffset <= 0 else { return nil }
        return Reminder(minutesBefore: Int((-alarm.relativeOffset / 60).rounded()))
    }

    /// EventKit's own status. `.canceled` must not read as confirmed: a cancelled invite can stay in Apple Calendar.
    static func status(_ status: EKEventStatus) -> EventStatus {
        switch status {
        case .canceled: .cancelled
        case .tentative: .tentative
        default: .confirmed
        }
    }

    /// `eventIdentifier` is shared by every occurrence of a repeating event, so an occurrence's `eventID` adds the
    /// original slot (`occurrenceDate`, which stays put when one occurrence is moved). Other events keep the plain
    /// identifier. Writes find occurrences through `seriesID` (the raw shared identifier) and `originalStart`.
    static func eventID(identifier: String, occurrenceDate: Date, isOccurrence: Bool) -> String {
        isOccurrence ? "\(identifier)#\(Int(occurrenceDate.timeIntervalSince1970))" : identifier
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
