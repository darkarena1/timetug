import CalendarCore
import Foundation

/// Apple Calendar as a connector kind. Access is a system permission, so `authorize` neither uses the
/// interaction nor the credential store, and the returned `Connection` is synthesized (hosts do not persist it).
public struct EventKitConnectorKind: ConnectorKind {
    public static let kindID = "eventkit"
    /// `sourceID` here would be "eventkit-this-mac"; hosts key EventKit by `EventKitSource.sourceID` ("eventkit").
    public static let connection = Connection(kindID: kindID, connectionID: "this-mac", displayName: "Apple Calendar")

    public var id: String { Self.kindID }
    public var displayName: String { "Apple Calendar" }
    public var supportedPlatforms: Platform { .macOS }
    public var authorization: AuthorizationMethod { .system }
    private let source: EventKitSource

    public init(source: EventKitSource = EventKitSource()) { self.source = source }

    public func authorize(using interaction: any AuthorizationInteraction, credentials: any CredentialStore) async throws -> Connection {
        guard await source.requestAccess() else { throw SourceError.needsPermission }
        return Self.connection
    }

    public func reauthorize(
        _ connection: Connection, using interaction: any AuthorizationInteraction, credentials: any CredentialStore
    ) async throws -> Connection {
        try await authorize(using: interaction, credentials: credentials)
    }

    public func makeSource(for connection: Connection, credentials: any CredentialStore, syncState: any SyncStateStore) throws -> any CalendarSource {
        source
    }
}
