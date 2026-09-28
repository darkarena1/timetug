import CalendarCore
import CalendarTestSupport
import Foundation
import ICalendar
import Testing
@testable import CalDAVCalendar

private func occurrence(_ source: CalDAVCalendarSource, on day: Int, hour: Int = 10) async throws -> CalendarEvent {
    try #require(try await source.events(in: september).first { $0.originalStart == pt(2026, 9, day, hour) })
}

private let autumn = DateInterval(start: pt(2026, 9, 1, 0), end: pt(2026, 11, 1, 0))

@Test func splitAnUntilSeriesMovesLaterExceptions() async throws {
    let h = CalDAVHarness()
    await h.server.store("home", "weekly.ics", weeklyICS(rule: "FREQ=WEEKLY;BYDAY=TU;UNTIL=20261013T235959Z", organizer: nil))
    let source = try await h.source()
    let fifteenth = try await occurrence(source, on: 15)   // the moved occurrence
    let tail = try await source.update(EventRef(fifteenth), EventPatch(title: "New sync"), scope: .thisAndFollowing, notify: .none)
    #expect(tail.eventID == "uuid-2.ics" && tail.seriesID == "uuid-2.ics" && tail.uid == "uuid-1")
    let head = try EventResource(data: Data(try #require(await h.server.body("home", "weekly.ics")).utf8))
    #expect(head.master?.property("RRULE")?.value.contains("UNTIL=20260915T165959Z") == true)
    #expect(head.overrides.isEmpty)
    let newer = try EventResource(data: Data(try #require(await h.server.body("home", "uuid-2.ics")).utf8))
    #expect(newer.overrides.count == 1 && newer.overrides.first?.property("UID")?.text == "uuid-1")
    let events = try await source.events(in: autumn)
    #expect(events.map(\.title) == ["Team sync", "Team sync (moved)", "New sync", "New sync", "New sync", "New sync"])
    #expect(events.map(\.start) == [pt(2026, 9, 1), pt(2026, 9, 16, 14), pt(2026, 9, 22), pt(2026, 9, 29), pt(2026, 10, 6), pt(2026, 10, 13)])
}

@Test func splitACountSeriesKeepsTheTotal() async throws {
    let h = CalDAVHarness()
    await h.server.store("home", "weekly.ics", weeklyICS(rule: "FREQ=WEEKLY;BYDAY=TU;COUNT=6", organizer: nil))
    let source = try await h.source()
    _ = try await source.update(EventRef(try await occurrence(source, on: 22)), EventPatch(title: "Later"), scope: .thisAndFollowing, notify: .none)
    let head = try EventResource(data: Data(try #require(await h.server.body("home", "weekly.ics")).utf8))
    let tail = try EventResource(data: Data(try #require(await h.server.body("home", "uuid-2.ics")).utf8))
    #expect(head.master?.property("RRULE")?.value == "FREQ=WEEKLY;BYDAY=TU;COUNT=3")
    #expect(tail.master?.property("RRULE")?.value == "FREQ=WEEKLY;BYDAY=TU;COUNT=3")
    let events = try await source.events(in: autumn)
    #expect(events.map(\.start) == [pt(2026, 9, 1), pt(2026, 9, 16, 14), pt(2026, 9, 22), pt(2026, 9, 29), pt(2026, 10, 6)])
}

@Test func splitWithATimeChangeMovesTheNewSeries() async throws {
    let h = CalDAVHarness()
    await h.server.store("home", "weekly.ics", weeklyICS(organizer: nil))
    let source = try await h.source()
    let later = EventTiming(start: pt(2026, 9, 22, 15), end: pt(2026, 9, 22, 16), timeZone: pacific, isAllDay: false)
    _ = try await source.update(EventRef(try await occurrence(source, on: 22)), EventPatch(timing: later), scope: .thisAndFollowing, notify: .none)
    let starts = try await source.events(in: september).map(\.start)
    #expect(starts == [pt(2026, 9, 1), pt(2026, 9, 16, 14), pt(2026, 9, 22, 15), pt(2026, 9, 29, 15)])
}

@Test func splitAtTheFirstOccurrenceIsAllInSeries() async throws {
    let h = CalDAVHarness()
    await h.server.store("home", "weekly.ics", weeklyICS(organizer: nil))
    let source = try await h.source()
    let series = try await source.update(EventRef(try await occurrence(source, on: 1)), EventPatch(title: "Renamed"), scope: .thisAndFollowing, notify: .none)
    #expect(series.eventID == "weekly.ics")
    #expect(await h.server.names("home") == ["weekly.ics"])
    #expect(try await source.events(in: september).filter { $0.title == "Renamed" }.count == 3)
}

@Test func aFailedSecondStepRestoresTheOriginal() async throws {
    let h = CalDAVHarness()
    await h.server.store("home", "weekly.ics", weeklyICS(organizer: nil))
    let source = try await h.source()
    let before = try await source.events(in: september).map(\.start)
    await h.server.fail("PUT", pathContains: "uuid-2.ics", status: 507)
    await #expect(throws: SourceError.server(status: 507)) {
        _ = try await source.update(EventRef(try await occurrence(source, on: 22)), EventPatch(title: "x"), scope: .thisAndFollowing, notify: .none)
    }
    #expect(try await source.events(in: september).map(\.start) == before)
    #expect(await h.server.names("home") == ["weekly.ics"])
}

@Test func aStaleRestoreIsPartial() async throws {
    let h = CalDAVHarness()
    await h.server.store("home", "weekly.ics", weeklyICS(organizer: nil))
    let source = try await h.source()
    await h.server.fail("PUT", pathContains: "uuid-2.ics", status: 507)
    await h.server.fail("PUT", pathContains: "weekly.ics", status: 412, after: 1)   // the truncation passes, the restore is stale
    do {
        _ = try await source.update(EventRef(try await occurrence(source, on: 22)), EventPatch(title: "x"), scope: .thisAndFollowing, notify: .none)
        Issue.record("expected partial")
    } catch WriteError.partial(let message) {
        #expect(message.contains("not restored"))
    }
}

// MARK: Beyond the brief: ordering, conditional headers, notify rule, restore under a concurrent edit, re-stamped overrides

/// Lets one edit from "another client" land on the original resource just before the new series is written, then
/// fails that write.
private struct MeddlingTransport: HTTPTransport {
    let server: FakeCalDAVServer

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        if request.method == "PUT", request.url.path.contains("uuid-2.ics") {
            await server.store("home", "weekly.ics", weeklyICS(organizer: nil).replacingOccurrences(of: "Team sync", with: "Edited elsewhere"))
            return HTTPResponse(status: 507)
        }
        return try await server.send(request)
    }
}

@Test func theHeadIsWrittenFirstUnderIfMatchAndTheTailUnderIfNoneMatch() async throws {
    let h = CalDAVHarness()
    await h.server.store("home", "weekly.ics", weeklyICS(organizer: nil))
    let source = try await h.source()
    let original = try #require(await h.server.etag("home", "weekly.ics"))
    let target = try await occurrence(source, on: 22)
    await h.server.clearLog()
    _ = try await source.update(EventRef(target), EventPatch(title: "x"), scope: .thisAndFollowing, notify: .none)
    let puts = await h.server.requests("PUT")
    #expect(puts.count == 2)
    #expect(puts[0].url.path.hasSuffix("weekly.ics") && puts[0].headers["If-Match"] == original && puts[0].headers["If-None-Match"] == nil)
    #expect(puts[1].url.path.hasSuffix("uuid-2.ics") && puts[1].headers["If-None-Match"] == "*" && puts[1].headers["If-Match"] == nil)
}

@Test func theRestoreGoesBackUnderTheTruncationsETag() async throws {
    let h = CalDAVHarness()
    await h.server.store("home", "weekly.ics", weeklyICS(organizer: nil))
    let source = try await h.source()
    let original = try #require(await h.server.etag("home", "weekly.ics"))
    let target = try await occurrence(source, on: 22)
    await h.server.fail("PUT", pathContains: "uuid-2.ics", status: 507)
    await h.server.clearLog()
    await #expect(throws: SourceError.server(status: 507)) {
        _ = try await source.update(EventRef(target), EventPatch(title: "x"), scope: .thisAndFollowing, notify: .none)
    }
    let puts = await h.server.requests("PUT")
    #expect(puts.count == 3)
    let restoreMatch = try #require(puts.last?.headers["If-Match"])
    #expect(restoreMatch != original)   // the truncation's ETag, not the one read at the start
    let restored = try EventResource(data: Data(try #require(await h.server.body("home", "weekly.ics")).utf8))
    #expect(restored.master?.property("RRULE")?.value == "FREQ=WEEKLY;BYDAY=TU")
    #expect(restored.overrides.count == 1)
}

@Test func aRestoreIsNeverForcedOverAnEditMadeMeanwhile() async throws {
    let h = CalDAVHarness()
    await h.server.store("home", "weekly.ics", weeklyICS(organizer: nil))
    let source = try await h.source(transport: MeddlingTransport(server: h.server))
    let target = try await occurrence(source, on: 22)
    do {
        _ = try await source.update(EventRef(target), EventPatch(title: "x"), scope: .thisAndFollowing, notify: .none)
        Issue.record("expected partial")
    } catch WriteError.partial(let message) {
        #expect(message.contains("not restored"))
    }
    #expect(try #require(await h.server.body("home", "weekly.ics")).contains("Edited elsewhere"))
    #expect(await h.server.names("home") == ["weekly.ics"])
}

@Test func aSplitThatTellsOthersIsRefusedBeforeAnyRequestUnlessNotifyIsAll() async throws {
    let h = CalDAVHarness()
    await h.server.store("home", "weekly.ics", weeklyICS())   // an organizer and attendees other than the account
    let source = try await h.source()
    let target = try await occurrence(source, on: 22)
    for policy in [NotifyPolicy.none, .externalOnly] {
        await h.server.clearLog()
        await #expect(throws: WriteError.unsupported(fields: [.attendees])) {
            _ = try await source.update(EventRef(target), EventPatch(title: "x"), scope: .thisAndFollowing, notify: policy)
        }
        #expect(await h.server.requests("PUT").isEmpty)
    }
    _ = try await source.update(EventRef(target), EventPatch(title: "x"), scope: .thisAndFollowing, notify: .all)
    #expect(await h.server.names("home") == ["uuid-2.ics", "weekly.ics"])
}

@Test func carriedOverExceptionsAreRestampedUnderTheNewUID() async throws {
    let h = CalDAVHarness()
    await h.server.store("home", "weekly.ics", weeklyICS(organizer: nil))
    let source = try await h.source()
    _ = try await source.update(EventRef(try await occurrence(source, on: 15)), EventPatch(title: "New sync"), scope: .thisAndFollowing, notify: .none)
    let tail = try EventResource(data: Data(try #require(await h.server.body("home", "uuid-2.ics")).utf8))
    let carried = try #require(tail.overrides.first)
    let master = try #require(tail.master)
    #expect(carried.property("DTSTAMP")?.value == master.property("DTSTAMP")?.value)
    #expect(carried.property("DTSTAMP")?.value != "20260901T000000Z")
    #expect(carried.property("LAST-MODIFIED")?.value == master.property("LAST-MODIFIED")?.value)
}
