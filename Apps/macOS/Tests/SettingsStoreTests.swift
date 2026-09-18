import TimeTugCore
import XCTest
@testable import TimeTug

@MainActor
final class SettingsStoreTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "TimeTugTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testDefaultsWhenEmpty() {
        let store = SettingsStore(defaults: freshDefaults())
        XCTAssertEqual(store.takeover, TakeoverSettings())
        XCTAssertEqual(store.menuBarMode, .iconOnly)
    }

    func testPersistsChanges() {
        let defaults = freshDefaults()
        let store = SettingsStore(defaults: defaults)
        store.takeover.leadTime = 300
        store.takeover.takeoverCalendarKeys = ["eventkit/work"]
        store.menuBarMode = .countdown

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.takeover.leadTime, 300)
        XCTAssertEqual(reloaded.takeover.takeoverCalendarKeys, ["eventkit/work"])
        XCTAssertEqual(reloaded.menuBarMode, .countdown)
    }
}
