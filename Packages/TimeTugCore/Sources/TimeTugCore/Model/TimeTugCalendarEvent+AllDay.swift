import CalendarCore
import Foundation

extension TimeTugCalendarEvent {
    /// The first covered date and the exclusive end date, read in the event's own zone (never the viewer's), so an
    /// all-day event stays on the dates it was created for. nil for timed events and for an all-day event without a zone.
    public var allDayDates: (first: CalendarDate, endExclusive: CalendarDate)? {
        guard isAllDay, let zone = timeZone else { return nil }
        return AllDay.dates(start: start, end: end, in: zone)
    }

    public func covers(_ date: CalendarDate) -> Bool {
        guard let dates = allDayDates else { return false }
        return dates.first <= date && date < dates.endExclusive
    }
}
