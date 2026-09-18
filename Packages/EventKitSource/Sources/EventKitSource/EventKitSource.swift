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
                accountName: (account?.isEmpty ?? true) ? nil : account)
        }
    }

    public func events(in interval: DateInterval) async throws -> [CalendarEvent] {
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

    private func map(_ event: EKEvent) -> CalendarEvent {
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
        return CalendarEvent(
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
            conferenceURL: nil   // CalendarStore fills this from location/url/notes
        )
    }
}
