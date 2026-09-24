// LiveSupport.swift
import EventKit
import Foundation
import Testing

/// Live EventKit tests are opt-in: `TIMETUG_LIVE_EVENTKIT=1 swift test --package-path Packages/EventKitSource --filter eventKit`.
let liveEventKit = ProcessInfo.processInfo.environment["TIMETUG_LIVE_EVENTKIT"] == "1"

/// Creates a scratch calendar in the local ("On My Mac") source, runs `body`, then deletes the calendar and
/// everything in it. Existing calendars are never touched.
func withScratchCalendar(_ body: (EKEventStore, EKCalendar) async throws -> Void) async throws {
    let store = EKEventStore()
    guard try await store.requestFullAccessToEvents() else {
        Issue.record("calendar access was denied")
        return
    }
    guard let source = store.sources.first(where: { $0.sourceType == .local }) else {
        Issue.record("no local calendar source; enable On My Mac in Calendar settings")
        return
    }
    let calendar = EKCalendar(for: .event, eventStore: store)
    calendar.title = "TimeTug live test \(UUID().uuidString.prefix(6))"
    calendar.source = source
    try store.saveCalendar(calendar, commit: true)
    defer { try? store.removeCalendar(calendar, commit: true) }
    try await body(store, calendar)
}

func nextHour(daysAhead: Int = 2) -> Date {
    let calendar = Calendar.current
    let day = calendar.date(byAdding: .day, value: daysAhead, to: Date())!
    return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day)!
}
