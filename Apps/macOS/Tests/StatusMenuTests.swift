import AppKit
import XCTest
@testable import TimeTug

@MainActor
final class StatusMenuTests: XCTestCase {
    private final class Target: NSObject {
        @objc func about() {}
        @objc func checkForUpdates() {}
        @objc func settings() {}
    }

    private func menu(_ t: Target) -> NSMenu {
        StatusItemController.makeMenu(target: t, about: #selector(Target.about),
                                      checkForUpdates: #selector(Target.checkForUpdates),
                                      settings: #selector(Target.settings))
    }

    func testMenuLayoutMatchesAppleMenuOrder() {
        let items = menu(Target()).items
        XCTAssertEqual(items.map { $0.isSeparatorItem ? "<separator>" : $0.title },
                       ["About TimeTug", "Check for Updates…", "<separator>", "Settings…", "<separator>", "Quit TimeTug"])
    }

    func testKeyEquivalents() {
        let items = menu(Target()).items
        XCTAssertEqual(items[0].keyEquivalent, "")
        XCTAssertEqual(items[1].keyEquivalent, "")
        XCTAssertEqual(items[3].keyEquivalent, ",")
        XCTAssertEqual(items[5].keyEquivalent, "q")
    }
}
