import XCTest
@testable import TimeTug

final class InstanceFilesTests: XCTestCase {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("InstanceFilesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testOnlyOneHolderAtATime() throws {
        let files = InstanceFiles(directory: try tempDirectory())
        var first = InstanceLock.acquire(at: files.lockURL)
        XCTAssertNotNil(first)
        XCTAssertNil(InstanceLock.acquire(at: files.lockURL))
        first = nil
        XCTAssertNotNil(InstanceLock.acquire(at: files.lockURL))
    }

    func testAcquireCreatesTheDirectory() throws {
        let nested = try tempDirectory().appendingPathComponent("a/b", isDirectory: true)
        XCTAssertNotNil(InstanceLock.acquire(at: InstanceFiles(directory: nested).lockURL))
    }

    func testRecordsRoundTrip() throws {
        let files = InstanceFiles(directory: try tempDirectory())
        let info = InstanceInfo(bundleID: "com.timetug.app", version: "2.0.0", build: "7", distribution: .appStore)
        files.write(info, to: files.recordURL)
        XCTAssertEqual(files.read(files.recordURL), info)
    }

    func testMissingOrCorruptRecordsReadAsNil() throws {
        let files = InstanceFiles(directory: try tempDirectory())
        XCTAssertNil(files.read(files.recordURL))
        try "not json".write(to: files.recordURL, atomically: true, encoding: .utf8)
        XCTAssertNil(files.read(files.recordURL))
    }
}
