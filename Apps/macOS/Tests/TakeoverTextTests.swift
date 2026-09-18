import Foundation
import XCTest
@testable import TimeTug

final class TakeoverTextTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let posix = Locale(identifier: "en_US_POSIX")
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = utc; return c }
    private func at(_ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: h, minute: m))!
    }

    // MARK: headline

    func testCountdownIsCalmAboveSixtySeconds() {
        let h = TakeoverText.headline(startsIn: 245)
        XCTAssertEqual(h.kind, .countdown)
        XCTAssertEqual(h.label, "Starts in")
        XCTAssertEqual(h.value, "4:05")
        XCTAssertEqual(h.tone, .calm)
        XCTAssertEqual(TakeoverText.headline(startsIn: 61).tone, .calm)
    }

    func testCountdownIsUrgentAtExactlySixtySeconds() {
        let h = TakeoverText.headline(startsIn: 60)
        XCTAssertEqual(h.kind, .countdown)
        XCTAssertEqual(h.tone, .urgent)
        XCTAssertEqual(h.value, "1:00")
        XCTAssertEqual(TakeoverText.headline(startsIn: 45).value, "0:45")
        XCTAssertEqual(TakeoverText.headline(startsIn: 1).tone, .urgent)
    }

    func testCountdownUsesHoursWhenAnHourOrMore() {
        XCTAssertEqual(TakeoverText.headline(startsIn: 3900).value, "1:05:00")
        XCTAssertEqual(TakeoverText.headline(startsIn: 3600).value, "1:00:00")
        XCTAssertEqual(TakeoverText.headline(startsIn: 3599).value, "59:59")
    }

    func testStartingNowFromZeroUntilAMinuteHasElapsed() {
        for s: TimeInterval in [0, -1, -59, -59.9] {
            let h = TakeoverText.headline(startsIn: s)
            XCTAssertEqual(h.kind, .startingNow, "\(s)")
            XCTAssertNil(h.label)
            XCTAssertEqual(h.value, "Starting now")
            XCTAssertEqual(h.tone, .urgent)
        }
    }

    func testStartedOnceAMinuteHasElapsed() {
        let one = TakeoverText.headline(startsIn: -60)
        XCTAssertEqual(one.kind, .started)
        XCTAssertNil(one.label)
        XCTAssertEqual(one.value, "Started 1 min ago")
        XCTAssertEqual(one.tone, .late)
        XCTAssertEqual(TakeoverText.headline(startsIn: -180).value, "Started 3 min ago")
        XCTAssertEqual(TakeoverText.headline(startsIn: -3900).value, "Started 1h 5m ago")
    }

    func testSpokenHeadline() {
        XCTAssertEqual(TakeoverText.spokenHeadline(startsIn: 45), "Starts in 45 seconds")
        XCTAssertEqual(TakeoverText.spokenHeadline(startsIn: 1), "Starts in 1 second")
        XCTAssertEqual(TakeoverText.spokenHeadline(startsIn: 245), "Starts in 4 minutes 5 seconds")
        XCTAssertEqual(TakeoverText.spokenHeadline(startsIn: 300), "Starts in 5 minutes")
        XCTAssertEqual(TakeoverText.spokenHeadline(startsIn: 0), "Starting now")
        XCTAssertEqual(TakeoverText.spokenHeadline(startsIn: -180), "Started 3 minutes ago")
        XCTAssertEqual(TakeoverText.spokenHeadline(startsIn: -60), "Started 1 minute ago")
    }

    // MARK: details

    private func details(calendar: String? = "Work", others: Int = 5) -> String {
        TakeoverText.details(start: at(10), end: at(10, 30), calendarTitle: calendar,
                             otherAttendees: others, locale: posix, timeZone: utc)
    }

    func testDetailsFull() {
        XCTAssertEqual(details(), "10:00 – 10:30 AM · Work · 6 people")
    }

    func testDetailsOmitsMissingParts() {
        XCTAssertEqual(details(calendar: nil), "10:00 – 10:30 AM · 6 people")
        XCTAssertEqual(details(calendar: ""), "10:00 – 10:30 AM · 6 people")
        XCTAssertEqual(details(others: 0), "10:00 – 10:30 AM · Work")
        XCTAssertEqual(details(calendar: nil, others: 0), "10:00 – 10:30 AM")
        XCTAssertEqual(details(others: -1), "10:00 – 10:30 AM · Work")
    }

    func testDetailsOneOtherAttendeeIsTwoPeople() {
        XCTAssertEqual(details(others: 1), "10:00 – 10:30 AM · Work · 2 people")
    }

    // MARK: hints

    func testHintsAllOptions() {
        XCTAssertEqual(TakeoverText.hints(hasJoin: true, snoozeOptions: [60, 300, 600]),
                       "Return joins · Esc dismisses · 1, 5 or 0 snoozes")
    }

    func testHintsWithoutJoin() {
        XCTAssertEqual(TakeoverText.hints(hasJoin: false, snoozeOptions: [60, 300, 600]),
                       "Esc dismisses · 1, 5 or 0 snoozes")
    }

    func testHintsListOnlyAvailableSnoozeKeys() {
        XCTAssertEqual(TakeoverText.hints(hasJoin: true, snoozeOptions: [60, 300]),
                       "Return joins · Esc dismisses · 1 or 5 snoozes")
        XCTAssertEqual(TakeoverText.hints(hasJoin: true, snoozeOptions: [60]),
                       "Return joins · Esc dismisses · 1 snoozes")
        XCTAssertEqual(TakeoverText.hints(hasJoin: true, snoozeOptions: []),
                       "Return joins · Esc dismisses")
        XCTAssertEqual(TakeoverText.hints(hasJoin: false, snoozeOptions: [120]), "Esc dismisses")
    }

    func testSpokenHintsSayTenMinutesForZero() {
        XCTAssertEqual(TakeoverText.spokenHints(hasJoin: true, snoozeOptions: [60, 300, 600]),
                       "Return joins. Escape dismisses. 1 snoozes for 1 minute, 5 for 5 minutes, 0 for 10 minutes.")
        XCTAssertEqual(TakeoverText.spokenHints(hasJoin: false, snoozeOptions: []), "Escape dismisses.")
    }

    func testSnoozeKey() {
        XCTAssertEqual(TakeoverText.snoozeKey(for: 60), "1")
        XCTAssertEqual(TakeoverText.snoozeKey(for: 300), "5")
        XCTAssertEqual(TakeoverText.snoozeKey(for: 600), "0")
        XCTAssertNil(TakeoverText.snoozeKey(for: 120))
        XCTAssertNil(TakeoverText.snoozeKey(for: 0))
    }

    func testSnoozeTitle() {
        XCTAssertEqual(TakeoverText.snoozeTitle(60), "1 minute")
        XCTAssertEqual(TakeoverText.snoozeTitle(300), "5 minutes")
        XCTAssertEqual(TakeoverText.snoozeTitle(600), "10 minutes")
    }

    // MARK: announcement

    func testAnnouncement() {
        XCTAssertEqual(TakeoverText.announcement(title: "Standup", startsIn: 245),
                       "Standup starts in 4 minutes")
        XCTAssertEqual(TakeoverText.announcement(title: "Standup", startsIn: 45),
                       "Standup starts in less than a minute")
        XCTAssertEqual(TakeoverText.announcement(title: "Standup", startsIn: 0), "Standup is starting now")
        XCTAssertEqual(TakeoverText.announcement(title: "Standup", startsIn: -30), "Standup is starting now")
        XCTAssertEqual(TakeoverText.announcement(title: "Standup", startsIn: -180), "Standup started 3 minutes ago")
        XCTAssertEqual(TakeoverText.announcement(title: "Standup", startsIn: -60), "Standup started 1 minute ago")
    }
}
