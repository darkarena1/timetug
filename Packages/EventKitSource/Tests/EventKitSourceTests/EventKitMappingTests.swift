import CalendarCore
import CalendarTestSupport
import CoreLocation
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

@Test func hexHelper() {
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

@Test func relativeAndAbsoluteAlarmsAreRead() {
    #expect(EventKitMapping.reminder(EKAlarm(relativeOffset: -600)) == Reminder(minutesBefore: 10))
    #expect(EventKitMapping.reminder(EKAlarm(relativeOffset: 0)) == Reminder(minutesBefore: 0))
    let at = iso("2026-09-18T09:00:00Z")
    #expect(EventKitMapping.reminder(EKAlarm(absoluteDate: at)).trigger == .absolute(at))
}

@Test func locationAlarmsKeepTheirPlaceAndProximity() {
    func alarm(_ proximity: EKAlarmProximity, radius: Double, geo: Bool) -> EKAlarm {
        let a = EKAlarm(relativeOffset: 0)
        let place = EKStructuredLocation(title: "Office")
        if geo { place.geoLocation = CLLocation(latitude: 40.5, longitude: -111.9) }
        place.radius = radius
        a.structuredLocation = place
        a.proximity = proximity
        return a
    }
    #expect(EventKitMapping.reminder(alarm(.enter, radius: 150, geo: true)).trigger
            == .location(StructuredLocation(title: "Office", latitude: 40.5, longitude: -111.9, radius: 150), .enter))
    // No coordinates keeps the title only, and radius 0 (EventKit's "use the default") is nil.
    #expect(EventKitMapping.reminder(alarm(.leave, radius: 0, geo: false)).trigger
            == .location(StructuredLocation(title: "Office"), .leave))
}

@Test func alarmTypesKeepTheirRelatedValue() {
    let sound = EKAlarm(relativeOffset: -60)
    sound.soundName = "Glass"
    #expect(EventKitMapping.reminder(sound).type == .audio(soundName: "Glass"))
    let mail = EKAlarm(relativeOffset: -60)
    mail.emailAddress = "me@x.test"
    #expect(EventKitMapping.reminder(mail).type == .email(address: "me@x.test"))
    #expect(EventKitMapping.reminder(EKAlarm(relativeOffset: -60)).type == .display)
    #expect(EventKitMapping.reminder(EKAlarm(relativeOffset: -60)).isCalendarDefault == nil)
}

// Calendar identity (Issue 6).

@Test func providerComesFromTheSourceTypeOnly() {
    #expect(EventKitMapping.provider(sourceType: .local, calendarType: .local) == .local)
    #expect(EventKitMapping.provider(sourceType: .exchange, calendarType: .exchange) == .microsoft)
    #expect(EventKitMapping.provider(sourceType: .mobileMe, calendarType: .calDAV) == .iCloud)
    #expect(EventKitMapping.provider(sourceType: .calDAV, calendarType: .calDAV) == .calDAV)   // iCloud, Google or other: EventKit says CalDAV
    #expect(EventKitMapping.provider(sourceType: .subscribed, calendarType: .subscription) == .subscription)
    #expect(EventKitMapping.provider(sourceType: .local, calendarType: .birthday) == .subscription)
    #expect(EventKitMapping.provider(sourceType: nil, calendarType: .local) == nil)
}

@Test func supportedAvailabilitiesFollowTheMask() {
    #expect(EventKitMapping.supportedAvailabilities([.busy, .free]) == [.busy, .free])
    #expect(EventKitMapping.supportedAvailabilities([.busy, .free, .tentative, .unavailable]) == [.busy, .free, .tentative, .unavailable])
    #expect(EventKitMapping.supportedAvailabilities([]) == [])
}

@Test func theDefaultCalendarIsTrueSiblingsFalseAndOtherAccountsUnknown() {
    #expect(EventKitMapping.isDefault(calendarID: "a", calendarSourceID: "s1", defaultCalendarID: "a", defaultSourceID: "s1") == true)
    #expect(EventKitMapping.isDefault(calendarID: "b", calendarSourceID: "s1", defaultCalendarID: "a", defaultSourceID: "s1") == false)
    #expect(EventKitMapping.isDefault(calendarID: "c", calendarSourceID: "s2", defaultCalendarID: "a", defaultSourceID: "s1") == nil)
    #expect(EventKitMapping.isDefault(calendarID: "a", calendarSourceID: "s1", defaultCalendarID: nil, defaultSourceID: nil) == nil)
}

