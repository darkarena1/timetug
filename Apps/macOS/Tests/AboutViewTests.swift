import XCTest
@testable import TimeTug

final class AboutViewTests: XCTestCase {
    func testCreditNamesTheAuthor() {
        XCTAssertTrue(AboutView.creditText.contains("Scott O"))
        XCTAssertTrue(AboutView.creditText.hasPrefix("Created by"))
    }
}
