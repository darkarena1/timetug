import TimeTugCore
import XCTest
@testable import TimeTug

@MainActor
final class SourceRefreshCoordinatorTests: XCTestCase {
    func testBurstDuringSuspendedRefreshRunsOneFollowUpWithAllDirtySources() async {
        var calls: [Set<String>?] = []
        var releaseFirst: CheckedContinuation<Void, Never>?
        let coordinator = SourceRefreshCoordinator { ids in
            calls.append(ids)
            if calls.count == 1 {
                await withCheckedContinuation { releaseFirst = $0 }
            }
        }
        coordinator.signal(.eventsChanged(sourceID: "a", calendarIDs: ["one"]))
        for _ in 0..<100 where calls.isEmpty { await Task.yield() }
        XCTAssertEqual(calls, [["a"]])
        for _ in 0..<100 { coordinator.signal(.eventsChanged(sourceID: "a", calendarIDs: ["one"])) }
        coordinator.signal(.sourceFailed(sourceID: "b"))
        releaseFirst?.resume()
        for _ in 0..<100 where calls.count < 2 { await Task.yield() }
        XCTAssertEqual(calls, [["a"], ["a", "b"]])
    }

    func testUnknownCalendarScopeRequestsFullRefresh() async {
        var calls: [Set<String>?] = []
        let coordinator = SourceRefreshCoordinator { ids in calls.append(ids) }
        coordinator.signal(.eventsChanged(sourceID: "a", calendarIDs: nil))
        for _ in 0..<100 where calls.isEmpty { await Task.yield() }
        XCTAssertEqual(calls.count, 1)
        XCTAssertNil(calls[0])
    }
}
