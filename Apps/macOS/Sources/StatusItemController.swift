import AppKit
import SwiftUI

/// Owns the menu bar item. Left click toggles the popover; right click shows About/Settings/Quit.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let onOpenSettings: () -> Void
    private let onCheckForUpdates: () -> Void
    private let onOpenAbout: () -> Void
    private let idleImage: NSImage?
    private let soonImage: NSImage?
    private var iconState = MenuBarIconState.idle
    private var appearanceObservation: NSKeyValueObservation?
    private var lastClickedScreen: NSScreen?

    /// The display of the last menu bar click (fallbacks: the item's own screen, then the main screen).
    var clickedScreen: NSScreen? { lastClickedScreen ?? item.button?.window?.screen ?? NSScreen.main }

    /// The brand accent used for the "soon" icon; matches `SettingsPane.tugRules`'s icon color.
    private static let soonColor = NSColor(red: 1.0, green: 0.62, blue: 0.10, alpha: 1)

    init(popoverContent: NSViewController, onOpenSettings: @escaping () -> Void,
         onCheckForUpdates: @escaping () -> Void, onOpenAbout: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        self.onCheckForUpdates = onCheckForUpdates
        self.onOpenAbout = onOpenAbout
        // Fall back to the clock symbols if the puppy assets are ever missing from the bundle.
        idleImage = Self.puppy(.idle, darkMenuBar: false) ?? Self.clockImage
        soonImage = Self.puppy(.soon, darkMenuBar: false)
            ?? Self.tinted(symbolName: "clock.fill", color: Self.soonColor) ?? idleImage
        soonImage?.accessibilityDescription = "TimeTug: meeting soon"
        super.init()
        popover.behavior = .transient
        popover.contentViewController = popoverContent
        if let button = item.button {
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            refreshIcon()
            // The idle puppy has a light and a dark variant; follow the menu bar's appearance.
            appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
                Task { @MainActor in self?.refreshIcon() }
            }
        }
    }

    /// Opens a meeting link from the popup and closes the popup.
    func join(_ url: URL) {
        NSWorkspace.shared.open(url)
        popover.performClose(nil)
    }

    /// Swaps between the idle puppy and the color puppy; a no-op when the state is unchanged.
    func setIconState(_ state: MenuBarIconState) {
        guard state != iconState else { return }
        iconState = state
        refreshIcon()
    }

    /// Shows the image for the current state and the menu bar's current light/dark appearance.
    private func refreshIcon() {
        guard let button = item.button else { return }
        switch iconState {
        case .soon:
            button.image = soonImage
            button.toolTip = "Meeting soon"
        case .idle:
            let dark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            button.image = Self.puppy(.idle, darkMenuBar: dark) ?? idleImage
            button.toolTip = nil
        }
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
        } else {
            togglePopover()
        }
    }

    /// Shows or hides the popup. Used by the button click and the global shortcut.
    func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = item.button else { return }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// The right-click menu, laid out like the macOS Apple menu.
    static func makeMenu(target: AnyObject, about: Selector, checkForUpdates: Selector, settings: Selector) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "About TimeTug", action: about, keyEquivalent: "").target = target
        menu.addItem(withTitle: "Check for Updates…", action: checkForUpdates, keyEquivalent: "").target = target
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: settings, keyEquivalent: ",").target = target
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit TimeTug", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private func showMenu() {
        item.menu = Self.makeMenu(target: self, about: #selector(openAbout),
                                    checkForUpdates: #selector(checkForUpdates), settings: #selector(openSettings))
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func checkForUpdates() { onCheckForUpdates() }
    @objc private func openAbout() { onOpenAbout() }
    @objc private func openSettings() { onOpenSettings() }

    private static var clockImage: NSImage? {
        let image = NSImage(systemSymbolName: "clock", accessibilityDescription: "TimeTug")
        image?.isTemplate = true                // the OS tints it for light/dark menu bars
        return image
    }

    /// A puppy image from the asset catalog, drawn as-is (not an OS-tinted template) at menu bar size.
    private static func puppy(_ state: MenuBarIconState, darkMenuBar: Bool) -> NSImage? {
        guard let image = NSImage(named: state.assetName(darkMenuBar: darkMenuBar)) else { return nil }
        image.isTemplate = false
        image.size = NSSize(width: 18, height: 18)
        image.accessibilityDescription = state == .soon ? "TimeTug: meeting soon" : "TimeTug"
        return image
    }

    /// An SF Symbol rendered in a fixed color rather than as an OS-tinted template.
    private static func tinted(symbolName: String, color: NSColor) -> NSImage? {
        guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else { return nil }
        let image = base.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))
        image?.isTemplate = false
        return image
    }
}