@Test func eventAvailabilityRoundTrips() {
    for value in [Availability.busy, .free, .tentative, .unavailable] {
        #expect(EventKitMapping.availability(EventKitMapping.eventAvailability(value)) == value)
    }
}

// UID scope and duplicate lookup (Issues 9 and 11).

@Test func uidScopeIsProviderOnlyForExchange() {
    #expect(EventKitMapping.uidScope(provider: .microsoft) == .provider)
    for provider in [CalendarProvider.iCloud, .local, .subscription, .calDAV, .google] { #expect(EventKitMapping.uidScope(provider: provider) == .global) }
    #expect(EventKitMapping.uidScope(provider: nil) == nil)
}

@Test func aCreateLooksForTheUIDAmongTheEventsAroundTheDraft() {
    #expect(EventKitWriteMapping.matchingIndex(uid: "u-2", candidates: ["u-1", nil, "u-2"]) == 2)
    #expect(EventKitWriteMapping.matchingIndex(uid: "u-9", candidates: ["u-1", nil]) == nil)
    let timing = EventTiming(start: iso("2026-09-21T10:00:00Z"), end: iso("2026-09-21T11:00:00Z"), timeZone: nil, isAllDay: false)
    let window = EventKitWriteMapping.duplicateSearchWindow(for: timing)
    #expect(window.start == iso("2026-09-20T10:00:00Z") && window.end == iso("2026-09-22T11:00:00Z"))
}

// Recurrence rules (Issue 3).

private func ekRule(_ frequency: EKRecurrenceFrequency, interval: Int = 1, days: [EKRecurrenceDayOfWeek]? = nil, monthDays: [Int]? = nil,
                    months: [Int]? = nil, end: EKRecurrenceEnd? = nil, firstDay: Int = 0) -> EKRecurrenceRule {
    let rule = EKRecurrenceRule(recurrenceWith: frequency, interval: interval, daysOfTheWeek: days,
                                daysOfTheMonth: monthDays?.map { NSNumber(value: $0) }, monthsOfTheYear: months?.map { NSNumber(value: $0) },
                                weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: end)
    return rule
}

@Test func aWeeklyRuleOnSeveralDaysIsMapped() {
    let rule = EventKitMapping.rule(ekRule(.weekly, interval: 2, days: [EKRecurrenceDayOfWeek(.monday), EKRecurrenceDayOfWeek(.wednesday)]))
    #expect(rule.frequency == .weekly && rule.interval == 2 && rule.weekdays == [.init(.monday), .init(.wednesday)] && rule.end == .never)
}

@Test func theLastFridayOfTheMonthKeepsItsPosition() {
    let rule = EventKitMapping.rule(ekRule(.monthly, days: [EKRecurrenceDayOfWeek(.friday, weekNumber: -1)]))
    #expect(rule.weekdays == [.init(.friday, ordinal: -1)])
}

@Test func aYearlyRuleKeepsItsMonthsAndDays() {
    let rule = EventKitMapping.rule(ekRule(.yearly, monthDays: [15], months: [3, 9]))
    #expect(rule.frequency == .yearly && rule.months == [3, 9] && rule.monthDays == [15])
}

@Test func theEndIsACountOrADate() {
    #expect(EventKitMapping.rule(ekRule(.daily, end: EKRecurrenceEnd(occurrenceCount: 5))).end == .count(5))
    let date = iso("2026-12-31T00:00:00Z")
    #expect(EventKitMapping.rule(ekRule(.daily, end: EKRecurrenceEnd(end: date))).end == .until(date))
}

@Test func aFirstDayOfTheWeekOfZeroIsTheICalendarDefault() {
    #expect(EventKitMapping.rule(ekRule(.weekly)).weekStart == .monday)
}

@Test func writtenRulesReadBackTheSame() {
    let rule = RecurrenceRule(frequency: .monthly, interval: 2, weekdays: [.init(.tuesday, ordinal: 2)], monthDays: [], end: .count(6))
    #expect(EventKitMapping.rule(EventKitWriteMapping.recurrenceRule(rule)) == rule)
}
