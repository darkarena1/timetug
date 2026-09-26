import XCTest
@testable import TimeTug

final class ProviderIconTests: XCTestCase {
    func testGoogleAccountsGetTheGoogleMark() {
        XCTAssertEqual(ProviderIcon.Style.forKind("google"), .google)
    }

    func testMicrosoftAccountsGetTheMicrosoftMark() {
        XCTAssertEqual(ProviderIcon.Style.forKind("microsoft"), .microsoft)
    }

    func testUnknownProvidersFallBackToAGenericIcon() {
        XCTAssertEqual(ProviderIcon.Style.forKind("caldav"), .generic)
        XCTAssertEqual(ProviderIcon.Style.forKind(""), .generic)
    }
}
