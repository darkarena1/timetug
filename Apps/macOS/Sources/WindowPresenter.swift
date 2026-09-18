import AppKit

/// Shows a window for the menu bar-only app: in the active Space (also over full-screen apps),
/// on the display the user clicked, and in front of other apps.
@MainActor
enum WindowPresenter {
    static func present(_ window: NSWindow, on screen: NSScreen?) {
        // moveToActiveSpace + fullScreenAuxiliary (not canJoinAllSpaces, which conflicts).
        window.collectionBehavior.insert([.moveToActiveSpace, .fullScreenAuxiliary])

        if let target = screen ?? NSScreen.main ?? NSScreen.screens.first,
           !window.isVisible || needsMove(windowFrame: window.frame, targetScreenFrame: target.frame) {
            window.setFrame(centeredFrame(size: window.frame.size, in: target.visibleFrame), display: false)
        }

        // Cooperative activation can refuse to raise us over the active app, so also float briefly.
        NSApp.activate()
        window.level = .floating
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak window] in
            window?.level = .normal
        }
    }

    /// Centers a window of `size` in `visibleFrame`, clamping the size to it.
    static func centeredFrame(size: NSSize, in visibleFrame: NSRect) -> NSRect {
        let w = min(size.width, visibleFrame.width)
        let h = min(size.height, visibleFrame.height)
        return NSRect(x: visibleFrame.midX - w / 2, y: visibleFrame.midY - h / 2, width: w, height: h)
    }

    /// True when the window's center is not inside the screen frame.
    static func needsMove(windowFrame: NSRect, targetScreenFrame: NSRect) -> Bool {
        !targetScreenFrame.contains(NSPoint(x: windowFrame.midX, y: windowFrame.midY))
    }
}
