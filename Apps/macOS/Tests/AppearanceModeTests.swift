import AppKit
import XCTest
@testable import TimeTug

final class AppearanceModeTests: XCTestCase {
    func testAutoHasNoOverride() {
        XCTAssertNil(AppearanceMode.auto.nsAppearance)
    }

    func testLightIsAqua() {
        XCTAssertEqual(AppearanceMode.light.nsAppearance?.name, .aqua)
    }

    func testDarkIsDarkAqua() {
        XCTAssertEqual(AppearanceMode.dark.nsAppearance?.name, .darkAqua)
    }

    func testTitles() {
        XCTAssertEqual(AppearanceMode.allCases.map(\.title), ["Auto", "Light", "Dark"])
    }
}
