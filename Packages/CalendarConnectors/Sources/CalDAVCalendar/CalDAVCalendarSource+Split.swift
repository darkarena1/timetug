import CalendarCore
import Foundation

extension CalDAVCalendarSource {
    /// `.thisAndFollowing` after the first occurrence. Filled in by the split task.
    func splitSeries(_ current: FetchedResource, ref: EventRef, patch: EventPatch, slot: Date, calendarZone: TimeZone) async throws -> PatchMerge.Attempt<CalendarEvent> {
        throw WriteError.unsupported(fields: [.recurrence])
    }
}
