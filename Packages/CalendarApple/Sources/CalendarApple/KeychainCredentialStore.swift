import CalendarCore
import Foundation
import Security

/// One instance is the app's credential authority. Actor isolation makes a conditional refresh-token
/// write atomic with sign-in/removal in that instance; other processes must not write these items.
public actor KeychainCredentialStore: CredentialStore {
    public struct KeychainError: Error, Equatable { public let status: OSStatus }

    private struct StoredCredential: Codable {
        var secrets: [String: String]
        var revision: UUID
    }

    private let service: String
    private let accessGroup: String?

    /// `accessGroup` nil is the app's private item in the login keychain. A group id (the App Group id) uses the
    /// data-protection keychain and shares the item with every app of the team that holds that group; it needs a
    /// team-signed build, so ad-hoc builds pass nil.
    public init(service: String, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    private func query(_ connectionID: ConnectionID) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: connectionID]
        if let accessGroup {
            q[kSecUseDataProtectionKeychain as String] = true
            q[kSecAttrAccessGroup as String] = accessGroup
        }
        return q
    }

    private func read(_ connectionID: ConnectionID) throws -> (credential: StoredCredential, isLegacy: Bool)? {
        var q = query(connectionID)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        if let stored = try? JSONDecoder().decode(StoredCredential.self, from: data) { return (stored, false) }
        let secrets = try JSONDecoder().decode([String: String].self, from: data)
        return (StoredCredential(secrets: secrets, revision: UUID()), true)
    }

    private func save(_ credential: StoredCredential, for connectionID: ConnectionID) throws {
        let data = try JSONEncoder().encode(credential)
        var status = SecItemUpdate(query(connectionID) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(connectionID)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func secrets(for connectionID: ConnectionID) async throws -> [String: String]? {
        try read(connectionID)?.credential.secrets
    }

    public func credentialSnapshot(for connectionID: ConnectionID) async throws -> CredentialSnapshot? {
        guard let found = try read(connectionID) else { return nil }
        if found.isLegacy { try save(found.credential, for: connectionID) }
        return CredentialSnapshot(secrets: found.credential.secrets, revision: found.credential.revision)
    }

    public func setSecrets(_ secrets: [String: String], for connectionID: ConnectionID) async throws {
        try save(StoredCredential(secrets: secrets, revision: UUID()), for: connectionID)
    }

    public func updateRefreshToken(_ token: String, for connectionID: ConnectionID, expectedRevision: UUID) async throws -> Bool {
        guard var stored = try read(connectionID)?.credential, stored.revision == expectedRevision else { return false }
        stored.secrets["refresh_token"] = token
        try save(stored, for: connectionID)
        return true
    }

    public func removeSecrets(for connectionID: ConnectionID) async throws {
        let status = SecItemDelete(query(connectionID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
