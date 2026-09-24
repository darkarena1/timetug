import CalendarCore
import CalendarTestSupport
import EventKit
import Foundation
import Testing
@testable import EventKitSource

// Opt-in live tests: they need calendar permission and create (then delete) a scratch calendar, so they never run in
// CI. Run: TIMETUG_LIVE_EVENTKIT=1 swift test --package-path Packages/EventKitSource --filter eventKit
// (every live test id starts with "eventKit"; a filter of "Live" matches nothing).

@Test(.enabled(if: liveEventKit)) func eventKitPassesTheWritableConformanceChecks() async throws {
    try await withScratchCalendar { store, calendar in
        let source = EventKitSource(store: store)
        let window = DateInterval(start: nextHour(daysAhead: 1), duration: 86_400 * 3)
        let violations = await WritableSourceConformance.violations(of: source, calendarID: calendar.calendarIdentifier, window: window)
        #expect(violations.isEmpty, "\(violations)")
    }
}

@Test(.enabled(if: liveEventKit)) func eventKitRecurringScopesEditTheRightOccurrences() async throws {
    try await withScratchCalendar { store, calendar in
        let source = EventKitSource(store: store)
        let id = calendar.calendarIdentifier
        let start = nextHour(daysAhead: 3)
        let window = DateInterval(start: start.addingTimeInterval(-3600), duration: 86_400 * 40)
        let draft = EventDraft(
            title: "Series", timing: EventTiming(start: start, end: start.addingTimeInterval(1800), timeZone: .current, isAllDay: false),
            recurrence: RecurrenceRule(frequency: .weekly, end: .count(4)))
        _ = try await source.create(draft, in: id, notify: .none)

        func occurrences() async throws -> [CalendarEvent] {
            try await source.events(in: window).filter { $0.calendarID == id }.sorted { $0.start < $1.start }
        }
        var list = try await occurrences()
        #expect(list.count == 4 && list.allSatisfy { $0.seriesID != nil && $0.originalStart != nil && $0.sourceID == "eventkit" })

        _ = try await source.update(EventRef(list[1]), EventPatch(title: "Only second"), scope: .thisInstance, notify: .none)
        list = try await occurrences()
        #expect(list.map(\.title) == ["Series", "Only second", "Series", "Series"])

        _ = try await source.update(EventRef(list[2]), EventPatch(location: .set("Lab")), scope: .thisAndFollowing, notify: .none)
        list = try await occurrences()
        #expect(list.map(\.location) == [nil, nil, "Lab", "Lab"])

        // Unverified: `.futureEvents` on list[2] may keep one series, or split it and re-identify the occurrences
        // from list[2] on. Print the identifiers so a failure is easy to read, and judge `.allInSeries` only on the
        // occurrences that share list[3]'s series, so a split does not produce a misleading failure.
        for (index, event) in list.enumerated() {
            print("LIVE occurrence \(index): eventIdentifier=\(event.eventID) seriesID=\(event.seriesID ?? "nil")")
        }
        _ = try await source.update(EventRef(list[3]), EventPatch(notes: .set("all")), scope: .allInSeries, notify: .none)
        let seriesOfLast = list[3].seriesID
        list = try await occurrences()
        for (index, event) in list.enumerated() {
            print("LIVE after allInSeries \(index): eventIdentifier=\(event.eventID) notes=\(event.notes ?? "nil")")
        }
        #expect(list.filter { $0.seriesID == seriesOfLast }.allSatisfy { $0.notes == "all" })

        // A series-wide time change from a later occurrence would move the whole series to that occurrence's date.
        do {
            _ = try await source.update(
                EventRef(list[3]),
                EventPatch(timing: EventTiming(start: list[3].start.addingTimeInterval(3600), end: list[3].end.addingTimeInterval(3600), timeZone: .current, isAllDay: false)),
                scope: .allInSeries, notify: .none)
            Issue.record("expected .unsupported")
        } catch let error as WriteError {
            #expect(error == .unsupported(fields: [.timing]))
        }

        try await source.delete(EventRef(list[2]), scope: .thisAndFollowing, notify: .none)
        list = try await occurrences()
        #expect(list.count == 2)
        try await source.delete(EventRef(list[0]), scope: .allInSeries, notify: .none)
        let remaining = try await occurrences()
        #expect(remaining.isEmpty)
    }
}

@Test(.enabled(if: liveEventKit)) func eventKitStaleVersionsMergeOrConflict() async throws {
    try await withScratchCalendar { store, calendar in
        let source = EventKitSource(store: store)
        let start = nextHour(daysAhead: 2)
        let draft = EventDraft(title: "Meeting", timing: EventTiming(start: start, end: start.addingTimeInterval(1800), timeZone: .current, isAllDay: false))
        let created = try await source.create(draft, in: calendar.calendarIdentifier, notify: .none)

        // Someone else changes the location in the meantime (a separate save bumps lastModifiedDate).
        try await Task.sleep(for: .seconds(1.2))
        let external = try #require(store.event(withIdentifier: created.eventID))
        external.location = "Elsewhere"
        try store.save(external, span: .thisEvent, commit: true)

        var edit = EventEdit(created)
        edit.event.title = "Renamed"
        let merged = try await source.update(EventRef(created), edit.patch, scope: .thisInstance, notify: .none)
        #expect(merged.title == "Renamed" && merged.location == "Elsewhere")

        // Now they change the title, and our stale edit of the title must conflict.
        try await Task.sleep(for: .seconds(1.2))
        let again = try #require(store.event(withIdentifier: created.eventID))
        again.title = "Theirs"
        try store.save(again, span: .thisEvent, commit: true)
        var second = EventEdit(merged)
        second.event.title = "Mine"
        do {
            _ = try await source.update(EventRef(merged), second.patch, scope: .thisInstance, notify: .none)
            Issue.record("expected a conflict")
        } catch let error as WriteError {
            #expect(error == .conflict(fields: [.title]))
        }
    }
}

@Test(.enabled(if: liveEventKit)) func eventKitRefusesWhatItCannotWrite() async throws {
    try await withScratchCalendar { store, calendar in
        let source = EventKitSource(store: store)
        let start = nextHour(daysAhead: 2)
        let timing = EventTiming(start: start, end: start.addingTimeInterval(1800), timeZone: .current, isAllDay: false)
        var draft = EventDraft(title: "T", timing: timing, attendees: [AttendeeDraft(email: "a@b.c")])
        do {
            _ = try await source.create(draft, in: calendar.calendarIdentifier, notify: .none)
            Issue.record("expected .unsupported")
        } catch let error as WriteError {
            #expect(error == .unsupported(fields: [.attendees]))
        }
        draft.attendees = []
        let created = try await source.create(draft, in: calendar.calendarIdentifier, notify: .none)
        do {
            _ = try await source.respond(to: EventRef(created), .accepted, scope: .thisInstance, notify: .none)
            Issue.record("expected .unsupported")
        } catch let error as WriteError {
            #expect(error == .unsupported(fields: [.attendees]))
        }
    }
}
