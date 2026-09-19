import Foundation
import TimeTugCore

/// One event card in the popup, with all text decided.
struct PopupRowModel: Identifiable, Equatable {
    enum Kind { case allDay, past, current, next, upcoming }

    let id: String
    let kind: Kind
    let timeText: String
    let title: String
    let metaText: String
    let colorHex: String?
    let joinURL: URL?
    let start: Date
    let end: Date
    var mergeBadge: String? = nil
    var isMerged = false

    /// Rows for every agenda item, in order. Kinds come from the agenda's own state; `now` is kept for
    /// callers that build rows on a timer.
    static func rows(agenda: DayAgenda, calendars: [CalendarInfo], now: Date,
                     locale: Locale = .current, timeZone: TimeZone = .current) -> [PopupRowModel] {
        let byKey = Dictionary(calendars.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        return agenda.items.map { item in
            let e = item.event
            let calendar = byKey[e.calendarKey]
            let kind: Kind
            if e.isAllDay { kind = .allDay }
            else if item.state == .past { kind = .past }
            else if item.state == .current { kind = .current }
            else if e.id == agenda.next?.id { kind = .next }
            else { kind = .upcoming }

            let range = PopupText.range(e.start, e.end, locale: locale, timeZone: timeZone)
            let withCalendar = [range, calendar?.title].compactMap { $0 }.joined(separator: " · ")
            let meta: String
            switch kind {
            case .allDay: meta = ["All day", calendar?.title].compactMap { $0 }.joined(separator: " · ")
            case .past: meta = PopupText.duration(e.end.timeIntervalSince(e.start)) + " · done"
            case .current: meta = "Ends " + PopupText.clock(e.end, locale: locale, timeZone: timeZone)
            case .next, .upcoming: meta = withCalendar
            }
            return PopupRowModel(
                id: item.id, kind: kind,
                timeText: kind == .allDay ? "All day" : PopupText.clock(e.start, locale: locale, timeZone: timeZone),
                title: e.title, metaText: meta, colorHex: calendar?.colorHex,
                joinURL: (kind == .current || kind == .next) ? e.conferenceURL : nil,
                start: e.start, end: e.end,
                mergeBadge: MergeBadge.text(e.mergeProvenance), isMerged: e.mergedMembers.count > 1)
        }
    }

    /// Current and upcoming timed events (not past, not all-day).
    static func meetingsLeft(agenda: DayAgenda) -> Int {
        agenda.items.filter { !$0.event.isAllDay && $0.state != .past }.count
    }
}
