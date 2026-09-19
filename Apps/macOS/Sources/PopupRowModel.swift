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
    /// Tug time and end: the progress bar and countdown follow these.
    let start: Date
    let end: Date
    /// Where the displayed range starts (a merged event shows its longer copy); equals `start` otherwise.
    var shownStart: Date? = nil
    var mergeBadge: String? = nil
    var isMerged = false
    /// "Merged with Apple Intelligence · 4 events" / "4 events merged"; nil when not merged.
    var mergeSummaryText: String? = nil
    /// Titles of the merged events joined with " + ", for the hover tooltip.
    var mergeTooltip: String? = nil
    var memberRows: [MergedMemberRow] = []

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

            let range = PopupText.range(e.shownStart, e.end, locale: locale, timeZone: timeZone)
            let withCalendar = [range, calendar?.title].compactMap { $0 }.joined(separator: " · ")
            let meta: String
            switch kind {
            case .allDay: meta = ["All day", calendar?.title].compactMap { $0 }.joined(separator: " · ")
            case .past: meta = PopupText.duration(e.end.timeIntervalSince(e.shownStart)) + " · done"
            case .current: meta = "Ends " + PopupText.clock(e.end, locale: locale, timeZone: timeZone)
            case .next, .upcoming: meta = withCalendar
            }
            return PopupRowModel(
                id: item.id, kind: kind,
                timeText: kind == .allDay ? "All day" : PopupText.clock(e.shownStart, locale: locale, timeZone: timeZone),
                title: e.title, metaText: meta, colorHex: calendar?.colorHex,
                joinURL: (kind == .current || kind == .next) ? e.conferenceURL : nil,
                start: e.start, end: e.end, shownStart: e.shownStart,
                mergeBadge: MergeBadge.text(e.mergeProvenance), isMerged: e.mergedMembers.count > 1,
                mergeSummaryText: mergeSummary(e), mergeTooltip: mergeTooltip(e),
                memberRows: e.mergedMembers.count > 1
                    ? MergedMemberRow.rows(for: e, calendars: calendars, locale: locale, timeZone: timeZone) : [])
        }
    }

    private static func mergeSummary(_ e: CalendarEvent) -> String? {
        let count = e.mergedMembers.count
        guard count > 1 else { return nil }
        if let badge = MergeBadge.text(e.mergeProvenance) { return "\(badge) \u{00B7} \(count) events" }
        return "\(count) events merged"
    }

    private static let tooltipLimit = 120

    private static func mergeTooltip(_ e: CalendarEvent) -> String? {
        guard e.mergedMembers.count > 1 else { return nil }
        let text = e.mergedMembers.map(\.title).joined(separator: " + ")
        return text.count <= tooltipLimit ? text : String(text.prefix(tooltipLimit - 1)) + "\u{2026}"
    }

    /// Current and upcoming timed events (not past, not all-day).
    static func meetingsLeft(agenda: DayAgenda) -> Int {
        agenda.items.filter { !$0.event.isAllDay && $0.state != .past }.count
    }
}

/// One original copy inside a merged card, with all text decided.
struct MergedMemberRow: Identifiable, Equatable {
    let id: String
    let title: String
    let calendarLabel: String
    let timeText: String
    /// The copy whose title and details the card shows.
    let isShown: Bool
    let member: MergedMember

    static func rows(for event: CalendarEvent, calendars: [CalendarInfo],
                     locale: Locale = .current, timeZone: TimeZone = .current) -> [MergedMemberRow] {
        let byKey = Dictionary(calendars.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var shownFound = false
        return event.mergedMembers.map { member in
            let label: String
            if let info = byKey[member.calendarKey] {
                label = [info.title, info.accountName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
            } else {
                label = member.calendarKey.split(separator: "/", maxSplits: 1).last.map(String.init) ?? member.calendarKey
            }
            let shown = !shownFound && member.title == event.title && member.calendarKey == event.calendarKey
            if shown { shownFound = true }
            return MergedMemberRow(
                id: member.contentKey, title: member.title, calendarLabel: label,
                timeText: PopupText.range(member.start, member.end, locale: locale, timeZone: timeZone),
                isShown: shown, member: member)
        }
    }
}
