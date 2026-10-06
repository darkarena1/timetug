import CalendarCore
import os
import XCTest
@testable import TimeTug

final class AppDiagnosticsTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    func testOSLogRenderingSplitsPublicAndPrivateFields() {
        let event = DiagnosticEvent(level: .info, category: "icalsub", name: "fetchCompleted",
                                    fields: [.int("status", 200), .bool("conditional", false), .string("uid", "abc"), .string("reason", "network", private: false)],
                                    date: date)
        let rendering = OSLogRendering(event: event)
        XCTAssertEqual(rendering.publicText, "fetchCompleted status=200 conditional=false reason=network")
        XCTAssertEqual(rendering.privateText, "uid=abc")
        XCTAssertFalse(rendering.publicText.contains("abc"))
    }

    func testStringFieldsArePrivateByDefaultInPieces() {
        let event = DiagnosticEvent(level: .info, category: "c", name: "n", fields: [.string("k", "v"), .int("n", 1)], date: date)
        XCTAssertEqual(OSLogRendering.pieces(for: event), [
            .init(text: "n", isPrivate: false), .init(text: "k=v", isPrivate: true), .init(text: "n=1", isPrivate: false),
        ])
    }

    func testEventWithoutPrivateFieldsHasEmptyPrivateText() {
        let rendering = OSLogRendering(event: DiagnosticEvent(level: .debug, category: "c", name: "n", date: date))
        XCTAssertEqual(rendering.publicText, "n")
        XCTAssertEqual(rendering.privateText, "")
    }

    func testLevelMapping() {
        XCTAssertEqual(OSLogDiagnosticLog.osLogType(for: .debug), .debug)
        XCTAssertEqual(OSLogDiagnosticLog.osLogType(for: .info), .info)
        XCTAssertEqual(OSLogDiagnosticLog.osLogType(for: .notice), .default)
        XCTAssertEqual(OSLogDiagnosticLog.osLogType(for: .warning), .error)
        XCTAssertEqual(OSLogDiagnosticLog.osLogType(for: .error), .fault)
    }

    func testReportHasHeaderAndRedactsPrivateFields() {
        let diagnostics = AppDiagnostics(capacity: 10, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        diagnostics.log.record(DiagnosticEvent(level: .notice, category: "icalsub", name: "rruleUnreadable",
                                               fields: [.string("uid", "secret-uid"), .int("count", 2)], date: date))
        let report = diagnostics.report()
        XCTAssertTrue(report.contains("App version:"))
        XCTAssertTrue(report.contains("macOS:"))
        XCTAssertTrue(report.contains("Generated: 2027-01-15T08:00:00Z"))
        XCTAssertTrue(report.contains("icalsub.rruleUnreadable uid=<private> count=2"))
        XCTAssertFalse(report.contains("secret-uid"))
    }

    func testClearEmptiesTheReportEvents() {
        let diagnostics = AppDiagnostics(capacity: 10)
        diagnostics.log.record(DiagnosticEvent(level: .info, category: "icalsub", name: "feedParsed", date: date))
        XCTAssertTrue(diagnostics.report().contains("feedParsed"))
        diagnostics.clear()
        XCTAssertFalse(diagnostics.report().contains("feedParsed"))
    }
}
