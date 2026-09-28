import CalendarCore
import Foundation

extension CalDAVCalendarSource {
    static let calendarsScope = "calendars"
    static func calendarScope(_ id: String) -> String { "calendar:" + id }

    /// What a consumer must reload the calendar list for: calendars added or removed, renamed, recoloured, access or
    /// zone changed. Event changes (the ctag) are not part of it.
    static func signature(_ calendars: [CalDAVCalendarInfo]) -> String {
        calendars.map { calendar in
            let d = calendar.descriptor
            return [d.id, d.title, d.colorHex ?? "", String(d.permissions.canEdit), String(d.permissions.canViewDetails), calendar.zone.identifier]
                .joined(separator: "\u{1F}")
        }.sorted().joined(separator: "\u{1E}")
    }

    /// `sync:<token>` when the calendar has a sync token (RFC 6578), else `ctag:<ctag>`.
    static func marker(_ calendar: CalDAVCalendarInfo) -> String {
        if let token = calendar.syncToken, !token.isEmpty { return "sync:" + token }
        return "ctag:" + (calendar.ctag ?? "")
    }

    /// One `PROPFIND` on the home; a `sync-collection` only for calendars whose token moved, so a token bump without
    /// a change is not reported. The first call stores the baseline and returns nil.
    public func checkForChanges() async throws -> CalendarChange? {
        let calendars = try await loadCalendars()
        let owner = connection.connectionID
        let signature = Self.signature(calendars)
        let stored = await syncState.token(for: owner, scope: Self.calendarsScope)
        guard stored == signature else {
            await syncState.setToken(signature, for: owner, scope: Self.calendarsScope)
            for calendar in calendars {
                await syncState.setToken(Self.marker(calendar), for: owner, scope: Self.calendarScope(calendar.descriptor.id))
            }
            return stored == nil ? nil : .calendarsChanged
        }
        var changed = Set<String>()
        for calendar in calendars where try await hasChanged(calendar) { changed.insert(calendar.descriptor.id) }
        return changed.isEmpty ? nil : .eventsChanged(calendarIDs: changed)
    }

    private func hasChanged(_ calendar: CalDAVCalendarInfo) async throws -> Bool {
        let owner = connection.connectionID
        let scope = Self.calendarScope(calendar.descriptor.id)
        let current = Self.marker(calendar)
        let stored = await syncState.token(for: owner, scope: scope)
        guard stored != current else { return false }
        // A ctag server (or a calendar that changed how it reports) has nothing finer to ask.
        guard let stored, stored.hasPrefix("sync:"), current.hasPrefix("sync:") else {
            await syncState.setToken(current, for: owner, scope: scope)
            return true
        }
        let reply = try await client.report(calendar.url, depth: 1, body: DAVXML.syncCollection(token: String(stored.dropFirst(5))))
        if DAVXML.isInvalidSyncToken(reply.response) {
            await syncState.setToken(current, for: owner, scope: scope)
            return true
        }
        switch reply.response.status {
        case 207: break
        // Removed or lost access since the list was read: the next list signature reports it.
        case 403, 404, 410: return false
        default: throw SourceError.invalidResponse("sync-collection answered \(reply.response.status)")
        }
        let status = try DAVXML.multistatus(reply.response.body)
        for response in status.responses {
            if let url = try? client.resolve(response.href, against: reply.url) { await state.forget(url) }
        }
        await syncState.setToken(status.syncToken.map { "sync:" + $0 } ?? current, for: owner, scope: scope)
        return !status.responses.isEmpty
    }
}
