import CalendarCore
import EventKitSource
import GoogleCalendar
import XCTest
@testable import TimeTug

final class AppConnectorsTests: XCTestCase {
    func testGoogleIsRegisteredOnlyWhenConfigured() {
        let none = AppConnectors.makeRegistry(google: nil, eventKit: EventKitSource())
        XCTAssertNil(none.kind(id: "google"))
        XCTAssertNotNil(none.kind(id: "eventkit"))
        let some = AppConnectors.makeRegistry(google: GoogleOAuthConfig(clientID: "i", clientSecret: "s"), eventKit: EventKitSource())
        XCTAssertNotNil(some.kind(id: "google"))
    }
}
