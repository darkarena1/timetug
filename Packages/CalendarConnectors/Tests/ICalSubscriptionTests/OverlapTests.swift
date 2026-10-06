import CalendarCore
import CalendarTestSupport
import Foundation
import Testing
@testable import ICalSubscription

/// Answers each request, in the order they arrive, with the next response, but only once the test releases it. That
/// lets a test finish overlapping fetches in any order.
private actor GatedTransport: HTTPTransport {
    private let responses: [HTTPResponse]
    private var waiting: [Int: CheckedContinuation<Void, Never>] = [:]
    private var released: Set<Int> = []
    private(set) var arrivals = 0

    init(_ responses: [HTTPResponse]) { self.responses = responses }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let index = arrivals
        arrivals += 1
        let response = responses[min(index, responses.count - 1)]
        if !released.contains(index) { await withCheckedContinuation { waiting[index] = $0 } }
        return response
    }

    func release(_ index: Int) {
        released.insert(index)
        waiting.removeValue(forKey: index)?.resume()
    }

    func waitForArrivals(_ count: Int) async {
        while arrivals < count { await Task.yield() }
    }
}

private func makeSource(_ transport: any HTTPTransport) -> ICalSubscriptionSource {
    ICalSubscriptionSource(
        connection: Connection(kindID: "icalsub", connectionID: "c1", displayName: "My Meetups (www.example.test)", config: ["host": "www.example.test"]),
        link: { feedURL }, transport: transport, monitor: ChangeMonitor(interval: .seconds(900), sleep: { _ in }),
        maxAge: 900, now: TestNow().provider, defaultZone: TimeZone(identifier: "Europe/Berlin")!)
}

private func ics(_ text: String) -> HTTPResponse { HTTPResponse(status: 200, body: Data(text.utf8)) }

@Test func overlappingChecksOfTheSameChangeReportItOnce() async throws {
    let old = ics(sampleFeed), new = ics(feedICS([boardGames]))
    let transport = GatedTransport([old, new, new])
    let source = makeSource(transport)
    let baseline = Task { try await source.checkForChanges() }
    await transport.waitForArrivals(1)
    await transport.release(0)
    #expect(try await baseline.value == nil)

    let first = Task { try await source.checkForChanges() }
    await transport.waitForArrivals(2)
    let second = Task { try await source.checkForChanges() }
    await transport.waitForArrivals(3)
    await transport.release(2)
    await transport.release(1)
    let results = try await [first.value, second.value]
    #expect(results.compactMap { $0 }.count == 1)
    #expect(results.compactMap { $0 } == [.eventsChanged(calendarIDs: ["feed"])])
}

@Test func anOlderFetchThatFinishesLastDoesNotReplaceTheNewerFeed() async throws {
    let old = ics(sampleFeed), new = ics(feedICS([boardGames]))
    let transport = GatedTransport([old, new])
    let source = makeSource(transport)
    let slow = Task { try await source.events(in: september) }
    await transport.waitForArrivals(1)
    let fast = Task { try await source.checkForChanges() }
    await transport.waitForArrivals(2)
    await transport.release(1)
    _ = try await fast.value
    await transport.release(0)
    _ = try await slow.value
    #expect(try await source.events(in: september).map(\.title) == ["Board games night"])
    #expect(await transport.arrivals == 2)
}
