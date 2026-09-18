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
        XCTAssertEqual(store.appearanceMode, .auto)
    }

    func testPersistsChanges() {
        let defaults = freshDefaults()
        let store = SettingsStore(defaults: defaults)
        store.takeover.leadTime = 300
        store.takeover.takeoverCalendarKeys = ["eventkit/work"]
        store.menuBarMode = .countdown
        store.appearanceMode = .dark

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.takeover.leadTime, 300)
        XCTAssertEqual(reloaded.takeover.takeoverCalendarKeys, ["eventkit/work"])
        XCTAssertEqual(reloaded.menuBarMode, .countdown)
        XCTAssertEqual(reloaded.appearanceMode, .dark)
    }

    func testPopupCardStyleDefault() {
        XCTAssertEqual(SettingsStore(defaults: freshDefaults()).popupCardStyle, PopupCardStyle.defaultStyle)
    }

    func testPopupCardStylePersists() {
        let defaults = freshDefaults()
        SettingsStore(defaults: defaults).popupCardStyle = .solid
        XCTAssertEqual(SettingsStore(defaults: defaults).popupCardStyle, .solid)
        XCTAssertEqual(defaults.string(forKey: "popupCardStyle.v1"), "solid")
    }

    func testPopupCardStyleInvalidFallsBackToDefault() {
        let defaults = freshDefaults()
        defaults.set("bogus", forKey: "popupCardStyle.v1")
        XCTAssertEqual(SettingsStore(defaults: defaults).popupCardStyle, PopupCardStyle.defaultStyle)
    }

    func testPopupCardStyleUnavailableFallsBackToDefault() {
        // Glass is stored but not available before macOS 26.
        let defaults = freshDefaults()
        defaults.set("glass", forKey: "popupCardStyle.v1")
        let style = SettingsStore(defaults: defaults).popupCardStyle
        if PopupCardStyle.available.contains(.glass) { XCTAssertEqual(style, .glass) }
        else { XCTAssertEqual(style, PopupCardStyle.defaultStyle) }
    }
}
