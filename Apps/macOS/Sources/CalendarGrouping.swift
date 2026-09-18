import Foundation
import TimeTugCore

struct CalendarGroup: Hashable, Identifiable {
    let account: String
    let calendars: [CalendarInfo]
    var id: String { account }
}

enum CalendarGrouping {
    static let fallbackAccount = "Other"

    /// Groups by account (first-seen order); calendars within a group sorted by title.
    static func groups(from calendars: [CalendarInfo]) -> [CalendarGroup] {
        var order: [String] = []
        var buckets: [String: [CalendarInfo]] = [:]
        for calendar in calendars {
            let trimmed = calendar.accountName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let account = trimmed.isEmpty ? fallbackAccount : trimmed
            if buckets[account] == nil { order.append(account) }
            buckets[account, default: []].append(calendar)
        }
        return order.map { account in
            CalendarGroup(
                account: account,
                calendars: buckets[account, default: []].sorted {
                    $0.title.localizedStandardCompare($1.title) == .orderedAscending
                })
        }
    }
}
