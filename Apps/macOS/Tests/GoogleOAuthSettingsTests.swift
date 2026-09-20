import XCTest
@testable import TimeTug

final class GoogleOAuthSettingsTests: XCTestCase {
    func testReadsBothKeys() {
        let config = GoogleOAuthSettings.config(from: ["TimeTugGoogleClientID": "id.apps", "TimeTugGoogleClientSecret": "s"])
        XCTAssertEqual(config?.clientID, "id.apps")
        XCTAssertEqual(config?.clientSecret, "s")
    }
    func testMissingEmptyOrUnexpandedValuesDisableGoogle() {
        XCTAssertNil(GoogleOAuthSettings.config(from: nil))
        XCTAssertNil(GoogleOAuthSettings.config(from: ["TimeTugGoogleClientID": "id"]))
        XCTAssertNil(GoogleOAuthSettings.config(from: ["TimeTugGoogleClientID": "", "TimeTugGoogleClientSecret": ""]))
        XCTAssertNil(GoogleOAuthSettings.config(from: ["TimeTugGoogleClientID": "$(GOOGLE_OAUTH_CLIENT_ID)", "TimeTugGoogleClientSecret": "s"]))
    }
}
