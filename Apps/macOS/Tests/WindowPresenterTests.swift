import AppKit
import XCTest
@testable import TimeTug

@MainActor
final class WindowPresenterTests: XCTestCase {
    func testCenteredFrameCentersInVisibleFrame() {
        let r = WindowPresenter.centeredFrame(size: NSSize(width: 400, height: 300),
                                              in: NSRect(x: 0, y: 25, width: 1440, height: 875))
        XCTAssertEqual(r, NSRect(x: 520, y: 312.5, width: 400, height: 300))
    }

    func testCenteredFrameClampsOversizeWindow() {
        let visible = NSRect(x: 0, y: 25, width: 1440, height: 875)
        let r = WindowPresenter.centeredFrame(size: NSSize(width: 3000, height: 2000), in: visible)
        XCTAssertEqual(r, visible)
    }

    func testNeedsMoveFalseWhenInsideScreen() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertFalse(WindowPresenter.needsMove(windowFrame: NSRect(x: 100, y: 100, width: 400, height: 300), targetScreenFrame: screen))
    }

    func testNeedsMoveTrueWhenOnAnotherScreen() {
        let screen = NSRect(x: 1440, y: 0, width: 1920, height: 1080)
        XCTAssertTrue(WindowPresenter.needsMove(windowFrame: NSRect(x: 100, y: 100, width: 400, height: 300), targetScreenFrame: screen))
    }

    func testNeedsMoveWithNegativeXSecondaryDisplay() {
        let left = NSRect(x: -1920, y: 0, width: 1920, height: 1080)
        XCTAssertTrue(WindowPresenter.needsMove(windowFrame: NSRect(x: 100, y: 100, width: 400, height: 300), targetScreenFrame: left))
        XCTAssertFalse(WindowPresenter.needsMove(windowFrame: NSRect(x: -1000, y: 100, width: 400, height: 300), targetScreenFrame: left))
    }

    func testPresentSetsSpaceBehaviorPlacesAndRaisesTemporarily() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("No main screen") }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        WindowPresenter.present(window, on: screen)
        defer { window.orderOut(nil) }

        XCTAssertTrue(window.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(window.collectionBehavior.contains(.canJoinAllSpaces))
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        XCTAssertTrue(screen.visibleFrame.contains(center))
        XCTAssertEqual(window.level, .floating)

        let done = expectation(description: "level restored")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { done.fulfill() }
        wait(for: [done], timeout: 3)
        XCTAssertEqual(window.level, .normal)
    }

    func testPresentKeepsPositionWhenWindowIsAlreadyOnTheTargetScreen() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("No main screen") }
        let origin = NSPoint(x: screen.frame.minX + 120, y: screen.frame.minY + 240)
        let window = NSWindow(contentRect: NSRect(origin: origin, size: NSSize(width: 400, height: 300)),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(origin)
        WindowPresenter.present(window, on: screen)
        defer { window.orderOut(nil) }

        XCTAssertEqual(window.frame.origin.x, origin.x, accuracy: 0.5)
        XCTAssertEqual(window.frame.origin.y, origin.y, accuracy: 0.5)
    }
}
