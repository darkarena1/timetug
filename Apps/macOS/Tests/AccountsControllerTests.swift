import CalendarCore
import TimeTugCore
import XCTest
@testable import TimeTug

private struct PrompterInteraction: AuthorizationInteraction {
    let prompter: CredentialPrompter
    func beginOAuthRedirect() async throws -> any OAuthRedirectSession { throw CalendarCore.SourceError.invalidResponse("unused") }
    func promptCredentials(_ fields: [CredentialField]) async throws -> [String: String] { try await prompter.prompt(fields) }
}

/// A `.password` kind like "Other CalDAV": it prompts, then accepts only `goodPassword` (or throws `failure`).
private final class PasswordKind: ConnectorKind, CredentialPromptHelp, @unchecked Sendable {
    let id = "caldav"
    let displayName = "Other CalDAV"
    let supportedPlatforms = Platform.macOS
    let fields = [
        CredentialField(key: "serverURL", label: "Server address"), CredentialField(key: "username", label: "User name"),
        CredentialField(key: "password", label: "Password", isSecret: true),
    ]
    var authorization: AuthorizationMethod { .password(fields: fields) }
    let credentialHelp: CredentialHelp? = CredentialHelp(text: "Use the address your provider gives you.")
    var goodPassword = "right"
    var failure: Error?
    private(set) var attempts = 0

    func authorize(using interaction: any AuthorizationInteraction, credentials: any CredentialStore) async throws -> Connection {
        let values = try await signIn(interaction)
        let connection = Connection(kindID: id, connectionID: "p\(attempts)", displayName: values["username"] ?? "",
                                    config: ["serverURL": values["serverURL"] ?? "", "username": values["username"] ?? ""])
        try await credentials.setSecrets(["username": values["username"] ?? "", "password": values["password"] ?? ""], for: connection.connectionID)
        return connection
    }
    func reauthorize(_ connection: Connection, using interaction: any AuthorizationInteraction, credentials: any CredentialStore) async throws -> Connection {
        _ = try await signIn(interaction)
        return connection
    }
    private func signIn(_ interaction: any AuthorizationInteraction) async throws -> [String: String] {
        attempts += 1
        let values = try await interaction.promptCredentials(fields)
        if let failure { throw failure }
        guard values["password"] == goodPassword else { throw CalendarCore.SourceError.authExpired }
        return values
    }
    func makeSource(for connection: Connection, credentials: any CredentialStore, syncState: any SyncStateStore) throws -> any CalendarCore.CalendarSource {
        fatalError("controller tests build core sources through the reconciler closure")
    }
}

private final class FakeKind: ConnectorKind, @unchecked Sendable {
    let id = "google"
    let displayName = "Google"
    let supportedPlatforms = Platform.macOS
    let authorization = AuthorizationMethod.oauth
    var nextEmail = "a@x.test"
    var nextConnectionID = "1"
    var reauthorizeError: Error?
    var reauthorizeSuspends = false
    private(set) var reauthorized = 0
    func authorize(using interaction: any AuthorizationInteraction, credentials: any CredentialStore) async throws -> Connection {
        let c = Connection(kindID: id, connectionID: nextConnectionID, displayName: nextEmail, config: ["email": nextEmail])
        try await credentials.setSecrets(["refresh_token": "r-\(nextConnectionID)"], for: c.connectionID)
        return c
    }
    func reauthorize(_ connection: Connection, using interaction: any AuthorizationInteraction, credentials: any CredentialStore) async throws -> Connection {
        if reauthorizeSuspends { try await Task.sleep(for: .seconds(30)) }
        if let reauthorizeError { throw reauthorizeError }
        reauthorized += 1
        return connection
    }
    func makeSource(for connection: Connection, credentials: any CredentialStore, syncState: any SyncStateStore) throws -> any CalendarCore.CalendarSource {
        fatalError("controller tests build core sources through the reconciler closure")
    }
}

