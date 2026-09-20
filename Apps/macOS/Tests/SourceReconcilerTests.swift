import CalendarCore
import TimeTugCore
import XCTest
@testable import TimeTug

final class FakeCoreSource: TimeTugCore.CalendarSource, @unchecked Sendable {
    let id: String
    let displayName: String
    let continuation: AsyncStream<Void>.Continuation
    private let stream: AsyncStream<Void>
    private(set) var listenerStarted = 0
    init(id: String) {
        self.id = id
        displayName = id
        (stream, continuation) = AsyncStream.makeStream(of: Void.self)
    }
    func calendars() async throws -> [CalendarInfo] { [] }
    func events(in interval: DateInterval) async throws -> [TimeTugCalendarEvent] { [] }
    func changes() -> AsyncStream<Void> { listenerStarted += 1; return stream }
}

@MainActor
final class SourceReconcilerTests: XCTestCase {
    private let a = Connection(kindID: "google", connectionID: "1", displayName: "a@x.test")
    private let b = Connection(kindID: "google", connectionID: "2", displayName: "b@x.test")
    private var built: [String: FakeCoreSource] = [:]
    private var changeCount = 0
    private var failNext: Set<ConnectionID> = []

    private func makeReconciler(failing: Set<ConnectionID> = []) -> SourceReconciler {
        SourceReconciler(
            buildAccount: { [unowned self] c in
                if failing.contains(c.connectionID) || failNext.contains(c.connectionID) { throw TimeTugCore.SourceError.authExpired }
                let s = FakeCoreSource(id: c.sourceID)   // library rule: google source id == Connection.sourceID
                built[c.connectionID] = s
                return s
            },
            buildEventKit: { FakeCoreSource(id: "eventkit") },
            onChange: { [unowned self] in changeCount += 1 })
    }

    func testBuildsEventKitFirstThenAccountsAndKeysBySourceID() {
        let r = makeReconciler()
        let update = r.reconcile(connections: [a, b], eventKitEnabled: true)
        XCTAssertEqual(update.sources.map(\.id), ["eventkit", "google-1", "google-2"])
        XCTAssertEqual(r.sourceID(forConnection: "1"), a.sourceID)
    }

    func testEventKitDisabledIsLeftOut() {
        XCTAssertEqual(makeReconciler().reconcile(connections: [a], eventKitEnabled: false).sources.map(\.id), ["google-1"])
    }

    func testUnchangedSourcesKeepTheirInstanceAndListener() async {
        let r = makeReconciler()
        _ = r.reconcile(connections: [a], eventKitEnabled: false)
        let first = built["1"]!
        let update = r.reconcile(connections: [a, b], eventKitEnabled: false)
        XCTAssertTrue((update.sources.first { $0.id == "google-1" } as AnyObject) === first)
        await Task.yield()
        XCTAssertEqual(first.listenerStarted, 1)
    }

    func testRemovedSourceStopsItsListener() async throws {
        let r = makeReconciler()
        _ = r.reconcile(connections: [a], eventKitEnabled: false)
        let source = built["1"]!
        _ = r.reconcile(connections: [], eventKitEnabled: false)
        source.continuation.yield()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(changeCount, 0)
    }

    func testAChangeFromASourceTriggersOnChange() async throws {
        let r = makeReconciler()
        _ = r.reconcile(connections: [a], eventKitEnabled: false)
        try await Task.sleep(for: .milliseconds(50))
        built["1"]!.continuation.yield()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(changeCount, 1)
    }

    func testFailingBuildIsReportedAndDoesNotStopOthers() {
        let update = makeReconciler(failing: ["1"]).reconcile(connections: [a, b], eventKitEnabled: false)
        XCTAssertEqual(update.sources.map(\.id), ["google-2"])
        XCTAssertNotNil(update.failures["1"])
    }

    func testRebuildReplacesTheInstanceAndRestartsTheListener() async throws {
        let r = makeReconciler()
        _ = r.reconcile(connections: [a], eventKitEnabled: false)
        let old = built["1"]!
        old.continuation.finish()   // like a source whose stream ended after .sourceFailed
        let update = r.rebuild(a, connections: [a], eventKitEnabled: false)
        let new = built["1"]!
        XCTAssertFalse(old === new)
        XCTAssertTrue((update.sources.first as AnyObject) === new)
        try await Task.sleep(for: .milliseconds(50))
        new.continuation.yield()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(changeCount, 1)
    }

    func testAFailedRebuildKeepsTheWorkingSourceAndItsListener() async throws {
        let r = makeReconciler()
        _ = r.reconcile(connections: [a], eventKitEnabled: false)
        let old = built["1"]!
        try await Task.sleep(for: .milliseconds(50))
        failNext = ["1"]
        let update = r.rebuild(a, connections: [a], eventKitEnabled: false)
        XCTAssertEqual(update.sources.count, 1)
        XCTAssertTrue((update.sources.first as AnyObject) === old)
        XCTAssertNotNil(update.failures["1"])
        old.continuation.yield()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(changeCount, 1)
    }
}
