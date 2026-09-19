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
            // Identical copies count as one event: only 2+ distinct events present as a merge.
            let showsMerge = distinctMembers(e).count > 1
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
                mergeBadge: showsMerge ? MergeBadge.text(e.mergeProvenance) : nil, isMerged: showsMerge,
                mergeSummaryText: mergeSummary(e), mergeTooltip: mergeTooltip(e),
                memberRows: showsMerge
                    ? MergedMemberRow.rows(for: e, calendars: calendars, locale: locale, timeZone: timeZone) : [])
        }
    }

    /// Distinct events (by content) among the merged copies, in first-appearance order.
    private static func distinctMembers(_ e: CalendarEvent) -> [MergedMember] {
        var seen = Set<String>()
        return e.mergedMembers.filter { seen.insert($0.contentKey).inserted }
    }

    private static func mergeSummary(_ e: CalendarEvent) -> String? {
        let distinct = distinctMembers(e).count
        guard distinct > 1 else { return nil }
        if let badge = MergeBadge.text(e.mergeProvenance) { return "\(badge) \u{00B7} \(distinct) events" }
        return "\(distinct) events merged"
    }

    private static let tooltipLimit = 120

    private static func mergeTooltip(_ e: CalendarEvent) -> String? {
        let distinct = distinctMembers(e)
        guard distinct.count > 1 else { return nil }
        let text = distinct.map(\.title).joined(separator: " + ")
        return text.count <= tooltipLimit ? text : String(text.prefix(tooltipLimit - 1)) + "\u{2026}"
    }

    /// Current and upcoming timed events (not past, not all-day).
    static func meetingsLeft(agenda: DayAgenda) -> Int {
        agenda.items.filter { !$0.event.isAllDay && $0.state != .past }.count
    }
}

/// One distinct event inside a merged card (identical copies on several calendars collapse into one row),
/// with all text decided.
struct MergedMemberRow: Identifiable, Equatable {
    /// The copies' shared `contentKey`.
    let id: String
    let title: String
    let calendarLabel: String
    let timeText: String
    /// How many identical copies this row stands for; the view shows "\u{00D7}N" when above 1.
    let copyCount: Int
    /// The row contains the copy whose title and details the card shows.
    let isShown: Bool
    let members: [MergedMember]

    static func rows(for event: CalendarEvent, calendars: [CalendarInfo],
                     locale: Locale = .current, timeZone: TimeZone = .current) -> [MergedMemberRow] {
        let byKey = Dictionary(calendars.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var order: [String] = []
        var groups: [String: [MergedMember]] = [:]
        for member in event.mergedMembers {
            if groups[member.contentKey] == nil { order.append(member.contentKey) }
            groups[member.contentKey, default: []].append(member)
        }
        var shownFound = false
        return order.map { key in
            let members = groups[key] ?? []
            let first = members[0]
            let shown = !shownFound && members.contains { $0.title == event.title && $0.calendarKey == event.calendarKey }
            if shown { shownFound = true }
            return MergedMemberRow(
                id: key, title: first.title, calendarLabel: label(members, byKey: byKey),
                timeText: PopupText.range(first.start, first.end, locale: locale, timeZone: timeZone),
                copyCount: members.count, isShown: shown, members: members)
        }
    }

    /// Calendar titles in first-appearance order, each with its accounts: "Work \u{00B7} Exchange, Personal \u{00B7} Gmail",
    /// or one title with several accounts: "Shared \u{00B7} Exchange, Gmail".
    private static func label(_ members: [MergedMember], byKey: [String: CalendarInfo]) -> String {
        var titles: [String] = []
        var accounts: [String: [String]] = [:]
        for member in members {
            let title: String
            var account: String?
            if let info = byKey[member.calendarKey] {
                title = info.title
                account = info.accountName
            } else {
                title = member.calendarKey.split(separator: "/", maxSplits: 1).last.map(String.init) ?? member.calendarKey
            }
            if accounts[title] == nil { titles.append(title) }
            var list = accounts[title] ?? []
            if let account, !account.isEmpty, !list.contains(account) { list.append(account) }
            accounts[title] = list
        }
        return titles.map { title in
            let list = accounts[title] ?? []
            return list.isEmpty ? title : title + " \u{00B7} " + list.joined(separator: ", ")
        }.joined(separator: ", ")
    }
}
