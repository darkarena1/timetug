import CalendarCore
import Foundation
import Testing
@testable import CalendarApple

/// A store whose writes fail, like a keychain group the build is not entitled to.
private struct FailingWrites: CredentialStore {
    struct Failure: Error {}
    func secrets(for connectionID: ConnectionID) async throws -> [String: String]? { nil }
    func setSecrets(_ secrets: [String: String], for connectionID: ConnectionID) async throws { throw Failure() }
    func removeSecrets(for connectionID: ConnectionID) async throws {}
    func credentialSnapshot(for connectionID: ConnectionID) async throws -> CredentialSnapshot? { nil }
    func updateRefreshToken(_ token: String, for connectionID: ConnectionID, expectedRevision: UUID) async throws -> Bool { false }
}

@Suite struct MigratingCredentialStoreTests {
    @Test func readsThePrimaryWithoutTouchingTheLegacyStore() async throws {
        let primary = InMemoryCredentialStore(), legacy = InMemoryCredentialStore()
        try await primary.setSecrets(["t": "new"], for: "a")
        try await legacy.setSecrets(["t": "old"], for: "a")
        let store = MigratingCredentialStore(primary: primary, legacy: legacy)
        #expect(try await store.secrets(for: "a") == ["t": "new"])
        #expect(try await legacy.secrets(for: "a") == ["t": "old"])
    }

    @Test func movesALegacyItemIntoThePrimaryOnFirstRead() async throws {
        let primary = InMemoryCredentialStore(), legacy = InMemoryCredentialStore()
        try await legacy.setSecrets(["t": "old"], for: "a")
        let store = MigratingCredentialStore(primary: primary, legacy: legacy)
        #expect(try await store.secrets(for: "a") == ["t": "old"])
        #expect(try await primary.secrets(for: "a") == ["t": "old"])
        #expect(try await legacy.secrets(for: "a") == nil)
    }

    @Test func returnsNilWhenNeitherStoreHasTheItem() async throws {
        let store = MigratingCredentialStore(primary: InMemoryCredentialStore(), legacy: InMemoryCredentialStore())
        #expect(try await store.secrets(for: "a") == nil)
        #expect(try await store.credentialSnapshot(for: "a") == nil)
    }

    @Test func aFailedPrimaryWriteKeepsTheLegacyItemAndStillServesIt() async throws {
        let legacy = InMemoryCredentialStore()
        try await legacy.setSecrets(["t": "old"], for: "a")
        let store = MigratingCredentialStore(primary: FailingWrites(), legacy: legacy)
        #expect(try await store.secrets(for: "a") == ["t": "old"])
        #expect(try await legacy.secrets(for: "a") == ["t": "old"])
    }

    @Test func writesGoToThePrimaryAndClearAStaleLegacyCopy() async throws {
        let primary = InMemoryCredentialStore(), legacy = InMemoryCredentialStore()
        try await legacy.setSecrets(["t": "old"], for: "a")
        let store = MigratingCredentialStore(primary: primary, legacy: legacy)
        try await store.setSecrets(["t": "fresh"], for: "a")
        #expect(try await primary.secrets(for: "a") == ["t": "fresh"])
        #expect(try await legacy.secrets(for: "a") == nil)
    }

    @Test func removeClearsBothStores() async throws {
        let primary = InMemoryCredentialStore(), legacy = InMemoryCredentialStore()
        try await primary.setSecrets(["t": "x"], for: "a")
        try await legacy.setSecrets(["t": "y"], for: "a")
        let store = MigratingCredentialStore(primary: primary, legacy: legacy)
        try await store.removeSecrets(for: "a")
        #expect(try await primary.secrets(for: "a") == nil)
        #expect(try await legacy.secrets(for: "a") == nil)
    }

    @Test func refreshTokenRotationTargetsTheStoreHoldingTheItem() async throws {
        let primary = InMemoryCredentialStore(), legacy = InMemoryCredentialStore()
        try await legacy.setSecrets(["refresh_token": "old"], for: "a")
        let store = MigratingCredentialStore(primary: primary, legacy: legacy)
        let snapshot = try #require(try await store.credentialSnapshot(for: "a"))
        #expect(try await store.updateRefreshToken("rotated", for: "a", expectedRevision: snapshot.revision))
        #expect(try await primary.secrets(for: "a")?["refresh_token"] == "rotated")
        #expect(try await legacy.secrets(for: "a") == nil)
    }

    @Test func aStaleRevisionDoesNotRotateTheToken() async throws {
        let primary = InMemoryCredentialStore()
        try await primary.setSecrets(["refresh_token": "current"], for: "a")
        let store = MigratingCredentialStore(primary: primary, legacy: InMemoryCredentialStore())
        #expect(try await store.updateRefreshToken("x", for: "a", expectedRevision: UUID()) == false)
        #expect(try await primary.secrets(for: "a")?["refresh_token"] == "current")
    }

    @Test func rotationFallsBackToTheLegacyItemWhenTheCopyFailed() async throws {
        let legacy = InMemoryCredentialStore()
        try await legacy.setSecrets(["refresh_token": "old"], for: "a")
        let store = MigratingCredentialStore(primary: FailingWrites(), legacy: legacy)
        let snapshot = try #require(try await store.credentialSnapshot(for: "a"))
        #expect(try await store.updateRefreshToken("rotated", for: "a", expectedRevision: snapshot.revision))
        #expect(try await legacy.secrets(for: "a")?["refresh_token"] == "rotated")
    }
}
