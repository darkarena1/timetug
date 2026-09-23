// EventKitLiveSpikeTests.swift
import EventKit
import Foundation
import Testing

@Test(.enabled(if: liveEventKit)) func eventKitRecurringSpike() async throws {
    try await withScratchCalendar { store, calendar in
        let start = nextHour()
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = "Spike weekly"
        event.startDate = start
        event.endDate = start.addingTimeInterval(1800)
        event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 4)))
        try store.save(event, span: .thisEvent, commit: true)

        func occurrences() -> [EKEvent] {
            let predicate = store.predicateForEvents(withStart: start.addingTimeInterval(-86_400), end: start.addingTimeInterval(86_400 * 40), calendars: [calendar])
            return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        }
        var list = occurrences()
        print("SPIKE1 occurrences=\(list.count) (expect 4)")
        print("SPIKE1 sharedEventIdentifier=\(Set(list.map { $0.eventIdentifier }).count == 1)")
        print("SPIKE1 occurrenceDateEqualsStart=\(list.allSatisfy { abs($0.occurrenceDate.timeIntervalSince($0.startDate)) < 1 })")
        print("SPIKE1 hasRecurrenceRulesOnEveryOccurrence=\(list.allSatisfy { $0.hasRecurrenceRules })")

        let id = list[0].eventIdentifier!
        let byID = store.event(withIdentifier: id)
        print("SPIKE2 eventWithIdentifierIsFirstOccurrence=\(byID.map { abs($0.startDate.timeIntervalSince(start)) < 1 } ?? false)")

        // Move the third occurrence: it becomes detached and keeps its original occurrenceDate.
        let third = list[2]
        let originalSlot = third.occurrenceDate!
        third.startDate = third.startDate.addingTimeInterval(3600)
        third.endDate = third.endDate.addingTimeInterval(3600)
        try store.save(third, span: .thisEvent, commit: true)
        list = occurrences()
        let moved = list[2]
        print("SPIKE3 movedIsDetached=\(moved.isDetached) startMoved=\(abs(moved.startDate.timeIntervalSince(originalSlot)) > 1) occurrenceDateKept=\(abs(moved.occurrenceDate.timeIntervalSince(originalSlot)) < 1)")
        print("SPIKE3 movedSharesIdentifier=\(moved.eventIdentifier == id) movedHasRecurrenceRules=\(moved.hasRecurrenceRules)")

        // Edit the whole series through a LATER occurrence's first-occurrence lookup.
        let first = store.event(withIdentifier: id)!
        first.title = "Spike renamed"
        try store.save(first, span: .futureEvents, commit: true)
        list = occurrences()
        print("SPIKE4 allTitles=\(list.map { $0.title ?? "-" })")

        // refresh() on a removed event.
        let victim = list[3]
        try store.remove(victim, span: .thisEvent, commit: true)
        print("SPIKE5 refreshAfterRemove=\(victim.refresh())")
        print("SPIKE5 lastModifiedDateSet=\(first.lastModifiedDate != nil)")

        // Two saves in the same second: does lastModifiedDate distinguish them?
        let a = first.lastModifiedDate
        first.notes = "one"
        try store.save(first, span: .thisEvent, commit: true)
        let b = first.lastModifiedDate
        first.notes = "two"
        try store.save(first, span: .thisEvent, commit: true)
        let c = first.lastModifiedDate
        print("SPIKE6 lastModifiedChangesEachSave=\(a != b && b != c) a=\(String(describing: a)) b=\(String(describing: b)) c=\(String(describing: c))")
    }
}
