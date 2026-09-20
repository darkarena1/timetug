import Foundation
import Security
import Testing
@testable import CalendarApple

private func makeStore() -> KeychainCredentialStore {
    KeychainCredentialStore(service: "com.timetug.tests.\(UUID().uuidString)")
}
/// `.enabled(if:)` needs a synchronous condition, so probe the Keychain with the Security API directly.
private func keychainAvailable() -> Bool {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.timetug.tests.probe.\(UUID().uuidString)",
        kSecAttrAccount as String: "probe",
        kSecValueData as String: Data("1".utf8),
    ]
    guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { return false }
    SecItemDelete(query as CFDictionary)
    return true
}

@Test(.enabled(if: keychainAvailable())) func setGetOverwriteRemove() async throws {
    let store = makeStore()
    #expect(try await store.secrets(for: "c1") == nil)
    try await store.setSecrets(["refresh_token": "r1"], for: "c1")
    #expect(try await store.secrets(for: "c1") == ["refresh_token": "r1"])
    try await store.setSecrets(["refresh_token": "r2", "extra": "x"], for: "c1")
    #expect(try await store.secrets(for: "c1") == ["refresh_token": "r2", "extra": "x"])
    try await store.removeSecrets(for: "c1")
    #expect(try await store.secrets(for: "c1") == nil)
    try await store.removeSecrets(for: "c1")   // idempotent
}

@Test(.enabled(if: keychainAvailable())) func connectionsAreIsolated() async throws {
    let store = makeStore()
    try await store.setSecrets(["a": "1"], for: "c1")
    try await store.setSecrets(["a": "2"], for: "c2")
    #expect(try await store.secrets(for: "c1") == ["a": "1"])
    try await store.removeSecrets(for: "c1")
    try await store.removeSecrets(for: "c2")
}
