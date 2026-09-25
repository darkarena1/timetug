import CalendarCore
import EventKit
import Foundation
import Testing
@testable import EventKitSource

private func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
private func newYork() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}

@Test func weeklyRuleMapsFrequencyIntervalDaysAndCount() {
    let rule = RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [.init(.monday), .init(.thursday)], end: .count(6))
    let ek = EventKitWriteMapping.recurrenceRule(rule)
    #expect(ek.frequency == .weekly && ek.interval == 2)
    #expect(ek.daysOfTheWeek?.map(\.dayOfTheWeek) == [.monday, .thursday])
    #expect(ek.recurrenceEnd?.occurrenceCount == 6)
}

@Test func monthlyOrdinalsMonthDaysAndYearlyMonthsMap() {
    let ordinal = EventKitWriteMapping.recurrenceRule(RecurrenceRule(frequency: .monthly, weekdays: [.init(.tuesday, ordinal: 2), .init(.friday, ordinal: -1)]))
    #expect(ordinal.daysOfTheWeek?.map(\.weekNumber) == [2, -1])
    let byDay = EventKitWriteMapping.recurrenceRule(RecurrenceRule(frequency: .monthly, monthDays: [1, 15, -1]))
    #expect(byDay.daysOfTheMonth?.map(\.intValue) == [1, 15, -1])
    let yearly = EventKitWriteMapping.recurrenceRule(RecurrenceRule(frequency: .yearly, months: [3, 9]))
    #expect(yearly.monthsOfTheYear?.map(\.intValue) == [3, 9])
}

@Test func untilAndNeverEndsMap() {
    let until = iso("2026-12-31T00:00:00Z")
    #expect(EventKitWriteMapping.recurrenceRule(RecurrenceRule(frequency: .daily, end: .until(until))).recurrenceEnd?.endDate == until)
    #expect(EventKitWriteMapping.recurrenceRule(RecurrenceRule(frequency: .daily)).recurrenceEnd == nil)
}

@Test func remindersBecomeNegativeRelativeOffsets() {
    let alarms = EventKitWriteMapping.alarms([Reminder(minutesBefore: 10), Reminder(minutesBefore: 60)])
    #expect(alarms.map(\.relativeOffset) == [-600, -3600])
}

@Test func hugeReminderOffsetsDoNotOverflow() {
    let alarms = EventKitWriteMapping.alarms([Reminder(minutesBefore: Int.max), Reminder(minutesBefore: Int.min)])
    #expect(alarms.count == 2)
    #expect(alarms[0].relativeOffset < 0 && alarms[1].relativeOffset > 0)
}

@Test func onlyThisInstanceUsesTheSingleEventSpan() {
    #expect(EventKitWriteMapping.span(for: .thisInstance) == .thisEvent)
    #expect(EventKitWriteMapping.span(for: .thisAndFollowing) == .futureEvents)
    #expect(EventKitWriteMapping.span(for: .allInSeries) == .futureEvents)
}

@Test func versionIsTheModificationDateOrNil() {
    #expect(EventKitWriteMapping.version(nil) == nil)
    #expect(EventKitWriteMapping.version(Date(timeIntervalSince1970: 1_790_000_000.5)) == "1790000000.5")
}

@Test func notificationPolicyOtherThanAllIsRefusedOnlyWhenOthersWouldBeNotified() async {
    #expect(throws: Never.self) { try EventKitWriteMapping.checkNotify(.all, hasOtherAttendees: true) }
    #expect(throws: Never.self) { try EventKitWriteMapping.checkNotify(.none, hasOtherAttendees: false) }
    do {
        try EventKitWriteMapping.checkNotify(.externalOnly, hasOtherAttendees: true)
        Issue.record("expected .unsupported")
    } catch let error as WriteError {
        #expect(error == .unsupported(fields: [.attendees]))
    } catch {
        Issue.record("wrong error \(error)")
    }
}

