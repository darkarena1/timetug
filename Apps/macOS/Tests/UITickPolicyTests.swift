import CalendarCore
import TimeTugCore
import XCTest
@testable import TimeTug

final class UITickPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }

    private func event(startAfter seconds: TimeInterval, length: TimeInterval = 1800) -> TimeTugCalendarEvent {
        let start = now.addingTimeInterval(seconds)
        return TimeTugCalendarEvent(event: CalendarCore.CalendarEvent(
            eventID: "e", calendarID: "c", title: "Meeting", start: start, end: start.addingTimeInterval(length)), sourceID: "s")
    }

    func testCountdownUsesMinuteTransitionsThenSeconds() {
        let far = event(startAfter: 61)
        let wake = UITickPolicy.next(now: now, mode: .countdown, nextEvent: far, events: [], leadTime: 60, calendar: calendar)!
        XCTAssertEqual(wake.date.timeIntervalSince(now), 1.02, accuracy: 0.01)
        XCTAssertFalse(wake.rebuildAgenda)
        let boundary = event(startAfter: 60)
        let boundaryWake = UITickPolicy.next(now: now, mode: .countdown, nextEvent: boundary,
                                             events: [], leadTime: 60, calendar: calendar)!
        XCTAssertEqual(boundaryWake.date.timeIntervalSince(now), 0.02, accuracy: 0.01)
        let near = event(startAfter: 59)
        let nearWake = UITickPolicy.next(now: now, mode: .countdown, nextEvent: near, events: [], leadTime: 60, calendar: calendar)!
        XCTAssertEqual(nearWake.date.timeIntervalSince(now), 0.02, accuracy: 0.01)
    }

    func testIconOnlyIdleWaitsForDayBoundaryAndEventStartRebuilds() {
        let idle = UITickPolicy.next(now: now, mode: .iconOnly, nextEvent: nil, events: [], leadTime: 60, calendar: calendar)!
        XCTAssertGreaterThan(idle.date.timeIntervalSince(now), 3600)
        XCTAssertTrue(idle.rebuildAgenda)
        let meeting = event(startAfter: 30)
        let wake = UITickPolicy.next(now: now, mode: .iconOnly, nextEvent: nil, events: [meeting], leadTime: 60, calendar: calendar)!
        XCTAssertEqual(wake.date, meeting.start)
        XCTAssertTrue(wake.rebuildAgenda)
    }

    func testAnIdleHourHasNoTickTriggeredStructuralRebuilds() {
        var cursor = now
        var rebuilds = 0
        let hourEnd = now.addingTimeInterval(3600)
        while let wake = UITickPolicy.next(now: cursor, mode: .iconOnly, nextEvent: nil,
                                           events: [], leadTime: 60, calendar: calendar), wake.date < hourEnd {
            if wake.rebuildAgenda { rebuilds += 1 }
            cursor = wake.date
        }
        XCTAssertEqual(rebuilds, 0)
    }
}
