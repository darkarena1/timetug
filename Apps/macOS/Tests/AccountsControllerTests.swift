import CalendarCore
import TimeTugCore
import XCTest
@testable import TimeTug

private struct NoInteraction: AuthorizationInteraction {
    func beginOAuthRedirect() async throws -> any OAuthRedirectSession { throw CalendarCore.SourceError.invalidResponse("unused") }
    func promptCredentials(_ fields: [CredentialField]) async throws -> [String: String] { [:] }
}

private final class FakeKind: ConnectorKind, @unchecked Sendable {
    let id = "google"
    let displayName = "Google"
    let supportedPlatforms = Platform.macOS
    let authorization = AuthorizationMethod.oauth
    var nextEmail = "a@x.test"
    var nextConnectionID = "1"
    var reauthorizeError: Error?
    private(set) var reauthorized = 0
    func authorize(using interaction: any AuthorizationInteraction, credentials: any CredentialStore) async throws -> Connection {
        let c = Connection(kindID: id, connectionID: nextConnectionID, displayName: nextEmail, config: ["email": nextEmail])
        try await credentials.setSecrets(["refresh_token": "r-\(nextConnectionID)"], for: c.connectionID)
        return c
    }
    func reauthorize(_ connection: Connection, using interaction: any AuthorizationInteraction, credentials: any CredentialStore) async throws -> Connection {
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

    private func makeController(credentials override: (any CredentialStore)? = nil) -> AccountsController {
        var registry = ConnectorRegistry()
        registry.register(kind)
        return AccountsController(
            registry: registry, connectionStore: connectionStore, credentials: override ?? credentials,
            syncState: syncState, interaction: NoInteraction(), settings: settings, reconciler: reconciler,
            applySources: { [unowned self] sources in applied.append(sources.map(\.id)) },
            requestEventKitAccess: {})
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
