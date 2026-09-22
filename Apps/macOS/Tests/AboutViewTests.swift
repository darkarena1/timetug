import XCTest
@testable import TimeTug

final class AboutViewTests: XCTestCase {
    func testCreditNamesTheAuthor() {
        XCTAssertTrue(AboutContent.creditText.contains("Scott O"))
        XCTAssertTrue(AboutContent.creditText.hasPrefix("Created by"))
    }
}
