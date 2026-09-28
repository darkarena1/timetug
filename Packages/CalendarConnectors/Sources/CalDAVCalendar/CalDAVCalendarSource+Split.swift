import CalendarCore
import Foundation
import ICalendar

extension CalDAVCalendarSource {
    /// `.thisAndFollowing` after the first occurrence: (1) the original resource keeps the occurrences before `slot`
    /// (`If-Match` its ETag), (2) a new resource with a new UID holds the rest with the patch applied, carrying the
    /// later overrides and exclusions. If (2) fails, the original body goes back with `If-Match` on the ETag (1)
    /// returned, even when the caller was cancelled; a 412 there (someone edited meanwhile) is not overwritten and the
    /// result is `WriteError.partial`.
    func splitSeries(_ current: FetchedResource, ref: EventRef, patch: EventPatch, slot: Date, calendarZone: TimeZone) async throws -> PatchMerge.Attempt<CalendarEvent> {
        let stamp = now()
        let newUID = makeUUID()
        let newName = makeUUID() + ".ics"
        let parts = try SeriesEditor.split(current.resource, at: slot, newUID: newUID, calendarZone: calendarZone, now: stamp)
        let head = parts.head
        var tail = parts.tail
        guard var tailMaster = tail.master,
              let before = EventReader.timing(of: tailMaster, resolver: tail.resolver, calendarZone: calendarZone) else { throw WriteError.notFound }
        var tailPatch = patch
        var delta: TimeInterval = 0
        if let wanted = patch.timing {
            let moved = Self.seriesTiming(master: before, slot: slot, wanted: wanted, calendarZone: calendarZone)
            tailPatch.timing = moved.timing
            delta = moved.delta
        }
        try EventWriter.apply(tailPatch, to: &tailMaster, now: stamp, organizerAddress: organizerAddress)
        tailMaster.set(ICalProperty(name: "SEQUENCE", value: "0"))
        // The carried exceptions are new components under a new UID: stamp them like the master (SeriesEditor.split
        // moves them across without touching DTSTAMP/LAST-MODIFIED).
        let carried = tail.overrides.map { vevent -> ICalComponent in
            var copy = vevent
            EventWriter.touch(&copy, now: stamp, bumpSequence: false)
            return copy
        }
        tail.setEvents([tailMaster] + carried)
        if delta != 0 { SeriesEditor.shift(&tail, by: delta, calendarZone: calendarZone) }
        if patch.recurrence != .keep { SeriesEditor.pruneUnmatched(&tail, calendarZone: calendarZone) }
        if let timing = patch.timing, let zone = timing.timeZone {
            tail.ensureTimeZones([zone], from: timing.start, through: timing.start.addingTimeInterval(20 * 366 * 86_400))
        }

        let truncatedETag: String
        switch try await put(head, to: current.url, ifMatch: current.etag) {
        case .stale: return .stale
        case .stored(let etag, _): truncatedETag = etag
        }

        let created: PutOutcome
        do {
            created = try await put(tail, to: resourceURL(calendarID: ref.calendarID, name: newName), ifNoneMatch: true)
            guard case .stored = created else { throw SourceError.invalidResponse("a resource with the new series' name already exists") }
        } catch {
            let original = current.resource
            let url = current.url
            // An unstructured task does not inherit the caller's cancellation.
            let restore = await Task { try await self.put(original, to: url, ifMatch: truncatedETag) }.result
            switch restore {
            case .success(.stored):
                throw error
            case .success(.stale):
                throw WriteError.partial("the series was cut short but the new series was not created (\(error)); it was changed meanwhile, so it was not restored")
            case .failure(let restoreError):
                throw WriteError.partial("the series was cut short but the new series was not created (\(error)); restoring it failed (\(restoreError))")
            }
        }
        guard case .stored(let etag, let copy) = created else { throw WriteError.notFound }
        return .done(try await readBack(copy, etag: etag, calendarID: ref.calendarID, name: newName, originalStart: nil))
    }
}
