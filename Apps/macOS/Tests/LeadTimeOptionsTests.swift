import XCTest
@testable import TimeTug

final class LeadTimeOptionsTests: XCTestCase {
    private func minutes(_ seconds: TimeInterval) -> [Int] {
        LeadTimeOptions.options(including: seconds).map(\.minutes)
    }

    func testDefaultList() {
        XCTAssertEqual(minutes(300), [0, 1, 2, 3, 5, 10, 15, 20, 30])
    }

    func testZeroIsAtStart() {
        let options = LeadTimeOptions.options(including: 0)
        XCTAssertEqual(options.first?.minutes, 0)
        XCTAssertEqual(options.first?.title, "At start")
        XCTAssertEqual(options.count, 9)
    }

    func testSingularAndPluralTitles() {
        let options = LeadTimeOptions.options(including: 60)
        XCTAssertEqual(options.first { $0.minutes == 1 }?.title, "1 minute")
        XCTAssertEqual(options.first { $0.minutes == 2 }?.title, "2 minutes")
        XCTAssertEqual(options.first { $0.minutes == 30 }?.title, "30 minutes")
    }

    func testOddSavedValueIsIncludedInSortedPosition() {
        XCTAssertEqual(minutes(7 * 60), [0, 1, 2, 3, 5, 7, 10, 15, 20, 30])
        XCTAssertEqual(LeadTimeOptions.options(including: 7 * 60).first { $0.minutes == 7 }?.title, "7 minutes")
    }

    func testValueAlreadyInListIsNotDuplicated() {
        XCTAssertEqual(minutes(10 * 60).filter { $0 == 10 }.count, 1)
    }

    func testLargeValueGoesLast() {
        XCTAssertEqual(minutes(45 * 60).last, 45)
    }
}