private struct FailingRemovalCredentials: CredentialStore {
    struct Failure: Error {}
    let inner: InMemoryCredentialStore
    func secrets(for connectionID: ConnectionID) async throws -> [String: String]? { try await inner.secrets(for: connectionID) }
    func setSecrets(_ secrets: [String: String], for connectionID: ConnectionID) async throws {
        try await inner.setSecrets(secrets, for: connectionID)
    }
    func removeSecrets(for connectionID: ConnectionID) async throws { throw Failure() }
}

@MainActor
final class AccountsControllerTests: XCTestCase {
    private var directory: URL!
    private var storeURL: URL!
    private var connectionStore: FileConnectionStore!
    private var credentials: InMemoryCredentialStore!
    private var syncState: InMemorySyncStateStore!
    private var settings: SettingsStore!
    private var kind: FakeKind!
    private var applied: [[String]] = []
    private var buildCount = 0
    private var reconciler: SourceReconciler!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("AccountsControllerTests-\(UUID().uuidString)")
        storeURL = directory.appendingPathComponent("connections.json")
        connectionStore = FileConnectionStore(url: storeURL)
        credentials = InMemoryCredentialStore()
        syncState = InMemorySyncStateStore()
        let suite = "AccountsControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        settings = SettingsStore(defaults: defaults)
        kind = FakeKind()
        applied = []
        buildCount = 0
        reconciler = SourceReconciler(
            buildAccount: { [unowned self] c in
                buildCount += 1
                return FakeCoreSource(id: c.sourceID)
            },
            buildEventKit: { FakeCoreSource(id: "eventkit") },
            onChange: {})
    }

    override func tearDown() async throws {
        reconciler.stop()
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeController(
        credentials override: (any CredentialStore)? = nil, password: PasswordKind? = nil, prompter: CredentialPrompter? = nil
    ) -> AccountsController {
        var registry = ConnectorRegistry()
        registry.register(kind)
        if let password { registry.register(password) }
        let prompter = prompter ?? CredentialPrompter()
        return AccountsController(
            registry: registry, connectionStore: connectionStore, credentials: override ?? credentials,
            syncState: syncState, interaction: PrompterInteraction(prompter: prompter), settings: settings, reconciler: reconciler,
            applySources: { [unowned self] sources in applied.append(sources.map(\.id)) },
            requestEventKitAccess: {}, credentialPrompter: prompter)
    }

    private let typed = ["serverURL": "https://dav.example.test", "username": "me"]

    private func submit(_ prompter: CredentialPrompter, password: String) {
        prompter.submit(typed.merging(["password": password]) { $1 })
    }

    func testAPasswordSignInUsesTheSheetAndAddsTheAccount() async throws {
        let prompter = CredentialPrompter()
        let controller = makeController(password: PasswordKind(), prompter: prompter)
        controller.beginAddAccount(kindID: "caldav")
        try await waitUntil { prompter.request != nil }
        XCTAssertEqual(controller.waitingText, "Signing in…")
        let request = try XCTUnwrap(prompter.request)
        XCTAssertEqual(request.title, "Other CalDAV account")
        XCTAssertEqual(request.help?.text, "Use the address your provider gives you.")
        XCTAssertEqual(request.fields.map(\.key), ["serverURL", "username", "password"])
        XCTAssertNil(request.error)
        submit(prompter, password: "right")
        try await waitUntil { !controller.isWorking }
        XCTAssertEqual(controller.accounts.map(\.displayName), ["me"])
        XCTAssertNil(controller.errorMessage)
    }

    func testARejectedPasswordReopensTheSheetWithTheErrorAndWhatWasTyped() async throws {
        let password = PasswordKind()
        let prompter = CredentialPrompter()
        let controller = makeController(password: password, prompter: prompter)
        controller.beginAddAccount(kindID: "caldav")
        try await waitUntil { prompter.request != nil }
        submit(prompter, password: "wrong")
        try await waitUntil { prompter.request?.error != nil }
        let retry = try XCTUnwrap(prompter.request)
        XCTAssertEqual(retry.error, "User name or password was not accepted.")
        XCTAssertEqual(retry.values, typed)   // never the password
        XCTAssertTrue(controller.accounts.isEmpty)
        submit(prompter, password: "right")
        try await waitUntil { !controller.isWorking }
        XCTAssertEqual(controller.accounts.map(\.connectionID), ["p2"])
        XCTAssertEqual(password.attempts, 2)
        XCTAssertNil(controller.errorMessage)
    }

    func testOtherSignInFailuresReopenTheSheetWithTheirDescription() async throws {
        let password = PasswordKind()
        password.failure = CalendarCore.SourceError.invalidResponse("the server address must start with https://")
        let prompter = CredentialPrompter()
        let controller = makeController(password: password, prompter: prompter)
        controller.beginAddAccount(kindID: "caldav")
        try await waitUntil { prompter.request != nil }
        submit(prompter, password: "right")
        try await waitUntil { prompter.request?.error != nil }
        XCTAssertEqual(prompter.request?.error, "Sign-in failed: the server address must start with https://.")
        prompter.cancel()
        try await waitUntil { !controller.isWorking }
        XCTAssertTrue(controller.accounts.isEmpty)
        XCTAssertNil(controller.errorMessage)
    }

    func testCancellingTheSheetAddsNothingAndShowsNoError() async throws {
        let password = PasswordKind()
        let prompter = CredentialPrompter()
        let controller = makeController(password: password, prompter: prompter)
        controller.beginAddAccount(kindID: "caldav")
        try await waitUntil { prompter.request != nil }
        prompter.cancel()
        try await waitUntil { !controller.isWorking }
        XCTAssertTrue(controller.accounts.isEmpty)
        XCTAssertNil(controller.errorMessage)
        XCTAssertEqual(password.attempts, 1)
    }

    func testCancelInThePaneClosesTheSheet() async throws {
        let prompter = CredentialPrompter()
        let controller = makeController(password: PasswordKind(), prompter: prompter)
        controller.beginAddAccount(kindID: "caldav")
        try await waitUntil { prompter.request != nil }
        controller.cancelAuthorization()
        try await waitUntil { !controller.isWorking }
        XCTAssertNil(prompter.request)
        XCTAssertTrue(controller.accounts.isEmpty)
        XCTAssertNil(controller.errorMessage)
    }

    func testSignInAgainPrefillsTheSavedNonSecretFields() async throws {
        let prompter = CredentialPrompter()
        let controller = makeController(password: PasswordKind(), prompter: prompter)
        controller.beginAddAccount(kindID: "caldav")
        try await waitUntil { prompter.request != nil }
        submit(prompter, password: "right")
        try await waitUntil { !controller.isWorking }
        controller.beginReauthorize(connectionID: "p1")
        try await waitUntil { prompter.request != nil }
        XCTAssertEqual(prompter.request?.values, typed)
        submit(prompter, password: "right")
        try await waitUntil { !controller.isWorking }
        XCTAssertNil(controller.errorMessage)
    }

    func testBrowserSignInsSayTheyWaitForTheBrowser() async throws {
        let prompter = CredentialPrompter()
        let controller = makeController(password: PasswordKind(), prompter: prompter)
        controller.beginAddAccount(kindID: "caldav")
        try await waitUntil { prompter.request != nil }
        prompter.cancel()
        try await waitUntil { !controller.isWorking }
        await controller.addAccount(kindID: "google")
        XCTAssertEqual(controller.waitingText, "Waiting for your browser…")
    }

    func testOtherCalDAVIsOfferedLast() {
        let controller = makeController(password: PasswordKind())
        XCTAssertEqual(controller.availableKinds.map(\.id), ["google", "caldav"])
    }

    func testARejectedPasswordNamesTheKindsOwnFields() {
        let icloud = [CredentialField(key: "username", label: "Apple ID"), CredentialField(key: "password", label: "App-specific password", isSecret: true)]
        XCTAssertEqual(AccountsController.describeSignIn(CalendarCore.SourceError.authExpired, fields: icloud),
                       "Apple ID or app-specific password was not accepted.")
        XCTAssertEqual(AccountsController.describeSignIn(CalendarCore.SourceError.server(status: 500), fields: icloud),
                       "Sign-in failed (server(status: 500)).")
    }

    func testRejectedLinkIsDescribedForAKindWithOnlyASecretField() {
        let link = [CredentialField(key: "link", label: "iCal link", isSecret: true)]
        XCTAssertEqual(AccountsController.describeSignIn(CalendarCore.SourceError.authExpired, fields: link), "iCal link was not accepted.")
        XCTAssertEqual(AccountsController.describeSignIn(CalendarCore.SourceError.invalidResponse("that link did not return a calendar"), fields: link),
                       "Sign-in failed: that link did not return a calendar.")
    }

    func testAddPersistsAppliesAndTracksTheAccount() async {
        let controller = makeController()
        await controller.addAccount(kindID: "google")
        XCTAssertEqual(controller.accounts.map(\.connectionID), ["1"])
        let stored = await connectionStore.connections()
        XCTAssertEqual(stored.map(\.connectionID), ["1"])
        XCTAssertEqual(applied.last, ["eventkit", "google-1"])
        XCTAssertNil(controller.errorMessage)
    }

    func testAddingTheSameAccountTwiceIsRejectedAndItsSecretsAreDiscarded() async throws {
        let controller = makeController()
        await controller.addAccount(kindID: "google")
        kind.nextConnectionID = "2"
        await controller.addAccount(kindID: "google")
        XCTAssertEqual(controller.accounts.map(\.connectionID), ["1"])
        XCTAssertNotNil(controller.errorMessage)
        let secrets = try await credentials.secrets(for: "2")
        XCTAssertNil(secrets)
        let first = try await credentials.secrets(for: "1")
        XCTAssertNotNil(first)
    }

    func testADuplicateSignInThatReusesTheStoredConnectionIDKeepsTheStoredSecrets() async throws {
        let controller = makeController()
        await controller.addAccount(kindID: "google")
        await controller.addAccount(kindID: "google")
        XCTAssertEqual(controller.accounts.map(\.connectionID), ["1"])
        let stored = await connectionStore.connections()
        XCTAssertEqual(stored.map(\.connectionID), ["1"])
        XCTAssertNotNil(controller.errorMessage)
        let secrets = try await credentials.secrets(for: "1")
        XCTAssertNotNil(secrets)
    }

    func testCancelDuringSignInAgainStopsItAndChangesNothing() async throws {
        let controller = makeController()
        await controller.addAccount(kindID: "google")
        let before = controller.accounts
        let buildsBefore = buildCount
        kind.reauthorizeSuspends = true
        controller.beginReauthorize(connectionID: "1")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(controller.isWorking)
        controller.cancelAuthorization()
        for _ in 0..<50 where controller.isWorking { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(controller.isWorking)
        XCTAssertEqual(controller.accounts, before)
        XCTAssertEqual(buildCount, buildsBefore)
        XCTAssertNil(controller.errorMessage)
    }

    func testAFailedAccountSaveDiscardsTheNewSignIn() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = directory.appendingPathComponent("blocker")
        try Data("x".utf8).write(to: blocker)
        connectionStore = FileConnectionStore(url: blocker.appendingPathComponent("connections.json"))
        let controller = makeController()
        await controller.addAccount(kindID: "google")
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertTrue(controller.accounts.isEmpty)
        let secrets = try await credentials.secrets(for: "1")
        XCTAssertNil(secrets)
    }

    func testRemoveDeletesConnectionSelectionsSecretsAndSyncState() async throws {
        let controller = makeController()
        await controller.addAccount(kindID: "google")
        settings.takeover.takeoverCalendarKeys = ["google-1/c", "eventkit/x"]
        settings.takeover.hiddenCalendarKeys = ["google-1/d"]
        await syncState.setToken("t", for: "1", scope: "s")

        await controller.removeAccount(connectionID: "1")

        XCTAssertTrue(controller.accounts.isEmpty)
        let stored = await connectionStore.connections()
        XCTAssertTrue(stored.isEmpty)
        XCTAssertEqual(settings.takeover.takeoverCalendarKeys, ["eventkit/x"])
        XCTAssertTrue(settings.takeover.hiddenCalendarKeys.isEmpty)
        let secrets = try await credentials.secrets(for: "1")
        XCTAssertNil(secrets)
        let token = await syncState.token(for: "1", scope: "s")
        XCTAssertNil(token)
        XCTAssertEqual(applied.last, ["eventkit"])
        XCTAssertNil(controller.errorMessage)
    }

    func testRemoveIsIdempotent() async {
        let controller = makeController()
        await controller.addAccount(kindID: "google")
        await controller.removeAccount(connectionID: "1")
        settings.takeover.takeoverCalendarKeys = ["eventkit/x"]
        await controller.removeAccount(connectionID: "1")
        XCTAssertTrue(controller.accounts.isEmpty)
        XCTAssertEqual(settings.takeover.takeoverCalendarKeys, ["eventkit/x"])
        XCTAssertNil(controller.errorMessage)
    }

    func testKeychainFailureDuringRemovalDoesNotUndoIt() async {
        let controller = makeController(credentials: FailingRemovalCredentials(inner: credentials))
        await controller.addAccount(kindID: "google")
        await controller.removeAccount(connectionID: "1")
        XCTAssertTrue(controller.accounts.isEmpty)
        let stored = await connectionStore.connections()
        XCTAssertTrue(stored.isEmpty)
        XCTAssertNotNil(controller.errorMessage)
    }

    func testLaunchSweepRemovesOrphanedAccountSelectionsButNeverEventKit() async throws {
        try await connectionStore.save([Connection(kindID: "google", connectionID: "1", displayName: "a@x.test")])
        settings.takeover.takeoverCalendarKeys = ["google-1/c", "google-9/c", "eventkit/x"]
        let controller = makeController()
        await controller.start()
        XCTAssertEqual(settings.takeover.takeoverCalendarKeys, ["google-1/c", "eventkit/x"])
        XCTAssertEqual(controller.accounts.map(\.connectionID), ["1"])
    }

    func testLaunchSweepIsSkippedWhenTheAccountFileIsUnreadable() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: storeURL)
        settings.takeover.takeoverCalendarKeys = ["google-1/c", "google-9/c", "eventkit/x"]
        let controller = makeController()
        await controller.start()
        XCTAssertEqual(settings.takeover.takeoverCalendarKeys, ["google-1/c", "google-9/c", "eventkit/x"])
        XCTAssertNotNil(controller.errorMessage)
    }

    func testReauthorizeRebuildsTheSource() async {
        let controller = makeController()
        await controller.addAccount(kindID: "google")
        XCTAssertEqual(buildCount, 1)
        await controller.reauthorize(connectionID: "1")
        XCTAssertEqual(kind.reauthorized, 1)
        XCTAssertEqual(buildCount, 2)
        XCTAssertEqual(applied.last, ["eventkit", "google-1"])
    }

    func testEventKitToggleKeepsSelectionsAndChangesTheSourceSet() async {
        let controller = makeController()
        settings.takeover.takeoverCalendarKeys = ["eventkit/x"]
        await controller.start()
        XCTAssertEqual(applied.last, ["eventkit"])

        await controller.setEventKitEnabled(false)
        XCTAssertEqual(applied.last, [])
        XCTAssertFalse(settings.eventKitEnabled)
        XCTAssertTrue(settings.takeover.takeoverCalendarKeys.contains("eventkit/x"))

        await controller.setEventKitEnabled(true)
        XCTAssertEqual(applied.last, ["eventkit"])
        XCTAssertTrue(settings.eventKitEnabled)
        XCTAssertTrue(settings.takeover.takeoverCalendarKeys.contains("eventkit/x"))
    }
}
