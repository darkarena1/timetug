import Foundation
import TimeTugCore
import XCTest
@testable import TimeTug

final class TimeFormattingTests: XCTestCase {
    func testCompact() {
        XCTAssertEqual(TimeFormatting.compact(45), "45s")
        XCTAssertEqual(TimeFormatting.compact(60), "1m")
        XCTAssertEqual(TimeFormatting.compact(299), "4m")
        XCTAssertEqual(TimeFormatting.compact(3900), "1h 5m")
    }

    func testClock() {
        XCTAssertEqual(TimeFormatting.clock(245), "4:05")
        XCTAssertEqual(TimeFormatting.clock(5), "0:05")
        XCTAssertEqual(TimeFormatting.clock(-3), "0:00")
    }

    private func event(startingIn seconds: TimeInterval, from now: Date, title: String = "Design Review") -> CalendarEvent {
        CalendarEvent(sourceEventID: "1", sourceID: "s", calendarID: "c", title: title,
                      start: now.addingTimeInterval(seconds), end: now.addingTimeInterval(seconds + 1800))
    }

    func testStatusTitleIconOnlyIsNil() {
        let now = Date()
        XCTAssertNil(TimeFormatting.statusTitle(mode: .iconOnly, next: event(startingIn: 299, from: now), now: now))
    }

    func testStatusTitleCountdownOnly() {
        let now = Date()
        XCTAssertEqual(TimeFormatting.statusTitle(mode: .countdown, next: event(startingIn: 299, from: now), now: now), "4m")
    }

    func testStatusTitleNextMeetingTruncatesLongTitles() {
        let now = Date()
        let long = String(repeating: "x", count: 40)
        let title = TimeFormatting.statusTitle(mode: .nextMeeting, next: event(startingIn: 299, from: now, title: long), now: now)
        XCTAssertEqual(title, String(repeating: "x", count: 24) + "… · 4m")
    }

    func testStatusTitleNilWhenNoNextEvent() {
        XCTAssertNil(TimeFormatting.statusTitle(mode: .countdown, next: nil, now: Date()))
    }
}
