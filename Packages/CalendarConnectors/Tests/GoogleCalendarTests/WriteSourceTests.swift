import CalendarCore
import CalendarTestSupport
import Foundation
import Testing
@testable import GoogleCalendar

private let utc = TimeZone(identifier: "UTC")!
private func instant(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
private let cal = "me@x.com"
private let calPath = "calendars/me%40x.com/events"

private func timing() -> EventTiming {
    EventTiming(start: instant("2026-09-21T10:00:00Z"), end: instant("2026-09-21T10:30:00Z"), timeZone: utc, isAllDay: false)
}
private func base(title: String = "Standup", version: String = "e1", attendees: [Attendee] = []) -> CalendarEvent {
    CalendarEvent(eventID: "ev1", calendarID: cal, title: title, start: instant("2026-09-21T10:00:00Z"), end: instant("2026-09-21T10:30:00Z"),
                  timeZone: utc, attendees: attendees, version: version)
}

@Test func googleDeclaresItsWriteCapabilities() async throws {
    let h = try await Harness()
    let c = h.source.capabilities
    #expect(c.canWrite && c.canEditAttendees && c.canRespondToInvite && c.controlsNotifications)
    #expect(c.writableFields == Set(EventField.allCases) && c.recurrenceScopes == [.thisInstance, .allInSeries])
}

@Test func createPostsToTheCalendarAndMapsTheResult() async throws {
    let h = try await Harness()
    await h.transport.route(calPath, [.json(googleEvent(id: "new1", etag: "e9", summary: "Sync"))])
    let draft = EventDraft(title: "Sync", timing: timing(), attendees: [AttendeeDraft(email: "bob@x.com")], conference: .generate)
    let created = try await h.source.create(draft, in: cal, notify: .all)
    let post = try #require(await h.transport.requests(matching: calPath).last)
    #expect(post.method == "POST" && post.url.absoluteString.contains("sendUpdates=all") && post.url.absoluteString.contains("conferenceDataVersion=1"))
    #expect(bodyJSON(post)["summary"] as? String == "Sync")
    #expect(created.eventID == "new1" && created.version == "e9" && created.sourceID == "google-c1" && created.calendarID == cal)
}

@Test func writesToAReadOnlyCalendarAreForbiddenBeforeAnyEventRequest() async throws {
    let h = try await Harness()
    await expectWriteError(.forbidden("read-only calendar")) {
        _ = try await h.source.create(EventDraft(title: "T", timing: timing()), in: "team@group.calendar.google.com", notify: .none)
    }
    await expectWriteError(.notFound) { _ = try await h.source.create(EventDraft(title: "T", timing: timing()), in: "nope", notify: .none) }
    #expect(await h.transport.requests(matching: "/events").isEmpty)
}

@Test func createRefusesAnInvalidDraftBeforeAnyRequest() async throws {
    let h = try await Harness()
    var draft = EventDraft(title: "T", timing: timing())
    draft.reminders = [Reminder(minutesBefore: -1)]
    await expectWriteError(.invalid("reminder minutes must not be negative")) { _ = try await h.source.create(draft, in: cal, notify: .none) }
    #expect(await h.transport.requests.isEmpty)
    // A rule only Google's mapper enforces is also caught before the calendar lookup.
    draft.reminders = [Reminder(minutesBefore: 40321)]
    await expectWriteError(.invalid("reminder minutes must be between 0 and 40320")) { _ = try await h.source.create(draft, in: cal, notify: .none) }
    #expect(await h.transport.requests.isEmpty)
}

@Test func updateSendsOnlyTheChangedFieldsWithIfMatch() async throws {
    let h = try await Harness()
    await h.transport.route("\(calPath)/ev1", [.json(googleEvent(id: "ev1", etag: "e2", summary: "New"))])
    let updated = try await h.source.update(EventRef(calendarID: cal, eventID: "ev1", version: "e1"), EventPatch(title: "New"),
                                            scope: .thisInstance, notify: .none)
    let patch = try #require(await h.transport.requests(matching: "\(calPath)/ev1").last)
    #expect(patch.method == "PATCH" && patch.headers["If-Match"] == "e1" && patch.url.absoluteString.contains("sendUpdates=none"))
    #expect((bodyJSON(patch) as NSDictionary).isEqual(["summary": "New"] as NSDictionary))
    #expect(updated.title == "New" && updated.version == "e2")
}

@Test func aStaleVersionWithNoOverlapIsRetriedOnTheFreshEtag() async throws {
    let h = try await Harness()
    var edit = EventEdit(base())
    edit.event.title = "New"
    await h.transport.route("\(calPath)/ev1", [
        googleError("conditionNotMet", status: 412),
        .json(googleEvent(id: "ev1", etag: "e2", summary: "Standup", extra: ["location": "Elsewhere"])),   // someone else set the location
        .json(googleEvent(id: "ev1", etag: "e3", summary: "New", extra: ["location": "Elsewhere"])),
    ])
    let updated = try await h.source.update(EventRef(base()), edit.patch, scope: .thisInstance, notify: .none)
    let sent = await h.transport.requests(matching: "\(calPath)/ev1")
    #expect(sent.map(\.method) == ["PATCH", "GET", "PATCH"] && sent[0].headers["If-Match"] == "e1" && sent[2].headers["If-Match"] == "e2")
    #expect(updated.title == "New" && updated.location == "Elsewhere")
}

@Test func aStaleVersionWithAnOverlapIsAConflict() async throws {
    let h = try await Harness()
    var edit = EventEdit(base())
    edit.event.title = "Mine"
    await h.transport.route("\(calPath)/ev1", [googleError("conditionNotMet", status: 412), .json(googleEvent(id: "ev1", etag: "e2", summary: "Theirs"))])
    await expectWriteError(.conflict(fields: [.title])) { _ = try await h.source.update(EventRef(base()), edit.patch, scope: .thisInstance, notify: .none) }
}

@Test func attendeeChangesFetchThenPatchTheFullArrayWithTheFetchedEtag() async throws {
    let h = try await Harness()
    let attendees: [[String: Any]] = [["email": "me@x.com", "self": true, "responseStatus": "accepted"], ["email": "bob@x.com", "responseStatus": "accepted"]]
    await h.transport.route("\(calPath)/ev1", [
        .json(googleEvent(id: "ev1", etag: "e1", extra: ["attendees": attendees])),
        .json(googleEvent(id: "ev1", etag: "e2")),
    ])
    let patch = EventPatch(attendees: AttendeeChanges(add: [AttendeeDraft(email: "dee@x.com")], remove: ["bob@x.com"]))
    _ = try await h.source.update(EventRef(calendarID: cal, eventID: "ev1", version: "e1"), patch, scope: .thisInstance, notify: .externalOnly)
    let sent = await h.transport.requests(matching: "\(calPath)/ev1")
    #expect(sent.map(\.method) == ["GET", "PATCH"] && sent[1].headers["If-Match"] == "e1" && sent[1].url.absoluteString.contains("sendUpdates=externalOnly"))
    let merged = try #require(bodyJSON(sent[1])["attendees"] as? [[String: Any]])
    #expect(merged.map { $0["email"] as? String } == ["me@x.com", "dee@x.com"])
}

@Test func anAttendeeChangeConflictsWhenSomeoneElseChangedTheSameAttendee() async throws {
    let h = try await Harness()
    var edit = EventEdit(base(version: "e5", attendees: [Attendee(email: "bob@x.com", role: .required)]))
    edit.event.attendees[0].role = .resource
    await h.transport.route("\(calPath)/ev1", [.json(googleEvent(id: "ev1", etag: "e6", extra: ["attendees": [["email": "bob@x.com", "optional": true]]]))])
    await expectWriteError(.conflict(fields: [.attendees])) {
        _ = try await h.source.update(EventRef(calendarID: cal, eventID: "ev1", version: "e5"), edit.patch, scope: .thisInstance, notify: .none)
    }
    #expect(await h.transport.requests(matching: "\(calPath)/ev1").allSatisfy { $0.method == "GET" })
}

@Test func anEmptyPatchReturnsTheBaseWithoutAnyRequest() async throws {
    let h = try await Harness()
    let edit = EventEdit(base())
    let result = try await h.source.update(EventRef(base()), edit.patch, scope: .thisInstance, notify: .none)
    let requestCount = await h.transport.requests.count
    #expect(result == base() && requestCount == 1)   // only the calendar list used for the access check
}

@Test func instanceAndSeriesScopesTargetTheInstanceOrTheMaster() async throws {
    let h = try await Harness()
    await h.transport.route("\(calPath)/master1", [.json(googleEvent(id: "master1", etag: "m2", summary: "All"))])
    await h.transport.route("\(calPath)/master1_20260921T100000Z", [.json(googleEvent(id: "master1_20260921T100000Z", etag: "i2", summary: "One"))])
    let ref = EventRef(calendarID: cal, eventID: "master1_20260921T100000Z", version: "i1", seriesID: "master1", originalStart: instant("2026-09-21T10:00:00Z"))
    _ = try await h.source.update(ref, EventPatch(title: "One"), scope: .thisInstance, notify: .none)
    _ = try await h.source.update(ref, EventPatch(title: "All"), scope: .allInSeries, notify: .none)
    let instance = try #require(await h.transport.requests(matching: "master1_2026").last)
    let master = try #require(await h.transport.requests(matching: "\(calPath)/master1?").last)
    #expect(instance.headers["If-Match"] == "i1")
    #expect(master.headers["If-Match"] == nil && master.method == "PATCH")   // an instance etag cannot lock the master
}

@Test func respondPatchesOnlyTheSelfAttendeeWithTheFetchedEtag() async throws {
    let h = try await Harness()
    let attendees: [[String: Any]] = [["email": "me@x.com", "self": true, "responseStatus": "needsAction"], ["email": "bob@x.com", "responseStatus": "accepted"]]
    await h.transport.route("\(calPath)/ev1", [.json(googleEvent(id: "ev1", etag: "e4", extra: ["attendees": attendees])), .json(googleEvent(id: "ev1", etag: "e5"))])
    _ = try await h.source.respond(to: EventRef(calendarID: cal, eventID: "ev1", version: "e1"), .declined, scope: .thisInstance, notify: .all)
    let patch = try #require(await h.transport.requests(matching: "\(calPath)/ev1").last)
    #expect(patch.method == "PATCH" && patch.headers["If-Match"] == "e4" && patch.url.absoluteString.contains("sendUpdates=all"))
    let sent = try #require(bodyJSON(patch)["attendees"] as? [[String: Any]])
    #expect(sent[0]["responseStatus"] as? String == "declined" && sent[1]["responseStatus"] as? String == "accepted")
    await expectWriteError(.unsupported(fields: [.attendees])) {
        _ = try await h.source.respond(to: EventRef(calendarID: cal, eventID: "ev1", seriesID: "m", originalStart: Date()), .accepted, scope: .thisAndFollowing, notify: .none)
    }
}

@Test func deleteSendsDeleteWithTheNotifyPolicyAndMapsGoneToNotFound() async throws {
    let h = try await Harness()
    await h.transport.route("\(calPath)/ev1", [HTTPResponse(status: 204)])
    try await h.source.delete(EventRef(calendarID: cal, eventID: "ev1"), scope: .thisInstance, notify: .all)
    let request = try #require(await h.transport.requests(matching: "\(calPath)/ev1").last)
    #expect(request.method == "DELETE" && request.url.absoluteString.contains("sendUpdates=all"))
    await h.transport.route("\(calPath)/ev2", [googleError("deleted", status: 410)])
    await expectWriteError(.notFound) { try await h.source.delete(EventRef(calendarID: cal, eventID: "ev2"), scope: .thisInstance, notify: .none) }
}

@Test func aForbiddenWriteIsReportedAsForbidden() async throws {
    let h = try await Harness()
    await h.transport.route("\(calPath)/ev1", [googleError("forbiddenForNonOrganizer", status: 403)])
    await expectWriteError(.forbidden(nil)) { _ = try await h.source.update(EventRef(calendarID: cal, eventID: "ev1", version: "e1"), EventPatch(title: "X"), scope: .thisInstance, notify: .none) }
}

// MARK: Edge cases beyond the brief

@Test func aRequestThatCannotBeBuiltIsRefusedBeforeAnyEventRequest() async throws {
    let h = try await Harness()
    // An invalid patch is caught even though the attendee path would otherwise fetch first.
    var patch = EventPatch(reminders: .set(Array(repeating: Reminder(minutesBefore: 5), count: 6)))
    patch.attendees = AttendeeChanges(add: [AttendeeDraft(email: "dee@x.com")])
    await expectWriteError(.invalid("Google allows at most 5 reminders")) {
        _ = try await h.source.update(EventRef(calendarID: cal, eventID: "ev1", version: "e1"), patch, scope: .thisInstance, notify: .none)
    }
    // An empty event id would address the events collection itself.
    await expectWriteError(.invalid("the event id must not be empty")) {
        try await h.source.delete(EventRef(calendarID: cal, eventID: ""), scope: .thisInstance, notify: .none)
    }
    await expectWriteError(.invalid("the event id must not be empty")) {
        _ = try await h.source.update(EventRef(calendarID: cal, eventID: "", version: "e1"), EventPatch(title: "X"), scope: .thisInstance, notify: .none)
    }
    await expectWriteError(.invalid("cannot respond with needsAction")) {
        _ = try await h.source.respond(to: EventRef(calendarID: cal, eventID: "ev1"), .needsAction, scope: .thisInstance, notify: .none)
    }
    #expect(await h.transport.requests(matching: "/events").isEmpty)
}

@Test func anUnreadableEventResponseIsAnInvalidResponseNotACocoaError() async throws {
    let h = try await Harness()
    await h.transport.route("\(calPath)/ev1", [.text("<html>oops</html>"), .json([1, 2, 3])])
    for _ in 0..<2 {
        do {
            _ = try await h.source.respond(to: EventRef(calendarID: cal, eventID: "ev1"), .accepted, scope: .thisInstance, notify: .none)
            Issue.record("expected an error")
        } catch let error as SourceError {
            #expect(error == .invalidResponse("google: unreadable event"))
        } catch {
            Issue.record("expected SourceError, got \(error)")
        }
    }
}

@Test func respondingToADeletedEventIsNotFound() async throws {
    let h = try await Harness()
    await h.transport.route("\(calPath)/ev1", [.json(googleEvent(id: "ev1", extra: ["status": "cancelled"]))])
    await expectWriteError(.notFound) {
        _ = try await h.source.respond(to: EventRef(calendarID: cal, eventID: "ev1"), .accepted, scope: .thisInstance, notify: .none)
    }
    #expect(await h.transport.requests(matching: "\(calPath)/ev1").allSatisfy { $0.method == "GET" })
}

@Test func respondRetriesOnTheFreshEtagWhenTheEventChangesBetweenFetchAndPatch() async throws {
    let h = try await Harness()
    let attendees: [[String: Any]] = [["email": "me@x.com", "self": true, "responseStatus": "needsAction"]]
    await h.transport.route("\(calPath)/ev1", [
        .json(googleEvent(id: "ev1", etag: "e4", extra: ["attendees": attendees])), googleError("conditionNotMet", status: 412),
        .json(googleEvent(id: "ev1", etag: "e5", extra: ["attendees": attendees])), .json(googleEvent(id: "ev1", etag: "e6")),
    ])
    let result = try await h.source.respond(to: EventRef(calendarID: cal, eventID: "ev1"), .accepted, scope: .thisInstance, notify: .none)
    let sent = await h.transport.requests(matching: "\(calPath)/ev1")
    #expect(sent.map(\.method) == ["GET", "PATCH", "GET", "PATCH"] && sent[3].headers["If-Match"] == "e5" && result.version == "e6")
}

@Test func aQuotaForbiddenWriteIsRateLimitedNotAPermissionError() async throws {
    let h = try await Harness()
    await h.transport.route("\(calPath)/ev1", [googleError("quotaExceeded", status: 403, headers: ["Retry-After": "30"])])
    do {
        _ = try await h.source.update(EventRef(calendarID: cal, eventID: "ev1", version: "e1"), EventPatch(title: "X"), scope: .thisInstance, notify: .none)
        Issue.record("expected an error")
    } catch let error as SourceError {
        #expect(error == .rateLimited(retryAfter: 30))
    } catch {
        Issue.record("expected SourceError, got \(error)")
    }
    await h.transport.route("\(calPath)/ev3", [googleError("calendarUsageLimitsExceeded", status: 403)])
    await #expect(throws: SourceError.rateLimited(retryAfter: nil)) {
        try await h.source.delete(EventRef(calendarID: cal, eventID: "ev3"), scope: .thisInstance, notify: .none)
    }
    // Reads keep their behaviour.
    await h.transport.route("calendars/me%40x.com/events", [googleError("quotaExceeded", status: 403)])
    await #expect(throws: SourceError.invalidResponse("HTTP 403: quotaExceeded")) {
        _ = try await h.source.events(in: DateInterval(start: .now, duration: 3600))
    }
}
