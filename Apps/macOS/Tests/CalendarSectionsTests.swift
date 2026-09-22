import CalendarCore
import TimeTugCore
import XCTest
@testable import TimeTug

final class CalendarSectionsTests: XCTestCase {
    private func cal(_ source: String, _ id: String, _ title: String, account: String? = nil,
                     kind: CalendarKind = .standard) -> CalendarInfo {
        CalendarInfo(sourceID: source, calendarID: id, title: title, accountName: account, kind: kind)
    }
    private let google = Connection(kindID: "google", connectionID: "g1", displayName: "me@gmail.com")

    private func make(_ calendars: [CalendarInfo], tug: Set<String> = []) -> CalendarLayout {
        CalendarSections.make(calendars: calendars, connections: [google], sourceIDFor: { _ in "google-g1" }, takeoverKeys: tug)
    }

    func testAppleCalendarComesFirstThenAccountsAndEachIsLabelled() {
        let layout = make([cal("google-g1", "1", "Mine"), cal("eventkit", "2", "Home", account: "iCloud")])
        XCTAssertEqual(layout.sections.map(\.title), ["Apple Calendar", "Google"])
        XCTAssertEqual(layout.sections.map(\.subtitle), ["Calendars on this Mac", "me@gmail.com \u{00B7} connected directly"])
        XCTAssertEqual(layout.sections.map(\.origin), [.appleCalendar, .account(kindID: "google")])
    }

    func testAppleCalendarIsSubGroupedByItsAccountsButDirectAccountsAreNot() {
        let layout = make([
            cal("eventkit", "1", "A", account: "Exchange"), cal("eventkit", "2", "B", account: "Gmail"),
            cal("google-g1", "3", "C", account: "me@gmail.com"),
        ])
        XCTAssertEqual(layout.sections[0].groups.map(\.account), ["Exchange", "Gmail"])
        XCTAssertTrue(layout.sections[0].showsGroupNames)
        XCTAssertFalse(layout.sections[1].showsGroupNames)
    }

    func testBirthdaysAndSubscriptionsMoveToSystemUnlessTugIsOn() {
        let layout = make([
            cal("eventkit", "1", "Work", kind: .standard),
            cal("eventkit", "2", "Birthdays", kind: .birthdays),
            cal("eventkit", "3", "Holidays", kind: .subscribed),
            cal("eventkit", "4", "Team Feed", kind: .subscribed),
        ], tug: ["eventkit/4"])
        XCTAssertEqual(layout.sections.flatMap(\.groups).flatMap(\.calendars).map(\.title), ["Team Feed", "Work"])
        XCTAssertEqual(layout.system.map(\.title), ["Birthdays", "Holidays"])
    }

    func testSectionsWithNoMainCalendarsAreDropped() {
        let layout = make([cal("eventkit", "1", "Birthdays", kind: .birthdays)])
        XCTAssertEqual(layout.sections, [])
        XCTAssertEqual(layout.system.count, 1)
    }

    func testCalendarsOfAnUnknownSourceGoToOther() {
        let layout = make([cal("gone", "1", "Orphan")])
        XCTAssertEqual(layout.sections.map(\.title), ["Other"])
    }

    func testProviderNames() {
        XCTAssertEqual(ProviderIcon.displayName(forKindID: "google"), "Google")
        XCTAssertEqual(ProviderIcon.displayName(forKindID: "caldav"), "Caldav")
    }
}
