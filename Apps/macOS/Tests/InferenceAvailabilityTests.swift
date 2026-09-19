import TimeTugCore
import XCTest
@testable import TimeTug

final class InferenceAvailabilityTests: XCTestCase {
    func testOnlyDefinitiveUnavailabilityIsFalse() {
        XCTAssertTrue(InferenceStatus.disabled.isAvailableOnThisMac)
        XCTAssertFalse(InferenceStatus.noEngine.isAvailableOnThisMac)
        XCTAssertFalse(InferenceStatus.unavailable(reason: "x").isAvailableOnThisMac)
        XCTAssertFalse(InferenceStatus.notOnDevice.isAvailableOnThisMac)
    }
}
