import CalendarCore
import Foundation
import Security

/// A `CredentialStore` in the macOS Keychain: one generic-password item per connection (account =
/// `connectionID`), whose data is the JSON of that connection's secrets. `service` namespaces the app's items.
public struct KeychainCredentialStore: CredentialStore {
    public struct KeychainError: Error, Equatable { public let status: OSStatus }

    private let service: String
    public init(service: String) { self.service = service }

    private func query(_ connectionID: ConnectionID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: connectionID]
    }

    public func secrets(for connectionID: ConnectionID) async throws -> [String: String]? {
        var q = query(connectionID)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    public func setSecrets(_ secrets: [String: String], for connectionID: ConnectionID) async throws {
        let data = try JSONEncoder().encode(secrets)
        var status = SecItemUpdate(query(connectionID) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(connectionID)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func removeSecrets(for connectionID: ConnectionID) async throws {
        let status = SecItemDelete(query(connectionID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
