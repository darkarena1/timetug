import XCTest
@testable import TimeTug

final class MicrosoftOAuthSettingsTests: XCTestCase {
    func testReadsTheClientID() {
        let config = MicrosoftOAuthSettings.config(from: ["TimeTugMicrosoftClientID": " 11111111-2222-3333-4444-555555555555 "])
        XCTAssertEqual(config?.clientID, "11111111-2222-3333-4444-555555555555")
    }

    func testMissingEmptyOrUnexpandedValuesDisableMicrosoft() {
        XCTAssertNil(MicrosoftOAuthSettings.config(from: nil))
        XCTAssertNil(MicrosoftOAuthSettings.config(from: [:]))
        XCTAssertNil(MicrosoftOAuthSettings.config(from: ["TimeTugMicrosoftClientID": ""]))
        XCTAssertNil(MicrosoftOAuthSettings.config(from: ["TimeTugMicrosoftClientID": "$(MICROSOFT_OAUTH_CLIENT_ID)"]))
    }
}
