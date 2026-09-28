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

    /// Kind ids TimeTug supports in code but couldn't register this build — e.g. Google without an OAuth
    /// client configured. Distinct from a kind that's simply not built yet: the Accounts pane shows these
    /// with their real icon, dimmed, plus a warning, instead of silently leaving them out.
    let unconfiguredKindIDs: [String]

    /// What the pane shows while a sign-in runs: a password sign-in happens in the app, an OAuth one in the browser.
    @Published private(set) var waitingText = "Waiting for your browser…"

    /// Shows the credential sheet for `.password` kinds; the same instance answers `promptCredentials` (see AppCoordinator).
    let credentialPrompter: CredentialPrompter

    private let registry: ConnectorRegistry
    private let connectionStore: FileConnectionStore
    private let credentials: any CredentialStore
    private let syncState: any SyncStateStore
    private let interaction: any AuthorizationInteraction
    private let settings: SettingsStore
    private let reconciler: SourceReconciler
    private let applySources: ([any TimeTugCore.CalendarSource]) async -> Void
    private let requestEventKitAccess: () async -> Void
    private var authTask: Task<Void, Never>?

    init(
        registry: ConnectorRegistry, connectionStore: FileConnectionStore, credentials: any CredentialStore,
        syncState: any SyncStateStore, interaction: any AuthorizationInteraction, settings: SettingsStore,
        reconciler: SourceReconciler, applySources: @escaping ([any TimeTugCore.CalendarSource]) async -> Void,
        requestEventKitAccess: @escaping () async -> Void, unconfiguredKindIDs: [String] = [],
        credentialPrompter: CredentialPrompter? = nil
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
        self.unconfiguredKindIDs = unconfiguredKindIDs
        self.credentialPrompter = credentialPrompter ?? CredentialPrompter()
    }

    /// Account kinds offered by `+` (system-permission kinds such as Apple Calendar are a switch, not an account).
    /// "Other CalDAV" goes last: it is the catch-all for providers without their own entry.
    var availableKinds: [any ConnectorKind] {
        let kinds = registry.kinds(for: .current).filter { if case .system = $0.authorization { false } else { true } }
        return kinds.filter { $0.id != "caldav" } + kinds.filter { $0.id == "caldav" }
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
            let connection = try await signIn(with: kind, prefill: [:]) {
                try await kind.authorize(using: interaction, credentials: credentials)
            }
            authorized = connection
            if accounts.contains(where: { $0.kindID == connection.kindID && $0.displayName == connection.displayName }) {
                await discardSecretsIfUnowned(connection.connectionID)
                errorMessage = "\(connection.displayName) is already added."
                return
            }
            try await connectionStore.add(connection)
            accounts.append(connection)
            await reconcileAndApply()
        } catch is CancellationError {
            // The user cancelled the sign-in.
            if let authorized { await discardSecretsIfUnowned(authorized.connectionID) }
        } catch {
            if let authorized { await discardSecretsIfUnowned(authorized.connectionID) }
            errorMessage = Self.describe(error)
        }
    }

    /// Deletes a discarded sign-in's secrets, unless a stored account has the same connection id. A connector that
    /// reuses one id per account has then just overwritten that account's own secrets with a fresh sign-in, which stays.
    private func discardSecretsIfUnowned(_ connectionID: ConnectionID) async {
        guard !accounts.contains(where: { $0.connectionID == connectionID }) else { return }
        try? await credentials.removeSecrets(for: connectionID)
    }

    /// Starts `addAccount` as a cancellable task (the pane's Cancel button calls `cancelAuthorization`).
    func beginAddAccount(kindID: String) {
        authTask = Task { await addAccount(kindID: kindID) }
    }

    /// Starts `reauthorize` as the same cancellable task, so Cancel works during "Sign in again" too.
    func beginReauthorize(connectionID: ConnectionID) {
        guard !isWorking else { return }
        authTask = Task { await reauthorize(connectionID: connectionID) }
    }

    func cancelAuthorization() { authTask?.cancel() }

    /// Runs one sign-in. A `.password` kind signs in through the credential sheet: when a submitted form fails, the sheet
    /// opens again with the error and what the user typed (never the password), until it succeeds or the user cancels.
    /// `prefill` may hold any connection config; only the kind's non-secret fields are shown.
    private func signIn(
        with kind: any ConnectorKind, prefill: [String: String], _ attempt: () async throws -> Connection
    ) async throws -> Connection {
        guard case .password(let fields) = kind.authorization else {
            waitingText = "Waiting for your browser…"
            return try await attempt()
        }
        waitingText = "Signing in…"
        let help = (kind as? CredentialPromptHelp)?.credentialHelp
        var values = prefill
        var message: String?
        while true {
            credentialPrompter.prepare(title: "\(kind.displayName) account", help: help, values: values, error: message)
            do {
                return try await attempt()
            } catch let error as CancellationError {
                throw error
            } catch {
                if Task.isCancelled { throw CancellationError() }
                guard let typed = credentialPrompter.lastNonSecretValues else { throw error }   // failed before the form
                values = typed
                message = Self.describeSignIn(error, fields: fields)
            }
        }
    }

    /// "Apple ID or app-specific password was not accepted." for a rejected password, in the kind's own words;
    /// the usual description otherwise.
    static func describeSignIn(_ error: Error, fields: [CredentialField]) -> String {
        guard case CalendarCore.SourceError.authExpired = error,
              let name = fields.first(where: { !$0.isSecret && $0.key == "username" }) ?? fields.first(where: { !$0.isSecret }),
              let secret = fields.first(where: \.isSecret) else { return describe(error) }
        return "\(name.label) or \(secret.label.prefix(1).lowercased() + secret.label.dropFirst()) was not accepted."
    }

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
            let updated = try await signIn(with: kind, prefill: connection.config) {
                try await kind.reauthorize(connection, using: interaction, credentials: credentials)
            }
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
        case CalendarCore.SourceError.invalidResponse(let message): "Sign-in failed: \(message)."
        case let e as CalendarCore.SourceError: "Sign-in failed (\(e))."
        default: error.localizedDescription
        }
    }
}
