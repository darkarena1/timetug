import XCTest
@testable import TimeTug

final class PopupCardStyleTests: XCTestCase {
    func testAvailableAlwaysHasFrostedAndSolid() {
        XCTAssertTrue(PopupCardStyle.available.contains(.frosted))
        XCTAssertTrue(PopupCardStyle.available.contains(.solid))
    }

    func testGlassOnlyAvailableOnMacOS26() {
        if #available(macOS 26.0, *) {
            XCTAssertEqual(PopupCardStyle.available, [.glass, .frosted, .solid])
        } else {
            XCTAssertFalse(PopupCardStyle.available.contains(.glass))
        }
    }

    func testDefaultIsAvailable() {
        XCTAssertTrue(PopupCardStyle.available.contains(PopupCardStyle.defaultStyle))
        if #available(macOS 26.0, *) { XCTAssertEqual(PopupCardStyle.defaultStyle, .glass) }
        else { XCTAssertEqual(PopupCardStyle.defaultStyle, .frosted) }
    }

    func testTitles() {
        XCTAssertEqual(PopupCardStyle.allCases.map(\.title), ["Glass", "Frosted", "Solid"])
    }

    func testCodableRoundTrip() throws {
        for style in PopupCardStyle.allCases {
            let data = try JSONEncoder().encode(style)
            XCTAssertEqual(try JSONDecoder().decode(PopupCardStyle.self, from: data), style)
            XCTAssertEqual(PopupCardStyle(rawValue: style.rawValue), style)
        }
    }
}
