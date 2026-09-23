import CalendarCore
import Foundation

extension GoogleCalendarSource: WritableCalendarSource {
    public func create(_ draft: EventDraft, in calendarID: String, notify: NotifyPolicy) async throws -> CalendarEvent {
        try await translated {
            try draft.validate()
            try WriteValidation.requireWritable(draft.usedFields, capabilities)
            // Build (and so validate) the body before the first request.
            let body = try GoogleWriteMapper.createBody(draft)
            let calendar = try await writableCalendar(calendarID)
            let data = try await api.send(
                method: "POST", path: GoogleAPIClient.calendarPath(calendarID, "/events"),
                query: query(notify, conference: body.needsConferenceVersion), body: try GoogleWriteMapper.data(body.json), mode: .write)
            return try mapped(data, calendar: calendar)
        }
    }

    /// Callers read expanded instances, so a `timing` in `patch` is the instance's absolute date. Sent to the series
    /// master (`.allInSeries`) it would move the whole series, so a series-wide time change is accepted only when `ref`
    /// is the series' first occurrence (its `originalStart` equals the master's start, within a second); otherwise it
    /// throws `WriteError.unsupported(fields: [.timing])` before any PATCH. Other fields are unaffected.
    public func update(_ ref: EventRef, _ patch: EventPatch, scope: RecurrenceScope, notify: NotifyPolicy) async throws -> CalendarEvent {
        try await translated {
            try WriteValidation.requireWritable(patch.touchedFields, capabilities)
            try Self.requireEventID(ref)
            // Validate the whole patch before the first request; the attendee array is filled in later from a fresh fetch.
            _ = try GoogleWriteMapper.patchBody(patch, currentAttendees: [])
            let calendar = try await writableCalendar(ref.calendarID)
            if patch.isEmpty {
                if let base = patch.base { return base }
                return try mapped(try await fetchRaw(ref.calendarID, ref.eventID).data, calendar: calendar)
            }
            if scope == .thisAndFollowing, ref.seriesID != nil {
                guard let event = try await splitSeries(ref, calendar: calendar, patch: patch, notify: notify) else {
                    throw SourceError.invalidResponse("google: the split returned no event")
                }
                return event
            }
            let (targetID, useVersion) = target(ref, scope: scope)
            if scope == .allInSeries, patch.timing != nil, targetID != ref.eventID {
                try await requireFirstOccurrence(ref, seriesID: targetID, calendar: calendar)
            }
            return try await PatchMerge.apply(
                patch: patch, version: useVersion ? ref.version : nil,
                fetchCurrent: { try self.mapped(try await self.fetchRaw(ref.calendarID, targetID).data, calendar: calendar) },
                write: { expected -> PatchMerge.Attempt<CalendarEvent> in
                    var ifMatch = expected
                    var attendees: [[String: Any]]?
                    if let changes = patch.attendees, !changes.isEmpty {
                        // Google replaces the whole array, so start from a fresh copy and judge staleness against the caller's version.
                        let raw = try await self.fetchRaw(ref.calendarID, targetID)
                        if let expected, let etag = raw.etag, etag != expected { return .stale }
                        attendees = raw.attendees
                        ifMatch = raw.etag ?? expected
                    }
                    let body = try GoogleWriteMapper.patchBody(patch, currentAttendees: attendees)
                    var headers: [String: String] = [:]
                    if let ifMatch { headers["If-Match"] = ifMatch }
                    do {
                        let data = try await self.api.send(
                            method: "PATCH", path: GoogleAPIClient.eventPath(ref.calendarID, targetID),
                            query: self.query(notify, conference: body.needsConferenceVersion), body: try GoogleWriteMapper.data(body.json),
                            headers: headers, mode: .write)
                        return .done(try self.mapped(data, calendar: calendar))
                    } catch GoogleAPIError.preconditionFailed {
                        return .stale
                    }
                })
        }
    }

    public func delete(_ ref: EventRef, scope: RecurrenceScope, notify: NotifyPolicy) async throws {
        try await translated {
            try Self.requireEventID(ref)
            let calendar = try await writableCalendar(ref.calendarID)
            if scope == .thisAndFollowing, ref.seriesID != nil {
                _ = try await splitSeries(ref, calendar: calendar, patch: nil, notify: notify)
                return
            }
            let (targetID, _) = target(ref, scope: scope)
            _ = try await api.send(method: "DELETE", path: GoogleAPIClient.eventPath(ref.calendarID, targetID), query: query(notify), mode: .write)
        }
    }

