import TimeTugCore
import XCTest
@testable import TimeTug

final class CalendarGroupingTests: XCTestCase {
    private func cal(_ id: String, _ title: String, _ account: String?) -> CalendarInfo {
        CalendarInfo(sourceID: "s", calendarID: id, title: title, accountName: account)
    }

    func testEmptyInputGivesNoGroups() {
        XCTAssertEqual(CalendarGrouping.groups(from: []), [])
    }

    func testAccountsAppearInFirstSeenOrder() {
        let groups = CalendarGrouping.groups(from: [
            cal("1", "A", "Work"), cal("2", "B", "iCloud"), cal("3", "C", "Work"),
        ])
        XCTAssertEqual(groups.map(\.account), ["Work", "iCloud"])
    }

    func testCalendarsSortedByTitleWithinGroup() {
        let groups = CalendarGrouping.groups(from: [
            cal("1", "Zeta", "iCloud"), cal("2", "alpha", "iCloud"), cal("3", "Item 10", "iCloud"), cal("4", "Item 2", "iCloud"),
        ])
        XCTAssertEqual(groups.first?.calendars.map(\.title), ["alpha", "Item 2", "Item 10", "Zeta"])
    }

    func testNilEmptyAndWhitespaceAccountsBecomeOther() {
        let groups = CalendarGrouping.groups(from: [
            cal("1", "A", nil), cal("2", "B", ""), cal("3", "C", "  \n"),
        ])
        XCTAssertEqual(groups.map(\.account), ["Other"])
        XCTAssertEqual(groups.first?.calendars.count, 3)
    }

    func testSameTitleInDifferentAccountsStaysSeparate() {
        let groups = CalendarGrouping.groups(from: [
            cal("1", "Home", "iCloud"), cal("2", "Home", "Google"),
        ])
        XCTAssertEqual(groups.map(\.account), ["iCloud", "Google"])
        XCTAssertEqual(groups.map { $0.calendars.count }, [1, 1])
    }
}
