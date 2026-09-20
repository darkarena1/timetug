import EventKit
import Foundation
import TimeTugCore

/// Apple Calendar via EventKit. Includes iCloud, Google and Exchange accounts the user has
/// added to macOS. EventKit types never leave this file.
public final class EventKitSource: CalendarSource, @unchecked Sendable {
    public let id = "eventkit"
    public let displayName = "Apple Calendar"
    private let store = EKEventStore()

    public init() {}

    /// Prompts for calendar access if undetermined. Returns whether access is granted.
    public func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    public func calendars() async throws -> [CalendarInfo] {
        try requireAccess()
        return store.calendars(for: .event).map {
            let account = $0.source?.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return CalendarInfo(
                sourceID: id, calendarID: $0.calendarIdentifier, title: $0.title,
                accountName: (account?.isEmpty ?? true) ? nil : account,
                colorHex: Self.hex(from: $0.cgColor))
        }
    }

    private static func hex(from color: CGColor?) -> String? {
        guard let color, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let c = color.converted(to: space, intent: .defaultIntent, options: nil),
              let comps = c.components, comps.count >= 3 else { return nil }
        let v = comps.prefix(3).map { Int((min(max($0, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", v[0], v[1], v[2])
    }

    public func events(in interval: DateInterval) async throws -> [TimeTugCalendarEvent] {
        try requireAccess()
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        return store.events(matching: predicate).map(map)
    }

    public func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let token = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: store, queue: nil
            ) { _ in continuation.yield() }
            continuation.onTermination = { _ in NotificationCenter.default.removeObserver(token) }
        }
    }

    private func requireAccess() throws {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw SourceError.needsPermission
        }
    }

    private func map(_ event: EKEvent) -> TimeTugCalendarEvent {
        let attendees = event.attendees ?? []
        let me = attendees.first { $0.isCurrentUser }
        let status: ResponseStatus
        switch me?.participantStatus {
        case .accepted: status = .accepted
        case .tentative: status = .tentative
        case .declined: status = .declined
        case .pending: status = .pending
        default: status = .unknown
        }
        return TimeTugCalendarEvent(
            sourceEventID: event.eventIdentifier ?? event.calendarItemIdentifier,
            sourceID: id,
            calendarID: event.calendar.calendarIdentifier,
            title: event.title ?? "(No title)",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            otherAttendeeCount: attendees.filter { !$0.isCurrentUser }.count,
            responseStatus: status,
            location: event.location,
            notes: event.notes,
            url: event.url,
            conferenceURL: nil,
            attendees: attendees.filter { !$0.isCurrentUser }.map {
                Attendee(name: $0.name, email: Attendee.email(fromMailto: $0.url.absoluteString))
            },
            organizerEmail: event.organizer.flatMap {
                $0.isCurrentUser ? nil : Attendee.email(fromMailto: $0.url.absoluteString)
            },
            externalUID: event.calendarItemExternalIdentifier
        )
    }
}