@Test func floatingAllDayRebuildsTheCalendarDatesInTheDeviceZoneAndRoundTrips() throws {
    // Sep 18 and 19 in New York (exclusive end Sep 20), authored in New York.
    let timing = EventTiming(start: iso("2026-09-18T04:00:00Z"), end: iso("2026-09-20T04:00:00Z"), timeZone: TimeZone(identifier: "America/New_York")!, isAllDay: true)
    let floating = try #require(EventKitWriteMapping.floatingAllDay(timing, calendar: newYork()))
    #expect(floating.start == iso("2026-09-18T04:00:00Z") && floating.end == iso("2026-09-20T03:59:59Z"))
    let canonical = EventKitMapping.canonicalAllDay(start: floating.start, end: floating.end, calendar: newYork())
    #expect(canonical.start == timing.start && canonical.end == timing.end)
}

@Test func floatingAllDayKeepsTheCalendarDatesWhenTheDeviceZoneDiffers() throws {
    // Tokyo Sep 18 (one day) written on a New York device is still Sep 18 there.
    let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    let timing = EventTiming(start: iso("2026-09-17T15:00:00Z"), end: iso("2026-09-18T15:00:00Z"), timeZone: tokyo, isAllDay: true)
    let floating = try #require(EventKitWriteMapping.floatingAllDay(timing, calendar: newYork()))
    #expect(floating.start == iso("2026-09-18T04:00:00Z") && floating.end == iso("2026-09-19T03:59:59Z"))
}

@Test func floatingAllDayNeedsAZone() {
    let timing = EventTiming(start: iso("2026-09-18T00:00:00Z"), end: iso("2026-09-19T00:00:00Z"), timeZone: nil, isAllDay: true)
    #expect(EventKitWriteMapping.floatingAllDay(timing, calendar: newYork()) == nil)
}

@Test func floatingAllDayAcrossDaylightSavingKeepsWholeCalendarDays() throws {
    // Nov 1 2026 is the 25-hour fall-back day in New York. One-day event on Nov 1, and a two-day event Nov 1-2.
    let ny = TimeZone(identifier: "America/New_York")!
    let one = EventTiming(start: iso("2026-11-01T04:00:00Z"), end: iso("2026-11-02T05:00:00Z"), timeZone: ny, isAllDay: true)
    let floatingOne = try #require(EventKitWriteMapping.floatingAllDay(one, calendar: newYork()))
    #expect(floatingOne.start == iso("2026-11-01T04:00:00Z") && floatingOne.end == iso("2026-11-02T04:59:59Z"))
    let canonical = EventKitMapping.canonicalAllDay(start: floatingOne.start, end: floatingOne.end, calendar: newYork())
    #expect(canonical.start == one.start && canonical.end == one.end)
    // The spring-forward day (Mar 8 2026) is 23 hours long.
    let spring = EventTiming(start: iso("2026-03-08T05:00:00Z"), end: iso("2026-03-09T04:00:00Z"), timeZone: ny, isAllDay: true)
    let floatingSpring = try #require(EventKitWriteMapping.floatingAllDay(spring, calendar: newYork()))
    #expect(floatingSpring.start == iso("2026-03-08T05:00:00Z") && floatingSpring.end == iso("2026-03-09T03:59:59Z"))
}

@Test func floatingAllDayNeverEndsBeforeItStarts() throws {
    // An unvalidated zero-length timing must still cover one day rather than produce end < start.
    let ny = TimeZone(identifier: "America/New_York")!
    let timing = EventTiming(start: iso("2026-09-18T04:00:00Z"), end: iso("2026-09-18T04:00:00Z"), timeZone: ny, isAllDay: true)
    let floating = try #require(EventKitWriteMapping.floatingAllDay(timing, calendar: newYork()))
    #expect(floating.start == iso("2026-09-18T04:00:00Z") && floating.end == iso("2026-09-19T03:59:59Z"))
}

@Test func theOccurrenceSearchWindowCoversOccurrencesMovedFarFromTheirSlot() {
    let slot = iso("2026-10-14T15:00:00Z")
    let window = EventKitWriteMapping.occurrenceSearchWindow(around: slot)
    for days in [3.0, 60, -30, 365, -365] {
        let moved = slot.addingTimeInterval(days * 86_400)
        #expect(window.contains(moved) && window.contains(moved.addingTimeInterval(1800)), "moved by \(days) days")
    }
    #expect(window.contains(slot))
    // EventKit only searches up to four years at a time.
    #expect(window.duration < 4 * 365 * 86_400)
}
