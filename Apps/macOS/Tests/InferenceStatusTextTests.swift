import TimeTugCore
import XCTest
@testable import TimeTug

final class InferenceStatusTextTests: XCTestCase {
    func testOffShowsNothing() {
        XCTAssertNil(InferenceStatusText.make(.disabled))
    }

    func testActiveNamesTheEngine() {
        let engine = EngineInfo(id: "apple-intelligence", displayName: "Apple Intelligence", isOnDevice: true)
        XCTAssertEqual(InferenceStatusText.make(.active(engine)), "Using Apple Intelligence.")
    }

    func testEveryFallbackSaysRulesOnly() {
        for status in [InferenceStatus.noEngine, .unavailable(reason: "not eligible"), .notOnDevice] {
            XCTAssertTrue(InferenceStatusText.make(status)?.contains("rules only") == true, "\(status)")
        }
        XCTAssertTrue(InferenceStatusText.make(.unavailable(reason: "not eligible"))?.contains("not eligible") == true)
    }
}
