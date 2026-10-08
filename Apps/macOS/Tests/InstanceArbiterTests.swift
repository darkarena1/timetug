import XCTest
@testable import TimeTug

final class InstanceArbiterTests: XCTestCase {
    private final class FakeSignals: InstanceSignaling {
        var yields = 0, collisions = 0
        func postYield() { yields += 1 }
        func postCollision() { collisions += 1 }
    }

    private func tempFiles() throws -> InstanceFiles {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("InstanceArbiterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return InstanceFiles(directory: url)
    }

    /// The build number decides which copy is newer, so the tests name copies by it.
    private func info(_ build: String, _ distribution: Distribution = .direct) -> InstanceInfo {
        InstanceInfo(bundleID: distribution == .direct ? "com.timetug.app" : "com.timetug.app.store",
                     version: "1.0.0", build: build, distribution: distribution)
    }

    private func arbiter(_ me: InstanceInfo, _ files: InstanceFiles, _ signals: FakeSignals = FakeSignals(),
                         attempts: Int = 5, pause: @escaping () -> Void = {}) -> InstanceArbiter {
        InstanceArbiter(me: me, files: files, signals: signals, attempts: attempts, pause: pause)
    }

    func testFirstInstanceRunsAndRecordsItself() throws {
        let files = try tempFiles()
        let first = arbiter(info("20261001000000"), files)
        XCTAssertEqual(first.arbitrate(), .run(collidedWith: nil))
        XCTAssertEqual(files.read(files.recordURL), info("20261001000000"))
    }

    func testOlderNewcomerExitsAndLeavesANoticeForTheHolder() throws {
        let files = try tempFiles(), signals = FakeSignals()
        let holder = arbiter(info("20261008000000"), files)
        _ = holder.arbitrate()
        let newcomer = arbiter(info("20261001000000"), files, signals)
        XCTAssertEqual(newcomer.arbitrate(), .exit)
        XCTAssertEqual(files.read(files.collisionURL), info("20261001000000"))
        XCTAssertEqual(signals.collisions, 1)
        XCTAssertEqual(signals.yields, 0)
    }

    func testNewerNewcomerAsksTheHolderToQuitThenTakesOver() throws {
        let files = try tempFiles(), signals = FakeSignals()
        let holder = arbiter(info("20261001000000"), files)
        _ = holder.arbitrate()
        var pauses = 0
        let newcomer = arbiter(info("20261008000000", .appStore), files, signals, pause: {
            pauses += 1
            if pauses == 2 { holder.release() }
        })
        XCTAssertEqual(newcomer.arbitrate(), .run(collidedWith: info("20261001000000")))
        XCTAssertEqual(signals.yields, 1)
        XCTAssertEqual(files.read(files.handoffURL), info("20261008000000", .appStore))
        XCTAssertEqual(files.read(files.recordURL), info("20261008000000", .appStore))
    }

    func testNewcomerGivesUpWhenTheHolderNeverQuits() throws {
        let files = try tempFiles(), signals = FakeSignals()
        let holder = arbiter(info("20261001000000"), files)
        _ = holder.arbitrate()
        let newcomer = arbiter(info("20261008000000"), files, signals, attempts: 3)
        XCTAssertEqual(newcomer.arbitrate(), .exit)
        XCTAssertEqual(signals.collisions, 1)
    }

    func testMissingHolderRecordMakesTheNewcomerExit() throws {
        let files = try tempFiles()
        let holder = arbiter(info("20261001000000"), files)
        _ = holder.arbitrate()
        try FileManager.default.removeItem(at: files.recordURL)
        XCTAssertEqual(arbiter(info("20261008000000"), files).arbitrate(), .exit)
    }

    func testTheHolderYieldsToANewerRequesterOnly() throws {
        let files = try tempFiles()
        let holder = arbiter(info("20261008000000"), files)
        _ = holder.arbitrate()
        XCTAssertFalse(holder.shouldYield(), "no request on file")
        files.write(info("20261001000000"), to: files.handoffURL)
        XCTAssertFalse(holder.shouldYield(), "an older requester must not make the running copy quit")
        files.write(info("20261008000000"), to: files.handoffURL)
        XCTAssertFalse(holder.shouldYield(), "an equal requester must not either")
        files.write(info("20261009000000"), to: files.handoffURL)
        XCTAssertTrue(holder.shouldYield())
    }

    func testReleasingTheLockLetsAnotherInstanceIn() throws {
        let files = try tempFiles()
        let first = arbiter(info("20261001000000"), files)
        _ = first.arbitrate()
        first.release()
        XCTAssertEqual(arbiter(info("20261001000000"), files).arbitrate(), .run(collidedWith: nil))
    }
}
