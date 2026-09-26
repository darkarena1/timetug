import CalendarApple
import CalendarCore
import EventKitSource
import GoogleCalendar
import MicrosoftCalendar

enum AppConnectors {
    static func makeRegistry(google: GoogleOAuthConfig?, microsoft: MicrosoftOAuthConfig?, eventKit: EventKitSource) -> ConnectorRegistry {
        var registry = ConnectorRegistry()
        registry.register(EventKitConnectorKind(source: eventKit))
        if let google { registry.register(GoogleConnectorKind(config: google, hasher: CryptoKitSHA256())) }
        if let microsoft { registry.register(MicrosoftConnectorKind(config: microsoft, hasher: CryptoKitSHA256())) }
        return registry
    }
}
