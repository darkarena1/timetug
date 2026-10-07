import CalendarApple
import CalendarCore
import Foundation
import Security

/// The app's `CredentialStore`: the shared keychain group (migrating the old private items on first read) when this
/// build was signed with the `keychain-access-groups` entitlement, the old private keychain item otherwise. Only the
/// release signing step (`scripts/release/sign-app.sh`, with a Developer ID provisioning profile) adds that
/// entitlement; ad-hoc and Xcode development builds cannot hold it and keep their own credentials.
enum AppCredentials {
    static let service = "com.timetug.app.credentials"

    /// True when this process was signed with a keychain access group that covers the App Group id.
    static var hasSharedKeychainGroup: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil),
              let groups = value as? [String] else { return false }
        return groups.contains { $0 == AppGroup.identifier || ($0.hasSuffix(".*") && AppGroup.identifier.hasPrefix($0.dropLast())) }
    }

    static func make(sharedGroup: Bool = hasSharedKeychainGroup) -> any CredentialStore {
        let legacy = KeychainCredentialStore(service: service)
        guard sharedGroup else { return legacy }
        return MigratingCredentialStore(
            primary: KeychainCredentialStore(service: service, accessGroup: AppGroup.identifier), legacy: legacy)
    }
}
