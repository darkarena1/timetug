import CalendarCore
import Foundation
import Testing
@testable import EventKitSource

@Test func eventKitKindDescribesASystemPermissionMacConnector() throws {
    let kind = EventKitConnectorKind()
    #expect(kind.id == "eventkit")
    if case .system = kind.authorization {} else { Issue.record("expected .system authorization") }
    #expect(kind.supportedPlatforms.contains(.macOS))
    let s = try kind.makeSource(for: EventKitConnectorKind.connection, credentials: InMemoryCredentialStore(), syncState: InMemorySyncStateStore())
    #expect(s.id == "eventkit")
    #expect(EventKitConnectorKind.connection.sourceID == "eventkit-this-mac")
}
