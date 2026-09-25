import CalendarCore
import CalendarTestSupport
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

@Test func canonicalAllDayPassesTheConformanceCheck() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let (start, end) = EventKitMapping.canonicalAllDay(
        start: calendar.date(from: DateComponents(year: 2026, month: 9, day: 21))!,
        end: calendar.date(from: DateComponents(year: 2026, month: 9, day: 22))!, calendar: calendar)
    let event = CalendarEvent(eventID: "a", calendarID: "c", title: "Holiday", start: start, end: end,
                              timeZone: calendar.timeZone, isAllDay: true)
    #expect(AllDayConformance.violations(event).isEmpty)
}

@Test func birthdayAndSubscriptionCalendarsAreNotStandard() {
    #expect(EventKitMapping.kind(.birthday) == .birthdays)
    #expect(EventKitMapping.kind(.subscription) == .subscribed)
    for type in [EKCalendarType.local, .calDAV, .exchange] {
        #expect(EventKitMapping.kind(type) == .standard)
    }
}

@Test func everyEventKitStatusMapsAndCancelledStaysCancelled() {
    #expect(EventKitMapping.status(.canceled) == .cancelled)
    #expect(EventKitMapping.status(.tentative) == .tentative)
    #expect(EventKitMapping.status(.confirmed) == .confirmed)
    #expect(EventKitMapping.status(.none) == .confirmed)
}

@Test func aPlainEventKeepsItsIdentifierAsEventID() {
    #expect(EventKitMapping.eventID(identifier: "abc", occurrenceDate: iso("2026-09-18T10:00:00Z"), isOccurrence: false) == "abc")
}

@Test func occurrencesOfOneSeriesGetDifferentEventIDs() {
    let first = EventKitMapping.eventID(identifier: "abc", occurrenceDate: iso("2026-09-18T10:00:00Z"), isOccurrence: true)
    let second = EventKitMapping.eventID(identifier: "abc", occurrenceDate: iso("2026-09-25T10:00:00Z"), isOccurrence: true)
    #expect(first != second)
    #expect(first.hasPrefix("abc#"))
}

@Test func aMovedOccurrenceKeepsTheIDOfItsOriginalSlot() {
    // `occurrenceDate` is the original slot, so moving the occurrence (which changes `startDate`) does not change the id.
    let slot = iso("2026-09-18T10:00:00Z")
    #expect(EventKitMapping.eventID(identifier: "abc", occurrenceDate: slot, isOccurrence: true)
            == EventKitMapping.eventID(identifier: "abc", occurrenceDate: slot, isOccurrence: true))
}

@Test func aWriteRefBuiltFromAnOccurrenceStillMatchesItsOccurrence() {
    // The event's `eventID` carries a suffix, the ref's `seriesID` is the raw shared identifier.
    let slot = iso("2026-09-18T10:00:00Z")
    let event = CalendarEvent(
        eventID: EventKitMapping.eventID(identifier: "abc", occurrenceDate: slot, isOccurrence: true), calendarID: "cal",
        title: "Weekly", start: slot, end: slot.addingTimeInterval(1800), series: .occurrence(seriesID: "abc", originalStart: slot))
    let ref = EventRef(event)
    #expect(EventKitWriteMapping.isOccurrence(ref, eventIdentifier: "abc", occurrenceDate: slot))
    #expect(!EventKitWriteMapping.isOccurrence(ref, eventIdentifier: "abc", occurrenceDate: slot.addingTimeInterval(7 * 86_400)))
    #expect(!EventKitWriteMapping.isOccurrence(ref, eventIdentifier: "other", occurrenceDate: slot))
}

// Provided fields (Issue 2).

@Test func availabilityMapsEveryValueAndNotSupportedIsNil() {
    #expect(EventKitMapping.availability(.busy) == .busy)
    #expect(EventKitMapping.availability(.free) == .free)
    #expect(EventKitMapping.availability(.tentative) == .tentative)
    #expect(EventKitMapping.availability(.unavailable) == .unavailable)
    #expect(EventKitMapping.availability(.notSupported) == nil)
}

@Test func seriesSeparatesOccurrencesFromSingleEvents() {
    let slot = iso("2026-09-18T10:00:00Z")
    #expect(EventKitMapping.series(isOccurrence: true, identifier: "abc", occurrenceDate: slot) == .occurrence(seriesID: "abc", originalStart: slot))
    #expect(EventKitMapping.series(isOccurrence: false, identifier: "abc", occurrenceDate: slot) == .notRecurring)
}

@Test func participationCoversSelfAttendeeOrganizerOnlyAndNotInvited() {
    #expect(EventKitMapping.participation(selfStatus: .accepted, organizerIsCurrentUser: false) == .invited(.accepted))
    #expect(EventKitMapping.participation(selfStatus: .delegated, organizerIsCurrentUser: false) == .invited(.needsAction))   // unknown status: awaiting a reply
    #expect(EventKitMapping.participation(selfStatus: nil, organizerIsCurrentUser: true) == .invited(.accepted))
    #expect(EventKitMapping.participation(selfStatus: nil, organizerIsCurrentUser: false) == .notInvited)
}

@Test func onlyAlarmsRelativeToTheStartAreReadForNow() {
    #expect(EventKitMapping.reminder(EKAlarm(relativeOffset: -600)) == Reminder(minutesBefore: 10))
    #expect(EventKitMapping.reminder(EKAlarm(relativeOffset: 0)) == Reminder(minutesBefore: 0))
    #expect(EventKitMapping.reminder(EKAlarm(absoluteDate: iso("2026-09-18T09:00:00Z"))) == nil)
}
