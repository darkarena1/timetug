import CalendarCore
import CalendarTestSupport
import Foundation
import Testing
@testable import ICalSubscription

// TestNow starts at 2027-01-15 00:00 Pacific, so the window is Jan 14 00:00 to Jan 22 00:00 Pacific.
private let window = RetentionWindow(daysBack: 1, daysAhead: 7)
private let everything = DateInterval(start: pt(2026, 8, 1, 0), end: pt(2027, 12, 1, 0))

private func oneOff(_ title: String, _ start: String, _ end: String) -> [String] {
    vevent(uid: "\(title.replacingOccurrences(of: " ", with: "-"))@example.test", title: title, start: start, end: end)
}

private func allDay(_ title: String, _ first: String, _ next: String) -> [String] {
    ["BEGIN:VEVENT", "UID:\(title.replacingOccurrences(of: " ", with: "-"))@example.test", "DTSTAMP:20260901T000000Z", "SUMMARY:\(title)",
     "DTSTART;VALUE=DATE:\(first)", "DTEND;VALUE=DATE:\(next)", "END:VEVENT"]
}

private let farPast = oneOff("Far past", "20260901T100000", "20260901T110000")
private let farFuture = oneOff("Far future", "20270301T100000", "20270301T110000")
private let inWindow = oneOff("In window", "20270118T100000", "20270118T110000")
private let comingUp = oneOff("Coming up", "20270125T100000", "20270125T110000")
private let oldWeekly = vevent(uid: "walk@example.test", title: "Old weekly", start: "20260901T100000", end: "20260901T110000",
                               extra: ["RRULE:FREQ=WEEKLY;BYDAY=TU"])

private func makeSource(
    _ transport: FakeTransport, now: TestNow, retention: RetentionWindow? = window
) -> ICalSubscriptionSource {
    ICalSubscriptionSource(
        connection: Connection(kindID: "icalsub", connectionID: "c1", displayName: "x (www.example.test)", config: ["host": "www.example.test"]),
        link: { feedURL }, transport: transport, monitor: ChangeMonitor(interval: .seconds(900), sleep: { _ in }),
        maxAge: 900, now: now.provider, defaultZone: pacific, retention: retention)
}

private func serve(_ transport: FakeTransport, _ responses: [HTTPResponse]) async { await transport.route(privatePath, responses) }

private func ics(_ events: [[String]], etag: String? = nil) -> HTTPResponse {
    HTTPResponse(status: 200, headers: etag.map { ["ETag": $0] } ?? [:], body: Data(feedICS(events).utf8))
}

private func titles(_ source: ICalSubscriptionSource) async throws -> Set<String> {
    Set(try await source.events(in: everything).map(\.title))
}

@Test func theWindowDropsFarOneOffsAndKeepsInWindowAndRecurringEvents() async throws {
    let transport = FakeTransport()
    await serve(transport, [ics([farPast, farFuture, inWindow, oldWeekly])])
    let found = try await titles(makeSource(transport, now: TestNow()))
    #expect(found == ["In window", "Old weekly"])
}

@Test func allDayEventsAtTheEdgesOfTheWindow() async throws {
    let transport = FakeTransport()
    await serve(transport, [ics([
        allDay("Ends as the window starts", "20270113", "20270114"), allDay("Last day before the window", "20270114", "20270115"),
        allDay("Last day inside", "20270121", "20270122"), allDay("Starts as the window ends", "20270122", "20270123"),
    ])])
    #expect(try await titles(makeSource(transport, now: TestNow())) == ["Last day before the window", "Last day inside"])
}

@Test func noWindowKeepsEverything() async throws {
    let transport = FakeTransport()
    await serve(transport, [ics([farPast, farFuture, inWindow])])
    #expect(try await titles(makeSource(transport, now: TestNow(), retention: nil)) == ["Far past", "Far future", "In window"])
}

