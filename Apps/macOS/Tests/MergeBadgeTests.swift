import TimeTugCore
import XCTest
@testable import TimeTug

final class MergeBadgeTests: XCTestCase {
    func testNoBadgeForPlainOrRuleMerges() {
        XCTAssertNil(MergeBadge.text(nil))
        XCTAssertNil(MergeBadge.text(.rule))
    }

    func testInferenceBadgeNamesTheEngine() {
        XCTAssertEqual(MergeBadge.text(.inference(engineID: "apple-intelligence", engineName: "Apple Intelligence")),
                       "Merged with Apple Intelligence")
    }

    func testUserConfirmedBadge() {
        XCTAssertEqual(MergeBadge.text(.userConfirmed), "Merged manually")
    }
}
