import CalendarCore
import EventKitSource
import GoogleCalendar
import MicrosoftCalendar
import XCTest
@testable import TimeTug

final class AppConnectorsTests: XCTestCase {
    func testGoogleIsRegisteredOnlyWhenConfigured() {
        let none = AppConnectors.makeRegistry(google: nil, microsoft: nil, eventKit: EventKitSource())
        XCTAssertNil(none.kind(id: "google"))
        XCTAssertNotNil(none.kind(id: "eventkit"))
        let some = AppConnectors.makeRegistry(
            google: GoogleOAuthConfig(clientID: "i", clientSecret: "s"), microsoft: nil, eventKit: EventKitSource())
        XCTAssertNotNil(some.kind(id: "google"))
    }

    func testMicrosoftIsRegisteredOnlyWhenConfigured() {
        let none = AppConnectors.makeRegistry(google: nil, microsoft: nil, eventKit: EventKitSource())
        XCTAssertNil(none.kind(id: "microsoft"))
        let some = AppConnectors.makeRegistry(google: nil, microsoft: MicrosoftOAuthConfig(clientID: "i"), eventKit: EventKitSource())
        XCTAssertNotNil(some.kind(id: "microsoft"))
    }

    func testICloudAndOtherCalDAVAreAlwaysRegistered() {
        let registry = AppConnectors.makeRegistry(google: nil, microsoft: nil, eventKit: EventKitSource())
        XCTAssertEqual(registry.kind(id: "icloud")?.displayName, "iCloud")
        XCTAssertEqual(registry.kind(id: "caldav")?.displayName, "Other CalDAV")
        guard case .password? = registry.kind(id: "icloud")?.authorization else { return XCTFail("iCloud signs in with a password") }
        XCTAssertNotNil((registry.kind(id: "icloud") as? CredentialPromptHelp)?.credentialHelp?.url)
    }

    func testICalLinkIsAlwaysRegistered() {
        let registry = AppConnectors.makeRegistry(google: nil, microsoft: nil, eventKit: EventKitSource())
        XCTAssertEqual(registry.kind(id: "icalsub")?.displayName, "iCal link")
        guard case .password(let fields)? = registry.kind(id: "icalsub")?.authorization else { return XCTFail("the iCal link kind uses the credential sheet") }
        XCTAssertEqual(fields.map(\.key), ["link"])
        XCTAssertNotNil((registry.kind(id: "icalsub") as? CredentialPromptHelp)?.credentialHelp?.url)
    }

    func testICalLinkKindIsRegisteredWithADiagnosticsLog() {
        let diagnostics = AppDiagnostics(capacity: 5)
        let registry = AppConnectors.makeRegistry(google: nil, microsoft: nil, eventKit: EventKitSource(), diagnostics: diagnostics.log)
        XCTAssertNotNil(registry.kind(id: "icalsub"))
    }
}
