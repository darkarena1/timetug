import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let content: () -> SettingsView

    init(content: @escaping () -> SettingsView) { self.content = content }

    func show() {
        if window == nil {
            let created = NSWindow(contentViewController: NSHostingController(rootView: content()))
            created.title = "TimeTug Settings"
            created.styleMask = [.titled, .closable]
            created.isReleasedWhenClosed = false
            window = created
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
