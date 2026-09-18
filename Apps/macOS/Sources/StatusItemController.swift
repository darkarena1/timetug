import AppKit
import SwiftUI

/// Owns the menu bar item. Left click toggles the popover; right click shows About/Settings/Quit.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let onOpenSettings: () -> Void
    private let onOpenAbout: () -> Void
    private let idleImage: NSImage?
    private let soonImage: NSImage?
    private var iconState = MenuBarIconState.idle
    private var lastClickedScreen: NSScreen?

    /// The display of the last menu bar click (fallbacks: the item's own screen, then the main screen).
    var clickedScreen: NSScreen? { lastClickedScreen ?? item.button?.window?.screen ?? NSScreen.main }

    init(popoverContent: NSViewController, onOpenSettings: @escaping () -> Void, onOpenAbout: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        self.onOpenAbout = onOpenAbout
        let fallback = NSImage(systemSymbolName: "alarm", accessibilityDescription: "TimeTug")
        idleImage = NSImage(named: "MenuBarTemplate") ?? fallback
        idleImage?.isTemplate = true            // the OS tints it for light/dark menu bars
        idleImage?.accessibilityDescription = "TimeTug"
        soonImage = NSImage(named: "MenuBarColor") ?? idleImage
        if soonImage !== idleImage { soonImage?.isTemplate = false }
        soonImage?.accessibilityDescription = "TimeTug: meeting soon"
        super.init()
        popover.behavior = .transient
        popover.contentViewController = popoverContent
        if let button = item.button {
            button.image = idleImage
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    /// Swaps between the template icon and the color icon; a no-op when the state is unchanged.
    func setIconState(_ state: MenuBarIconState) {
        guard state != iconState, let button = item.button else { return }
        iconState = state
        button.image = state == .soon ? soonImage : idleImage
        button.toolTip = state == .soon ? "Meeting soon" : nil
    }

    /// nil shows the icon only.
    func setTitle(_ text: String?) {
        let title = text.map { " " + $0 } ?? ""
        if item.button?.title != title { item.button?.title = title }
    }

    @objc private func clicked() {
        lastClickedScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? item.button?.window?.screen ?? NSScreen.main
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
