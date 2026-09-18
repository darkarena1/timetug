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

    private let eventKit = EventKitSource()
    private let store: CalendarStore
    private var snapshot = CalendarSnapshot.empty
    private var ledger = TakeoverLedger()
    private var fireTimer: Timer?
    private var tickTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var statusItem: StatusItemController?

    init() {
        store = CalendarStore(sources: [eventKit])
    }

    func start() async {
        statusItem = StatusItemController(
            popoverContent: NSHostingController(
                rootView: DropdownView(model: model, onOpenSettings: { [weak self] in self?.openSettings() })
            ),
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
        _ = await eventKit.requestAccess()
        observeSystemEvents()
        settings.$takeover.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.rearm(); self?.updateUI() }
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
        if settings.takeover.takeoverCalendarKeys.isEmpty { openSettings() }

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

    // MARK: Stubs replaced in later tasks

    private var isOverlayVisible: Bool { false }
    private func present(_ request: TakeoverRequest) {
        print("TAKEOVER:", request.event.title)   // replaced in Task 10
    }
    func openSettings() {}                        // replaced in Task 11
}
