import CalendarCore
import EventKit
import Foundation

extension EventKitSource: SeriesSource {
    /// The series' rules, from the event with this `eventIdentifier` (the id instances carry as `seriesID`). EventKit
    /// cannot list a series' extra or skipped dates, so those are nil. An unknown id, one in another calendar, or an
    /// event that does not repeat is `SourceError.notFound`.
    public func series(id: String, calendarID: String) async throws -> CalendarSeries {
        try requireAccess()
        guard let event = store.event(withIdentifier: id), event.calendar?.calendarIdentifier == calendarID,
              let rules = event.recurrenceRules, !rules.isEmpty else { throw SourceError.notFound }
        let anchor = map(event)
        return CalendarSeries(
            seriesID: id, calendarID: calendarID, start: anchor.start, timeZone: anchor.timeZone, isAllDay: anchor.isAllDay,
            recurrence: RecurrenceSet(rules: rules.map(EventKitMapping.rule), extraDates: nil, excludedDates: nil))
    }
}
