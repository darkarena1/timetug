import Foundation
import TimeTugCore

/// Visible label strings, shared by the views and the search catalog so they cannot drift.
enum SettingsText {
    static let accounts = "Accounts"
    static let appleCalendar = "Apple Calendar"
    static let enableTug = "Enable Tug"
    static let leadTime = "Lead time"
    static let videoLink = "Require a video link"
    static let requireAttendees = "Require other attendees"
    static let testTug = "Test tug"
    static let skipAllDay = "Skip all-day events"
    static let dedupInference = "Find duplicates with on-device intelligence"
    static let appearance = "Appearance"
    static let popupCards = "Popup cards"
    static let menuBarText = "Menu bar text"
    static let launchAtLogin = "Launch at login"
    static let tugCheckbox = "Tug"
    static let checkForUpdates = "Check for Updates"
    static let automaticUpdates = "Automatic updates"
    static let betaUpdates = "Beta updates"
    static let popupShortcut = "Show today's meetings"
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
        .init(id: "accounts", title: SettingsText.accounts,
              keywords: ["google", "account", "accounts", "sign in", "add account", "remove account", "apple calendar", "eventkit", "icloud", "connect"], pane: .accounts),
        .init(id: "software-update", title: SettingsText.checkForUpdates,
              keywords: ["update", "updates", "upgrade", "version", "software update", "sparkle"], pane: .general),
        .init(id: "automatic-updates", title: SettingsText.automaticUpdates,
              keywords: ["update", "updates", "automatic", "download", "install", "software update"], pane: .general),
        .init(id: "beta-updates", title: SettingsText.betaUpdates,
              keywords: ["update", "updates", "beta", "prerelease", "pre-release", "preview", "early access", "software update"], pane: .general),
        .init(id: "enable-tug", title: SettingsText.enableTug,
              keywords: ["disable", "pause", "off", "mute", "stop", "do not disturb", "focus", "takeover", "take over", "tug"], pane: .tugRules),
        .init(id: "lead-time", title: SettingsText.leadTime,
              keywords: ["tug", "takeover", "take over", "before", "start", "minutes", "at start", "warning"], pane: .tugRules),
        .init(id: "video-link", title: SettingsText.videoLink,
              keywords: ["tug", "takeover", "take over", "zoom", "meet", "teams", "conference", "only events", "only events with a video link", "video link required"], pane: .tugRules),
        .init(id: "require-attendees", title: SettingsText.requireAttendees,
              keywords: ["tug", "takeover", "take over", "solo", "alone", "attendees", "guests", "skip", "only events"], pane: .tugRules),
        .init(id: "test-takeover", title: SettingsText.testTug,
              keywords: ["tug", "takeover", "take over", "preview", "overlay", "try"], pane: .tugRules),
        .init(id: "skip-all-day", title: SettingsText.skipAllDay,
              keywords: ["list", "hide", "all day", "takeover", "take over", "tug"], pane: .calendars),
        .init(id: "dedup-inference", title: SettingsText.dedupInference,
              keywords: ["duplicate", "duplicates", "merge", "merged", "same meeting", "ai", "apple intelligence", "on-device", "beta", "inference"], pane: .calendars),
        .init(id: "appearance", title: SettingsText.appearance,
              keywords: ["theme", "light", "dark", "auto", "automatic", "mode", "dark mode", "color scheme"], pane: .appearance),
        .init(id: "popup-card-style", title: SettingsText.popupCards,
              keywords: ["glass", "frosted", "translucent", "solid", "bubbles", "cards", "style", "popup"], pane: .appearance),
        .init(id: "menu-bar-text", title: SettingsText.menuBarText,
              keywords: ["menu bar", "text", "next meeting", "countdown", "title", "next to the icon"], pane: .appearance),
        .init(id: "launch-at-login", title: SettingsText.launchAtLogin,
              keywords: ["startup", "open at login", "boot"], pane: .general),
        .init(id: "popup-shortcut", title: SettingsText.popupShortcut,
              keywords: ["hotkey", "shortcut", "keyboard", "global", "popup", "open", "toggle"], pane: .general),
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
