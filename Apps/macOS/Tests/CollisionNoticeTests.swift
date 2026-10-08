import XCTest
@testable import TimeTug

final class CollisionNoticeTests: XCTestCase {
    private let store = InstanceInfo(bundleID: "com.timetug.app.store", version: "2.0.0", build: "9", distribution: .appStore)
    private let direct = InstanceInfo(bundleID: "com.timetug.app", version: "1.4.1", build: "5", distribution: .direct)

    func testMessageNamesBothCopiesAndSuggestsKeepingOne() {
        let notice = CollisionNotice.make(survivor: store, other: direct)
        XCTAssertTrue(notice.message.contains("App Store 2.0.0"))
        XCTAssertTrue(notice.message.contains("downloaded 1.4.1"))
        XCTAssertTrue(notice.message.contains("Only one copy runs at a time"))
        XCTAssertTrue(notice.message.contains("Keeping just one installed"))
    }

    func testPairKeyIsTheSameFromEitherSide() {
        XCTAssertEqual(CollisionNotice.make(survivor: store, other: direct).pairKey,
                       CollisionNotice.make(survivor: direct, other: store).pairKey)
    }

    func testPairKeyChangesWhenAVersionChanges() {
        let newer = InstanceInfo(bundleID: "com.timetug.app", version: "1.5.0", build: "6", distribution: .direct)
        XCTAssertNotEqual(CollisionNotice.make(survivor: store, other: direct).pairKey,
                          CollisionNotice.make(survivor: store, other: newer).pairKey)
    }

    func testShownUnlessThisPairWasDismissed() {
        let notice = CollisionNotice.make(survivor: store, other: direct)
        XCTAssertTrue(CollisionNotice.shouldShow(notice, dismissedPair: nil))
        XCTAssertFalse(CollisionNotice.shouldShow(notice, dismissedPair: notice.pairKey))
        XCTAssertTrue(CollisionNotice.shouldShow(notice, dismissedPair: "direct-1.0.0+direct-1.1.0"))
    }
}
