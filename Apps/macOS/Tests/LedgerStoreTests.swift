import CalendarCore
import TimeTugCore
import XCTest
@testable import TimeTug

final class LedgerStoreTests: XCTestCase {
    private func tempURL() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TimeTugTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.appendingPathComponent("nested/takeover-ledger.json")
    }

    private func event(_ id: String = "e1") -> TimeTugCalendarEvent {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return TimeTugCalendarEvent(
            event: CalendarCore.CalendarEvent(
                eventID: id, calendarID: "c", title: "Standup", start: start, end: start.addingTimeInterval(1800)),
            sourceID: "s")
    }

    func testDefaultLocationIsApplicationSupportTimeTug() {
        let url = LedgerStore.defaultURL
        XCTAssertEqual(url.lastPathComponent, "takeover-ledger.json")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "TimeTug")
        XCTAssertTrue(url.path.contains("Application Support"))
    }

    func testMissingFileLoadsEmptyLedger() {
        XCTAssertEqual(LedgerStore(url: tempURL()).load(), TakeoverLedger())
    }

    func testCorruptFileLoadsEmptyLedger() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json {".utf8).write(to: url)
        XCTAssertEqual(LedgerStore(url: url).load(), TakeoverLedger())
    }

    func testRoundTripCreatesDirectoryAndKeepsFiredEventFired() throws {
        let url = tempURL()
        var ledger = TakeoverLedger()
        ledger.markFired(event(), now: Date(timeIntervalSince1970: 1_799_999_000))
        XCTAssertTrue(LedgerStore(url: url).save(ledger, now: Date(timeIntervalSince1970: 1_799_999_500)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let loaded = LedgerStore(url: url).load()
        XCTAssertEqual(loaded, ledger)
        XCTAssertTrue(loaded.hasFired(event()))
        XCTAssertTrue(loaded.hasFired(event("resynced-id")))
    }

    func testSaveFailureReturnsFalse() {
        // A path under a regular file cannot be created.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("TimeTugTests-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: file.path, contents: Data())
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        XCTAssertFalse(LedgerStore(url: file.appendingPathComponent("x/ledger.json")).save(TakeoverLedger(), now: Date()))
    }

    func testSavePrunesExpiredEntriesBeforeWriting() {
        let url = tempURL()
        var ledger = TakeoverLedger()
        ledger.markFired(event(), now: Date(timeIntervalSince1970: 1_799_999_000))
        let afterEnd = Date(timeIntervalSince1970: 1_800_000_000 + 1800 + 1)
        XCTAssertTrue(LedgerStore(url: url).save(ledger, now: afterEnd))
        XCTAssertEqual(LedgerStore(url: url).load(), TakeoverLedger())
    }

    func testLoadOfFileWithExpiredEntriesIsPrunedByLaunchPrune() {
        let url = tempURL()
        var ledger = TakeoverLedger()
        ledger.markFired(event(), now: Date(timeIntervalSince1970: 1_799_999_000))
        XCTAssertTrue(LedgerStore(url: url).save(ledger, now: Date(timeIntervalSince1970: 1_799_999_500)))

        var loaded = LedgerStore(url: url).load()
        XCTAssertTrue(loaded.hasFired(event()))
        XCTAssertTrue(loaded.prune(now: Date(timeIntervalSince1970: 1_800_000_000 + 1800 + 1)))
        XCTAssertEqual(loaded, TakeoverLedger())
    }
}
