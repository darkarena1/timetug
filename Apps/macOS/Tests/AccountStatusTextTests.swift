import TimeTugCore
import XCTest
@testable import TimeTug

final class AccountStatusTextTests: XCTestCase {
    func testStatusWording() {
        XCTAssertEqual(AccountStatusText.make(.ok), "Connected")
        XCTAssertEqual(AccountStatusText.make(.authExpired), "Sign in again")
        XCTAssertEqual(AccountStatusText.make(.needsPermission), "Calendar access is off")
        XCTAssertEqual(AccountStatusText.make(.failing("boom")), "Can't reach this calendar right now")
        XCTAssertEqual(AccountStatusText.make(nil), "Connecting…")
    }
}
