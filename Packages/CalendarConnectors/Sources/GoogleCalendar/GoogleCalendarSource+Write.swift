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

    /// The start of a raw event resource in the calendar's zone (a floating or all-day start reads in that zone). The one
    /// place series code reads a master's start.
    private func start(of raw: RawEvent, calendar: CalendarDescriptor) throws -> GoogleEventMapper.Resolved {
        let dto = try api.decode(GoogleEventDTO.self, from: raw.data)
        guard let start = GoogleEventMapper.resolve(dto.start, calendarZone: calendar.timeZone ?? TimeZone(identifier: "UTC")!) else {
            throw SourceError.invalidResponse("google: unreadable event")
        }
        return start
    }

    /// Throws `.unsupported(fields: [.timing])` unless `ref` is the first occurrence of the series (see `update`).
    private func requireFirstOccurrence(_ ref: EventRef, seriesID: String, calendar: CalendarDescriptor) async throws {
        let start = try start(of: try await fetchRaw(ref.calendarID, seriesID), calendar: calendar)
        guard let slot = ref.originalStart, abs(slot.timeIntervalSince(start.date)) < 1 else {
            throw WriteError.unsupported(fields: [.timing])
        }
    }

    // MARK: Splitting a series

    private struct InstancePage: Decodable {
        struct Item: Decodable { var originalStartTime: GoogleTimeDTO? }
        var items: [Item]?
        var nextPageToken: String?
    }

    /// Occurrences of the series that start before `split`, including individually deleted ones (they still count
    /// toward a `COUNT` rule).
    private func priorInstances(calendarID: String, masterID: String, before split: Date, zone: TimeZone) async throws -> Int {
        var count = 0
        try await api.pages(
            InstancePage.self, path: GoogleAPIClient.eventPath(calendarID, masterID) + "/instances",
            query: [
                URLQueryItem(name: "showDeleted", value: "true"), URLQueryItem(name: "maxResults", value: "250"),
                URLQueryItem(name: "fields", value: "nextPageToken,items(originalStartTime)"),
            ],
            next: { $0.nextPageToken },
            handle: { page in
                for item in page.items ?? [] {
                    if let resolved = GoogleEventMapper.resolve(item.originalStartTime, calendarZone: zone), resolved.date < split { count += 1 }
                }
            })
        return count
    }

    private func patchRecurrence(_ calendarID: String, _ eventID: String, _ lines: [String], etag: String?, notify: NotifyPolicy) async throws {
        var headers: [String: String] = [:]
        if let etag { headers["If-Match"] = etag }
        do {
            _ = try await api.send(
                method: "PATCH", path: GoogleAPIClient.eventPath(calendarID, eventID), query: query(notify),
                body: try GoogleWriteMapper.data(["recurrence": lines]), headers: headers, mode: .write)
        } catch GoogleAPIError.preconditionFailed {
            throw WriteError.conflict(fields: [.recurrence])
        }
    }

    /// Puts the master's original rule back after a failed insert. Runs even when the caller was cancelled (a cancelled
    /// request would otherwise fail at once and leave the series cut off), and is unconditional so it cannot lose to a
    /// concurrent edit of another field. If it fails too the result is `WriteError.partial`.
    private func restoreRecurrence(_ calendarID: String, _ masterID: String, _ original: [String]) async throws {
        do {
            try await Task { try await self.patchRecurrence(calendarID, masterID, original, etag: nil, notify: .none) }.value
        } catch {
            throw WriteError.partial(
                "the series was cut off before this occurrence but the new series could not be created, and restoring the original rule failed")
        }
    }

    /// Whether a failed request may nevertheless have been applied: the reply was lost (a 5xx, a broken connection, a
    /// cancellation) rather than the request refused.
    private static func mightHaveApplied(_ error: Error) -> Bool {
        if error is GoogleAPIError || error is WriteError { return false }
        if let source = error as? SourceError {
            switch source {
            case .server, .network: return true
            default: return false
            }
        }
        return true
    }

    /// The event with this id if it exists, else nil (also when it cannot be checked). Runs even when the caller was
    /// cancelled, because the answer decides whether the master is restored.
    private func existingEvent(_ calendarID: String, _ eventID: String) async -> Data? {
        let lookup = Task<Data?, Never> { try? await self.fetchRaw(calendarID, eventID).data }
        return await lookup.value
    }

    /// The insert body for the new series. Everything that can fail without changing anything (the occurrence, the
    /// count of earlier occurrences, validating the patch) is done here, before the master is touched.
    private func newSeriesBody(
        _ ref: EventRef, master: RawEvent, original: [String], split: Date, masterZone: TimeZone, patch: EventPatch,
        calendar: CalendarDescriptor
    ) async throws -> GoogleWriteMapper.Body {
        let instance = try await fetchRaw(ref.calendarID, ref.eventID)
        var lines = GoogleWriteMapper.rruleLines(original)
        if patch.recurrence == .keep {
            if let total = GoogleWriteMapper.count(in: original) {
                let prior = try await priorInstances(calendarID: ref.calendarID, masterID: master.json["id"] as? String ?? ref.seriesID ?? "", before: split,
                                                     zone: calendar.timeZone ?? TimeZone(identifier: "UTC")!)
                guard total - prior >= 1 else { throw WriteError.invalid("the series has no occurrences left to split off") }
                lines = GoogleWriteMapper.replacingCount(lines, with: total - prior)
            }
            lines += GoogleWriteMapper.carriedOver(original, from: split, zone: masterZone)
        }
        let zoneName = (master.json["start"] as? [String: Any])?["timeZone"] as? String
        return try GoogleWriteMapper.newSeriesBody(
            master: master.json, instance: instance.json, patch: patch, recurrence: lines,
            fallbackZone: zoneName ?? calendar.timeZone?.identifier ?? "UTC")
    }

    /// `.thisAndFollowing`: cut the master's rule just before the occurrence. Delete (`patch == nil`) stops there and
    /// returns nil. Update also inserts a new series from the occurrence with the patch applied. Splitting at the first
    /// occurrence is the same as `.allInSeries`. Truncation notifies attendees only for delete; for update the insert
    /// carries the notification, so they are not told twice.
    ///
    /// Failure handling for update: everything that can fail without changing anything happens before the truncation.
    /// The insert carries an id we chose, so if its reply is lost we can look the event up instead of guessing. If the
    /// insert fails, the master's original rule is restored, and if restoring fails too the result is
    /// `WriteError.partial`. Once the insert has succeeded it is never undone, even if its reply cannot be read.
    private func splitSeries(_ ref: EventRef, calendar: CalendarDescriptor, patch: EventPatch?, notify: NotifyPolicy) async throws -> CalendarEvent? {
        guard let masterID = ref.seriesID, let split = ref.originalStart else {
            throw WriteError.invalid("this and following needs the occurrence's original start")
        }
        let master = try await fetchRaw(ref.calendarID, masterID)
        let first = try start(of: master, calendar: calendar)
        if abs(first.date.timeIntervalSince(split)) < 1 {
            if let patch { return try await update(ref, patch, scope: .allInSeries, notify: notify) }
            try await delete(ref, scope: .allInSeries, notify: notify)
            return nil
        }
        let original = master.json["recurrence"] as? [String] ?? []
        guard !GoogleWriteMapper.rruleLines(original).isEmpty else { throw WriteError.invalid("the series has no recurrence rule") }
        let masterZone = first.zone ?? calendar.timeZone ?? TimeZone(identifier: "UTC")!
        let truncated = GoogleWriteMapper.truncated(original, before: split, allDay: first.isAllDay, zone: masterZone)

        var newSeries: GoogleWriteMapper.Body?
        if let patch {
            newSeries = try await newSeriesBody(ref, master: master, original: original, split: split, masterZone: masterZone, patch: patch, calendar: calendar)
        }
        try await patchRecurrence(ref.calendarID, masterID, truncated, etag: master.etag, notify: patch == nil ? notify : .none)
        guard let newSeries else { return nil }

        var json = newSeries.json
        let newID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()   // base32hex: 0-9 a-v
        json["id"] = newID
        let created: Data
        do {
            created = try await api.send(
                method: "POST", path: GoogleAPIClient.calendarPath(ref.calendarID, "/events"),
                query: query(notify, conference: newSeries.needsConferenceVersion), body: try GoogleWriteMapper.data(json), mode: .write)
        } catch {
            if Self.mightHaveApplied(error),
               let found = await existingEvent(ref.calendarID, newID) {
                return try mapped(found, calendar: calendar)
            }
            try await restoreRecurrence(ref.calendarID, masterID, original)
            throw error
        }
        return try mapped(created, calendar: calendar)
    }
}
