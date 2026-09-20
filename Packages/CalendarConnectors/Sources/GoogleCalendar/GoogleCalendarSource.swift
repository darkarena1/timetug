import CalendarCore
import Foundation

public final class GoogleCalendarSource: PollingCalendarSource {
    private static let eventFields =
        "nextPageToken,items(id,iCalUID,status,summary,description,location,htmlLink,etag,hangoutLink,transparency,visibility,eventType,recurringEventId,start,end,originalStartTime,attendees(email,displayName,responseStatus,optional,resource,organizer,self),organizer(email,displayName,self),conferenceData(entryPoints(entryPointType,uri),conferenceSolution(key(type),name)),reminders(useDefault,overrides(minutes)))"

    let connection: Connection
    let api: GoogleAPIClient
    let syncState: any SyncStateStore
    let monitor: ChangeMonitor

    init(connection: Connection, api: GoogleAPIClient, syncState: any SyncStateStore, monitor: ChangeMonitor) {
        self.connection = connection
        self.api = api
        self.syncState = syncState
        self.monitor = monitor
    }

    public var id: String { connection.sourceID }
    public var displayName: String { connection.displayName }
    public var capabilities: SourceCapabilities {
        SourceCapabilities(providesConference: true, syncKind: .token)
    }

    public func calendars() async throws -> [CalendarDescriptor] {
        let account = connection.config["email"]
        do {
            return try await api.calendarList().compactMap { GoogleEventMapper.descriptor(from: $0, accountName: account) }
        } catch let error as GoogleAPIError {
            throw error.sourceError
        }
    }

    public func events(in interval: DateInterval) async throws -> [CalendarEvent] {
        let calendars = try await calendars()
        return try await withThrowingTaskGroup(of: [CalendarEvent].self) { group in
            for calendar in calendars {
                group.addTask { try await self.events(for: calendar, in: interval) }
            }
            var all: [CalendarEvent] = []
            for try await part in group { all += part }
            return all.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        }
    }

    private func events(for calendar: CalendarDescriptor, in interval: DateInterval) async throws -> [CalendarEvent] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let query = [
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "timeMin", value: formatter.string(from: interval.start)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: interval.end)),
            URLQueryItem(name: "maxResults", value: "250"),
            URLQueryItem(name: "showDeleted", value: "false"),
            URLQueryItem(name: "fields", value: Self.eventFields),
        ]
        var events: [CalendarEvent] = []
        do {
            try await api.pages(
                GoogleEventsPageDTO.self, path: GoogleAPIClient.calendarPath(calendar.id, "/events"), query: query,
                next: { $0.nextPageToken },
                handle: { events += ($0.items ?? []).compactMap { GoogleEventMapper.map($0, calendar: calendar) } })
        } catch let error as GoogleAPIError {
            // A calendar that was removed or lost access is skipped; anything else is not ours to interpret.
            if error == .notFound || error == .forbidden { return [] }
            throw error.sourceError
        }
        return events
    }

    public func changes() -> AsyncStream<CalendarChange> { monitor.changes(polling: self) }

    // Temporary stub, replaced in Task 9. It probes the API so provider errors still map to SourceError.
    public func checkForChanges() async throws -> CalendarChange? {
        do { _ = try await api.calendarList(); return nil }
        catch let error as GoogleAPIError { throw error.sourceError }
    }
}
