import CalDAVCalendar
import CalendarApple
import CalendarCore
import EventKitSource
import GoogleCalendar
import ICalSubscription
import MicrosoftCalendar

enum AppConnectors {
    static func makeRegistry(google: GoogleOAuthConfig?, microsoft: MicrosoftOAuthConfig?, eventKit: EventKitSource) -> ConnectorRegistry {
        var registry = ConnectorRegistry()
        registry.register(EventKitConnectorKind(source: eventKit))
        registry.register(ICloudConnectorKind())
        registry.register(CalDAVConnectorKind())
        registry.register(ICalSubscriptionKind())
        if let google { registry.register(GoogleConnectorKind(config: google, hasher: CryptoKitSHA256())) }
        if let microsoft { registry.register(MicrosoftConnectorKind(config: microsoft, hasher: CryptoKitSHA256())) }
        return registry
    }
}
