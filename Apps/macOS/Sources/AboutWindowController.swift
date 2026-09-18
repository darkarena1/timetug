import AppKit
import SwiftUI

/// Owns the standalone About window. It follows `NSApp.appearance` (Light/Dark/Auto) automatically.
@MainActor
final class AboutWindowController {
    private var window: NSWindow?

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        if window.isMiniaturized { window.deminiaturize(nil) }
        // Menu bar-only app: activate first, then force the window in front.
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let created = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        created.title = "About TimeTug"
        created.isReleasedWhenClosed = false
        let host = NSHostingController(rootView: AboutView(onDone: { [weak created] in created?.close() }))
        created.contentViewController = host
        created.setContentSize(host.view.fittingSize)
        created.center()
        return created
    }
}
