import CalendarCore
import Foundation

/// Reads from `primary` (the shared keychain group); an item found only in `legacy` (the app's old private keychain
/// item) is copied into `primary` and then removed from `legacy`. If the copy fails the legacy item is kept and still
/// served, so a credential is never lost to a failed migration. An actor, so the check-then-copy cannot interleave
/// with another call.
public actor MigratingCredentialStore: CredentialStore {
    private let primary: any CredentialStore
    private let legacy: any CredentialStore

    public init(primary: any CredentialStore, legacy: any CredentialStore) {
        self.primary = primary
        self.legacy = legacy
    }

    public func secrets(for connectionID: ConnectionID) async throws -> [String: String]? {
        try await credentialSnapshot(for: connectionID)?.secrets
    }

    public func credentialSnapshot(for connectionID: ConnectionID) async throws -> CredentialSnapshot? {
        if let current = try await primary.credentialSnapshot(for: connectionID) { return current }
        guard let old = try await legacy.credentialSnapshot(for: connectionID) else { return nil }
        do {
            try await primary.setSecrets(old.secrets, for: connectionID)
        } catch {
            return old   // keep serving (and updating) the legacy item; the next read tries the copy again
        }
        // Best effort: a leftover legacy item is harmless because the primary wins from now on.
        try? await legacy.removeSecrets(for: connectionID)
        return try await primary.credentialSnapshot(for: connectionID) ?? old
    }

    public func setSecrets(_ secrets: [String: String], for connectionID: ConnectionID) async throws {
        try await primary.setSecrets(secrets, for: connectionID)
        try? await legacy.removeSecrets(for: connectionID)
    }

    public func removeSecrets(for connectionID: ConnectionID) async throws {
        try await primary.removeSecrets(for: connectionID)
        try await legacy.removeSecrets(for: connectionID)
    }

    public func updateRefreshToken(_ token: String, for connectionID: ConnectionID, expectedRevision: UUID) async throws -> Bool {
        if try await primary.credentialSnapshot(for: connectionID) != nil {
            return try await primary.updateRefreshToken(token, for: connectionID, expectedRevision: expectedRevision)
        }
        return try await legacy.updateRefreshToken(token, for: connectionID, expectedRevision: expectedRevision)
    }
}
