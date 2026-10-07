import XCTest
@testable import TimeTug

final class AppSupportFilesTests: XCTestCase {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AppSupportFilesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func write(_ text: String, _ name: String, in dir: URL) throws {
        try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func read(_ name: String, in dir: URL) -> String? {
        try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
    }

    func testDirectoryUsesGroupContainerWhenPresent() {
        let group = URL(fileURLWithPath: "/tmp/group")
        let legacy = URL(fileURLWithPath: "/tmp/legacy")
        XCTAssertEqual(AppSupportFiles.directory(groupContainer: group, legacy: legacy).path, "/tmp/group/TimeTug")
    }

    func testDirectoryFallsBackToLegacyWithoutGroup() {
        let legacy = URL(fileURLWithPath: "/tmp/legacy")
        XCTAssertEqual(AppSupportFiles.directory(groupContainer: nil, legacy: legacy), legacy)
    }

    func testMigrationCopiesKnownFilesAndLeavesLegacyInPlace() throws {
        let legacy = try tempDirectory(), destination = try tempDirectory().appendingPathComponent("TimeTug")
        try write("A", "accounts.json", in: legacy)
        try write("L", "takeover-ledger.json", in: legacy)
        try write("X", "unrelated.txt", in: legacy)
        let copied = AppSupportFiles.migrateLegacyFiles(from: legacy, to: destination)
        XCTAssertEqual(Set(copied), ["accounts.json", "takeover-ledger.json"])
        XCTAssertEqual(read("accounts.json", in: destination), "A")
        XCTAssertEqual(read("takeover-ledger.json", in: destination), "L")
        XCTAssertNil(read("unrelated.txt", in: destination))
        XCTAssertEqual(read("accounts.json", in: legacy), "A")
    }

    func testMigrationNeverOverwritesAnExistingGroupFile() throws {
        let legacy = try tempDirectory(), destination = try tempDirectory()
        try write("old", "accounts.json", in: legacy)
        try write("new", "accounts.json", in: destination)
        XCTAssertEqual(AppSupportFiles.migrateLegacyFiles(from: legacy, to: destination), [])
        XCTAssertEqual(read("accounts.json", in: destination), "new")
    }

    func testMigrationIsANoOpWithoutLegacyFilesOrWhenFoldersAreTheSame() throws {
        let legacy = try tempDirectory(), destination = try tempDirectory()
        XCTAssertEqual(AppSupportFiles.migrateLegacyFiles(from: legacy, to: destination), [])
        try write("A", "accounts.json", in: legacy)
        XCTAssertEqual(AppSupportFiles.migrateLegacyFiles(from: legacy, to: legacy), [])
    }

    func testMigrationCopiesOnlyWhatIsMissingOnASecondRun() throws {
        let legacy = try tempDirectory(), destination = try tempDirectory()
        try write("A", "accounts.json", in: legacy)
        XCTAssertEqual(AppSupportFiles.migrateLegacyFiles(from: legacy, to: destination), ["accounts.json"])
        try write("S", "sync-state.json", in: legacy)
        XCTAssertEqual(AppSupportFiles.migrateLegacyFiles(from: legacy, to: destination), ["sync-state.json"])
    }
}
