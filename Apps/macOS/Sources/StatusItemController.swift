import AppKit
import SwiftUI

/// Owns the menu bar item. Left click toggles the popover; right click shows Settings/Quit.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let onOpenSettings: () -> Void

    init(popoverContent: NSViewController, onOpenSettings: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        super.init()
        popover.behavior = .transient
        popover.contentViewController = popoverContent
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "alarm", accessibilityDescription: "TimeTug")
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    /// nil shows the icon only.
    func setTitle(_ text: String?) {
        let title = text.map { " " + $0 } ?? ""
        if item.button?.title != title { item.button?.title = title }
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else if let button = item.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit TimeTug", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func openSettings() { onOpenSettings() }
}
