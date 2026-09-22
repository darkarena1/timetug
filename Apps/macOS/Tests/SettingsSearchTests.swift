import KeyboardShortcuts
import TimeTugCore
import XCTest
@testable import TimeTug

final class SettingsSearchTests: XCTestCase {
    private func ids(_ query: String, calendars: [CalendarInfo] = []) -> [String] {
        SettingsSearch.results(for: query, calendars: calendars).map(\.id)
    }

    func testTitleSubstringMatch() {
        XCTAssertTrue(ids("lead").contains("lead-time"))
    }

    func testCaseInsensitive() {
        XCTAssertTrue(ids("LOGIN").contains("launch-at-login"))
    }

    func testDiacriticInsensitive() {
        let cal = CalendarInfo(sourceID: "s", calendarID: "1", title: "Café")
        XCTAssertEqual(ids("cafe", calendars: [cal]), ["calendar:s/1"])
    }

    func testKeywordOnlyMatch() {
        XCTAssertEqual(ids("startup"), ["launch-at-login"])
    }

    func testEmptyAndWhitespaceReturnNothing() {
        XCTAssertEqual(ids(""), [])
        XCTAssertEqual(ids("   \n"), [])
    }

    func testQueryIsTrimmed() {
        XCTAssertTrue(ids("  lead  ").contains("lead-time"))
    }

    func testNonsenseReturnsNothing() {
        XCTAssertEqual(ids("qzxwv"), [])
    }

