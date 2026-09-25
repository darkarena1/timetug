import CalendarCore
import EventKit
import Foundation

/// Apple Calendar via EventKit (includes iCloud, Google and Exchange accounts added to macOS). EventKit types
/// never leave this module. Its id is the constant "eventkit" (existing stored calendar keys start with
/// `eventkit/`), which deliberately differs from `Connection.sourceID`; hosts identify sources by `source.id`.
public final class EventKitSource: CalendarCore.CalendarSource, @unchecked Sendable {
    public static let sourceID = "eventkit"
    public let id = EventKitSource.sourceID
    public let displayName = "Apple Calendar"
    public var capabilities: SourceCapabilities {
        SourceCapabilities(
            canWrite: true, providedFields: [.reminders, .series, .participation, .supportedAvailabilities], syncKind: .notification,
            writableFields: [.title, .notes, .location, .timing, .availability, .reminders, .recurrence],
            controlsNotifications: false, recurrenceScopes: Set(RecurrenceScope.allCases))
    }
    let store: EKEventStore

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    /// Prompts for calendar access if undetermined. Returns whether access is granted.
    public func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    public func calendars() async throws -> [CalendarDescriptor] {
        try requireAccess()
        let defaultCalendar = store.defaultCalendarForNewEvents
        return store.calendars(for: .event).map {
            let account = $0.source?.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return CalendarDescriptor(
                id: $0.calendarIdentifier, title: $0.title, service: .eventKit, colorHex: EventKitMapping.hex(from: $0.cgColor),
                permissions: CalendarPermissions(canViewDetails: true, canEdit: $0.allowsContentModifications),
                isDefault: EventKitMapping.isDefault(
                    calendarID: $0.calendarIdentifier, calendarSourceID: $0.source?.sourceIdentifier,
                    defaultCalendarID: defaultCalendar?.calendarIdentifier, defaultSourceID: defaultCalendar?.source?.sourceIdentifier),
                accountName: (account?.isEmpty ?? true) ? nil : account, kind: EventKitMapping.kind($0.type),
                provider: EventKitMapping.provider(sourceType: $0.source?.sourceType, calendarType: $0.type),
                supportedAvailabilities: EventKitMapping.supportedAvailabilities($0.supportedEventAvailabilities))
        }
    }

    public func events(in interval: DateInterval) async throws -> [CalendarEvent] {
        try requireAccess()
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        return store.events(matching: predicate).map(map)
    }

    public func changes() -> AsyncStream<CalendarChange> {
        AsyncStream { continuation in
            let token = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: store, queue: nil
            ) { _ in continuation.yield(.calendarsChanged) }
            continuation.onTermination = { _ in NotificationCenter.default.removeObserver(token) }
        }
    }

    func requireAccess() throws {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw SourceError.needsPermission }
    }

    private func attendee(_ p: EKParticipant, isOrganizer: Bool) -> Attendee {
        Attendee(name: p.name, email: EventKitMapping.email(fromMailto: p.url.absoluteString), role: EventKitMapping.role(p),
                 response: EventKitMapping.response(p.participantStatus) ?? .needsAction,
                 isSelf: p.isCurrentUser, isOrganizer: isOrganizer)
    }

    func map(_ event: EKEvent) -> CalendarEvent {
        let attendees = (event.attendees ?? []).map { attendee($0, isOrganizer: false) }
        let me = (event.attendees ?? []).first { $0.isCurrentUser }
        var start = event.startDate ?? Date(), end = event.endDate ?? start
        var zone = event.timeZone ?? .current
        if event.isAllDay {
            // Floating device-local dates: normalize to the canonical form in the device zone.
            let calendar = Calendar.current
            (start, end) = EventKitMapping.canonicalAllDay(start: start, end: end, calendar: calendar)
            zone = calendar.timeZone
        }
        let isSeries = event.hasRecurrenceRules || event.isDetached
        // One value feeds both ids, so a ref never has an occurrence `eventID` with a nil `seriesID`.
        let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
        return CalendarEvent(
            eventID: EventKitMapping.eventID(identifier: identifier, occurrenceDate: event.occurrenceDate ?? start, isOccurrence: isSeries),
            uid: event.calendarItemExternalIdentifier,
            uidScope: EventKitMapping.uidScope(provider: EventKitMapping.provider(sourceType: event.calendar.source?.sourceType, calendarType: event.calendar.type)),
            calendarID: event.calendar.calendarIdentifier,
            title: event.title ?? "(No title)",
            notes: event.notes, location: event.location, start: start, end: end, timeZone: zone,
            isAllDay: event.isAllDay, status: EventKitMapping.status(event.status),
            availability: EventKitMapping.availability(event.availability),
            series: EventKitMapping.series(isOccurrence: isSeries, identifier: identifier, occurrenceDate: event.occurrenceDate),
            attendees: attendees, organizer: event.organizer.map { attendee($0, isOrganizer: true) },
            conferences: ConferenceDetector.conferences(location: event.location, url: event.url, notes: event.notes),
            reminders: (event.alarms ?? []).map(EventKitMapping.reminder),
            url: event.url, version: EventKitWriteMapping.version(event.lastModifiedDate),
            lastModified: event.lastModifiedDate, created: event.creationDate,
            participation: EventKitMapping.participation(selfStatus: me?.participantStatus, organizerIsCurrentUser: event.organizer?.isCurrentUser ?? false),
            sourceID: EventKitSource.sourceID)
    }
}
