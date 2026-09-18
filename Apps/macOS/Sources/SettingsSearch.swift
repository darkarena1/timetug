import Foundation
import TimeTugCore

/// Visible label strings, shared by the views and the search catalog so they cannot drift.
enum SettingsText {
    static let leadTime = "Lead time"
    static let videoLink = "Only events with a video link"
    static let skipSolo = "Skip events with no other attendees"
    static let skipDeclined = "Skip declined events"
    static let testTakeover = "Test takeover"
    static let skipAllDay = "Skip all-day events"
    static let menuBarText = "Next to the icon"
    static let launchAtLogin = "Launch at login"
}

struct SettingsSearchItem: Hashable, Identifiable {
    let id: String
    let title: String
    let keywords: [String]
    let pane: SettingsPane
}

enum SettingsSearch {
    static let calendarIDPrefix = "calendar:"

    static let catalog: [SettingsSearchItem] = [
        .init(id: "lead-time", title: SettingsText.leadTime,
              keywords: ["before", "start", "minutes", "at start", "warning"], pane: .takeover),
        .init(id: "video-link", title: SettingsText.videoLink,
              keywords: ["zoom", "meet", "teams", "conference"], pane: .takeover),
        .init(id: "skip-solo", title: SettingsText.skipSolo,
              keywords: ["solo", "alone", "attendees"], pane: .takeover),
        .init(id: "skip-declined", title: SettingsText.skipDeclined,
              keywords: ["declined", "rejected"], pane: .takeover),
        .init(id: "test-takeover", title: SettingsText.testTakeover,
              keywords: ["preview", "overlay", "try"], pane: .takeover),
        .init(id: "skip-all-day", title: SettingsText.skipAllDay,
              keywords: ["list", "hide", "all day"], pane: .calendars),
        .init(id: "menu-bar-text", title: SettingsText.menuBarText,
              keywords: ["menu bar", "text", "next meeting", "countdown", "title"], pane: .menuBar),
        .init(id: "launch-at-login", title: SettingsText.launchAtLogin,
              keywords: ["startup", "open at login", "boot"], pane: .general),
    ]

    static func results(for query: String, calendars: [CalendarInfo]) -> [SettingsSearchItem] {
        let needle = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return [] }

        let calendarItems = calendars.map {
            SettingsSearchItem(id: calendarIDPrefix + $0.key, title: $0.title, keywords: [], pane: .calendars)
        }
        let all = catalog + calendarItems
        let titleMatches = all.filter { fold($0.title).contains(needle) }
        let keywordMatches = all.filter { item in
            !fold(item.title).contains(needle) && item.keywords.contains { fold($0).contains(needle) }
        }
        return titleMatches + keywordMatches
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
