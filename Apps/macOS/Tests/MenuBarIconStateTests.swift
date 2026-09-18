import AppKit
import TimeTugCore
import XCTest
@testable import TimeTug

final class MenuBarIconStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let calendarKey = CalendarInfo.key(sourceID: "src", calendarID: "cal")

    private var settings: TakeoverSettings {
        var s = TakeoverSettings()
        s.takeoverCalendarKeys = [calendarKey]
        return s
    }

    private func event(startingIn offset: TimeInterval, duration: TimeInterval = 1800,
                       calendarID: String = "cal", isAllDay: Bool = false,
                       response: ResponseStatus = .unknown) -> CalendarEvent {
        CalendarEvent(sourceEventID: "e1", sourceID: "src", calendarID: calendarID, title: "Sync",
                      start: now.addingTimeInterval(offset), end: now.addingTimeInterval(offset + duration),
                      isAllDay: isAllDay, otherAttendeeCount: 1, responseStatus: response)
    }

    private func resolve(_ events: [CalendarEvent], ledger: TakeoverLedger = TakeoverLedger()) -> MenuBarIconState {
        MenuBarIconState.resolve(events: events, settings: settings, ledger: ledger, now: now)
    }

    func testNoEventsIsIdle() { XCTAssertEqual(resolve([]), .idle) }
    func testThirtyMinutesAwayIsIdle() { XCTAssertEqual(resolve([event(startingIn: 30 * 60)]), .idle) }
    func testNineMinutesAwayIsSoon() { XCTAssertEqual(resolve([event(startingIn: 9 * 60)]), .soon) }
    func testExactlyTenMinutesIsSoon() { XCTAssertEqual(resolve([event(startingIn: 10 * 60)]), .soon) }
    func testElevenMinutesAwayIsIdle() { XCTAssertEqual(resolve([event(startingIn: 11 * 60)]), .idle) }
    func testInProgressUnacknowledgedIsSoon() { XCTAssertEqual(resolve([event(startingIn: -300)]), .soon) }

    func testAcknowledgedIsIdle() {
        let e = event(startingIn: -300)
        var ledger = TakeoverLedger()
        ledger.markFired(e, now: Date(timeIntervalSince1970: 1_799_999_000))
        XCTAssertEqual(resolve([e], ledger: ledger), .idle)
    }

    func testSnoozedStaysSoon() {
        let e = event(startingIn: -300)
        var ledger = TakeoverLedger()
        ledger.snooze(e, for: 300, now: now)
        XCTAssertEqual(resolve([e], ledger: ledger), .soon)
    }

    func testEndedMeetingIsIdle() { XCTAssertEqual(resolve([event(startingIn: -3600, duration: 1800)]), .idle) }
    func testNotOptedInCalendarIsIdle() { XCTAssertEqual(resolve([event(startingIn: 60, calendarID: "other")]), .idle) }
    func testAllDayIsIdle() { XCTAssertEqual(resolve([event(startingIn: 60, isAllDay: true)]), .idle) }
    func testDeclinedIsIdle() { XCTAssertEqual(resolve([event(startingIn: 60, response: .declined)]), .idle) }

    func testIconAssetsExistInBundle() {
        XCTAssertNotNil(NSImage(named: "MenuBarColor"))
        XCTAssertNotNil(NSImage(named: "MenuBarTemplate"))
    }
}
