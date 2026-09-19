import TimeTugCore
import XCTest
@testable import TimeTug

final class SharedInfraTests: XCTestCase {
    private func freshSettings() -> SharedSettings {
        let name = "TimeTugShared-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return SharedSettings(defaults: defaults)
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testUnsetKeyIsNil() { XCTAssertNil(freshSettings().bool(.disableTug)) }

    func testSetAndReadBoolIncludingFalse() {
        let settings = freshSettings()
        settings.set(false, for: .skipAllDay)
        settings.set(true, for: .disableTug)
        XCTAssertEqual(settings.bool(.skipAllDay), false)
        XCTAssertEqual(settings.bool(.disableTug), true)
    }

    func testSnapshotRoundTrip() throws {
        let store = WidgetSnapshotStore(directory: try tempDir())
        let event = WidgetEvent(id: "e", title: "Sync", start: Date(timeIntervalSince1970: 1_800_000_000),
                                end: Date(timeIntervalSince1970: 1_800_001_800), colorHex: "#FF0000",
                                joinURL: URL(string: "https://meet.google.com/a"))
        let snapshot = WidgetSnapshot(generatedAt: Date(timeIntervalSince1970: 1_799_999_000), events: [event])
        try store.write(snapshot)
        XCTAssertEqual(store.read(), snapshot)
    }

    func testMissingOrCorruptSnapshotReadsAsNil() throws {
        let dir = try tempDir()
        let store = WidgetSnapshotStore(directory: dir)
        XCTAssertNil(store.read())
        try Data("not json".utf8).write(to: dir.appendingPathComponent("agenda-snapshot.json"))
        XCTAssertNil(store.read())
    }

    func testWriteWithoutContainerThrows() {
        XCTAssertThrowsError(try WidgetSnapshotStore(directory: nil).write(WidgetSnapshot(generatedAt: .now, events: [])))
    }

    func testChangeSignalReachesObserver() {
        let received = expectation(description: "signal")
        received.assertForOverFulfill = false
        let observer = SettingsChangeSignal.Observer { received.fulfill() }
        SettingsChangeSignal.post()
        wait(for: [received], timeout: 2)
        withExtendedLifetime(observer) {}
    }
}