    func testCalendarNameMatches() {
        let cal = CalendarInfo(sourceID: "eventkit", calendarID: "1", title: "Personal")
        let results = SettingsSearch.results(for: "person", calendars: [cal])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.pane, .calendars)
        XCTAssertEqual(results.first?.id, "calendar:eventkit/1")
        XCTAssertEqual(results.first?.title, "Personal")
    }

    func testTitleMatchesRankBeforeKeywordOnlyMatches() {
        // "start": Lead time (keyword "at start") and Launch at login (keyword "startup")
        // match by keyword only, in catalog order; the calendar title match comes first.
        let cal = CalendarInfo(sourceID: "s", calendarID: "9", title: "Start Here")
        XCTAssertEqual(ids("start"), ["lead-time", "launch-at-login"])
        XCTAssertEqual(ids("start", calendars: [cal]), ["calendar:s/9", "lead-time", "launch-at-login"])
    }

    func testSkipFindsTheAllDayToggleThenTheRenamedAttendeesToggle() {
        XCTAssertEqual(ids("skip"), ["skip-all-day", "require-attendees"])
    }

    func testAppearanceFoundByDarkAndTheme() {
        for query in ["dark", "theme"] {
            let hit = SettingsSearch.results(for: query, calendars: []).first { $0.id == "appearance" }
            XCTAssertEqual(hit?.pane, .appearance, query)
        }
    }

    func testCatalogIDsAreUnique() {
        let all = SettingsSearch.catalog.map(\.id)
        XCTAssertEqual(Set(all).count, all.count)
    }

    func testAccountsIsFoundByProviderAndSignInWords() {
        XCTAssertTrue(ids("google").contains("accounts"))
        XCTAssertTrue(ids("sign in").contains("accounts"))
        XCTAssertTrue(ids("apple calendar").contains("accounts"))
    }

    func testEveryCatalogPaneIsValid() {
        for item in SettingsSearch.catalog {
            XCTAssertTrue(SettingsPane.allCases.contains(item.pane), item.id)
        }
    }

    func testPaneOrderAndTitles() {
        XCTAssertEqual(SettingsPane.allCases, [.general, .appearance, .accounts, .calendars, .tugRules])
        XCTAssertEqual(SettingsPane.allCases.map(\.title),
                       ["General", "Appearance", "Accounts", "Calendars", "Tug Rules"])
    }

    @MainActor func testDefaultPaneIsGeneral() {
        XCTAssertEqual(SettingsNavigation().pane, .general)
    }

    @MainActor func testRevealingASoftwareUpdateItemDrillsIntoItsSubPage() {
        for id in ["software-update", "automatic-updates", "beta-updates"] {
            let navigation = SettingsNavigation()
            let item = SettingsSearch.catalog.first { $0.id == id }!
            navigation.reveal(item)
            XCTAssertEqual(navigation.pane, .general, id)
            XCTAssertEqual(navigation.generalPath, [.softwareUpdate], id)
        }
    }

    @MainActor func testRevealingANonSoftwareUpdateItemPopsToTheGeneralHub() {
        let navigation = SettingsNavigation()
        navigation.generalPath = [.softwareUpdate]
        let item = SettingsSearch.catalog.first { $0.id == "launch-at-login" }!
        navigation.reveal(item)
        XCTAssertEqual(navigation.generalPath, [])
    }

    @MainActor func testRevealingAnAppearanceItemAlsoPopsGeneralToItsHub() {
        let navigation = SettingsNavigation()
        navigation.generalPath = [.softwareUpdate]
        let item = SettingsSearch.catalog.first { $0.id == "appearance" }!
        navigation.reveal(item)
        XCTAssertEqual(navigation.pane, .appearance)
        XCTAssertEqual(navigation.generalPath, [])
    }

    func testOldTakeoverTermStillFindsItems() {
        let found = ids("takeover")
        XCTAssertTrue(found.contains("lead-time"))
        XCTAssertTrue(found.contains("test-takeover"))
        XCTAssertTrue(ids("take over").contains("test-takeover"))
        XCTAssertEqual(SettingsSearch.catalog.first { $0.id == "test-takeover" }?.title, "Test tug")
    }

    func testTugFindsTugRulesItems() {
        let found = SettingsSearch.results(for: "tug", calendars: [])
        XCTAssertTrue(found.contains { $0.id == "test-takeover" && $0.pane == .tugRules })
        XCTAssertTrue(found.contains { $0.id == "lead-time" && $0.pane == .tugRules })
    }

    func testAboutIsNoLongerInSettingsSearch() {
        let found = SettingsSearch.results(for: "about", calendars: [])
        XCTAssertFalse(found.contains { $0.pane == .general && $0.id == "about" })
        let ids = SettingsSearch.catalog.map(\.id)
        XCTAssertFalse(ids.contains("about"))
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testGeneralItemsLiveInGeneral() {
        XCTAssertEqual(SettingsSearch.catalog.first { $0.id == "launch-at-login" }?.pane, .general)
    }

    func testAppearanceItemsLiveInAppearance() {
        for id in ["appearance", "popup-card-style", "menu-bar-text"] {
            XCTAssertEqual(SettingsSearch.catalog.first { $0.id == id }?.pane, .appearance, id)
        }
    }

    func testCalendarFoundByAccountName() {
        let cal = CalendarInfo(sourceID: "s", calendarID: "1", title: "Family", accountName: "iCloud")
        let hit = SettingsSearch.results(for: "iCloud", calendars: [cal]).first { $0.id == "calendar:s/1" }
        XCTAssertEqual(hit?.title, "Family")
        XCTAssertEqual(hit?.pane, .calendars)
    }

    func testOldMenuBarPhraseStillFindsMenuBarText() {
        XCTAssertTrue(ids("next to the icon").contains("menu-bar-text"))
        XCTAssertEqual(SettingsSearch.catalog.first { $0.id == "menu-bar-text" }?.title, "Menu Bar Text")
    }

    func testOldVideoLinkPhraseStillFindsVideoLink() {
        XCTAssertTrue(ids("only events with a video link").contains("video-link"))
        XCTAssertTrue(ids("video link").contains("video-link"))
        XCTAssertEqual(SettingsSearch.catalog.first { $0.id == "video-link" }?.title, "Require a video link")
    }

    func testPopupCardStyleFoundByGlassAndFrosted() {
        for query in ["glass", "frosted", "popup cards"] {
            let hit = SettingsSearch.results(for: query, calendars: []).first { $0.id == "popup-card-style" }
            XCTAssertEqual(hit?.pane, .appearance, query)
            XCTAssertEqual(hit?.title, "Popup Cards")
        }
    }

    func testPopupShortcutFoundByHotkeyShortcutKeyboard() {
        for query in ["hotkey", "shortcut", "keyboard"] {
            let hit = SettingsSearch.results(for: query, calendars: []).first { $0.id == "popup-shortcut" }
            XCTAssertEqual(hit?.pane, .general, query)
            XCTAssertEqual(hit?.title, "Show today's meetings")
        }
    }

    func testPopupShortcutNameIsStable() {
        XCTAssertEqual(KeyboardShortcuts.Name.togglePopup.rawValue, "togglePopup")
    }

    func testDedupInferenceLivesInCalendarsAndIsFoundByAliases() {
        XCTAssertEqual(SettingsSearch.catalog.first { $0.id == "dedup-inference" }?.pane, .calendars)
        for query in ["duplicate", "merge", "apple intelligence", "beta"] {
            XCTAssertTrue(SettingsSearch.results(for: query, calendars: []).contains { $0.id == "dedup-inference" }, query)
        }
    }

    func testEnableTugIsSearchableByItsOldNameAndPause() {
        XCTAssertEqual(ids("enable tug").first, "enable-tug")
        XCTAssertTrue(ids("disable").contains("enable-tug"))
        XCTAssertTrue(ids("pause").contains("enable-tug"))
        XCTAssertEqual(SettingsSearch.catalog.first { $0.id == "enable-tug" }?.pane, .tugRules)
    }

    func testRequireAttendeesIsSearchableAndDeclinedIsGone() {
        XCTAssertEqual(ids("require other").first, "require-attendees")
        XCTAssertEqual(SettingsSearch.catalog.first { $0.id == "require-attendees" }?.pane, .tugRules)
        XCTAssertNil(SettingsSearch.catalog.first { $0.id == "skip-declined" })
    }

    func testUpdateSettingsAreFoundInGeneral() {
        for (query, id) in [("update", "software-update"), ("automatic updates", "automatic-updates"), ("beta updates", "beta-updates")] {
            let hit = SettingsSearch.results(for: query, calendars: []).first { $0.id == id }
            XCTAssertEqual(hit?.pane, .general, query)
        }
    }
}
