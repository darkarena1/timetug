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
        let cal = CalendarInfo(sourceID: "eventkit", calendarID: "1", title: "Darkarena")
        let results = SettingsSearch.results(for: "dark", calendars: [cal])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.pane, .calendars)
        XCTAssertEqual(results.first?.id, "calendar:eventkit/1")
        XCTAssertEqual(results.first?.title, "Darkarena")
    }

    func testTitleMatchesRankBeforeKeywordOnlyMatches() {
        // "start": Lead time (keyword "at start") and Launch at login (keyword "startup")
        // match by keyword only, in catalog order; the calendar title match comes first.
        let cal = CalendarInfo(sourceID: "s", calendarID: "9", title: "Start Here")
        XCTAssertEqual(ids("start"), ["lead-time", "launch-at-login"])
        XCTAssertEqual(ids("start", calendars: [cal]), ["calendar:s/9", "lead-time", "launch-at-login"])
    }

    func testCatalogOrderAmongTitleMatches() {
        XCTAssertEqual(ids("skip"), ["skip-solo", "skip-declined", "skip-all-day"])
    }

    func testCatalogIDsAreUnique() {
        let all = SettingsSearch.catalog.map(\.id)
        XCTAssertEqual(Set(all).count, all.count)
    }

    func testEveryCatalogPaneIsValid() {
        for item in SettingsSearch.catalog {
            XCTAssertTrue(SettingsPane.allCases.contains(item.pane), item.id)
        }
    }

    func testPaneOrderAndTitles() {
        XCTAssertEqual(SettingsPane.allCases, [.general, .calendars, .tugRules])
        XCTAssertEqual(SettingsPane.allCases.map(\.title), ["General", "Calendars", "Tug Rules"])
    }

    @MainActor func testDefaultPaneIsGeneral() {
        XCTAssertEqual(SettingsNavigation().pane, .general)
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

    func testAboutIsInGeneral() {
        let found = SettingsSearch.results(for: "about", calendars: [])
        XCTAssertEqual(found.first { $0.id == "about" }?.pane, .general)
        XCTAssertEqual(found.first { $0.id == "about" }?.title, "About TimeTug")
    }

    func testGeneralItemsLiveInGeneral() {
        for id in ["menu-bar-text", "launch-at-login", "about"] {
            XCTAssertEqual(SettingsSearch.catalog.first { $0.id == id }?.pane, .general, id)
        }
    }
}
