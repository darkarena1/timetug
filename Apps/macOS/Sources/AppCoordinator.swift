import AppKit
import Combine
import EventKitSource
import SwiftUI
import TimeTugCore

/// Wires sources, store, scheduler and the UI. Holds no presentation logic itself.
@MainActor
final class AppCoordinator {
    private static let periodicRefresh: TimeInterval = 300

    let settings = SettingsStore()
    let model = AppModel()
    let navigation = SettingsNavigation()

    private let eventKit = EventKitSource()
    private let store: CalendarStore
    private var snapshot = CalendarSnapshot.empty
    private var ledger = TakeoverLedger()
    private var fireTimer: Timer?
    private var tickTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var statusItem: StatusItemController?
    private let overlay = OverlayController()
    private lazy var aboutWindow = AboutWindowController()
    private lazy var settingsWindow = SettingsWindowController { [unowned self] in
        SettingsView(settings: settings, model: model, navigation: navigation, onTestTug: { [weak self] in self?.fireTest() })
    }

    init() {
        store = CalendarStore(sources: [eventKit])
    }

    func start() async {
        NSApp.appearance = settings.appearanceMode.nsAppearance
        statusItem = StatusItemController(
            popoverContent: NSHostingController(
                rootView: DropdownView(model: model, onOpenSettings: { [weak self] in self?.openSettings() })
            ),
            onOpenSettings: { [weak self] in self?.openSettings() },
            onOpenAbout: { [weak self] in self?.aboutWindow.show() }
        )
        _ = await eventKit.requestAccess()
        observeSystemEvents()
        settings.$takeover.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.rearm(); self?.updateUI() }
        }.store(in: &cancellables)
        settings.$appearanceMode.dropFirst().sink { mode in
            NSApp.appearance = mode.nsAppearance
        }.store(in: &cancellables)
        settings.$menuBarMode.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.updateUI() }
        }.store(in: &cancellables)

        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateUI() }
        }
        Timer.scheduledTimer(withTimeInterval: Self.periodicRefresh, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        await refresh()
        if settings.takeover.takeoverCalendarKeys.isEmpty { openSettings(pane: .calendars) }

        for await _ in eventKit.changes() { await refresh() }
    }

    func refresh() async {
        snapshot = await store.refresh(now: Date(), leadTime: settings.takeover.leadTime)
        model.calendars = snapshot.calendars
        model.statuses = snapshot.statuses
        model.sourceNames = snapshot.sourceNames
        ledger.prune(now: Date())
        rearm()
        updateUI()
    }

    /// Arms one timer for the next takeover. Skipped while an overlay is up (see Task 10).
    func rearm() {
        fireTimer?.invalidate()
        fireTimer = nil
        guard !isOverlayVisible,
              let next = Scheduler.next(events: snapshot.events, settings: settings.takeover,
                                        ledger: ledger, now: Date()) else { return }
        let timer = Timer(fire: next.fireAt, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fire(next.event) }
        }
        RunLoop.main.add(timer, forMode: .common)
        fireTimer = timer
    }

    private func fire(_ event: CalendarEvent) {
        ledger.markFired(event)
        present(TakeoverRequest.make(for: event, now: Date()))
    }

    func updateUI() {
        let now = Date()
        let agenda = DayAgenda.make(events: snapshot.events, settings: settings.takeover,
                                    now: now, calendar: .current)
        if agenda != model.agenda { model.agenda = agenda }
        statusItem?.setTitle(TimeFormatting.statusTitle(mode: settings.menuBarMode, next: agenda.next, now: now))
    }

    /// Timers alone are not trusted: recompute after wake, clock, timezone and day changes.
    private func observeSystemEvents() {
        let recompute: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: recompute)
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange, .NSCalendarDayChanged] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main, using: recompute)
        }
    }

    private var isOverlayVisible: Bool { overlay.isVisible }

    private func present(_ request: TakeoverRequest) {
        let event = request.event
        overlay.show(request, actions: .init(
            join: { [weak self] in
                if let url = request.joinURL { NSWorkspace.shared.open(url) }
                self?.closeOverlay()
            },
            snooze: { [weak self] seconds in
                self?.ledger.snooze(event, for: seconds, now: Date())
                self?.closeOverlay()
            },
            dismiss: { [weak self] in self?.closeOverlay() }
        ))
    }

    private func closeOverlay() {
        overlay.hide()
        rearm()
    }

    /// Settings' "Test tug" button: a sample event that never touches the ledger.
    func fireTest() {
        let now = Date()
        let sample = CalendarEvent(
            sourceEventID: "test", sourceID: "test", calendarID: "test", title: "Sample meeting",
            start: now.addingTimeInterval(settings.takeover.leadTime),
            end: now.addingTimeInterval(settings.takeover.leadTime + 1800),
            otherAttendeeCount: 1, conferenceURL: URL(string: "https://meet.google.com/aaa-bbbb-ccc"))
        overlay.show(TakeoverRequest.make(for: sample, now: now), actions: .init(
            join: { [weak self] in self?.overlay.hide() },
            snooze: { [weak self] _ in self?.overlay.hide() },
            dismiss: { [weak self] in self?.overlay.hide() }
        ))
    }

    func openSettings(pane: SettingsPane? = nil) {
        if let pane { navigation.pane = pane }
        settingsWindow.show()
    }
}
