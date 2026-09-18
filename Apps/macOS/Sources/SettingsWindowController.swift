import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let content: () -> SettingsView

    init(content: @escaping () -> SettingsView) { self.content = content }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        if window.isMiniaturized { window.deminiaturize(nil) }
        // A menu bar-only app is not active by default, so activate first, then force the
        // window in front even if another app's windows cover it.
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let created = NSWindow(contentViewController: NSHostingController(rootView: content()))
        created.title = "TimeTug Settings"
        created.styleMask = [.titled, .closable, .miniaturizable]
        created.isReleasedWhenClosed = false
        created.center()   // only on creation, so reopening keeps the user's placement
        return created
    }
}
