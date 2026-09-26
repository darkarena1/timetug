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
}
