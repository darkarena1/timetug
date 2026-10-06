import CalendarCore
import XCTest
@testable import TimeTug

final class AccountNoticeTextTests: XCTestCase {
    func testNothingToWarnAbout() {
        XCTAssertNil(AccountNoticeText.make(nil))
        XCTAssertNil(AccountNoticeText.make([]))
        XCTAssertNil(AccountNoticeText.make([SourceNotice(kind: .unreadableRecurrence, count: 0)]))
    }

    func testOneUnreadableRecurrence() {
        XCTAssertEqual(AccountNoticeText.make([SourceNotice(kind: .unreadableRecurrence, count: 1)]),
                       "Some repeating events from this link use a rule TimeTug can't read, so they may not appear.")
    }

    func testSeveralMentionTheCount() {
        XCTAssertEqual(AccountNoticeText.make([SourceNotice(kind: .unreadableRecurrence, count: 3)]),
                       "3 repeating events from this link use a rule TimeTug can't read, so they may not appear.")
    }

    @MainActor func testModelStartsEmptyAndHoldsNotices() {
        let model = AppModel()
        XCTAssertTrue(model.notices.isEmpty)
        model.notices = ["s": [SourceNotice(kind: .unreadableRecurrence, count: 1)]]
        XCTAssertNotNil(AccountNoticeText.make(model.notices["s"]))
        model.notices = [:]
        XCTAssertNil(AccountNoticeText.make(model.notices["s"]))
    }
}
