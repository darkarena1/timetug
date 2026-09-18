import AppKit
import SwiftUI
import TimeTugCore

/// A borderless window per display at a high level so it covers full-screen apps.
@MainActor
final class OverlayController {
    struct Actions {
        let join: () -> Void
        let snooze: (TimeInterval) -> Void
        let dismiss: () -> Void
    }

    private final class OverlayWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    private var windows: [NSWindow] = []
    private var request: TakeoverRequest?
    private var actions: Actions?
    private var screenObserver: NSObjectProtocol?

    var isVisible: Bool { !windows.isEmpty }

    func show(_ request: TakeoverRequest, actions: Actions) {
        self.request = request
        self.actions = actions
        rebuild()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }

    func hide() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        request = nil
        actions = nil
        closeWindows()
    }

    private func closeWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func rebuild() {
        closeWindows()
        guard let request, let actions else { return }
        for (index, screen) in NSScreen.screens.enumerated() {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless,
                                       backing: .buffered, defer: false)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: index == 0
                ? AnyView(OverlayView(request: request, onJoin: actions.join,
                                      onSnooze: actions.snooze, onDismiss: actions.dismiss))
                : AnyView(DimCoverView(title: request.event.title)))
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            if index == 0 { window.makeKey() }
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
