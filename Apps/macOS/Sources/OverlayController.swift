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
    private var calendarTitle: String?
    private var actions: Actions?
    private var screenObserver: NSObjectProtocol?

    var isVisible: Bool { !windows.isEmpty }

    func show(_ request: TakeoverRequest, calendarTitle: String?, actions: Actions) {
        self.request = request
        self.calendarTitle = calendarTitle
        self.actions = actions
        rebuild(fadeIn: true)
        announce(request)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild(fadeIn: false) }
        }
    }

    func hide() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        request = nil
        calendarTitle = nil
        actions = nil
        closeWindows()
    }

    private func closeWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    /// Tells VoiceOver which meeting is taking over, at high priority.
    private func announce(_ request: TakeoverRequest) {
        guard let window = windows.first else { return }
        let text = TakeoverText.announcement(title: request.event.title,
                                             startsIn: request.event.start.timeIntervalSinceNow)
        NSAccessibility.post(element: window, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high,
        ])
    }

    private func rebuild(fadeIn: Bool) {
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
                ? AnyView(OverlayView(request: request, calendarTitle: calendarTitle, onJoin: actions.join,
                                      onSnooze: actions.snooze, onDismiss: actions.dismiss))
                : AnyView(SecondaryOverlayView(title: request.event.title, start: request.event.start)))
            window.setFrame(screen.frame, display: true)
            let animate = fadeIn && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            if animate { window.alphaValue = 0 }
            window.orderFrontRegardless()
            if animate {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    window.animator().alphaValue = 1
                }
            }
            if index == 0 { window.makeKey() }
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
