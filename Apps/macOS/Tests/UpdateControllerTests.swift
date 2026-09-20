import Combine
import XCTest
@testable import TimeTug

@MainActor
final class UpdateControllerTests: XCTestCase {
    private final class FakeDriver: UpdaterDriving {
        var automaticallyChecksForUpdates = true
        var lastUpdateCheckDate: Date?
        var checks = 0
        var onUpdateCycleFinished: (() -> Void)?
        func checkForUpdates() { checks += 1 }
    }

    private func freshDefaults() -> UserDefaults {
        let name = "TimeTugTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func make(_ driver: FakeDriver = FakeDriver(), defaults: UserDefaults? = nil) -> UpdateController {
        UpdateController(driver: driver, defaults: defaults ?? freshDefaults(), currentVersion: "0.2.0")
    }

    func testNoOpUpdaterDoesNothing() {
        let updater = NoOpUpdater()
        XCTAssertFalse(updater.automaticallyChecksForUpdates)
        XCTAssertNil(updater.lastUpdateCheckDate)
        updater.checkForUpdates()
        updater.automaticallyChecksForUpdates = true
        XCTAssertTrue(updater.automaticallyChecksForUpdates)
        var finished = false
        updater.onUpdateCycleFinished = { finished = true }
        XCTAssertNotNil(updater.onUpdateCycleFinished)
        XCTAssertFalse(finished)
        XCTAssertNil(updater.lastUpdateCheckDate)
    }

    func testBetasOffByDefault() {
        XCTAssertFalse(make().includeBetas)
    }

    func testIncludeBetasPersists() {
        let defaults = freshDefaults()
        make(defaults: defaults).includeBetas = true
        XCTAssertTrue(make(defaults: defaults).includeBetas)
    }

    func testAllowedChannels() {
        XCTAssertEqual(UpdateController.allowedChannels(includeBetas: true), ["beta"])
        XCTAssertEqual(UpdateController.allowedChannels(includeBetas: false), [])
    }

    func testAutomaticChecksReadFromAndWrittenToDriver() {
        let driver = FakeDriver()
        driver.automaticallyChecksForUpdates = false
        let controller = make(driver)
        XCTAssertFalse(controller.automaticallyChecks)
        controller.automaticallyChecks = true
        XCTAssertTrue(driver.automaticallyChecksForUpdates)
    }

    func testCheckForUpdatesForwards() {
        let driver = FakeDriver()
        make(driver).checkForUpdates()
        XCTAssertEqual(driver.checks, 1)
    }

    func testLastCheckDateAndVersionExposed() {
        let driver = FakeDriver()
        let date = Date(timeIntervalSince1970: 100)
        driver.lastUpdateCheckDate = date
        let controller = make(driver)
        XCTAssertEqual(controller.lastCheckDate, date)
        XCTAssertEqual(controller.currentVersion, "0.2.0")
    }

    func testFinishedUpdateCycleNotifiesObservers() {
        let driver = FakeDriver()
        let controller = make(driver)
        let changed = expectation(description: "objectWillChange")
        changed.assertForOverFulfill = false
        let sub = controller.objectWillChange.sink { changed.fulfill() }
        driver.onUpdateCycleFinished?()
        wait(for: [changed], timeout: 2)
        sub.cancel()
    }
}
