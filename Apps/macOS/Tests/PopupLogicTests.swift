import AppKit
import Foundation
import SwiftUI
import TimeTugCore
import XCTest
@testable import TimeTug

final class PopupLogicTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let posix = Locale(identifier: "en_US_POSIX")
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = utc; return c }

    /// 2026-09-18 at the given UTC hour/minute.
    private func at(_ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: h, minute: m))!
    }

    private func event(_ id: String, _ title: String, _ start: Date, _ end: Date, allDay: Bool = false,
                       calendarID: String = "work", conference: String? = nil) -> CalendarEvent {
        CalendarEvent(sourceEventID: id, sourceID: "src", calendarID: calendarID, title: title,
                      start: start, end: end, isAllDay: allDay,
                      conferenceURL: conference.flatMap(URL.init(string:)))
    }

    private let calendars = [
        CalendarInfo(sourceID: "src", calendarID: "work", title: "Work", colorHex: "#FF0000"),
        CalendarInfo(sourceID: "src", calendarID: "home", title: "Personal", colorHex: "#00FF00"),
    ]

    private func agenda(_ events: [CalendarEvent], now: Date) -> DayAgenda {
        var s = TakeoverSettings()
        s.skipAllDayEvents = false
        return DayAgenda.make(events: events, settings: s, now: now, calendar: cal)
    }

    private func rows(_ events: [CalendarEvent], now: Date, calendars: [CalendarInfo]? = nil) -> [PopupRowModel] {
        PopupRowModel.rows(agenda: agenda(events, now: now), calendars: calendars ?? self.calendars,
                           now: now, locale: posix, timeZone: utc)
    }

    // MARK: rows

    func testMergedEventShowsTheLongerRangeButKeepsTheTugStart() {
        var merged = event("m", "Sync", at(13), at(13, 45), conference: "https://zoom.us/j/9")
        merged.displayStart = at(12, 30)
        let r = rows([merged], now: at(8))[0]
        XCTAssertEqual(r.timeText, "12:30 PM")
        XCTAssertEqual(r.metaText, "12:30 – 1:45 PM · Work")
        XCTAssertEqual(r.start, at(13))
        XCTAssertEqual(r.end, at(13, 45))
        XCTAssertEqual(r.shownStart, at(12, 30))
    }

    func testKindsAndMetaTexts() {
        let now = at(15, 20)
        let evs = [
            event("a", "Holiday", at(0), at(23, 59), allDay: true, calendarID: "home"),
            event("b", "Standup", at(9), at(9, 30)),
            event("c", "Design review", at(15), at(16), conference: "https://zoom.us/j/1"),
            event("d", "Dance Party", at(19, 15), at(20), calendarID: "home", conference: "https://zoom.us/j/2"),
            event("e", "Wind down", at(21), at(22, 30), calendarID: "home", conference: "https://zoom.us/j/3"),
        ]
        let r = rows(evs, now: now)
        XCTAssertEqual(r.map(\.kind), [.allDay, .past, .current, .next, .upcoming])
        XCTAssertEqual(r[0].timeText, "All day")
        XCTAssertEqual(r[0].metaText, "All day · Personal")
        XCTAssertEqual(r[1].timeText, "9:00 AM")
        XCTAssertEqual(r[1].metaText, "30 min · done")
        XCTAssertEqual(r[2].metaText, "Ends 4:00 PM")
        XCTAssertEqual(r[3].timeText, "7:15 PM")
        XCTAssertEqual(r[3].metaText, "7:15 – 8:00 PM · Personal")
        XCTAssertEqual(r[4].metaText, "9:00 – 10:30 PM · Personal")
        XCTAssertEqual(r[2].colorHex, "#FF0000")
        XCTAssertEqual(r[3].colorHex, "#00FF00")
        XCTAssertEqual(r[3].start, at(19, 15))
        XCTAssertEqual(r[3].end, at(20))
    }

    func testRangeAcrossNoon() {
        let r = rows([event("a", "Lunch", at(11, 30), at(12, 15))], now: at(8))
        XCTAssertEqual(r[0].metaText, "11:30 AM – 12:15 PM · Work")
    }

    func testJoinURLOnlyForCurrentAndNext() {
        let now = at(15, 20)
        let r = rows([
            event("b", "Past", at(9), at(10), conference: "https://zoom.us/j/0"),
            event("c", "Current", at(15), at(16), conference: "https://zoom.us/j/1"),
            event("d", "Next", at(19), at(20), conference: "https://zoom.us/j/2"),
            event("e", "Later", at(21), at(22), conference: "https://zoom.us/j/3"),
            event("f", "NoLink", at(15), at(16)),
        ], now: now)
        let byTitle = Dictionary(uniqueKeysWithValues: r.map { ($0.title, $0) })
        XCTAssertNil(byTitle["Past"]!.joinURL)
        XCTAssertEqual(byTitle["Current"]!.joinURL, URL(string: "https://zoom.us/j/1"))
        XCTAssertEqual(byTitle["Next"]!.joinURL, URL(string: "https://zoom.us/j/2"))
        XCTAssertNil(byTitle["Later"]!.joinURL)
        XCTAssertNil(byTitle["NoLink"]!.joinURL)
    }

    func testMissingCalendarHasNilColorAndBareMeta() {
        let r = rows([event("a", "X", at(19), at(20), calendarID: "gone")], now: at(8))
        XCTAssertNil(r[0].colorHex)
        XCTAssertEqual(r[0].kind, .next)
        XCTAssertEqual(r[0].metaText, "7:00 – 8:00 PM")
    }

    func testDurationFormatting() {
        let now = at(23, 0)
        let r = rows([
            event("a", "A", at(1), at(2)),
            event("b", "B", at(3), at(4, 30)),
            event("c", "C", at(5), at(5, 45)),
        ], now: now)
        XCTAssertEqual(r.map(\.metaText), ["1 h · done", "1 h 30 min · done", "45 min · done"])
    }

    func testEmptyAgenda() {
        XCTAssertEqual(rows([], now: at(8)), [])
        XCTAssertEqual(PopupRowModel.meetingsLeft(agenda: .empty), 0)
    }

    func testMeetingsLeftCountsCurrentAndUpcomingTimedOnly() {
        let now = at(15, 20)
        let a = agenda([
            event("a", "Holiday", at(0), at(23, 59), allDay: true),
            event("b", "Past", at(9), at(10)),
            event("c", "Current", at(15), at(16)),
            event("d", "Next", at(19), at(20)),
            event("e", "Later", at(21), at(22)),
        ], now: now)
        XCTAssertEqual(PopupRowModel.meetingsLeft(agenda: a), 3)
    }

    // MARK: text

    func testSummaryVariants() {
        let now = at(10)
        func s(_ left: Int, _ total: Int) -> String {
            PopupText.summary(now: now, meetingsLeft: left, totalTimed: total, locale: posix, timeZone: utc)
        }
        XCTAssertEqual(s(3, 4), "Sep 18 · 3 meetings left")
        XCTAssertEqual(s(1, 4), "Sep 18 · 1 meeting left")
        XCTAssertEqual(s(0, 4), "Sep 18 · No meetings left")
        XCTAssertEqual(s(0, 0), "Sep 18 · No meetings today")
    }

    func testWeekday() {
        XCTAssertEqual(PopupText.weekday(now: at(10), locale: posix, timeZone: utc), "Friday")
    }

    func testCountdown() {
        XCTAssertEqual(PopupText.countdown(until: at(19, 15), now: at(15, 35)), "in 3h 40m")
        XCTAssertEqual(PopupText.countdown(until: at(15, 40), now: at(15, 35)), "in 5m")
    }

    func testTugFooter() {
        XCTAssertEqual(PopupText.tugFooter(leadTime: 0), "Tugs you at start")
        XCTAssertEqual(PopupText.tugFooter(leadTime: 60), "Tugs you 1 min before")
        XCTAssertEqual(PopupText.tugFooter(leadTime: 300), "Tugs you 5 min before")
    }

    func testProgress() {
        XCTAssertEqual(PopupText.progress(start: at(10), end: at(11), now: at(9)), 0)
        XCTAssertEqual(PopupText.progress(start: at(10), end: at(11), now: at(10, 30)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(PopupText.progress(start: at(10), end: at(11), now: at(12)), 1)
        XCTAssertEqual(PopupText.progress(start: at(11), end: at(11), now: at(11)), 0)
        XCTAssertEqual(PopupText.progress(start: at(11), end: at(10), now: at(12)), 0)
    }

    func testSpokenDuration() {
        XCTAssertEqual(PopupText.spokenDuration(13200), "3 hours 40 minutes")
        XCTAssertEqual(PopupText.spokenDuration(3600), "1 hour")
        XCTAssertEqual(PopupText.spokenDuration(60), "1 minute")
        XCTAssertEqual(PopupText.spokenDuration(30), "less than a minute")
    }

    // MARK: JoinLabel and Color(hex:)

    func testJoinLabel() {
        func t(_ s: String) -> String { JoinLabel.text(for: URL(string: s)!) }
        XCTAssertEqual(t("https://us02web.zoom.us/j/1"), "Join Zoom")
        XCTAssertEqual(t("https://zoom.com/j/1"), "Join Zoom")
        XCTAssertEqual(t("zoommtg://zoom.us/join?confno=1"), "Join Zoom")
        XCTAssertEqual(t("https://meet.google.com/aaa-bbbb-ccc"), "Join Google Meet")
        XCTAssertEqual(t("https://teams.microsoft.com/l/meetup-join/1"), "Join Teams")
        XCTAssertEqual(t("https://teams.live.com/meet/1"), "Join Teams")
        XCTAssertEqual(t("https://acme.webex.com/meet/x"), "Join Webex")
        XCTAssertEqual(t("https://app.slack.com/huddle/T1/C1"), "Join Slack huddle")
        XCTAssertEqual(t("https://example.com/room"), "Join meeting")
        XCTAssertEqual(t("https://notzoom.us.evil.example/x"), "Join meeting")
    }

    func testColorHex() throws {
        let c = try XCTUnwrap(Color(hex: "#FF8000"))
        let ns = try XCTUnwrap(NSColor(c).usingColorSpace(.sRGB))
        XCTAssertEqual(ns.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(ns.greenComponent, 128.0 / 255, accuracy: 0.01)
        XCTAssertEqual(ns.blueComponent, 0, accuracy: 0.01)
        XCTAssertNotNil(Color(hex: "#00ff00"))
        XCTAssertNil(Color(hex: nil))
        XCTAssertNil(Color(hex: "#FFF"))
        XCTAssertNil(Color(hex: "GGGGGG"))
        XCTAssertNil(Color(hex: ""))
        XCTAssertNil(Color(hex: "#FF80001"))
    }

    func testMergedRowsCarryBadgeAndFlag() {
        var merged = event("1", "Intermountain Health", at(10), at(11))
        merged.mergedMembers = [
            MergedMember(title: "Intermountain Health", calendarKey: "src/work", contentKey: "k1", details: "location", start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3600)),
            MergedMember(title: "Scott: Doctor", calendarKey: "src/home", contentKey: "k2", details: "bare", start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3600)),
        ]
        merged.mergeProvenance = .inference(engineID: "apple-intelligence", engineName: "Apple Intelligence")
        let row = rows([merged], now: at(9)).first!
        XCTAssertEqual(row.mergeBadge, "Merged with Apple Intelligence")
        XCTAssertTrue(row.isMerged)

        merged.mergeProvenance = .rule
        let ruleRow = rows([merged], now: at(9)).first!
        XCTAssertNil(ruleRow.mergeBadge)
        XCTAssertTrue(ruleRow.isMerged)                       // still offers "Unmerge all"

        let plain = rows([event("2", "Standup", at(11), at(12))], now: at(9)).first!
        XCTAssertNil(plain.mergeBadge)
        XCTAssertFalse(plain.isMerged)
    }

    // MARK: merged members

    private func mergedEvent(provenance: MergeProvenance?, count: Int = 2) -> CalendarEvent {
        var merged = event("1", "Intermountain Health", at(13), at(13, 30))
        var members = [
            MergedMember(title: "Scott: Doctor", calendarKey: "src/home", contentKey: "k2", details: "bare",
                         start: at(12, 45), end: at(13, 45)),
            MergedMember(title: "Intermountain Health", calendarKey: "src/work", contentKey: "k1", details: "location",
                         start: at(13), end: at(13, 30)),
        ]
        if count > 2 {
            members += (2..<count).map {
                MergedMember(title: "Copy \($0)", calendarKey: "src/other\($0)", contentKey: "c\($0)", details: "bare",
                             start: at(13), end: at(13, 30))
            }
        }
        merged.mergedMembers = members
        merged.mergeProvenance = provenance
        return merged
    }

    func testMergeSummaryTextCountsEventsPerProvenance() {
        let ai = rows([mergedEvent(provenance: .inference(engineID: "a", engineName: "Apple Intelligence"), count: 4)], now: at(9))[0]
        XCTAssertEqual(ai.mergeSummaryText, "Merged with Apple Intelligence \u{00B7} 4 events")
        let manual = rows([mergedEvent(provenance: .userConfirmed)], now: at(9))[0]
        XCTAssertEqual(manual.mergeSummaryText, "Merged manually \u{00B7} 2 events")
        let rule = rows([mergedEvent(provenance: .rule, count: 3)], now: at(9))[0]
        XCTAssertEqual(rule.mergeSummaryText, "3 events merged")
        let plain = rows([event("2", "Standup", at(11), at(12))], now: at(9))[0]
        XCTAssertNil(plain.mergeSummaryText)
        XCTAssertNil(plain.mergeTooltip)
        XCTAssertTrue(plain.memberRows.isEmpty)
    }

    func testMergeTooltipJoinsTitlesAndTruncates() {
        let row = rows([mergedEvent(provenance: .rule)], now: at(9))[0]
        XCTAssertEqual(row.mergeTooltip, "Scott: Doctor + Intermountain Health")
        var long = mergedEvent(provenance: .rule)
        long.mergedMembers = (0..<6).map {
            MergedMember(title: String(repeating: "x", count: 30) + "\($0)", calendarKey: "src/work", contentKey: "k\($0)",
                         details: "bare", start: at(13), end: at(14))
        }
        let tip = rows([long], now: at(9))[0].mergeTooltip!
        XCTAssertLessThanOrEqual(tip.count, 120)
        XCTAssertTrue(tip.hasSuffix("\u{2026}"))
    }

    func testMemberRowsCarryTitleCalendarTimeAndShownFlag() {
        let infos = [
            CalendarInfo(sourceID: "src", calendarID: "work", title: "Work", accountName: "Acme"),
            CalendarInfo(sourceID: "src", calendarID: "home", title: "Personal"),
        ]
        let rows = MergedMemberRow.rows(for: mergedEvent(provenance: .rule, count: 3), calendars: infos,
                                        locale: posix, timeZone: utc)
        XCTAssertEqual(rows.map(\.id), ["k2", "k1", "c2"])
        XCTAssertEqual(rows[0].title, "Scott: Doctor")
        XCTAssertEqual(rows[0].calendarLabel, "Personal")
        XCTAssertEqual(rows[0].copyCount, 1)
        XCTAssertEqual(rows[0].timeText, "12:45 \u{2013} 1:45 PM")
        XCTAssertFalse(rows[0].isShown)
        XCTAssertEqual(rows[1].calendarLabel, "Work \u{00B7} Acme")
        XCTAssertEqual(rows[1].timeText, "1:00 \u{2013} 1:30 PM")
        XCTAssertTrue(rows[1].isShown)
        XCTAssertEqual(rows.filter(\.isShown).count, 1)
        XCTAssertEqual(rows[2].calendarLabel, "other2")          // unknown calendar: the raw calendar id
    }

    func testPopupRowsExposeMemberRowsOnlyForMergedEvents() {
        let r = rows([mergedEvent(provenance: .rule)], now: at(9))[0]
        XCTAssertEqual(r.memberRows.count, 2)
        XCTAssertEqual(r.memberRows.first { $0.isShown }?.title, "Intermountain Health")
    }

    // MARK: identical copies collapse

    private func identicalCopies(provenance: MergeProvenance?, extra: Bool = false) -> CalendarEvent {
        var merged = event("1", "Mando (X1102)'s Upcoming Appointment", at(13), at(13, 30), calendarID: "a")
        var members = ["a", "b", "c"].map {
            MergedMember(title: "Mando (X1102)'s Upcoming Appointment", calendarKey: "src/\($0)", contentKey: "same",
                         details: "bare", start: at(13), end: at(13, 30))
        }
        if extra {
            members.append(MergedMember(title: "Mando Spem Collection", calendarKey: "src/s", contentKey: "other",
                                        details: "bare", start: at(12, 45), end: at(13, 45)))
        }
        merged.mergedMembers = members
        merged.mergeProvenance = provenance
        return merged
    }

    func testIdenticalCopiesCollapseIntoOneRowWithJoinedLabel() {
        let infos = [
            CalendarInfo(sourceID: "src", calendarID: "a", title: "Shared", accountName: "Exchange"),
            CalendarInfo(sourceID: "src", calendarID: "b", title: "Shared", accountName: "Gmail"),
            CalendarInfo(sourceID: "src", calendarID: "c", title: "Shared", accountName: "Cloud"),
            CalendarInfo(sourceID: "src", calendarID: "s", title: "Work", accountName: "Acme"),
        ]
        let rows = MergedMemberRow.rows(for: identicalCopies(provenance: .rule, extra: true), calendars: infos,
                                        locale: posix, timeZone: utc)
        XCTAssertEqual(rows.map(\.id), ["same", "other"])
        XCTAssertEqual(rows[0].copyCount, 3)
        XCTAssertEqual(rows[0].members.count, 3)
        XCTAssertEqual(rows[0].calendarLabel, "Shared \u{00B7} Exchange, Gmail, Cloud")
        XCTAssertTrue(rows[0].isShown)
        XCTAssertEqual(rows[1].copyCount, 1)
        XCTAssertEqual(rows[1].calendarLabel, "Work \u{00B7} Acme")
        XCTAssertFalse(rows[1].isShown)
    }

    func testDifferentlyNamedCalendarsAreListedSeparately() {
        let infos = [
            CalendarInfo(sourceID: "src", calendarID: "a", title: "Work", accountName: "Exchange"),
            CalendarInfo(sourceID: "src", calendarID: "b", title: "Personal", accountName: "Gmail"),
        ]
        let rows = MergedMemberRow.rows(for: identicalCopies(provenance: .rule), calendars: infos,
                                        locale: posix, timeZone: utc)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].calendarLabel, "Work \u{00B7} Exchange, Personal \u{00B7} Gmail, c")
    }

    func testSummaryCountsDistinctEventsAndCopies() {
        let ai = MergeProvenance.inference(engineID: "a", engineName: "Apple Intelligence")
        XCTAssertEqual(rows([identicalCopies(provenance: ai, extra: true)], now: at(9))[0].mergeSummaryText,
                       "Merged with Apple Intelligence \u{00B7} 2 events")
        XCTAssertEqual(rows([identicalCopies(provenance: .userConfirmed, extra: true)], now: at(9))[0].mergeSummaryText,
                       "Merged manually \u{00B7} 2 events")
        XCTAssertEqual(rows([identicalCopies(provenance: .rule, extra: true)], now: at(9))[0].mergeSummaryText,
                       "2 events merged")
        XCTAssertEqual(rows([identicalCopies(provenance: .rule)], now: at(9))[0].mergeSummaryText, "3 copies merged")
        XCTAssertEqual(rows([identicalCopies(provenance: ai)], now: at(9))[0].mergeSummaryText,
                       "Merged with Apple Intelligence \u{00B7} 3 copies")
        XCTAssertEqual(rows([identicalCopies(provenance: .rule, extra: true)], now: at(9))[0].mergeTooltip,
                       "Mando (X1102)'s Upcoming Appointment + Mando Spem Collection")
    }
}
