import CalendarApple
import CalendarCore
import XCTest
@testable import TimeTug

final class AppCredentialsTests: XCTestCase {
    func testBuildWithoutTheKeychainGroupUsesThePrivateItemOnly() {
        XCTAssertTrue(AppCredentials.make(sharedGroup: false) is KeychainCredentialStore)
    }

    func testBuildWithTheKeychainGroupMigratesIntoTheSharedGroup() {
        XCTAssertTrue(AppCredentials.make(sharedGroup: true) is MigratingCredentialStore)
    }

    /// Needs a test host signed with the keychain-access-groups entitlement; skipped otherwise (CI, Xcode builds).
    func testSharedKeychainGroupRoundTrips() async throws {
        try XCTSkipUnless(AppCredentials.hasSharedKeychainGroup, "this build was not signed with the keychain access group")
        let store = KeychainCredentialStore(service: "com.timetug.tests.\(UUID().uuidString)", accessGroup: AppGroup.identifier)
        try await store.setSecrets(["refresh_token": "r1"], for: "c1")
        let read = try await store.secrets(for: "c1")
        XCTAssertEqual(read, ["refresh_token": "r1"])
        try await store.removeSecrets(for: "c1")
        let after = try await store.secrets(for: "c1")
        XCTAssertNil(after)
    }
}
