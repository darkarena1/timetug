import XCTest
@testable import TimeTug

final class ProviderIconTests: XCTestCase {
    func testGoogleAccountsGetTheGoogleMark() {
        XCTAssertEqual(ProviderIcon.Style.forKind("google"), .google)
    }

    func testMicrosoftAccountsGetTheMicrosoftMark() {
        XCTAssertEqual(ProviderIcon.Style.forKind("microsoft"), .microsoft)
    }

    func testICloudAndCalDAVAccountsGetTheirOwnMarks() {
        XCTAssertEqual(ProviderIcon.Style.forKind("icloud"), .icloud)
        XCTAssertEqual(ProviderIcon.Style.forKind("caldav"), .caldav)
    }

    func testUnknownProvidersFallBackToAGenericIcon() {
        XCTAssertEqual(ProviderIcon.Style.forKind("zoom"), .generic)
        XCTAssertEqual(ProviderIcon.Style.forKind(""), .generic)
    }

    func testICalLinkAccountsGetTheirOwnMark() {
        XCTAssertEqual(ProviderIcon.Style.forKind("icalsub"), .feed)
    }
}
