import TimeTugCore
import XCTest
@testable import TimeTug

final class DedupStateStoreTests: XCTestCase {
    private func tempURL() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TimeTugTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.appendingPathComponent("nested/dedup-state.json")
    }

    func testDefaultLocationIsApplicationSupportTimeTug() {
        let url = DedupStateStore.defaultURL
        XCTAssertEqual(url.lastPathComponent, "dedup-state.json")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "TimeTug")
    }

    func testMissingFileLoadsEmptyState() {
        XCTAssertEqual(DedupStateStore(url: tempURL()).load(), DedupState())
    }

    func testRoundTripsLessonsAndVerdicts() {
        let store = DedupStateStore(url: tempURL())
        var state = DedupState()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        state.lessons.record(MergedMember(title: "A", calendarKey: "s/x", contentKey: "k1", details: "bare"),
                             MergedMember(title: "B", calendarKey: "s/y", contentKey: "k2", details: "bare"),
                             decision: .same, now: now)
        state.verdicts.store(AdjudicationVerdict(requestID: "r", answer: .same),
                             engine: EngineInfo(id: "e", displayName: "E", isOnDevice: true),
                             end: now.addingTimeInterval(3600), now: now)
        XCTAssertTrue(store.save(state))
        XCTAssertEqual(store.load(), state)
    }

    func testCorruptFileLoadsEmptyState() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        XCTAssertEqual(DedupStateStore(url: url).load(), DedupState())
    }
}