    public func respond(to ref: EventRef, _ response: ResponseStatus, scope: RecurrenceScope, notify: NotifyPolicy) async throws -> CalendarEvent {
        try await translated {
            // Splitting a series only to change one guest's response is not offered.
            if scope == .thisAndFollowing, ref.seriesID != nil { throw WriteError.unsupported(fields: [.attendees]) }
            try Self.requireEventID(ref)
            // Refuse a response Google cannot store before any request (the attendee list here is only a placeholder).
            _ = try GoogleWriteMapper.respondAttendees(current: [["self": true]], response: response)
            let calendar = try await writableCalendar(ref.calendarID)
            let (targetID, _) = target(ref, scope: scope)
            // Only our own response changes, so when the event moves between the fetch and the write, start over on the new etag.
            for _ in 0..<3 {
                try Task.checkCancellation()
                let raw = try await fetchRaw(ref.calendarID, targetID)
                let attendees = try GoogleWriteMapper.respondAttendees(current: raw.attendees, response: response)
                var headers: [String: String] = [:]
                if let etag = raw.etag { headers["If-Match"] = etag }
                do {
                    let data = try await api.send(
                        method: "PATCH", path: GoogleAPIClient.eventPath(ref.calendarID, targetID), query: query(notify),
                        body: try GoogleWriteMapper.data(["attendees": attendees]), headers: headers, mode: .write)
                    return try mapped(data, calendar: calendar)
                } catch GoogleAPIError.preconditionFailed {
                    continue
                }
            }
            throw WriteError.conflict(fields: [.attendees])
        }
    }

    // MARK: Helpers

    /// Translates provider outcomes into `WriteError`; `SourceError` and `WriteError` pass through unchanged.
    private func translated<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() }
        catch let error as GoogleAPIError {
            switch error {
            case .gone, .notFound: throw WriteError.notFound
            case .forbidden: throw WriteError.forbidden(nil)
            case .badRequest(let message): throw WriteError.invalid(message)
            // Unreachable: only writes that carry `If-Match` can get a 412, and each of them handles it itself.
            case .preconditionFailed: throw SourceError.invalidResponse("google: unexpected 412")
            }
        }
    }

    private func query(_ notify: NotifyPolicy, conference: Bool = false) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "sendUpdates", value: GoogleWriteMapper.sendUpdates(notify))]
        if conference { items.append(URLQueryItem(name: "conferenceDataVersion", value: "1")) }
        return items
    }

    /// An empty id would address the events collection itself instead of one event.
    private static func requireEventID(_ ref: EventRef) throws {
        if ref.eventID.isEmpty { throw WriteError.invalid("the event id must not be empty") }
    }

    /// The calendar, provided it exists and the account can write to it.
    private func writableCalendar(_ calendarID: String) async throws -> CalendarDescriptor {
        guard let calendar = try await calendars().first(where: { $0.id == calendarID }) else { throw WriteError.notFound }
        guard calendar.accessRole == .owner || calendar.accessRole == .writer else { throw WriteError.forbidden("read-only calendar") }
        return calendar
    }

    private func mapped(_ data: Data, calendar: CalendarDescriptor) throws -> CalendarEvent {
        let dto = try api.decode(GoogleEventDTO.self, from: data)
        if dto.status == "cancelled" { throw WriteError.notFound }
        guard let event = GoogleEventMapper.map(dto, calendar: calendar, sourceID: id) else {
            throw SourceError.invalidResponse("google: unreadable event")
        }
        return event
    }

    struct RawEvent {
        var data: Data
        var json: [String: Any]
        var etag: String? { json["etag"] as? String }
        var attendees: [[String: Any]] { json["attendees"] as? [[String: Any]] ?? [] }
    }

    /// The full event resource (no `fields` mask), so unmodeled fields and `attendees(self)` are present. A deleted
    /// event (status `cancelled`, still readable by id) is `.notFound`, so it is never patched back to life.
    func fetchRaw(_ calendarID: String, _ eventID: String) async throws -> RawEvent {
        let data = try await api.send(method: "GET", path: GoogleAPIClient.eventPath(calendarID, eventID), mode: .write)
        // `try?`: a body that is not JSON throws a Cocoa error, which must not escape the library.
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw SourceError.invalidResponse("google: unreadable event")
        }
        if json["status"] as? String == "cancelled" { throw WriteError.notFound }
        return RawEvent(data: data, json: json)
    }

    /// The id a write addresses: the instance, or the series master for `.allInSeries` (whose etag differs from the
    /// instance's, so the caller's version cannot lock it).
    private func target(_ ref: EventRef, scope: RecurrenceScope) -> (id: String, useVersion: Bool) {
        guard let series = ref.seriesID, !series.isEmpty else { return (ref.eventID, true) }
        return scope == .allInSeries ? (series, false) : (ref.eventID, true)
    }

    /// Throws `.unsupported(fields: [.timing])` unless `ref` is the first occurrence of the series (see `update`).
    private func requireFirstOccurrence(_ ref: EventRef, seriesID: String, calendar: CalendarDescriptor) async throws {
        let master = try await fetchRaw(ref.calendarID, seriesID)
        let dto = try api.decode(GoogleEventDTO.self, from: master.data)
        guard let start = GoogleEventMapper.resolve(dto.start, calendarZone: calendar.timeZone ?? TimeZone(identifier: "UTC")!) else {
            throw SourceError.invalidResponse("google: unreadable event")
        }
        guard let slot = ref.originalStart, abs(slot.timeIntervalSince(start.date)) < 1 else {
            throw WriteError.unsupported(fields: [.timing])
        }
    }

    /// Implemented in Task 11.
    private func splitSeries(_ ref: EventRef, calendar: CalendarDescriptor, patch: EventPatch?, notify: NotifyPolicy) async throws -> CalendarEvent? {
        throw WriteError.unsupported(fields: [.recurrence])
    }
}
