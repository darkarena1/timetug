import CalendarCore
import CalendarTestSupport
import Foundation
import Testing
@testable import CalDAVCalendar

@Test func firstCheckIsABaselineAndAQuietOneIsNil() async throws {
    let h = CalDAVHarness()
    let source = try await h.source()
    #expect(try await source.checkForChanges() == nil)
    #expect(try await source.checkForChanges() == nil)
    #expect(await h.server.requests("REPORT").isEmpty)   // unchanged tokens need no sync-collection
}

@Test func anotherClientsEditAndRemovalAreReported() async throws {
    let h = CalDAVHarness()
    let source = try await h.source()
    _ = try await source.checkForChanges()
    await h.server.store("home", "single.ics", singleICS())
    #expect(try await source.checkForChanges() == .eventsChanged(calendarIDs: ["home"]))
    #expect(try await source.checkForChanges() == nil)
    await h.server.remove("home", "single.ics")
    #expect(try await source.checkForChanges() == .eventsChanged(calendarIDs: ["home"]))
}

@Test func aNewCalendarIsCalendarsChanged() async throws {
    let h = CalDAVHarness()
    let source = try await h.source()
    _ = try await source.checkForChanges()
    await h.server.configure { $0.collections["work"] = .init(displayName: "Work") }
    #expect(try await source.checkForChanges() == .calendarsChanged)
    #expect(try await source.checkForChanges() == nil)
    await h.server.configure { $0.collections["work"]?.displayName = "Work (renamed)" }
    #expect(try await source.checkForChanges() == .calendarsChanged)
}

@Test func anExpiredTokenRebaselinesAndReportsTheCalendar() async throws {
    let h = CalDAVHarness()
    let source = try await h.source()
    _ = try await source.checkForChanges()
    await h.server.expireSyncTokens()
    await h.server.store("home", "single.ics", singleICS())
    #expect(try await source.checkForChanges() == .eventsChanged(calendarIDs: ["home"]))
    #expect(try await source.checkForChanges() == nil)
}

@Test func aServerWithoutSyncTokensFallsBackToTheCtag() async throws {
    let h = CalDAVHarness()
    await h.server.configure { $0.supportsSync = false }
    let source = try await h.source()
    _ = try await source.checkForChanges()
    await h.server.store("home", "single.ics", singleICS())
    #expect(try await source.checkForChanges() == .eventsChanged(calendarIDs: ["home"]))
    #expect(await h.server.requests("REPORT").isEmpty)
}

@Test func authExpiredEndsTheStream() async throws {
    let h = CalDAVHarness()
    let source = try await h.source()
    try await h.credentials.setSecrets(["username": "me@icloud.test", "password": "revoked"], for: "c1")
    var received: [CalendarChange] = []
    for await change in source.changes() { received.append(change) }
    #expect(received == [.sourceFailed(.authExpired)])
}
