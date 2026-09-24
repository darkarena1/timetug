import CalendarCore
import EventKit
import Foundation
import Testing
@testable import EventKitSource

private let start = Date(timeIntervalSince1970: 1_790_000_000)
private let timing = EventTiming(start: start, end: start.addingTimeInterval(1800), timeZone: TimeZone(identifier: "UTC"), isAllDay: false)
private let ref = EventRef(calendarID: "cal", eventID: "event")

@Test func eventKitDeclaresWhatItCanAndCannotWrite() {
    let caps = EventKitSource().capabilities
    #expect(caps.canWrite && !caps.canEditAttendees && !caps.canRespondToInvite && !caps.controlsNotifications)
    #expect(caps.writableFields == [.title, .notes, .location, .timing, .availability, .reminders, .recurrence])
    #expect(caps.recurrenceScopes == Set(RecurrenceScope.allCases))
    #expect(caps.canEditAttendees == caps.writableFields.contains(.attendees))
    let source: any CalendarSource = EventKitSource()
    #expect(source is any WritableCalendarSource)
}

// The checks below throw before the store is touched (and before the permission check), so they run without
// calendar access. An invalid recurrence rule would otherwise crash EventKit with an NSException.

@Test func createRefusesAnInvalidRecurrenceRuleBeforeTouchingTheStore() async {
    let source = EventKitSource()
    for rule in [RecurrenceRule(frequency: .weekly, interval: 0), RecurrenceRule(frequency: .daily, end: .count(0))] {
        await expectWriteError(.invalid(rule.interval < 1 ? "recurrence interval must be at least 1" : "recurrence count must be at least 1")) {
            _ = try await source.create(EventDraft(title: "T", timing: timing, recurrence: rule), in: "cal", notify: .none)
        }
    }
}

@Test func updateRefusesAnInvalidRecurrenceRuleBeforeTouchingTheStore() async {
    let source = EventKitSource()
    await expectWriteError(.invalid("recurrence interval must be at least 1")) {
        _ = try await source.update(ref, EventPatch(recurrence: .set(RecurrenceRule(frequency: .weekly, interval: 0))), scope: .allInSeries, notify: .none)
    }
    await expectWriteError(.invalid("recurrence count must be at least 1")) {
        _ = try await source.update(ref, EventPatch(recurrence: .set(RecurrenceRule(frequency: .daily, end: .count(-1)))), scope: .thisInstance, notify: .none)
    }
}

@Test func updateRefusesBadTimingAndNegativeRemindersBeforeTouchingTheStore() async {
    let source = EventKitSource()
    let backwards = EventTiming(start: timing.end, end: timing.start, timeZone: nil, isAllDay: false)
    await expectWriteError(.invalid("end must be after start")) {
        _ = try await source.update(ref, EventPatch(timing: backwards), scope: .thisInstance, notify: .none)
    }
    await expectWriteError(.invalid("reminder minutes must not be negative")) {
        _ = try await source.update(ref, EventPatch(reminders: .set([Reminder(minutesBefore: -1)])), scope: .thisInstance, notify: .none)
    }
}

@Test func unwritableFieldsAreRefusedBeforeTouchingTheStore() async {
    let source = EventKitSource()
    await expectWriteError(.unsupported(fields: [.attendees])) {
        _ = try await source.create(EventDraft(title: "T", timing: timing, attendees: [AttendeeDraft(email: "a@b.c")]), in: "cal", notify: .none)
    }
    await expectWriteError(.unsupported(fields: [.visibility])) {
        _ = try await source.update(ref, EventPatch(visibility: .privateEvent), scope: .thisInstance, notify: .none)
    }
    await expectWriteError(.unsupported(fields: [.attendees])) {
        _ = try await source.respond(to: ref, .accepted, scope: .thisInstance, notify: .none)
    }
}

@Test func mappingAnEventThatIsNotRecurringHasNoSeries() {
    let store = EKEventStore()
    let event = EKEvent(eventStore: store)
    event.calendar = EKCalendar(for: .event, eventStore: store)
    event.title = "Solo"
    event.startDate = start
    event.endDate = start.addingTimeInterval(1800)
    let mapped = EventKitSource(store: store).map(event)
    #expect(mapped.seriesID == nil && mapped.originalStart == nil && mapped.sourceID == "eventkit")
}

private func expectWriteError(_ expected: WriteError, _ body: () async throws -> Void) async {
    do {
        try await body()
        Issue.record("expected \(expected)")
    } catch let error as WriteError {
        #expect(error == expected)
    } catch {
        Issue.record("expected \(expected), got \(error)")
    }
}
