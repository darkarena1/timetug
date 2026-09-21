import AppKit
import AppleIntelligenceInference
import CalendarApple
import CalendarBridge
import CalendarCore
import Combine
import EventKitSource
import KeyboardShortcuts
import OSLog
import SwiftUI
import TimeTugCore
import WidgetKit

/// Wires sources, store, scheduler and the UI. Holds no presentation logic itself.
@MainActor
final class AppCoordinator {
    private static let periodicRefresh: TimeInterval = 300
    /// Meetings that started longer than this before launch are treated as already handled.
    private static let launchGrace: TimeInterval = 120

    let settings = SettingsStore(shared: .appGroup)
    let model = AppModel()
    let navigation = SettingsNavigation()
    let updates = UpdateController(
        driver: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
            ? SparkleUpdater(includeBetas: { UserDefaults.standard.bool(forKey: UpdateController.betaKey) })
            : NoOpUpdater(),
        currentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")

    private let eventKit = EventKitSource()
    private let store: CalendarStore
    private var snapshot = CalendarSnapshot.empty
    private let ledgerStore = LedgerStore()
    private static let maxResolvePasses = 10
    private let dedupStore = DedupStateStore()
    private var lastSavedDedupState: DedupState?
    private var ledger: TakeoverLedger
    /// True until the first successful refresh after launch has acknowledged in-progress meetings.
    private var needsLaunchAcknowledge = true
    private var fireTimer: Timer?
    private var tickTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var statusItem: StatusItemController?
    private let snapshotStore = WidgetSnapshotStore()
    private var lastWidgetEvents: [WidgetEvent]?
    private var widgetReloadTask: Task<Void, Never>?
    private var settingsSignal: SettingsChangeSignal.Observer?
    private static let widgetLog = Logger(subsystem: "com.timetug.app", category: "widgets")
    private let overlay = OverlayController()
    private lazy var registry = AppConnectors.makeRegistry(google: GoogleOAuthSettings.config(), eventKit: eventKit)
    private let credentials = KeychainCredentialStore(service: "com.timetug.app.credentials")
    private let syncState = FileSyncStateStore(url: AppSupportFiles.url("sync-state.json"))
    private lazy var reconciler = SourceReconciler(
        buildAccount: { [unowned self] connection in
            guard let kind = registry.kind(id: connection.kindID) else { throw CalendarCore.SourceError.invalidResponse("unknown account type") }
            return ConnectedSource(try kind.makeSource(for: connection, credentials: credentials, syncState: syncState))
        },
        buildEventKit: { [unowned self] in ConnectedSource(eventKit) },
        onChange: { [weak self] in await self?.refresh() })
    lazy var accounts: AccountsController = AccountsController(
        registry: registry, connectionStore: FileConnectionStore(url: AppSupportFiles.url("accounts.json")),
        credentials: credentials, syncState: syncState,
        interaction: LoopbackAuthorizationInteraction(
            openURL: { url in await MainActor.run { NSWorkspace.shared.open(url) } },
            presenter: WebAuthenticationSessionPresenter(anchor: { [weak self] in self?.settingsWindow.currentWindow ?? NSApp.keyWindow })),
        settings: settings, reconciler: reconciler,
        applySources: { [weak self] sources in
            await self?.store.setSources(sources)
            await self?.refresh()
        },
        requestEventKitAccess: { [unowned self] in _ = await eventKit.requestAccess() })
    private lazy var aboutWindow = AboutWindowController()
    private lazy var settingsWindow = SettingsWindowController { [unowned self] in
        SettingsView(settings: settings, model: model, navigation: navigation, accounts: accounts, updates: updates, onTestTug: { [weak self] in self?.fireTest() },
                     onForgetCorrections: { [weak self] in self?.forgetCorrections() })
    }

    init() {
        store = CalendarStore(sources: [], adjudicator: AppleIntelligence.makeAdjudicator())
        var loaded = ledgerStore.load()
        loaded.prune(now: Date())
        ledger = loaded
        TakeoverLog.ledgerLoaded(count: loaded.keyCount)
        persistLedger()
    }

    func start() async {
        NSApp.appearance = settings.appearanceMode.nsAppearance
        statusItem = StatusItemController(
            popoverContent: Self.makePopoverController(
                DropdownView(
                    model: model,
                    onOpenSettings: { [weak self] in self?.openSettings() },
                    onJoin: { [weak self] url in self?.statusItem?.join(url) },
                    onUnmerge: { [weak self] event in self?.unmerge(event) },
                    onSeparate: { [weak self] event, members in self?.separate(event, members: members) },
                    onMerge: { [weak self] a, b in self?.merge(a, b) }
                )
            ),
            onOpenSettings: { [weak self] in self?.openSettings() },
            onCheckForUpdates: { [weak self] in self?.updates.checkForUpdates() },
            onOpenAbout: { [weak self] in self?.aboutWindow.show(on: self?.statusItem?.clickedScreen) }
        )
        KeyboardShortcuts.onKeyUp(for: .togglePopup) { [weak self] in
            Task { @MainActor in self?.statusItem?.togglePopover() }
        }
        model.popupCardStyle = settings.popupCardStyle
        observeSystemEvents()
        settings.$takeover.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.rearm(); self?.updateUI(); self?.publishWidgetSnapshot() }
        }.store(in: &cancellables)
        settings.$appearanceMode.dropFirst().sink { mode in
            NSApp.appearance = mode.nsAppearance
        }.store(in: &cancellables)
        settings.$popupCardStyle.dropFirst().sink { [weak self] style in
            self?.model.popupCardStyle = style
        }.store(in: &cancellables)
        settings.$menuBarMode.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.updateUI() }
        }.store(in: &cancellables)
        settingsSignal = SettingsChangeSignal.Observer { [weak self] in
            DispatchQueue.main.async { self?.settings.reloadFromShared() }
        }

        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateUI() }
        }
        Timer.scheduledTimer(withTimeInterval: Self.periodicRefresh, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        let loadedDedup = dedupStore.load()
        lastSavedDedupState = loadedDedup
        await store.load(loadedDedup)
        _ = await store.setInferenceEnabled(settings.inferenceEnabled, now: Date())
        settings.$inferenceEnabled.dropFirst().sink { [weak self] enabled in
            Task { @MainActor in await self?.setInference(enabled) }
        }.store(in: &cancellables)
        await accounts.start()   // requests Apple Calendar access if enabled, builds the sources and refreshes
        if settings.takeover.takeoverCalendarKeys.isEmpty { openSettings(pane: .calendars) }
    }

    /// Hosting controller that reports its content size so the popover is exactly as tall as the popup.
    private static func makePopoverController(_ view: DropdownView) -> NSViewController {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.preferredContentSize]
        return controller
    }

    func refresh() async {
        // Self-heals a dropped Darwin notification from the widget extension.
        settings.reloadFromShared()
        apply(await store.refresh(now: Date(), leadTime: settings.takeover.leadTime))
        // Inference never blocks a refresh (or start / the change loop).
        Task { @MainActor [weak self] in await self?.resolvePending() }
    }

    /// Publishes a snapshot to the model, ledger bookkeeping, timers and UI.
    private func apply(_ newSnapshot: CalendarSnapshot) {
        snapshot = newSnapshot
        model.calendars = snapshot.calendars
        model.statuses = snapshot.statuses
        model.sourceNames = snapshot.sourceNames
        model.candidates = snapshot.candidates
        if ledger.prune(now: Date()) { persistLedger() }
        if needsLaunchAcknowledge {
            // Meetings already underway at launch never take over (late fire is for wake-from-sleep).
            needsLaunchAcknowledge = false
            let count = ledger.acknowledgeInProgress(events: snapshot.events, now: Date(), grace: Self.launchGrace)
            TakeoverLog.acknowledgedOnLaunch(count: count)
            if count > 0 { persistLedger() }
        }
        rearm()
        updateUI()
        publishWidgetSnapshot()
    }

    /// Asks the on-device model about look-alike pairs off the refresh path; each verdict republishes.
    private func resolvePending() async {
        model.inferenceStatus = await store.inferenceStatus()
        publishInferenceAvailability()
        // Bounded backstop: each pass drains a batch, but never loop forever if a verdict fails to stick.
        var passes = 0
        while passes < Self.maxResolvePasses, let updated = await store.resolvePending(now: Date()) {
            apply(updated)
            passes += 1
        }
        model.inferenceStatus = await store.inferenceStatus()
        publishInferenceAvailability()
        await persistDedup()
    }

    /// Writes the agenda snapshot for widgets; reloads their timelines only when the events changed.
    private func publishWidgetSnapshot() {
        let widgetSnapshot = WidgetSnapshot.make(
            events: snapshot.events, calendars: snapshot.calendars, settings: settings.takeover,
            now: Date(), calendar: .current)
        do {
            try snapshotStore.write(widgetSnapshot)
        } catch {
            Self.widgetLog.error("widget snapshot not written: \(error.localizedDescription, privacy: .public)")
            return
        }
        if #available(macOS 26.0, *) { ControlCenter.shared.reloadAllControls() }
        guard widgetSnapshot.events != lastWidgetEvents else { return }
        lastWidgetEvents = widgetSnapshot.events
        widgetReloadTask?.cancel()
        widgetReloadTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func publishInferenceAvailability() {
        settings.shared.set(model.inferenceStatus.isAvailableOnThisMac, for: .inferenceAvailable)
        if #available(macOS 26.0, *) { ControlCenter.shared.reloadAllControls() }
    }

    private func setInference(_ enabled: Bool) async {
        apply(await store.setInferenceEnabled(enabled, now: Date()))
        await resolvePending()
    }

    func unmerge(_ event: TimeTugCalendarEvent) {
        Task { @MainActor in
            apply(await store.unmerge(event, now: Date()))
            await persistDedup()
        }
    }

    func separate(_ event: TimeTugCalendarEvent, members: [MergedMember]) {
        Task { @MainActor in
            apply(await store.separate(members, from: event, now: Date()))
            await persistDedup()
        }
    }

    func merge(_ a: TimeTugCalendarEvent, _ b: TimeTugCalendarEvent) {
        Task { @MainActor in
            apply(await store.merge(a, b, now: Date()))
            await persistDedup()
        }
    }

    private func forgetCorrections() {
        Task { @MainActor in
            apply(await store.forgetLessons(now: Date()))
            await persistDedup()
            await resolvePending()
        }
    }

    private func persistDedup() async {
        let state = await store.state()
        guard state != lastSavedDedupState else { return }
        dedupStore.save(state)
        lastSavedDedupState = state
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

    private func persistLedger() {
        ledgerStore.save(ledger, now: Date())
    }

    /// Always checks the ledger and the current calendar snapshot BEFORE showing anything: the
    /// event captured when the timer was armed may be stale.
    private func fire(_ event: TimeTugCalendarEvent) {
        let now = Date()
        let decision = TakeoverGuard.evaluate(
            event: event, currentEvents: snapshot.events, settings: settings.takeover,
            ledger: ledger, now: now, overlayVisible: overlay.isVisible)
        switch decision {
        case .suppress(.overlayVisible):
            // Stays pending, not marked fired; closeOverlay() re-arms.
            TakeoverLog.suppressed(.overlayVisible, event: event)
        case .suppress(let reason):
            TakeoverLog.suppressed(reason, event: event)
            rearm()
        case .present:
            let current = snapshot.events.first { $0.isSameMeeting(as: event) } ?? event
            let reason = ledger.isSnoozed(current) ? "snooze expired"
                : now >= current.start.addingTimeInterval(Self.launchGrace) ? "late after wake" : "lead time"
            ledger.markFired(current, now: now)
            persistLedger()
            TakeoverLog.presented(reason: reason, event: current)
            present(TakeoverRequest.make(for: current, now: now))
        }
    }

    func updateUI() {
        let now = Date()
        let agenda = DayAgenda.make(events: snapshot.events, settings: settings.takeover,
                                    now: now, calendar: .current)
        if agenda != model.agenda { model.agenda = agenda }
        if model.leadTime != settings.takeover.leadTime { model.leadTime = settings.takeover.leadTime }
        statusItem?.setTitle(TimeFormatting.statusTitle(mode: settings.menuBarMode, next: agenda.next, now: now))
        statusItem?.setIconState(MenuBarIconState.resolve(
            events: snapshot.events, settings: settings.takeover, ledger: ledger, now: now))
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
        let calendarTitle = snapshot.calendars.first { $0.key == event.calendarKey }?.title
        overlay.show(request, calendarTitle: calendarTitle, actions: .init(
            join: { [weak self] in
                if let url = request.joinURL { NSWorkspace.shared.open(url) }
                self?.closeOverlay()
            },
            snooze: { [weak self] seconds in
                self?.ledger.snooze(event, for: seconds, now: Date())
                self?.persistLedger()
                self?.closeOverlay()
            },
            dismiss: { [weak self] in self?.closeOverlay() }
        ))
    }

    private func closeOverlay() {
        overlay.hide()
        rearm()
        updateUI()
    }

    /// Settings' "Test tug" button: a sample event that never touches the ledger.
    func fireTest() {
        let now = Date()
        var sample = TimeTugCalendarEvent(
            event: CalendarCore.CalendarEvent(
                eventID: "test", calendarID: "test", title: "Sample meeting",
                start: now.addingTimeInterval(settings.takeover.leadTime),
                end: now.addingTimeInterval(settings.takeover.leadTime + 1800)),
            sourceID: "test")
        sample.otherAttendeeCount = 1
        sample.conferenceURL = URL(string: "https://meet.google.com/aaa-bbbb-ccc")
        overlay.show(TakeoverRequest.make(for: sample, now: now), calendarTitle: "Sample calendar", actions: .init(
            join: { [weak self] in self?.overlay.hide() },
            snooze: { [weak self] _ in self?.overlay.hide() },
            dismiss: { [weak self] in self?.overlay.hide() }
        ))
    }

    func openSettings(pane: SettingsPane? = nil) {
        if let pane { navigation.pane = pane }
        settingsWindow.show(on: statusItem?.clickedScreen)
    }
}
