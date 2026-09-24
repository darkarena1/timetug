import CalendarCore
import CalendarOAuth
import Foundation
import GoogleCalendar
import Testing
@testable import CalendarApple

private let liveGoogle = ProcessInfo.processInfo.environment["TIMETUG_LIVE_GOOGLE"] == "1"

/// Every event this test creates starts with this prefix, and nothing without it is ever deleted.
private let smokePrefix = "TimeTug write smoke"

/// Opt-in, interactive: `TIMETUG_LIVE_GOOGLE=1 GOOGLE_OAUTH_CLIENT_ID=... GOOGLE_OAUTH_CLIENT_SECRET=... swift test
/// --package-path Packages/CalendarApple --filter googleWriteSmoke`. Signs in through the browser, creates events named
/// "TimeTug write smoke" in the primary calendar (no attendees, nothing is emailed), and deletes them at the end,
/// including when it fails half way.
///
/// What it settles (the unit tests only use a fake transport for these), printed as `LIVE ...` lines to record in the spec:
/// - `If-Match` etag behaviour on PATCH: the stale-edit merge and conflict below.
/// - The recurring insert's zone: the series uses an IANA zone (`Europe/London`), not UTC. Darwin's `TimeZone(identifier:
///   "UTC").identifier` is "GMT", which Google may reject or mishandle, so this test does not depend on it; a request
///   error is printed as `LIVE failure: ...`.
/// - The `.thisAndFollowing` split and its `COUNT` arithmetic (old series keeps the earlier occurrences, the new series
///   gets `total - prior`): printed as the instance count per series after the split (expected `[2, 2]`).
/// - The Meet re-request on the new series: printed as each instance's conference provider before and after the split.
/// - `supportsAttachments`: NOT exercised. The series has no attachments, so the split never sends that parameter;
///   confirming it needs an event with a Drive attachment, added by hand.
@Test(.enabled(if: liveGoogle), .timeLimit(.minutes(10))) func googleWriteSmoke() async throws {
    let env = ProcessInfo.processInfo.environment
    let clientID = try #require(env["GOOGLE_OAUTH_CLIENT_ID"])
    let clientSecret = try #require(env["GOOGLE_OAUTH_CLIENT_SECRET"])
    let kind = GoogleConnectorKind(config: GoogleOAuthConfig(clientID: clientID, clientSecret: clientSecret), hasher: CryptoKitSHA256())
    let interaction = LoopbackAuthorizationInteraction(openURL: { url in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        do { try process.run(); return true } catch { return false }
    })
    let credentials = InMemoryCredentialStore()
    let connection = try await kind.authorize(using: interaction, credentials: credentials)
    let source = try kind.makeSource(for: connection, credentials: credentials, syncState: InMemorySyncStateStore())
    let writable = try #require(source as? WritableCalendarSource)
    let calendars = try await source.calendars()
    let primaryCalendar = calendars.first { $0.isPrimary }
    let primary = try #require(primaryCalendar)
    print("LIVE signed in as \(connection.displayName); writing to the primary calendar")

    // An IANA zone, not "UTC" (see the doc comment).
    let zone = try #require(TimeZone(identifier: "Europe/London"))
    var london = Calendar(identifier: .gregorian)
    london.timeZone = zone
    let tomorrow = try #require(london.date(byAdding: .day, value: 1, to: Date()))
    let start = try #require(london.date(bySettingHour: 3, minute: 0, second: 0, of: tomorrow))
    func timing(_ offsetDays: Int) -> EventTiming {
        let s = start.addingTimeInterval(Double(offsetDays) * 86_400)
        return EventTiming(start: s, end: s.addingTimeInterval(1800), timeZone: zone, isAllDay: false)
    }
    // The series (weekly, four occurrences, from day 2) ends about day 23; the window covers all of it.
    let window = DateInterval(start: start.addingTimeInterval(-3600), duration: 86_400 * 40)

    /// Our events in the primary calendar, oldest first. The prefix and calendar filter is what keeps every delete below
    /// away from the user's own events.
    func mine() async throws -> [CalendarEvent] {
        try await source.events(in: window).filter { $0.title.hasPrefix(smokePrefix) && $0.calendarID == primary.id }.sorted { $0.start < $1.start }
    }

    // Each series (or single event) is deleted at most once, whichever path reaches it first. Only events with the smoke
    // prefix are accepted, and a series is keyed by its master id (`seriesID`, or `eventID` for the master itself).
    var deletedKeys = Set<String>()
    func remove(_ event: CalendarEvent, scope: RecurrenceScope = .allInSeries) async throws {
        guard event.title.hasPrefix(smokePrefix) else { return }
        let key = event.seriesID ?? event.eventID
        guard !deletedKeys.contains(key) else { return }
        try await writable.delete(EventRef(event), scope: scope, notify: .none)
        deletedKeys.insert(key)
    }
    /// Deletes every smoke event still in the window, one delete per series. Failures are printed, not thrown.
    func sweep() async {
        do {
            for event in try await mine() {
                do { try await remove(event) } catch { print("LIVE cleanup could not delete \"\(event.title)\": \(error)") }
            }
        } catch { print("LIVE cleanup could not list events: \(error)") }
    }

    // Leftovers from an earlier run that died before it could clean up.
    let earlier = try await mine()
    if !earlier.isEmpty {
        print("LIVE removing \(earlier.count) smoke events left by an earlier run")
        await sweep()
    }

    // Events this run has created (masters), so a failure can delete them even if listing them fails.
    var created: [CalendarEvent] = []
    do {
        // 1. A single event: create, edit through EventEdit, then a stale edit merges and a conflicting one fails.
        let single = try await writable.create(EventDraft(title: smokePrefix, timing: timing(0), location: "Room 1"), in: primary.id, notify: .none)
        created.append(single)
        #expect(single.title == smokePrefix && single.sourceID == source.id)
        var edit = EventEdit(single)
        edit.event.title = "\(smokePrefix) renamed"
        let renamed = try await writable.update(EventRef(single), edit.patch, scope: .thisInstance, notify: .none)
        #expect(renamed.title == "\(smokePrefix) renamed" && renamed.location == "Room 1" && renamed.version != single.version)
        // `single` is now stale. A patch to notes only merges; a patch to the title conflicts.
        var notesEdit = EventEdit(single)
        notesEdit.event.notes = "merged"
        let merged = try await writable.update(EventRef(single), notesEdit.patch, scope: .thisInstance, notify: .none)
        #expect(merged.notes == "merged" && merged.title == "\(smokePrefix) renamed")
        var titleEdit = EventEdit(single)
        titleEdit.event.title = "\(smokePrefix) mine"
        do {
            _ = try await writable.update(EventRef(single), titleEdit.patch, scope: .thisInstance, notify: .none)
            Issue.record("expected a conflict")
        } catch let error as WriteError { #expect(error == .conflict(fields: [.title])) }
        try await remove(merged, scope: .thisInstance)

        // 2. A weekly series of four: instance, this-and-following and whole-series edits, then delete.
        let recurrence = RecurrenceRule(frequency: .weekly, end: .count(4))
        let seriesTitle = "\(smokePrefix) series"
        let master: CalendarEvent
        do {
            master = try await writable.create(
                EventDraft(title: seriesTitle, timing: timing(2), conference: .generate, recurrence: recurrence), in: primary.id, notify: .none)
        } catch {
            // The Meet request is the part most likely to differ by account type; keep going without it.
            print("LIVE creating the series with a Meet link failed, retrying without: \(error)")
            master = try await writable.create(EventDraft(title: seriesTitle, timing: timing(2), recurrence: recurrence), in: primary.id, notify: .none)
        }
        created.append(master)
        try await Task.sleep(for: .seconds(2))
        var list = try await mine()
        print("LIVE conference before the split: \(list.map { $0.conference.map { "\($0.provider)" } ?? "-" })")
        #expect(list.count == 4 && list.allSatisfy { $0.seriesID != nil && $0.originalStart != nil })
        _ = try await writable.update(EventRef(list[1]), EventPatch(title: "\(seriesTitle) (second)"), scope: .thisInstance, notify: .none)
        _ = try await writable.update(EventRef(list[2]), EventPatch(location: .set("Lab")), scope: .thisAndFollowing, notify: .none)
        try await Task.sleep(for: .seconds(2))
        list = try await mine()
        print("LIVE after split: \(list.map { ($0.title, $0.location ?? "-") })")
        // COUNT arithmetic: the old series keeps the two earlier occurrences and the new series gets the other two.
        let perSeries = Dictionary(grouping: list, by: { $0.seriesID ?? $0.eventID }).values.map(\.count).sorted()
        print("LIVE instances per series after split (expected [2, 2]): \(perSeries)")
        print("LIVE conference after the split: \(list.map { $0.conference.map { "\($0.provider)" } ?? "-" })")
        #expect(list.count == 4 && list[0].location == nil && list[1].title.hasSuffix("(second)") && list[2].location == "Lab" && list[3].location == "Lab")
        _ = try await writable.update(EventRef(list[3]), EventPatch(notes: .set("whole series")), scope: .allInSeries, notify: .none)
        try await Task.sleep(for: .seconds(2))
        list = try await mine()
        // Instances after the split belong to the new series, so only the series the ref points at is guaranteed to change.
        print("LIVE notes after allInSeries: \(list.map { $0.notes ?? "-" })")
        // The split left the old and the new series both present; `remove` deletes each once.
        for event in list { try await remove(event) }
    } catch {
        print("LIVE failure: \(error)")
        // The masters we created (a no-op for anything already deleted), then anything else carrying the prefix, such
        // as the new series a split created.
        for event in created {
            do { try await remove(event) } catch { print("LIVE cleanup could not delete \"\(event.title)\": \(error)") }
        }
        await sweep()
        throw error
    }
    try await Task.sleep(for: .seconds(2))
    let leftovers = try await mine()
    #expect(leftovers.isEmpty, "smoke events were left behind: \(leftovers.map(\.title))")
    if !leftovers.isEmpty { await sweep() }
}
