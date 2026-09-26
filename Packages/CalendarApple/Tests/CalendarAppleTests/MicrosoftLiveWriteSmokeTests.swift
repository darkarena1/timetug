import CalendarApple
import CalendarCore
import CalendarOAuth
import Foundation
import MicrosoftCalendar
import Testing

private let liveMicrosoft = ProcessInfo.processInfo.environment["TIMETUG_LIVE_MICROSOFT"] == "1"

/// Every event this test creates starts with this prefix, and nothing without it is ever deleted.
private let smokePrefix = "TimeTug write smoke"

/// Deletes every smoke event in `window` (series once, by master). Failures are printed, not thrown.
private func cleanUp(_ source: any CalendarSource, _ writable: any WritableCalendarSource, calendarID: String, window: DateInterval) async {
    await Task.detached {   // detached so it still runs when the test task was cancelled
        do {
            let mine = try await source.events(in: window).filter { $0.title.hasPrefix(smokePrefix) && $0.calendarID == calendarID }
            var seen = Set<String>()
            for event in mine {
                let key = event.seriesID ?? event.eventID
                guard seen.insert(key).inserted else { continue }
                do { try await writable.delete(EventRef(event), scope: .allInSeries, notify: .none) }
                catch { print("LIVE cleanup could not delete \"\(event.title)\": \(error)") }
            }
        } catch { print("LIVE cleanup could not list events: \(error)") }
    }.value
}

/// Opt-in, interactive: `TIMETUG_LIVE_MICROSOFT=1 MICROSOFT_OAUTH_CLIENT_ID=<id> swift test
/// --package-path Packages/CalendarApple --filter microsoftWriteSmoke` (read the id from your xcconfig; do not paste
/// it into shared logs). Prints `LIVE ...` lines; record the answers in the Phase 4 spec:
/// - the sign-in with the `http://localhost` redirect and the account's identity;
/// - the calendars and their permissions, and the account's zone (`LIVE calendar ...`);
/// - a created single event's version, uid scope and stored zone, and whether an edit changes the version;
/// - a Teams meeting on `.generate` (a personal account may refuse it: `LIVE teams: ...`);
/// - a weekly numbered series: the occurrences read back, and `.thisAndFollowing` on the third occurrence, printed as
///   the instance count per series after the split (expected `[2, 2]`), including the numbered-count arithmetic;
/// - `originalStart` on each occurrence (`LIVE occurrence ...`), which the split depends on.
@Test(.enabled(if: liveMicrosoft), .timeLimit(.minutes(10))) func microsoftWriteSmoke() async throws {
    let clientID = try #require(ProcessInfo.processInfo.environment["MICROSOFT_OAUTH_CLIENT_ID"])
    let kind = MicrosoftConnectorKind(config: MicrosoftOAuthConfig(clientID: clientID), hasher: CryptoKitSHA256())
    let interaction = LoopbackAuthorizationInteraction(openURL: { url in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        do { try process.run(); return true } catch { return false }
    })
    let credentials = InMemoryCredentialStore()
    let connection = try await kind.authorize(using: interaction, credentials: credentials)
    print("LIVE signed in (\(connection.displayName.contains("@") ? "identity read" : "no identity"))")
    let source = try kind.makeSource(for: connection, credentials: credentials, syncState: InMemorySyncStateStore())
    let writable = try #require(source as? WritableCalendarSource)
    let calendars = try await source.calendars()
    for calendar in calendars {
        print("LIVE calendar default=\(calendar.isDefault == true) canEdit=\(calendar.permissions.canEdit) zone=\(calendar.timeZone?.identifier ?? "nil")")
    }
    let primary = try #require(calendars.first { $0.isDefault == true })

    let zone = try #require(primary.timeZone)   // a nil zone here means the connector did not read one
    var local = Calendar(identifier: .gregorian)
    local.timeZone = zone
    let tomorrow = try #require(local.date(byAdding: .day, value: 1, to: Date()))
    let start = try #require(local.date(bySettingHour: 3, minute: 0, second: 0, of: tomorrow))
    func timing(_ offsetDays: Int) -> EventTiming {
        let s = start.addingTimeInterval(Double(offsetDays) * 86_400)
        return EventTiming(start: s, end: s.addingTimeInterval(1800), timeZone: zone, isAllDay: false)
    }
    // The series below ends about day 23 (weekly, four occurrences from day 2).
    let window = DateInterval(start: start.addingTimeInterval(-3600), duration: 86_400 * 30)

    await cleanUp(source, writable, calendarID: primary.id, window: window)   // leftovers from an earlier run
    do {
        // 1. A single event: create, edit, and see whether the version changes.
        let single = try await writable.create(EventDraft(title: smokePrefix, timing: timing(0), location: "Room 1"), in: primary.id, notify: .none)
        print("LIVE single uidScope=\(String(describing: single.uidScope)) zone=\(single.timeZone.identifier) version=\(single.version != nil)")
        let renamed = try await writable.update(EventRef(single), EventPatch(title: "\(smokePrefix) renamed"), scope: .thisInstance, notify: .none)
        #expect(renamed.title == "\(smokePrefix) renamed" && renamed.location == "Room 1")
        print("LIVE edit changed the version: \(renamed.version != single.version)")
        try await writable.delete(EventRef(renamed), scope: .thisInstance, notify: .none)

        // 2. Teams on generate. A personal account may refuse it; either answer is recorded.
        do {
            let meeting = try await writable.create(
                EventDraft(title: "\(smokePrefix) teams", timing: timing(1), conference: .generate), in: primary.id, notify: .none)
            print("LIVE teams: created, conferences=\(meeting.conferences.map { "\($0.provider)" })")
            try await writable.delete(EventRef(meeting), scope: .thisInstance, notify: .none)
        } catch { print("LIVE teams: \(error)") }

        // 3. A weekly numbered series, read back, then split at the third occurrence.
        let rule = RecurrenceRule(frequency: .weekly, end: .count(4))
        let master = try await writable.create(
            EventDraft(title: "\(smokePrefix) series", timing: timing(2), recurrence: rule), in: primary.id, notify: .none)
        var occurrences: [CalendarEvent] = []
        for _ in 0..<15 {
            occurrences = try await source.events(in: window).filter { $0.title == "\(smokePrefix) series" }.sorted { $0.start < $1.start }
            if occurrences.count == 4 { break }
            try await Task.sleep(for: .seconds(1))
        }
        for occurrence in occurrences {
            print("LIVE occurrence start=\(occurrence.start) originalStart=\(String(describing: occurrence.originalStart)) seriesID=\(occurrence.seriesID != nil)")
        }
        let third = try #require(occurrences.count == 4 ? occurrences[2] : nil)
        _ = try await writable.update(EventRef(third), EventPatch(title: "\(smokePrefix) series 2"), scope: .thisAndFollowing, notify: .none)
        var counts: [Int] = []
        for _ in 0..<15 {
            let now = try await source.events(in: window)
            counts = [now.filter { $0.title == "\(smokePrefix) series" }.count, now.filter { $0.title == "\(smokePrefix) series 2" }.count]
            if counts == [2, 2] { break }
            try await Task.sleep(for: .seconds(1))
        }
        print("LIVE split instance counts [old, new] = \(counts)")
        #expect(counts == [2, 2])
        _ = master
    } catch {
        print("LIVE smoke failed: \(error)")
        await cleanUp(source, writable, calendarID: primary.id, window: window)
        throw error
    }
    await cleanUp(source, writable, calendarID: primary.id, window: window)
}
