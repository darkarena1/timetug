import Foundation
import TimeTugCore

/// Visible label strings, shared by the views and the search catalog so they cannot drift.
enum SettingsText {
    static let leadTime = "Lead time"
    static let videoLink = "Require a video link"
    static let skipSolo = "Skip events with no other attendees"
    static let skipDeclined = "Skip declined events"
    static let testTug = "Test tug"
    static let skipAllDay = "Skip all-day events"
    static let appearance = "Appearance"
    static let menuBarText = "Menu bar text"
    static let launchAtLogin = "Launch at login"
    static let about = "About TimeTug"
    static let aboutButton = "About TimeTug…"
    static let tugCheckbox = "Tug"
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
              keywords: ["tug", "takeover", "take over", "before", "start", "minutes", "at start", "warning"], pane: .tugRules),
        .init(id: "video-link", title: SettingsText.videoLink,
              keywords: ["tug", "takeover", "take over", "zoom", "meet", "teams", "conference", "only events", "only events with a video link", "video link required"], pane: .tugRules),
        .init(id: "skip-solo", title: SettingsText.skipSolo,
              keywords: ["tug", "takeover", "take over", "solo", "alone", "attendees"], pane: .tugRules),
        .init(id: "skip-declined", title: SettingsText.skipDeclined,
              keywords: ["tug", "takeover", "take over", "declined", "rejected"], pane: .tugRules),
        .init(id: "test-takeover", title: SettingsText.testTug,
              keywords: ["tug", "takeover", "take over", "preview", "overlay", "try"], pane: .tugRules),
        .init(id: "skip-all-day", title: SettingsText.skipAllDay,
              keywords: ["list", "hide", "all day", "takeover", "take over", "tug"], pane: .calendars),
        .init(id: "appearance", title: SettingsText.appearance,
              keywords: ["theme", "light", "dark", "auto", "automatic", "mode", "dark mode", "color scheme"], pane: .general),
        .init(id: "menu-bar-text", title: SettingsText.menuBarText,
              keywords: ["menu bar", "text", "next meeting", "countdown", "title", "next to the icon"], pane: .general),
        .init(id: "launch-at-login", title: SettingsText.launchAtLogin,
              keywords: ["startup", "open at login", "boot"], pane: .general),
        .init(id: "about", title: SettingsText.about,
              keywords: ["version", "license", "credits", "info"], pane: .general),
    ]

    static func results(for query: String, calendars: [CalendarInfo]) -> [SettingsSearchItem] {
        let needle = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return [] }

        let calendarItems = calendars.map {
            SettingsSearchItem(id: calendarIDPrefix + $0.key, title: $0.title, keywords: [$0.accountName].compactMap { $0 }, pane: .calendars)
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
