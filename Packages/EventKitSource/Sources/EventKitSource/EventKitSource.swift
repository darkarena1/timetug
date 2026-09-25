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
            canWrite: true, providedFields: [.reminders, .series, .participation, .supportedAvailabilities, .recurrenceRules], syncKind: .notification,
            writableFields: [.title, .notes, .location, .timing, .availability, .reminders, .recurrence],
            controlsNotifications: false, recurrenceScopes: Set(RecurrenceScope.allCases))
    }
    let store: EKEventStore
    let contacts: ContactEmailResolver

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
        self.contacts = ContactEmailResolver()
    }

    init(store: EKEventStore, contacts: ContactEmailResolver) {
        self.store = store
        self.contacts = contacts
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
        let events = store.events(matching: predicate)
        let resolved = contacts.emails(for: Self.unresolvedParticipants(in: events))
        return events.map { map($0, resolvedEmails: resolved) }
    }

    /// The distinct participants whose address is not an email (so matching would lose them).
    static func unresolvedParticipants(in events: [EKEvent]) -> [UnresolvedParticipant] {
        var seen = Set<String>()
        var result: [UnresolvedParticipant] = []
        for event in events {
            for participant in (event.attendees ?? []) + (event.organizer.map { [$0] } ?? []) {
                let url = participant.url.absoluteString
                guard CalendarUserAddress.email(from: url) == nil, seen.insert(url).inserted else { continue }
                result.append(UnresolvedParticipant(url: url, predicate: participant.contactPredicate))
            }
        }
        return result
    }

    public func changes() -> AsyncStream<CalendarChange> {
        AsyncStream { continuation in
            let token = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: store, queue: nil
            ) { _ in continuation.yield(.calendarsChanged) }
            // A Contacts grant makes emails resolvable: the host fetches events again.
            let grant = NotificationCenter.default.addObserver(
                forName: ContactEmailResolver.accessGranted, object: nil, queue: nil
            ) { _ in continuation.yield(.eventsChanged(calendarIDs: nil)) }
            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(token)
                NotificationCenter.default.removeObserver(grant)
            }
        }
    }

    func requireAccess() throws {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw SourceError.needsPermission }
    }

    private func attendee(_ p: EKParticipant, isOrganizer: Bool, resolvedEmails: [String: [String]], preferredDomains: Set<String>) -> Attendee {
        let email = CalendarUserAddress.email(from: p.url.absoluteString)
            ?? ContactEmailResolver.choose(resolvedEmails[p.url.absoluteString] ?? [], preferredDomains: preferredDomains)
        return Attendee(name: p.name, email: email, role: EventKitMapping.role(p),
                 response: EventKitMapping.response(p.participantStatus) ?? .needsAction,
                 isSelf: p.isCurrentUser, isOrganizer: isOrganizer)
    }

    /// `resolvedEmails` (participant URL to a contact's emails) fills in participants EventKit gave no email for.
    func map(_ event: EKEvent, resolvedEmails: [String: [String]] = [:]) -> CalendarEvent {
        let known = ((event.attendees ?? []) + (event.organizer.map { [$0] } ?? []))
            .compactMap { CalendarUserAddress.email(from: $0.url.absoluteString) }
        let domains = Set(known.compactMap { $0.split(separator: "@").last.map(String.init) })
        let attendees = (event.attendees ?? []).map { attendee($0, isOrganizer: false, resolvedEmails: resolvedEmails, preferredDomains: domains) }
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
            attendees: attendees, organizer: event.organizer.map { attendee($0, isOrganizer: true, resolvedEmails: resolvedEmails, preferredDomains: domains) },
            conferences: ConferenceDetector.conferences(location: event.location, url: event.url, notes: event.notes),
            reminders: (event.alarms ?? []).map(EventKitMapping.reminder),
            url: event.url, version: EventKitWriteMapping.version(event.lastModifiedDate),
            lastModified: event.lastModifiedDate, created: event.creationDate,
            participation: EventKitMapping.participation(selfStatus: me?.participantStatus, organizerIsCurrentUser: event.organizer?.isCurrentUser ?? false),
            sourceID: EventKitSource.sourceID)
    }
}
