import CalendarCore
import Foundation
import TimeTugCore

/// Owns the user's accounts: add, remove, re-sign-in and the Apple Calendar switch. It persists changes, keeps
/// the source set current through the reconciler and forgets a removed account's calendar selections.
@MainActor
final class AccountsController: ObservableObject {
    @Published private(set) var accounts: [Connection] = []
    @Published private(set) var isWorking = false
    @Published private(set) var buildFailures: [ConnectionID: String] = [:]
    @Published var errorMessage: String?

    private let registry: ConnectorRegistry
    private let connectionStore: FileConnectionStore
    private let credentials: any CredentialStore
    private let syncState: any SyncStateStore
    private let interaction: any AuthorizationInteraction
    private let settings: SettingsStore
    private let reconciler: SourceReconciler
    private let applySources: ([any TimeTugCore.CalendarSource]) async -> Void
    private let requestEventKitAccess: () async -> Void
    private var addTask: Task<Void, Never>?

    init(
        registry: ConnectorRegistry, connectionStore: FileConnectionStore, credentials: any CredentialStore,
        syncState: any SyncStateStore, interaction: any AuthorizationInteraction, settings: SettingsStore,
        reconciler: SourceReconciler, applySources: @escaping ([any TimeTugCore.CalendarSource]) async -> Void,
        requestEventKitAccess: @escaping () async -> Void
    ) {
        self.registry = registry
        self.connectionStore = connectionStore
        self.credentials = credentials
        self.syncState = syncState
        self.interaction = interaction
        self.settings = settings
        self.reconciler = reconciler
        self.applySources = applySources
        self.requestEventKitAccess = requestEventKitAccess
    }

    /// Account kinds offered by `+` (system-permission kinds such as Apple Calendar are a switch, not an account).
    var availableKinds: [any ConnectorKind] {
        registry.kinds(for: .current).filter { if case .system = $0.authorization { false } else { true } }
    }

    /// The key of this account's status in `CalendarSnapshot.statuses`.
    func statusKey(for connection: Connection) -> String {
        reconciler.sourceID(forConnection: connection.connectionID) ?? connection.sourceID
    }

    func start() async {
        switch await connectionStore.load() {
        case .loaded(let list):
            accounts = list
            sweepOrphanedSelections()
        case .missing:
            accounts = []
            sweepOrphanedSelections()
        case .unreadable:
            accounts = []
            errorMessage = "Your saved accounts could not be read, so none were loaded. Nothing was deleted."
        }
        if settings.eventKitEnabled { await requestEventKitAccess() }
        await reconcileAndApply()
    }

    func addAccount(kindID: String) async {
        guard !isWorking, let kind = registry.kind(id: kindID) else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        var authorized: Connection?
        do {
            let connection = try await kind.authorize(using: interaction, credentials: credentials)
            authorized = connection
            if accounts.contains(where: { $0.kindID == connection.kindID && $0.displayName == connection.displayName }) {
                try? await credentials.removeSecrets(for: connection.connectionID)
                errorMessage = "\(connection.displayName) is already added."
                return
            }
            try await connectionStore.add(connection)
            accounts.append(connection)
            await reconcileAndApply()
        } catch is CancellationError {
            // The user cancelled the sign-in.
            if let authorized, !accounts.contains(where: { $0.connectionID == authorized.connectionID }) {
                try? await credentials.removeSecrets(for: authorized.connectionID)
            }
        } catch {
            if let authorized, !accounts.contains(where: { $0.connectionID == authorized.connectionID }) {
                try? await credentials.removeSecrets(for: authorized.connectionID)
            }
            errorMessage = Self.describe(error)
        }
    }

    /// Starts `addAccount` as a cancellable task (the pane's Cancel button calls `cancelAdd`).
    func beginAddAccount(kindID: String) {
        addTask = Task { await addAccount(kindID: kindID) }
    }
    func cancelAdd() { addTask?.cancel() }

    /// Order matters so an interruption never leaves a half-removed account that looks alive: the stored connection
    /// goes first (it is what makes the account exist), the source is then stopped through the reconciler, the
    /// calendar selections are forgotten, and secrets and sync state are deleted last, best effort.
    func removeAccount(connectionID: ConnectionID) async {
        guard let connection = accounts.first(where: { $0.connectionID == connectionID }) else { return }
        let sourceID = statusKey(for: connection)
        do { try await connectionStore.remove(connectionID: connectionID) }
        catch { errorMessage = Self.describe(error); return }
        accounts.removeAll { $0.connectionID == connectionID }
        await reconcileAndApply()
        settings.takeover.removeCalendars(forSourceID: sourceID)
        await syncState.removeAll(for: connectionID)
        do { try await credentials.removeSecrets(for: connectionID) }
        catch { errorMessage = "The account was removed, but its saved sign-in could not be deleted: \(Self.describe(error))" }
    }

    func reauthorize(connectionID: ConnectionID) async {
        guard let connection = accounts.first(where: { $0.connectionID == connectionID }),
              let kind = registry.kind(id: connection.kindID) else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let updated = try await kind.reauthorize(connection, using: interaction, credentials: credentials)
            if let index = accounts.firstIndex(where: { $0.connectionID == connectionID }) { accounts[index] = updated }
            try await connectionStore.add(updated)
            let update = reconciler.rebuild(updated, connections: accounts, eventKitEnabled: settings.eventKitEnabled)
            buildFailures = update.failures
            await applySources(update.sources)
        } catch is CancellationError {
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// Turning it off hides the calendars but keeps their stored selections, so turning it back on is lossless.
    func setEventKitEnabled(_ enabled: Bool) async {
        settings.eventKitEnabled = enabled
        if enabled { await requestEventKitAccess() }
        await reconcileAndApply()
    }

    private func reconcileAndApply() async {
        let update = reconciler.reconcile(connections: accounts, eventKitEnabled: settings.eventKitEnabled)
        buildFailures = update.failures
        await applySources(update.sources)
    }

    /// Drops stored selections of account-based sources that no stored account owns (an interrupted removal).
    /// Never runs on an unreadable file and never touches Apple Calendar (`eventkit/...`) keys.
    private func sweepOrphanedSelections() {
        let prefixes = availableKinds.map { "\($0.id)-" }
        let known = Set(accounts.map { statusKey(for: $0) } + accounts.map(\.sourceID))
        settings.takeover.removeCalendars(whereSourceID: { id in
            prefixes.contains { id.hasPrefix($0) } && !known.contains(id)
        })
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case CalendarCore.SourceError.authExpired: "Sign-in was not completed."
        case let e as CalendarCore.SourceError: "Sign-in failed (\(e))."
        default: error.localizedDescription
        }
    }
}
