import Foundation
import XCTest
@testable import TimeTug

final class SafeJoinTests: XCTestCase {
    func testUnsafeCalendarURLNeverReachesOpener() {
        var opened: [URL] = []
        let unsafe = URL(string: "file:///tmp/payload")!
        XCTAssertFalse(SafeJoin.open(unsafe, using: { opened.append($0) }))
        XCTAssertTrue(opened.isEmpty)
        let safe = URL(string: "https://meet.google.com/abc")!
        XCTAssertTrue(SafeJoin.open(safe, using: { opened.append($0) }))
        XCTAssertEqual(opened, [safe])
    }
}
