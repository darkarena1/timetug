import CalendarApple
import CalendarCore
import EventKitSource
import GoogleCalendar

enum AppConnectors {
    static func makeRegistry(google: GoogleOAuthConfig?, eventKit: EventKitSource) -> ConnectorRegistry {
        var registry = ConnectorRegistry()
        registry.register(EventKitConnectorKind(source: eventKit))
        if let google { registry.register(GoogleConnectorKind(config: google, hasher: CryptoKitSHA256())) }
        return registry
    }
}
