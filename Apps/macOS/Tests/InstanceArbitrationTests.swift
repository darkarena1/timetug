import XCTest
@testable import TimeTug

final class InstanceArbitrationTests: XCTestCase {
    private func info(_ version: String = "1.0.0", build: String, _ distribution: Distribution = .direct) -> InstanceInfo {
        InstanceInfo(bundleID: "com.timetug.app", version: version, build: build, distribution: distribution)
    }

    func testLaterBuildWins() {
        XCTAssertTrue(InstanceArbitration.isNewer(info(build: "20261006010101"), than: info(build: "20261005010101")))
        XCTAssertFalse(InstanceArbitration.isNewer(info(build: "20261005010101"), than: info(build: "20261006010101")))
        XCTAssertFalse(InstanceArbitration.isNewer(info(build: "5"), than: info(build: "5")))
    }

    func testBuildNumbersCompareByValueNotText() {
        XCTAssertTrue(InstanceArbitration.isNewer(info(build: "10"), than: info(build: "9")))
    }

    func testABetaBuiltAfterItsReleaseBeatsTheRelease() {
        let release = info("1.4.1", build: "20261001000000")
        let beta = info("1.4.1-beta.20261008035539", build: "20261008035539")
        XCTAssertTrue(InstanceArbitration.isNewer(beta, than: release))
        XCTAssertFalse(InstanceArbitration.isNewer(release, than: beta))
    }

    func testANewerReleaseBeatsAnEarlierBeta() {
        let beta = info("1.4.1-beta.20261008035539", build: "20261008035539")
        let release = info("1.4.2", build: "20261012000000")
        XCTAssertTrue(InstanceArbitration.isNewer(release, than: beta))
    }

    func testAnUnreadableBuildLosesToARealOne() {
        XCTAssertTrue(InstanceArbitration.isNewer(info(build: "20261001000000"), than: info(build: "?")))
        XCTAssertFalse(InstanceArbitration.isNewer(info(build: "?"), than: info(build: "20261001000000")))
        XCTAssertFalse(InstanceArbitration.isNewer(info(build: "?"), than: info(build: "")))
    }

    func testANewerNewcomerAsksTheHolderToQuit() {
        XCTAssertEqual(InstanceArbitration.decide(me: info(build: "2"), holder: info(build: "1")), .askHolderToQuit)
    }

    func testAnOlderOrEqualNewcomerExits() {
        XCTAssertEqual(InstanceArbitration.decide(me: info(build: "1"), holder: info(build: "2")), .exit)
        XCTAssertEqual(InstanceArbitration.decide(me: info(build: "2"), holder: info(build: "2")), .exit)
    }

    func testAnUnknownHolderMeansTheNewcomerExits() {
        XCTAssertEqual(InstanceArbitration.decide(me: info(build: "2"), holder: nil), .exit)
    }

    func testDistributionDoesNotChangeTheOrder() {
        XCTAssertEqual(InstanceArbitration.decide(me: info(build: "9", .appStore), holder: info(build: "5", .direct)), .askHolderToQuit)
        XCTAssertEqual(InstanceArbitration.decide(me: info(build: "5", .direct), holder: info(build: "9", .appStore)), .exit)
    }
}
