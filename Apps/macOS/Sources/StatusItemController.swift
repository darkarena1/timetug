import AppKit
import SwiftUI

/// Owns the menu bar item. Left click toggles the popover; right click shows About/Settings/Quit.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let onOpenSettings: () -> Void
    private let onOpenAbout: () -> Void

    init(popoverContent: NSViewController, onOpenSettings: @escaping () -> Void, onOpenAbout: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        self.onOpenAbout = onOpenAbout
        super.init()
        popover.behavior = .transient
        popover.contentViewController = popoverContent
        if let button = item.button {
            let image = NSImage(named: "MenuBarTemplate")
                ?? NSImage(systemSymbolName: "alarm", accessibilityDescription: "TimeTug")
            image?.isTemplate = true            // the OS tints it for light/dark menu bars
            image?.accessibilityDescription = "TimeTug"
            button.image = image
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

    /// The right-click menu, laid out like the macOS Apple menu.
    static func makeMenu(target: AnyObject, about: Selector, settings: Selector) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "About TimeTug", action: about, keyEquivalent: "").target = target
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: settings, keyEquivalent: ",").target = target
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit TimeTug", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private func showMenu() {
        item.menu = Self.makeMenu(target: self, about: #selector(openAbout), settings: #selector(openSettings))
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func openAbout() { onOpenAbout() }
    @objc private func openSettings() { onOpenSettings() }
}
