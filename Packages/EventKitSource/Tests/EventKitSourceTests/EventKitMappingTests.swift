import CalendarCore
import EventKit
import Foundation
import Testing
@testable import EventKitSource

private func newYork() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}
private func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

@Test func allDayOneDayEndingAtEndOfDayBecomesExclusiveNextMidnight() {
    let r = EventKitMapping.canonicalAllDay(start: iso("2026-09-18T04:00:00Z"), end: iso("2026-09-19T03:59:59Z"), calendar: newYork())
    #expect(r.start == iso("2026-09-18T04:00:00Z") && r.end == iso("2026-09-19T04:00:00Z"))
}

@Test func allDayMultiDayEndingAtEndOfDay() {
    let r = EventKitMapping.canonicalAllDay(start: iso("2026-09-18T04:00:00Z"), end: iso("2026-09-21T03:59:59Z"), calendar: newYork())
    #expect(r.end == iso("2026-09-21T04:00:00Z"))
}

@Test func allDayAlreadyExclusiveEndIsKept() {
    let r = EventKitMapping.canonicalAllDay(start: iso("2026-09-18T04:00:00Z"), end: iso("2026-09-20T04:00:00Z"), calendar: newYork())
    #expect(r.end == iso("2026-09-20T04:00:00Z"))
}

@Test func allDayZeroLengthCoversOneDay() {
    let r = EventKitMapping.canonicalAllDay(start: iso("2026-09-18T04:00:00Z"), end: iso("2026-09-18T04:00:00Z"), calendar: newYork())
    #expect(r.end == iso("2026-09-19T04:00:00Z"))
}

@Test func allDayAcrossFallBackDay() {
    // 2026-11-01 is 25 hours long in New York: midnight EDT (04:00Z) to midnight EST (05:00Z next day).
    let r = EventKitMapping.canonicalAllDay(start: iso("2026-11-01T04:00:00Z"), end: iso("2026-11-02T04:59:59Z"), calendar: newYork())
    #expect(r.start == iso("2026-11-01T04:00:00Z") && r.end == iso("2026-11-02T05:00:00Z"))
}

@Test func participantStatusMapping() {
    #expect(EventKitMapping.response(.accepted) == .accepted)
    #expect(EventKitMapping.response(.tentative) == .tentative)
    #expect(EventKitMapping.response(.declined) == .declined)
    #expect(EventKitMapping.response(.pending) == .needsAction)
    #expect(EventKitMapping.response(.unknown) == nil)
}

@Test func mailtoAndHexHelpers() {
    #expect(EventKitMapping.email(fromMailto: "mailto:Bo@X.test?subject=hi") == "bo@x.test")
    #expect(EventKitMapping.email(fromMailto: "https://x.test") == nil)
    #expect(EventKitMapping.hex(from: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)) == "#FF0000")
}