@Test func anEditOutsideTheWindowIsNotAChangeButOneInsideIs() async throws {
    let editedFar = oneOff("Far future renamed", "20270301T100000", "20270301T110000")
    let editedIn = oneOff("In window renamed", "20270118T100000", "20270118T110000")
    let transport = FakeTransport()
    await serve(transport, [ics([farFuture, inWindow]), ics([editedFar, inWindow]), ics([editedFar, inWindow]), ics([editedFar, editedIn])])
    let source = makeSource(transport, now: TestNow())
    #expect(try await source.checkForChanges() == nil)
    #expect(try await source.checkForChanges() == nil)
    #expect(try await source.checkForChanges() == nil)
    #expect(try await source.checkForChanges() == .eventsChanged(calendarIDs: ["feed"]))
    #expect(try await titles(source) == ["In window renamed"])
}

@Test func anEventThatComesIntoTheWindowAsTimePassesIsReportedAndReadable() async throws {
    let now = TestNow()
    let transport = FakeTransport()
    await serve(transport, [ics([comingUp, inWindow])])
    let source = makeSource(transport, now: now)
    #expect(try await source.checkForChanges() == nil)
    #expect(try await titles(source) == ["In window"])
    now.advance(5 * 86_400)
    #expect(try await source.checkForChanges() == .eventsChanged(calendarIDs: ["feed"]))
    #expect(try await titles(source).contains("Coming up"))
}

@Test func aNotModifiedAnswerStillBringsAnEventIntoTheWindow() async throws {
    let now = TestNow()
    let transport = FakeTransport()
    await serve(transport, [ics([comingUp], etag: "\"v1\""), HTTPResponse(status: 304)])
    let source = makeSource(transport, now: now)
    #expect(try await source.checkForChanges() == nil)
    now.advance(5 * 86_400)
    #expect(try await source.checkForChanges() == .eventsChanged(calendarIDs: ["feed"]))
    let second = try #require(await transport.requests(matching: privatePath).last)
    #expect(second.headers["If-None-Match"] == "\"v1\"")
    #expect(try await titles(source).contains("Coming up"))
}

@Test func anEditOutsideTheWindowStillUpdatesWhatIsKeptForLater() async throws {
    // The edited far event comes into the window later; the 304 must re-read the edited version, not the first one.
    let now = TestNow()
    let edited = oneOff("Coming up edited", "20270125T100000", "20270125T110000")
    let transport = FakeTransport()
    await serve(transport, [ics([comingUp], etag: "\"v1\""), ics([edited], etag: "\"v2\""), HTTPResponse(status: 304)])
    let source = makeSource(transport, now: now)
    #expect(try await source.checkForChanges() == nil)
    #expect(try await source.checkForChanges() == nil)
    now.advance(5 * 86_400)
    #expect(try await source.checkForChanges() == .eventsChanged(calendarIDs: ["feed"]))
    #expect(try await titles(source) == ["Coming up edited"])
}

@Test func aFeedWithEverythingOutsideTheWindowIsAValidSignInAndTheKindPassesTheWindowOn() async throws {
    let transport = FakeTransport()
    await serve(transport, [ics([farPast, farFuture, inWindow])])
    let store = InMemoryCredentialStore()
    let kind = ICalSubscriptionKind(transport: transport, now: TestNow().provider, sleep: { _ in }, defaultZone: pacific, retention: window)
    let onlyFar = FakeTransport()
    await serve(onlyFar, [ics([farPast, farFuture])])
    let connection = try await ICalSubscriptionKind(transport: onlyFar, now: TestNow().provider, retention: window)
        .authorize(using: StubInteraction(["link": feedURL.absoluteString]), credentials: InMemoryCredentialStore())
    #expect(connection.displayName == "My Meetups (www.example.test)")

    let signedIn = try await kind.authorize(using: StubInteraction(["link": feedURL.absoluteString]), credentials: store)
    let source = try kind.makeSource(for: signedIn, credentials: store, syncState: InMemorySyncStateStore())
    #expect(try await source.events(in: everything).map(\.title) == ["In window"])
}
