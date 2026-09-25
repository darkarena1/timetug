import CalendarApple
import XCTest
@testable import TimeTug

final class BrowserPreferringPresenterTests: XCTestCase {
    private final class Recorder: AuthorizationPresenting, @unchecked Sendable {
        private(set) var presented = 0
        private(set) var dismissed = 0
        func present(_ url: URL, completionScheme: String, onEnded: @escaping @Sendable (Error?) -> Void) async -> Bool {
            presented += 1
            return true
        }
        func dismiss() async { dismissed += 1 }
    }

    private let url = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!

    func testSwitchOffUsesTheSheet() async {
        let sheet = Recorder()
        let presenter = BrowserPreferringPresenter(sheet: sheet, useBrowser: { false })
        let presented = await presenter.present(url, completionScheme: "timetug-oauth") { _ in }
        XCTAssertTrue(presented)
        XCTAssertEqual(sheet.presented, 1)
    }

    func testSwitchOnDeclinesSoTheCallerOpensTheBrowser() async {
        let sheet = Recorder()
        let presenter = BrowserPreferringPresenter(sheet: sheet, useBrowser: { true })
        let presented = await presenter.present(url, completionScheme: "timetug-oauth") { _ in }
        XCTAssertFalse(presented)
        XCTAssertEqual(sheet.presented, 0)
    }

    func testSwitchIsReadOnEveryPresentation() async {
        let sheet = Recorder()
        let flag = Flag()
        let presenter = BrowserPreferringPresenter(sheet: sheet, useBrowser: { flag.value })
        flag.value = true
        let first = await presenter.present(url, completionScheme: "timetug-oauth") { _ in }
        flag.value = false
        let second = await presenter.present(url, completionScheme: "timetug-oauth") { _ in }
        XCTAssertFalse(first)
        XCTAssertTrue(second)
    }

    func testDismissAlwaysReachesTheSheet() async {
        let sheet = Recorder()
        let presenter = BrowserPreferringPresenter(sheet: sheet, useBrowser: { true })
        await presenter.dismiss()
        XCTAssertEqual(sheet.dismissed, 1)
    }

    func testDefaultsKeyIsTheDocumentedOne() {
        XCTAssertEqual(BrowserPreferringPresenter.defaultsKey, "oauth.useBrowser.v1")
    }

    private final class Flag: @unchecked Sendable { var value = false }
}
