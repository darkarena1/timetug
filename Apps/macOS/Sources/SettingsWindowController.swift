import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let content: () -> SettingsView

    init(content: @escaping () -> SettingsView) { self.content = content }

    func show(on screen: NSScreen? = nil) {
        let window = window ?? makeWindow()
        self.window = window
        if window.isMiniaturized { window.deminiaturize(nil) }
        WindowPresenter.present(window, on: screen)
    }

    private func makeWindow() -> NSWindow {
        let created = NSWindow(contentViewController: NSHostingController(rootView: content()))
        created.title = "TimeTug Settings"
        created.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        created.isReleasedWhenClosed = false
        // Persist size/position; center only when there is no saved frame yet.
        // (`setFrameAutosaveName` reports whether the name could be set, not whether a frame
        // was restored, so restore explicitly first.)
        let name = "TimeTugSettings.v2"
        if !created.setFrameUsingName(name) { created.center() }
        created.setFrameAutosaveName(name)
        return created
    }
}
