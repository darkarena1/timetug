import XCTest
@testable import TimeTug

final class GroupDefaultsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "GroupDefaultsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testCopiesKnownKeysThatAreMissingFromTheGroup() {
        let source = freshDefaults(), group = freshDefaults()
        source.set("countdown", forKey: "menuBarMode.v1")
        source.set(false, forKey: "eventKitEnabled.v1")
        GroupDefaults.migrate(from: source, to: group)
        XCTAssertEqual(group.string(forKey: "menuBarMode.v1"), "countdown")
        XCTAssertEqual(group.object(forKey: "eventKitEnabled.v1") as? Bool, false)
    }

    func testNeverOverwritesAValueAlreadyInTheGroup() {
        let source = freshDefaults(), group = freshDefaults()
        source.set("countdown", forKey: "menuBarMode.v1")
        group.set("iconOnly", forKey: "menuBarMode.v1")
        GroupDefaults.migrate(from: source, to: group)
        XCTAssertEqual(group.string(forKey: "menuBarMode.v1"), "iconOnly")
    }

    func testIgnoresUnknownKeys() {
        let source = freshDefaults(), group = freshDefaults()
        source.set("x", forKey: "SULastCheckTime")
        GroupDefaults.migrate(from: source, to: group)
        XCTAssertNil(group.object(forKey: "SULastCheckTime"))
    }

    func testRunsOncePerSource() {
        let source = freshDefaults(), group = freshDefaults()
        GroupDefaults.migrate(from: source, to: group)
        source.set("countdown", forKey: "menuBarMode.v1")
        GroupDefaults.migrate(from: source, to: group)
        XCTAssertNil(group.object(forKey: "menuBarMode.v1"))
    }

    func testSameStoreIsANoOp() {
        let defaults = freshDefaults()
        defaults.set("countdown", forKey: "menuBarMode.v1")
        GroupDefaults.migrate(from: defaults, to: defaults)
        XCTAssertEqual(defaults.string(forKey: "menuBarMode.v1"), "countdown")
    }
}
