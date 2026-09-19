# Calendar De-duplication with Rules and Optional On-Device Inference Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge duplicate events across calendars with deterministic rules, plus an opt-in (default off, Beta) on-device model for the ambiguous remainder, with provenance badges, user overrides and small learned lessons.

**Architecture:** `TimeTugCore` gains a pure, synchronous `DuplicateResolver` (rules, learned pair memory, cached model verdicts) and a `DuplicateAdjudicator` protocol. `CalendarStore` runs the resolver on every refresh and asks the adjudicator about pending pairs off the hot path. `Packages/AppleIntelligenceInference` implements the protocol with Foundation Models; the app injects it and owns the setting, persistence and UI.

**Tech Stack:** Swift 6 (Core), Swift 5 mode (EventKitSource, AppleIntelligenceInference, app), Swift Testing (Core and the new package), XCTest (app), FoundationModels (macOS 26+, compile-guarded), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-19-calendar-dedup-inference-design.md`

## Global Constraints

- Core is platform-neutral: no UI or Apple-only imports; no display strings; never call `Date()` (time is passed in as `now`).
- Every Core behavior has a Swift Testing test written first (see `AGENTS.md`).
- Inference is opt-in: the setting defaults to **off**, is marked **Beta**, and off means the adjudicator is never called and cached AI verdicts are ignored.
- Only on-device engines are used (`EngineInfo.isOnDevice`); otherwise behavior is rules-only. A missing or `unavailable` engine is a normal mode, not an error.
- Time gate for candidates: intervals overlap, |start difference| <= 30 min, |end difference| <= 60 min.
- Only different calendars are merged by inference or rules (exact-title-and-time matches keep the existing behavior, including on one calendar). All-day events merge only on an exact match.
- Only `same` verdicts merge; `unsure` and `different` do not. Verdicts never block a refresh or a takeover.
- Bounds: group size 4; 300 lessons; 6-month lesson expiry; 5 lessons per prompt; notes truncated to 500 characters; verdict cache 1000 entries, 7-day TTL.
- Attendee emails are never sent to the model or stored in lessons.
- Provenance: `.rule` (no badge), `.inference(engineID, engineName)` (badge), `.userConfirmed` (badge "Merged manually"). A user decision outranks rules and AI.
- Commit messages end with `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.
- Commands: `swift test --package-path Packages/TimeTugCore`; `swift test --package-path Packages/AppleIntelligenceInference`; `swift build --package-path Packages/EventKitSource`; `xcodegen generate --spec Apps/macOS/project.yml`; `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test`.

## File Structure

Core (`Packages/TimeTugCore/Sources/TimeTugCore/`):
- Create `Model/MergeTypes.swift`: `Attendee`, `MergedMember`, `MergeProvenance`.
- Modify `Model/CalendarEvent.swift`: new fields, `allContentKeys`, `isSameMeeting(as:)`.
- Modify `Takeover/TakeoverLedger.swift`, `Takeover/TakeoverGuard.swift`: any-member matching.
- Create `Dedup/DuplicateRules.swift`: normalization, time gate, pair decision, detail score.
- Create `Dedup/LessonBook.swift`: `Lesson`, `LessonBook`.
- Create `Dedup/Adjudication.swift`: engine, request, verdict types, `DuplicateAdjudicator`, `VerdictCache`.
- Create `Dedup/DuplicateResolver.swift`: grouping and merge building.
- Modify `Store/CalendarStore.swift`: use the resolver; pending resolution; decisions; state.

Other:
- Modify `Packages/EventKitSource/Sources/EventKitSource/EventKitSource.swift`.
- Create `Packages/AppleIntelligenceInference/` (`Package.swift`, `PromptBuilder.swift`, `AppleIntelligence.swift`, tests).
- App (`Apps/macOS/Sources/`): create `DedupStateStore.swift`, `InferenceStatusText.swift`, `BetaBadge.swift`, `MergeBadge.swift`; modify `SettingsStore.swift`, `SettingsSearch.swift`, `AppModel.swift`, `CalendarsPane.swift`, `SettingsView.swift`, `AppCoordinator.swift`, `PopupRowModel.swift`, `DropdownView.swift`, `Apps/macOS/project.yml`.
- Docs: ADR 0009, `docs/architecture.md`, `AGENTS.md`, `docs/PROGRESS.md`, `docs/manual-tests/macos-checklist.md`, spec touch-ups.

---

### Task 1: Model types and any-member takeover identity

**Files:**
- Create: `Packages/TimeTugCore/Sources/TimeTugCore/Model/MergeTypes.swift`
- Modify: `Packages/TimeTugCore/Sources/TimeTugCore/Model/CalendarEvent.swift`
- Modify: `Packages/TimeTugCore/Sources/TimeTugCore/Takeover/TakeoverLedger.swift`
- Modify: `Packages/TimeTugCore/Sources/TimeTugCore/Takeover/TakeoverGuard.swift`
- Modify: `Packages/TimeTugCore/Tests/TimeTugCoreTests/Support.swift`
- Test: `Packages/TimeTugCore/Tests/TimeTugCoreTests/ModelTests.swift`, `TakeoverLedgerTests.swift`, `TakeoverGuardTests.swift`

**Interfaces:**
- Produces: `Attendee(name:email:)`, `Attendee.email(fromMailto:)`, `Attendee.normalizedEmail(_:)`; `MergedMember(title:calendarKey:contentKey:details:)`; `MergeProvenance { .rule, .inference(engineID:engineName:), .userConfirmed }`; on `CalendarEvent`: `attendees`, `organizerEmail`, `externalUID`, `mergedMembers`, `mergeProvenance`, `allContentKeys`, `isSameMeeting(as:)`.
- `mergedMembers` holds EVERY original copy (including the primary) when the event was merged, and is empty otherwise.

- [ ] **Step 1: Write the failing tests**

Append to `ModelTests.swift`:

```swift
@Test func contentKeysIncludeMergedMembers() {
    var event = makeEvent("1", title: "Doctor")
    #expect(event.allContentKeys == [event.contentKey])
    event.mergedMembers = [MergedMember(title: "Intermountain Health", calendarKey: "fake/other", contentKey: "k2", details: "bare")]
    #expect(event.allContentKeys == [event.contentKey, "k2"])
}

@Test func isSameMeetingMatchesAnyMemberKey() {
    let armed = makeEvent("1", title: "Scott: Doctor")
    var merged = makeEvent("2", title: "Intermountain Health")
    #expect(!merged.isSameMeeting(as: armed))
    merged.mergedMembers = [MergedMember(title: armed.title, calendarKey: armed.calendarKey, contentKey: armed.contentKey, details: "bare")]
    #expect(merged.isSameMeeting(as: armed))
    #expect(armed.isSameMeeting(as: merged))
}

@Test func attendeeEmailNormalizationAndMailtoParsing() {
    #expect(Attendee(email: "  Kristin@Example.COM ").email == "kristin@example.com")
    #expect(Attendee(email: "   ").email == nil)
    #expect(Attendee.email(fromMailto: "mailto:Bob@Example.com?subject=x") == "bob@example.com")
    #expect(Attendee.email(fromMailto: "https://example.com/principal/1") == nil)
    #expect(Attendee.email(fromMailto: nil) == nil)
}
```

Append to `TakeoverLedgerTests.swift`:

```swift
private func merged(_ primary: CalendarEvent, with others: [CalendarEvent]) -> CalendarEvent {
    var event = primary
    event.mergedMembers = ([primary] + others).map {
        MergedMember(title: $0.title, calendarKey: $0.calendarKey, contentKey: $0.contentKey, details: "bare")
    }
    return event
}

@Test func mergedEventCountsAsFiredWhenAnyMemberFired() {
    let original = makeEvent("1", title: "Scott: Doctor")
    let official = makeEvent("2", title: "Intermountain Health")
    var ledger = TakeoverLedger()
    ledger.markFired(original, now: recordedAt)
    #expect(ledger.hasFired(merged(official, with: [original])))
}

@Test func firingMergedEventMarksEveryMember() {
    let original = makeEvent("1", title: "Scott: Doctor")
    let official = makeEvent("2", title: "Intermountain Health")
    var ledger = TakeoverLedger()
    ledger.markFired(merged(official, with: [original]), now: recordedAt)
    #expect(ledger.hasFired(original))
    #expect(ledger.hasFired(official))
}
```

Append to `TakeoverGuardTests.swift`:

```swift
@Test func armedCopyStillMatchesAfterItWasMergedIntoAnotherEvent() {
    let armed = makeEvent("1", title: "Scott: Doctor")
    var current = makeEvent("2", title: "Intermountain Health")
    current.mergedMembers = [armed, current].map {
        MergedMember(title: $0.title, calendarKey: $0.calendarKey, contentKey: $0.contentKey, details: "bare")
    }
    let decision = TakeoverGuard.evaluate(
        event: armed, currentEvents: [current], settings: optedIn(), ledger: TakeoverLedger(),
        now: date("2026-09-18T09:59:00Z"), overlayVisible: false)
    #expect(decision != .suppress(.notInSnapshot))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path Packages/TimeTugCore 2>&1 | tail -20`
Expected: compile errors (`MergedMember`, `allContentKeys` not defined).

- [ ] **Step 3: Implement**

Create `Model/MergeTypes.swift`:

```swift
import Foundation

/// A meeting invitee other than the calendar owner. Emails are normalized (lowercased, trimmed).
public struct Attendee: Hashable, Sendable {
    public var name: String?
    public var email: String?

    public init(name: String? = nil, email: String? = nil) {
        self.name = name
        self.email = Self.normalizedEmail(email)
    }

    public static func normalizedEmail(_ raw: String?) -> String? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !s.isEmpty else { return nil }
        return s
    }

    /// The address in a "mailto:" URL string (as EventKit participants expose it); nil for any other URL.
    public static func email(fromMailto urlString: String?) -> String? {
        guard let urlString, urlString.lowercased().hasPrefix("mailto:") else { return nil }
        let rest = String(urlString.dropFirst("mailto:".count))
        return normalizedEmail(rest.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init))
    }
}

/// One original copy folded into a merged event.
public struct MergedMember: Hashable, Sendable {
    public var title: String
    public var calendarKey: String
    public var contentKey: String
    /// Which details the original copy had, e.g. "bare" or "location+notes" (see `DuplicateRules.detailSummary`).
    public var details: String

    public init(title: String, calendarKey: String, contentKey: String, details: String) {
        self.title = title
        self.calendarKey = calendarKey
        self.contentKey = contentKey
        self.details = details
    }
}

/// How a merged event came to be merged. Core carries data only; the app words the badge.
public enum MergeProvenance: Hashable, Sendable {
    case rule
    case inference(engineID: String, engineName: String)
    case userConfirmed
}
```

In `CalendarEvent.swift` add stored properties after `additionalCalendarKeys`:

```swift
    public var attendees: [Attendee]
    public var organizerEmail: String?
    public var externalUID: String?
    /// Every original copy folded into this event (including itself); empty when never merged.
    public var mergedMembers: [MergedMember]
    public var mergeProvenance: MergeProvenance?
```

Extend the initializer signature (new parameters last, with defaults) and body:

```swift
        additionalCalendarKeys: Set<String> = [],
        attendees: [Attendee] = [], organizerEmail: String? = nil, externalUID: String? = nil,
        mergedMembers: [MergedMember] = [], mergeProvenance: MergeProvenance? = nil
    ) {
        // ... existing assignments ...
        self.attendees = attendees
        self.organizerEmail = organizerEmail
        self.externalUID = externalUID
        self.mergedMembers = mergedMembers
        self.mergeProvenance = mergeProvenance
    }
```

Add after `allCalendarKeys`:

```swift
    /// Content keys of this event and every copy merged into it.
    public var allContentKeys: Set<String> { Set(mergedMembers.map(\.contentKey)).union([contentKey]) }

    /// True for the same occurrence or when any merged copy's content matches (an armed timer's
    /// event may since have been merged into another, or split back out).
    public func isSameMeeting(as other: CalendarEvent) -> Bool {
        id == other.id || !allContentKeys.isDisjoint(with: other.allContentKeys)
    }
```

In `TakeoverLedger.swift` replace `entry(for:)` and `record`:

```swift
    func entry(for event: CalendarEvent) -> Entry? {
        let found = ([event.id] + event.allContentKeys.sorted()).compactMap { records[$0]?.entry }
        return found.first(where: { $0 == .fired }) ?? found.first
    }

    private mutating func record(_ entry: Entry, for event: CalendarEvent, now: Date) {
        let record = Record(entry: entry, end: event.end, recordedAt: now)
        records[event.id] = record
        for key in event.allContentKeys { records[key] = record }
    }
```

Update the doc comment above the struct: "recorded under `CalendarEvent.id` and every key in `allContentKeys` (so a merge or split never re-fires a meeting)".

In `TakeoverGuard.evaluate` replace the `first(where:)` closure body with `$0.isSameMeeting(as: event)`.

In `Support.swift` add two parameters to `makeEvent` (after `conferenceURL`): `attendees: [Attendee] = [], externalUID: String? = nil`, and pass `attendees: attendees, externalUID: externalUID` to the initializer.

- [ ] **Step 4: Run tests**

Run: `swift test --package-path Packages/TimeTugCore 2>&1 | tail -5`
Expected: all pass (previous 106 plus the new ones).

- [ ] **Step 5: Commit**

```bash
git add Packages/TimeTugCore
git commit -m "feat(core): merge provenance types and any-member takeover identity

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Pair rules

**Files:**
- Create: `Packages/TimeTugCore/Sources/TimeTugCore/Dedup/DuplicateRules.swift`
- Test: `Packages/TimeTugCore/Tests/TimeTugCoreTests/DuplicateRulesTests.swift`

**Interfaces:**
- Consumes: `CalendarEvent`, `MergedMember`, `ConferenceLinkDetector.detect(location:url:notes:)`.
- Produces: `PairDecision { .merge(MergeReason), .separate(SeparateReason), .ambiguous }`; `DuplicateRules.decide(_:_:)`, `.isCandidate(_:_:)`, `.withinTimeGate(_:_:)`, `.normalize(_:)`, `.detailScore(_:)`, `.detailSummary(_:)`; `MergedMember.init(_ event:)`; `CalendarEvent.participants: [MergedMember]`.

- [ ] **Step 1: Write the failing tests**

Create `DuplicateRulesTests.swift`:

```swift
import Foundation
import Testing
@testable import TimeTugCore

private func decide(_ a: CalendarEvent, _ b: CalendarEvent) -> PairDecision { DuplicateRules.decide(a, b) }

@Test func exactMatchMergesEvenOnOneCalendar() {
    #expect(decide(makeEvent("1", title: "Sync"), makeEvent("2", title: "sync", calendarID: "other")) == .merge(.exactMatch))
    #expect(decide(makeEvent("1", title: "Sync"), makeEvent("2", title: "Sync")) == .merge(.exactMatch))
}

@Test func sameCalendarDifferentTitlesStaySeparate() {
    #expect(decide(makeEvent("1", title: "Doctor"), makeEvent("2", title: "Dance")) == .separate(.sameCalendar))
}

@Test func allDayEventsOnlyMergeOnExactMatch() {
    let a = makeEvent("1", title: "Birthday", isAllDay: true)
    let b = makeEvent("2", title: "Kristin birthday", calendarID: "other", isAllDay: true)
    #expect(decide(a, b) == .separate(.allDay))
}

@Test func timeGateBoundaries() {
    let a = makeEvent("1", title: "A", minutes: 60)                                        // 10:00-11:00
    #expect(decide(a, makeEvent("2", title: "B", start: "2026-09-18T10:30:00Z", minutes: 60, calendarID: "o")) == .ambiguous)
    #expect(decide(a, makeEvent("2", title: "B", start: "2026-09-18T10:31:00Z", minutes: 60, calendarID: "o")) == .separate(.outsideTimeGate))
    #expect(decide(makeEvent("1", title: "A", minutes: 30), makeEvent("2", title: "B", minutes: 90, calendarID: "o")) == .ambiguous)      // end +60
    #expect(decide(makeEvent("1", title: "A", minutes: 30), makeEvent("2", title: "B", minutes: 91, calendarID: "o")) == .separate(.outsideTimeGate))
}

@Test func sharedConferenceMergesDespiteDifferentTitlesAndQueries() {
    let a = makeEvent("1", title: "Weekly", location: "https://acme.zoom.us/j/555?pwd=abc")
    let b = makeEvent("2", title: "Team sync", calendarID: "o", notes: "Join https://acme.zoom.us/j/555/")
    #expect(decide(a, b) == .merge(.conferenceLink))
}

@Test func sharedExternalUIDMerges() {
    let a = makeEvent("1", title: "A", externalUID: "uid-1")
    let b = makeEvent("2", title: "B", calendarID: "o", externalUID: "uid-1")
    #expect(decide(a, b) == .merge(.externalUID))
}

@Test func sharedAttendeeEmailMergesCaseInsensitively() {
    let a = makeEvent("1", title: "A", attendees: [Attendee(email: "Kristin@x.com")])
    let b = makeEvent("2", title: "B", calendarID: "o", attendees: [Attendee(email: "kristin@X.com"), Attendee(email: "z@x.com")])
    #expect(decide(a, b) == .merge(.sharedAttendee))
}

@Test func sameLocationMergesIncludingContainment() {
    let a = makeEvent("1", title: "Doctor", location: "1234 Main St")
    let b = makeEvent("2", title: "Intermountain Health", calendarID: "o", location: "Intermountain Health, 1234 Main St")
    #expect(decide(a, b) == .merge(.sameLocation))
}

@Test func vetoesFireOnlyWhenBothSidesHaveTheField() {
    let loc1 = makeEvent("1", title: "A", location: "Room 101 East")
    let loc2 = makeEvent("2", title: "B", calendarID: "o", location: "Dentist Office")
    #expect(decide(loc1, loc2) == .separate(.conflictingLocation))

    let z1 = makeEvent("1", title: "A", conferenceURL: URL(string: "https://acme.zoom.us/j/1"))
    let z2 = makeEvent("2", title: "B", calendarID: "o", conferenceURL: URL(string: "https://acme.zoom.us/j/2"))
    #expect(decide(z1, z2) == .separate(.conflictingConference))

    let p1 = makeEvent("1", title: "A", attendees: [Attendee(email: "a@x.com")])
    let p2 = makeEvent("2", title: "B", calendarID: "o", attendees: [Attendee(email: "b@x.com")])
    #expect(decide(p1, p2) == .separate(.conflictingAttendees))

    // Absent on one side is not a veto.
    #expect(decide(loc1, makeEvent("2", title: "B", calendarID: "o")) == .ambiguous)
    #expect(decide(makeEvent("1", title: "Scott: Doctor"), makeEvent("2", title: "Intermountain Health", calendarID: "o")) == .ambiguous)
}

@Test func detailScoreAndSummary() {
    #expect(DuplicateRules.detailSummary(makeEvent(others: 0)) == "bare")
    let rich = makeEvent(others: 2, location: "1 Main St", notes: "Bring card")
    #expect(DuplicateRules.detailSummary(rich) == "location+attendees+notes")
    #expect(DuplicateRules.detailScore(rich) == 3)
}

@Test func participantsAreTheEventItselfWhenNeverMerged() {
    let event = makeEvent("1", title: "Doctor")
    #expect(event.participants.map(\.title) == ["Doctor"])
    #expect(event.participants.first?.calendarKey == "fake/cal")
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Packages/TimeTugCore --filter DuplicateRules 2>&1 | tail -10`
Expected: compile error (`DuplicateRules` not defined).

- [ ] **Step 3: Implement** `Dedup/DuplicateRules.swift`:

```swift
import Foundation

public enum MergeReason: String, Sendable { case exactMatch, externalUID, conferenceLink, sharedAttendee, sameLocation }
public enum SeparateReason: String, Sendable {
    case sameCalendar, allDay, outsideTimeGate, conflictingLocation, conflictingConference, conflictingAttendees
}
public enum PairDecision: Equatable, Sendable {
    case merge(MergeReason)
    case separate(SeparateReason)
    /// Nothing matched and nothing conflicted: the only case a model may be asked about.
    case ambiguous
}

/// Deterministic pair rules. Pure; no model involved.
public enum DuplicateRules {
    public static let maxStartDifference: TimeInterval = 30 * 60
    public static let maxEndDifference: TimeInterval = 60 * 60
    private static let minContainedLocationLength = 6

    /// Different calendars, timed, and inside the time gate.
    public static func isCandidate(_ a: CalendarEvent, _ b: CalendarEvent) -> Bool {
        a.calendarKey != b.calendarKey && !a.isAllDay && !b.isAllDay && withinTimeGate(a, b)
    }

    /// Overlapping, starts within 30 min, ends within 60 min (end times are uncertain and may include travel).
    public static func withinTimeGate(_ a: CalendarEvent, _ b: CalendarEvent) -> Bool {
        a.start < b.end && b.start < a.end
            && abs(a.start.timeIntervalSince(b.start)) <= maxStartDifference
            && abs(a.end.timeIntervalSince(b.end)) <= maxEndDifference
    }

    public static func decide(_ a: CalendarEvent, _ b: CalendarEvent) -> PairDecision {
        if a.contentKey == b.contentKey { return .merge(.exactMatch) }
        if a.calendarKey == b.calendarKey { return .separate(.sameCalendar) }
        if a.isAllDay || b.isAllDay { return .separate(.allDay) }
        if !withinTimeGate(a, b) { return .separate(.outsideTimeGate) }

        if let uid = a.externalUID, uid == b.externalUID { return .merge(.externalUID) }
        let confA = conferenceIdentity(a), confB = conferenceIdentity(b)
        if let confA, confA == confB { return .merge(.conferenceLink) }
        let emailsA = emails(a), emailsB = emails(b)
        if !emailsA.isDisjoint(with: emailsB) { return .merge(.sharedAttendee) }
        let location = locationRelation(a.location, b.location)
        if location == .same { return .merge(.sameLocation) }

        if location == .conflict { return .separate(.conflictingLocation) }
        if let confA, let confB, confA != confB { return .separate(.conflictingConference) }
        if !emailsA.isEmpty, !emailsB.isEmpty { return .separate(.conflictingAttendees) }
        return .ambiguous
    }

    /// Lowercased, accent-folded, punctuation collapsed to single spaces.
    public static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return String(folded.map { $0.isLetter || $0.isNumber ? $0 : " " })
            .split(separator: " ").joined(separator: " ")
    }

    public static func detailScore(_ event: CalendarEvent) -> Int { detailParts(event).count }

    /// "bare" or a "+"-joined list of location, conference, attendees, notes.
    public static func detailSummary(_ event: CalendarEvent) -> String {
        let parts = detailParts(event)
        return parts.isEmpty ? "bare" : parts.joined(separator: "+")
    }

    private static func detailParts(_ event: CalendarEvent) -> [String] {
        var parts: [String] = []
        if normalizedLocation(event.location) != nil { parts.append("location") }
        if conferenceIdentity(event) != nil { parts.append("conference") }
        if event.otherAttendeeCount > 0 || !event.attendees.isEmpty { parts.append("attendees") }
        if !(event.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) { parts.append("notes") }
        return parts
    }

    /// host + path of the conference link (query dropped, lowercased), from the structured link or
    /// one found in the location, url or notes.
    static func conferenceIdentity(_ event: CalendarEvent) -> String? {
        let url = event.conferenceURL
            ?? ConferenceLinkDetector.detect(location: event.location, url: event.url, notes: event.notes)
        guard let url, let host = url.host?.lowercased() else { return nil }
        var path = url.path.lowercased()
        while path.hasSuffix("/") { path.removeLast() }
        return host + path
    }

    static func emails(_ event: CalendarEvent) -> Set<String> {
        Set((event.attendees.map(\.email) + [event.organizerEmail]).compactMap(Attendee.normalizedEmail))
    }

    private enum LocationRelation { case unknown, same, conflict }

    private static func locationRelation(_ a: String?, _ b: String?) -> LocationRelation {
        guard let a = normalizedLocation(a), let b = normalizedLocation(b) else { return .unknown }
        if a == b { return .same }
        let (short, long) = a.count <= b.count ? (a, b) : (b, a)
        if short.count >= minContainedLocationLength, " \(long) ".contains(" \(short) ") { return .same }
        return .conflict
    }

    /// nil for empty text and for URLs (a link in the location field is a conference, not a place).
    static func normalizedLocation(_ raw: String?) -> String? {
        guard let raw, !raw.contains("://") else { return nil }
        let normalized = normalize(raw)
        return normalized.isEmpty ? nil : normalized
    }
}

extension MergedMember {
    public init(_ event: CalendarEvent) {
        self.init(title: event.title, calendarKey: event.calendarKey, contentKey: event.contentKey,
                  details: DuplicateRules.detailSummary(event))
    }
}

extension CalendarEvent {
    /// The (title, calendar) copies this event stands for: itself when it was never merged.
    public var participants: [MergedMember] { mergedMembers.isEmpty ? [MergedMember(self)] : mergedMembers }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --package-path Packages/TimeTugCore 2>&1 | tail -5`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/TimeTugCore
git commit -m "feat(core): deterministic duplicate pair rules with time gate and vetoes

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

### Task 3: Lessons

**Files:**
- Create: `Packages/TimeTugCore/Sources/TimeTugCore/Dedup/LessonBook.swift`
- Test: `Packages/TimeTugCore/Tests/TimeTugCoreTests/LessonBookTests.swift`

**Interfaces:**
- Consumes: `MergedMember`, `DuplicateRules.normalize`.
- Produces: `Lesson` (`Decision { same, different }`, `titleA/B` normalized, `calendarKeyA/B`, `signalsA/B`, `decision`, `lastUsed`, `pairKey`); `LessonBook` with `maxLessons`, `expiry`, `promptLimit`, `lessons`, `record(_:_:decision:now:)`, `decision(_:_:) -> Lesson?` (events), `relevant(to:_:) -> [Lesson]`, `touch(_:now:)`, `prune(now:)`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import TimeTugCore

private let t0 = date("2026-09-18T09:00:00Z")

private func member(_ title: String, _ calendar: String, _ details: String = "bare") -> MergedMember {
    MergedMember(title: title, calendarKey: calendar, contentKey: title, details: details)
}

@Test func lessonIsLookedUpInEitherOrderByNormalizedTitles() {
    var book = LessonBook()
    book.record(member("Scott: Doctor", "fake/personal"), member("Intermountain Health", "fake/work", "location"), decision: .same, now: t0)
    let a = makeEvent("1", title: "scott doctor!", calendarID: "personal")
    let b = makeEvent("2", title: "INTERMOUNTAIN HEALTH", calendarID: "work")
    #expect(book.decision(a, b)?.decision == .same)
    #expect(book.decision(b, a)?.decision == .same)
}

@Test func sameCalendarPairsAreNotRecorded() {
    var book = LessonBook()
    book.record(member("A", "fake/cal"), member("B", "fake/cal"), decision: .different, now: t0)
    #expect(book.lessons.isEmpty)
}

@Test func newDecisionReplacesTheOldOneForThePair() {
    var book = LessonBook()
    let a = member("A", "fake/x"), b = member("B", "fake/y")
    book.record(a, b, decision: .same, now: t0)
    book.record(b, a, decision: .different, now: t0.addingTimeInterval(60))
    #expect(book.lessons.count == 1)
    #expect(book.lessons.first?.decision == .different)
}

@Test func lessonsAreCappedOldestFirst() {
    var book = LessonBook()
    for i in 0..<(LessonBook.maxLessons + 5) {
        book.record(member("title\(i)", "fake/x"), member("other\(i)", "fake/y"), decision: .same,
                    now: t0.addingTimeInterval(TimeInterval(i)))
    }
    #expect(book.lessons.count == LessonBook.maxLessons)
    #expect(!book.lessons.contains { $0.titleA == "title0" || $0.titleB == "title0" })
}

@Test func unusedLessonsExpireAndTouchRefreshes() {
    var book = LessonBook()
    book.record(member("A", "fake/x"), member("B", "fake/y"), decision: .same, now: t0)
    book.record(member("C", "fake/x"), member("D", "fake/y"), decision: .same, now: t0)
    let key = book.lessons.first { $0.titleA == "a" }!.pairKey
    let later = t0.addingTimeInterval(LessonBook.expiry - 10)
    book.touch([key], now: later)
    book.prune(now: t0.addingTimeInterval(LessonBook.expiry + 10))
    #expect(book.lessons.map(\.titleA) == ["a"])
}

@Test func relevantLessonsPreferSharedWordsAndCalendarsOverRecency() {
    var book = LessonBook()
    book.record(member("Doctor visit", "fake/personal"), member("Clinic", "fake/work"), decision: .same, now: t0)
    book.record(member("Dance", "fake/personal"), member("Studio", "fake/work"), decision: .different, now: t0.addingTimeInterval(500))
    let a = makeEvent("1", title: "Doctor", calendarID: "personal")
    let b = makeEvent("2", title: "Mercy Clinic", calendarID: "work")
    #expect(book.relevant(to: a, b).first?.titleA == "clinic")
}

@Test func codableRoundTrip() throws {
    var book = LessonBook()
    book.record(member("A", "fake/x"), member("B", "fake/y"), decision: .same, now: t0)
    let decoded = try JSONDecoder().decode(LessonBook.self, from: JSONEncoder().encode(book))
    #expect(decoded == book)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Packages/TimeTugCore --filter LessonBook 2>&1 | tail -10`
Expected: compile error (`LessonBook` not defined).

- [ ] **Step 3: Implement** `Dedup/LessonBook.swift`:

```swift
import Foundation

/// One user correction. Titles are normalized; no notes, names or emails are kept.
public struct Lesson: Codable, Equatable, Sendable {
    public enum Decision: String, Codable, Sendable { case same, different }

    public var titleA: String
    public var titleB: String
    public var calendarKeyA: String
    public var calendarKeyB: String
    /// Which details each side had ("bare", "location+notes"), for the model's context.
    public var signalsA: String
    public var signalsB: String
    public var decision: Decision
    public var lastUsed: Date

    public var pairKey: String { LessonBook.pairKey(titleA: titleA, calendarKeyA: calendarKeyA, titleB: titleB, calendarKeyB: calendarKeyB) }
}

/// Small, bounded memory of the user's merge and unmerge decisions.
public struct LessonBook: Codable, Equatable, Sendable {
    public static let maxLessons = 300
    public static let expiry: TimeInterval = 182 * 24 * 60 * 60
    public static let promptLimit = 5

    public private(set) var lessons: [Lesson] = []

    public init() {}

    /// Order-independent identity of a (title, calendar) pair.
    public static func pairKey(titleA: String, calendarKeyA: String, titleB: String, calendarKeyB: String) -> String {
        let sides = ["\(DuplicateRules.normalize(titleA))|\(calendarKeyA)", "\(DuplicateRules.normalize(titleB))|\(calendarKeyB)"].sorted()
        return sides[0] + "#" + sides[1]
    }

    public mutating func record(_ a: MergedMember, _ b: MergedMember, decision: Lesson.Decision, now: Date) {
        guard a.calendarKey != b.calendarKey else { return }
        let sides = [a, b].sorted { side($0) < side($1) }
        let lesson = Lesson(
            titleA: DuplicateRules.normalize(sides[0].title), titleB: DuplicateRules.normalize(sides[1].title),
            calendarKeyA: sides[0].calendarKey, calendarKeyB: sides[1].calendarKey,
            signalsA: sides[0].details, signalsB: sides[1].details, decision: decision, lastUsed: now)
        lessons.removeAll { $0.pairKey == lesson.pairKey }
        lessons.append(lesson)
        prune(now: now)
    }

    /// The recorded decision for this pair of events, if any.
    public func decision(_ a: CalendarEvent, _ b: CalendarEvent) -> Lesson? {
        let key = Self.pairKey(titleA: a.title, calendarKeyA: a.calendarKey, titleB: b.title, calendarKeyB: b.calendarKey)
        return lessons.first { $0.pairKey == key }
    }

    /// Up to `promptLimit` lessons most similar to this pair (shared title words, same calendar pair).
    public func relevant(to a: CalendarEvent, _ b: CalendarEvent) -> [Lesson] {
        let words = Set(DuplicateRules.normalize(a.title).split(separator: " ") + DuplicateRules.normalize(b.title).split(separator: " "))
        let calendars: Set<String> = [a.calendarKey, b.calendarKey]
        let scored: [(lesson: Lesson, score: Int)] = lessons.map { lesson in
            let lessonWords = Set(lesson.titleA.split(separator: " ") + lesson.titleB.split(separator: " "))
            let calendarBonus = calendars == [lesson.calendarKeyA, lesson.calendarKeyB] ? 2 : 0
            return (lesson, words.intersection(lessonWords).count + calendarBonus)
        }
        return scored.filter { $0.score > 0 }
            .sorted { ($0.score, $0.lesson.lastUsed, $1.lesson.pairKey) > ($1.score, $1.lesson.lastUsed, $0.lesson.pairKey) }
            .prefix(Self.promptLimit).map(\.lesson)
    }

    public mutating func touch(_ pairKeys: Set<String>, now: Date) {
        for index in lessons.indices where pairKeys.contains(lessons[index].pairKey) { lessons[index].lastUsed = now }
    }

    /// Drops lessons unused for `expiry`, then the oldest beyond `maxLessons`.
    public mutating func prune(now: Date) {
        lessons.removeAll { now.timeIntervalSince($0.lastUsed) > Self.expiry }
        if lessons.count > Self.maxLessons {
            lessons.sort { $0.lastUsed < $1.lastUsed }
            lessons.removeFirst(lessons.count - Self.maxLessons)
        }
    }

    private func side(_ member: MergedMember) -> String { "\(DuplicateRules.normalize(member.title))|\(member.calendarKey)" }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --package-path Packages/TimeTugCore 2>&1 | tail -5`
Expected: all pass. (If the tuple comparison in `relevant` does not compile, replace the sort closure with explicit `if` comparisons on score, then `lastUsed`.)

- [ ] **Step 5: Commit**

```bash
git add Packages/TimeTugCore
git commit -m "feat(core): bounded lesson book for merge/unmerge corrections

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Adjudicator interface and verdict cache

**Files:**
- Create: `Packages/TimeTugCore/Sources/TimeTugCore/Dedup/Adjudication.swift`
- Test: `Packages/TimeTugCore/Tests/TimeTugCoreTests/AdjudicationTests.swift`

**Interfaces:**
- Consumes: `CalendarEvent`, `CalendarInfo`, `Lesson`.
- Produces: `EngineInfo(id:displayName:isOnDevice:)`; `AdjudicatorAvailability { .available(EngineInfo), .unavailable(reason:) }`; `AdjudicationEvent(_ event:calendar:)` (title, start, end, location, notes<=500 chars, attendeeNames, calendarTitle, accountName); `AdjudicationRequest(id:first:second:lessons:)` where `first` is the more detailed event; `AdjudicationVerdict(requestID:answer:)` with `Answer { same, different, unsure }`; `protocol DuplicateAdjudicator: Sendable { var availability; func judge(_:) async -> [AdjudicationVerdict] }`; `VerdictCache` with `entry(for:)`, `store(_:engine:end:now:)`, `prune(now:)`; `Fingerprint.fnv1a(_:)`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import TimeTugCore

private let t0 = date("2026-09-18T09:00:00Z")
private let engine = EngineInfo(id: "fake-ai", displayName: "Fake AI", isOnDevice: true)

@Test func adjudicationEventTruncatesNotesAndDropsEmailsByConstruction() {
    let event = makeEvent("1", title: "Doctor", notes: String(repeating: "x", count: 900),
                          attendees: [Attendee(name: "Kristin", email: "k@x.com"), Attendee(name: nil, email: "n@x.com")])
    let info = CalendarInfo(sourceID: "fake", calendarID: "cal", title: "Personal", accountName: "iCloud")
    let projected = AdjudicationEvent(event, calendar: info)
    #expect(projected.notes?.count == AdjudicationEvent.maxNotesLength)
    #expect(projected.attendeeNames == ["Kristin"])
    #expect(projected.calendarTitle == "Personal")
    #expect(projected.accountName == "iCloud")
}

@Test func verdictCacheStoresAndPrunesEndedAndOldEntries() {
    var cache = VerdictCache()
    cache.store(AdjudicationVerdict(requestID: "a", answer: .same), engine: engine, end: t0.addingTimeInterval(3600), now: t0)
    cache.store(AdjudicationVerdict(requestID: "b", answer: .unsure), engine: engine, end: t0.addingTimeInterval(60), now: t0)
    #expect(cache.entry(for: "a")?.answer == .same)
    #expect(cache.entry(for: "a")?.engine == engine)
    #expect(cache.prune(now: t0.addingTimeInterval(120)))
    #expect(cache.entry(for: "b") == nil)
    #expect(cache.prune(now: t0.addingTimeInterval(VerdictCache.retention + 1)))
    #expect(cache.entry(for: "a") == nil)
}

@Test func verdictCacheIsCappedOldestFirst() {
    var cache = VerdictCache()
    for i in 0..<(VerdictCache.maxEntries + 3) {
        cache.store(AdjudicationVerdict(requestID: "r\(i)", answer: .same), engine: engine,
                    end: t0.addingTimeInterval(86_400), now: t0.addingTimeInterval(TimeInterval(i)))
    }
    cache.prune(now: t0)
    #expect(cache.entries.count == VerdictCache.maxEntries)
    #expect(cache.entry(for: "r0") == nil)
}

@Test func verdictCacheCodableRoundTrip() throws {
    var cache = VerdictCache()
    cache.store(AdjudicationVerdict(requestID: "a", answer: .different), engine: engine, end: t0.addingTimeInterval(60), now: t0)
    #expect(try JSONDecoder().decode(VerdictCache.self, from: JSONEncoder().encode(cache)) == cache)
}

@Test func fingerprintIsStableAndSensitive() {
    #expect(Fingerprint.fnv1a("abc") == Fingerprint.fnv1a("abc"))
    #expect(Fingerprint.fnv1a("abc") != Fingerprint.fnv1a("abd"))
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Packages/TimeTugCore --filter Adjudication 2>&1 | tail -10`
Expected: compile error (`EngineInfo` not defined).

- [ ] **Step 3: Implement** `Dedup/Adjudication.swift`:

```swift
import Foundation

public struct EngineInfo: Hashable, Codable, Sendable {
    public var id: String
    /// Product name, e.g. "Apple Intelligence"; the front end words the badge around it.
    public var displayName: String
    public var isOnDevice: Bool

    public init(id: String, displayName: String, isOnDevice: Bool) {
        self.id = id
        self.displayName = displayName
        self.isOnDevice = isOnDevice
    }
}

public enum AdjudicatorAvailability: Equatable, Sendable {
    case available(EngineInfo)
    case unavailable(reason: String)
}

/// The fields of one event a model may see. No emails; notes are truncated.
public struct AdjudicationEvent: Equatable, Sendable {
    public static let maxNotesLength = 500

    public var title: String
    public var start: Date
    public var end: Date
    public var location: String?
    public var notes: String?
    public var attendeeNames: [String]
    public var calendarTitle: String?
    public var accountName: String?

    public init(_ event: CalendarEvent, calendar: CalendarInfo?) {
        title = event.title
        start = event.start
        end = event.end
        location = event.location
        notes = event.notes.map { String($0.prefix(Self.maxNotesLength)) }
        attendeeNames = event.attendees.compactMap(\.name).filter { !$0.isEmpty }
        calendarTitle = calendar?.title
        accountName = calendar?.accountName
    }
}

public struct AdjudicationRequest: Equatable, Sendable {
    /// Fingerprint of both events' relevant content; the cache key.
    public var id: String
    /// The more detailed event (ties: the earlier one); the other is `second`.
    public var first: AdjudicationEvent
    public var second: AdjudicationEvent
    public var lessons: [Lesson]

    public init(id: String, first: AdjudicationEvent, second: AdjudicationEvent, lessons: [Lesson]) {
        self.id = id
        self.first = first
        self.second = second
        self.lessons = lessons
    }
}

public struct AdjudicationVerdict: Equatable, Sendable {
    public enum Answer: String, Codable, Sendable { case same, different, unsure }
    public var requestID: String
    public var answer: Answer

    public init(requestID: String, answer: Answer) {
        self.requestID = requestID
        self.answer = answer
    }
}

/// A platform's on-device model. Implementations live outside Core.
public protocol DuplicateAdjudicator: Sendable {
    var availability: AdjudicatorAvailability { get }
    /// Verdicts for the requests it could judge; omit a request on failure so it is retried later.
    func judge(_ requests: [AdjudicationRequest]) async -> [AdjudicationVerdict]
}

/// Model verdicts, kept so each pair is judged once. Ended, old and surplus entries are pruned.
public struct VerdictCache: Codable, Equatable, Sendable {
    public static let retention: TimeInterval = 7 * 24 * 60 * 60
    public static let maxEntries = 1000

    public struct Entry: Codable, Equatable, Sendable {
        public var answer: AdjudicationVerdict.Answer
        public var engine: EngineInfo
        public var decidedAt: Date
        public var end: Date
    }

    public private(set) var entries: [String: Entry] = [:]

    public init() {}

    public func entry(for requestID: String) -> Entry? { entries[requestID] }

    public mutating func store(_ verdict: AdjudicationVerdict, engine: EngineInfo, end: Date, now: Date) {
        entries[verdict.requestID] = Entry(answer: verdict.answer, engine: engine, decidedAt: now, end: end)
    }

    /// True if anything was dropped.
    @discardableResult
    public mutating func prune(now: Date) -> Bool {
        let before = entries.count
        entries = entries.filter { $0.value.end > now && now.timeIntervalSince($0.value.decidedAt) <= Self.retention }
        if entries.count > Self.maxEntries {
            let oldestFirst = entries.sorted { ($0.value.decidedAt, $0.key) < ($1.value.decidedAt, $1.key) }
            for (key, _) in oldestFirst.prefix(entries.count - Self.maxEntries) { entries[key] = nil }
        }
        return entries.count != before
    }
}

enum Fingerprint {
    /// 64-bit FNV-1a as hex. Deterministic across launches and platforms (unlike `Hasher`).
    static func fnv1a(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --package-path Packages/TimeTugCore 2>&1 | tail -5`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/TimeTugCore
git commit -m "feat(core): DuplicateAdjudicator interface and verdict cache

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

### Task 5: Duplicate resolver

**Files:**
- Create: `Packages/TimeTugCore/Sources/TimeTugCore/Dedup/DuplicateResolver.swift`
- Test: `Packages/TimeTugCore/Tests/TimeTugCoreTests/DuplicateResolverTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1-4.
- Produces: `DuplicateResolution { events, pending: [AdjudicationRequest], candidates: [String: [CalendarEvent]], usedLessonKeys: Set<String> }`; `DuplicateResolver.resolve(events:calendars:lessons:verdicts:) -> DuplicateResolution` and `DuplicateResolver.maxGroupSize` (4). `verdicts == nil` means inference is off: ambiguous pairs stay separate and nothing is pending.

Per-pair order: (1) if `isCandidate` and a lesson exists, the lesson decides (`same` -> `.userConfirmed` merge, `different` -> blocked); (2) else `DuplicateRules.decide`; (3) for `.ambiguous` with `verdicts != nil`: cached `same` merges (`.inference`), cached `different` blocks, cached `unsure` leaves it alone, no entry makes it pending. Merge links are applied in index order; a merge is skipped if the combined group would exceed 4 or any cross pair is blocked (rules-separate, same calendar, `different` verdict or lesson). The richest copy (highest `detailScore`, ties earliest) is the primary; missing location, notes, url and conference URL are borrowed from the others. Group provenance: user > inference > rule.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import TimeTugCore

private let t0 = date("2026-09-18T09:00:00Z")
private let engine = EngineInfo(id: "test", displayName: "Test AI", isOnDevice: true)

private let doctor = makeEvent("1", title: "Scott: Doctor", minutes: 60, calendarID: "personal", others: 0)
private let official = makeEvent("2", title: "Intermountain Health", minutes: 60, calendarID: "work",
                                 location: "1234 Main St, Logan", notes: "Bring insurance card")
private let dance = makeEvent("3", title: "Kristin: Logan Dance", minutes: 60, calendarID: "personal", others: 0)

private func resolve(_ events: [CalendarEvent], lessons: LessonBook = LessonBook(),
                     verdicts: VerdictCache? = nil) -> DuplicateResolution {
    DuplicateResolver.resolve(events: events, calendars: [], lessons: lessons, verdicts: verdicts)
}

private func cache(answering answer: AdjudicationVerdict.Answer, for resolution: DuplicateResolution) -> VerdictCache {
    var cache = VerdictCache()
    for request in resolution.pending {
        cache.store(AdjudicationVerdict(requestID: request.id, answer: answer), engine: engine,
                    end: t0.addingTimeInterval(86_400), now: t0)
    }
    return cache
}

@Test func exactDuplicatesMergeWithRuleProvenanceAndKeepTheFirstOnATie() {
    let a = makeEvent("1", title: "Sync", calendarID: "family")
    let b = makeEvent("2", title: "sync", calendarID: "work")
    let result = resolve([a, b])
    #expect(result.events.count == 1)
    #expect(result.events[0].calendarKey == "fake/family")
    #expect(result.events[0].additionalCalendarKeys == ["fake/work"])
    #expect(result.events[0].mergeProvenance == .rule)
    #expect(result.events[0].mergedMembers.count == 2)
}

@Test func richerCopyBecomesPrimaryAndBorrowsMissingDetails() {
    let bare = makeEvent("1", title: "Sync", calendarID: "a")
    let rich = makeEvent("2", title: "Sync", calendarID: "b", notes: "Join https://acme.zoom.us/j/123")
    let merged = resolve([bare, rich]).events[0]
    #expect(merged.calendarKey == "fake/b")
    #expect(merged.additionalCalendarKeys == ["fake/a"])
}

@Test func ambiguousPairIsPendingWhenInferenceIsOnAndUnknown() {
    let result = resolve([doctor, official], verdicts: VerdictCache())
    #expect(result.events.count == 2)
    #expect(result.pending.count == 1)
    #expect(result.pending[0].first.title == "Intermountain Health")   // richer first
    #expect(result.pending[0].second.title == "Scott: Doctor")
}

@Test func rulesOnlyNeverProducesPending() {
    let result = resolve([doctor, official], verdicts: nil)
    #expect(result.events.count == 2)
    #expect(result.pending.isEmpty)
}

@Test func cachedSameVerdictMergesWithInferenceProvenance() {
    let verdicts = cache(answering: .same, for: resolve([doctor, official], verdicts: VerdictCache()))
    let result = resolve([doctor, official], verdicts: verdicts)
    #expect(result.events.count == 1)
    #expect(result.pending.isEmpty)
    let merged = result.events[0]
    #expect(merged.title == "Intermountain Health")
    #expect(merged.mergeProvenance == .inference(engineID: "test", engineName: "Test AI"))
    #expect(merged.additionalCalendarKeys == ["fake/personal"])
    #expect(merged.mergedMembers.map(\.title).sorted() == ["Intermountain Health", "Scott: Doctor"])
}

@Test func unsureAndDifferentVerdictsDoNotMerge() {
    for answer in [AdjudicationVerdict.Answer.unsure, .different] {
        let verdicts = cache(answering: answer, for: resolve([doctor, official], verdicts: VerdictCache()))
        let result = resolve([doctor, official], verdicts: verdicts)
        #expect(result.events.count == 2)
        #expect(result.pending.isEmpty)
    }
}

@Test func sameCalendarEventsAtTheSameTimeStaySeparate() {
    let result = resolve([doctor, dance], verdicts: VerdictCache())
    #expect(result.events.count == 2)
    #expect(result.pending.isEmpty)
}

@Test func lessonSameMergesEvenWithoutInferenceAndIsReported() {
    var lessons = LessonBook()
    lessons.record(MergedMember(doctor), MergedMember(official), decision: .same, now: t0)
    let result = resolve([doctor, official], lessons: lessons, verdicts: nil)
    #expect(result.events.count == 1)
    #expect(result.events[0].mergeProvenance == .userConfirmed)
    #expect(result.usedLessonKeys.count == 1)
}

@Test func lessonDifferentBeatsAStrongRuleAndOffersAManualMerge() {
    let zoom = "https://acme.zoom.us/j/9"
    let a = makeEvent("1", title: "Weekly", calendarID: "a", location: zoom)
    let b = makeEvent("2", title: "Team sync", calendarID: "b", location: zoom)
    #expect(resolve([a, b]).events.count == 1)
    var lessons = LessonBook()
    lessons.record(MergedMember(a), MergedMember(b), decision: .different, now: t0)
    let result = resolve([a, b], lessons: lessons)
    #expect(result.events.count == 2)
    #expect(result.candidates[a.id]?.map(\.id) == [b.id])
    #expect(result.candidates[b.id]?.map(\.id) == [a.id])
}

@Test func lessonSameStillRespectsTheTimeGate() {
    var lessons = LessonBook()
    let late = makeEvent("2", title: "Intermountain Health", start: "2026-09-18T15:00:00Z", minutes: 60, calendarID: "work")
    lessons.record(MergedMember(doctor), MergedMember(late), decision: .same, now: t0)
    #expect(resolve([doctor, late], lessons: lessons).events.count == 2)
}

@Test func mergeIsSkippedWhenAnyGroupMemberBlocksIt() {
    let zoom = "https://acme.zoom.us/j/9"
    let a = makeEvent("1", title: "One", calendarID: "a", location: zoom)
    let b = makeEvent("2", title: "Two", calendarID: "b", location: zoom)
    let c = makeEvent("3", title: "Three", calendarID: "a", location: zoom)   // same calendar as a
    let result = resolve([a, b, c])
    #expect(result.events.count == 2)
}

@Test func candidatesListSeparateLookAlikes() {
    let result = resolve([doctor, official], verdicts: nil)
    #expect(result.candidates[doctor.id]?.map(\.id) == [official.id])
    #expect(result.candidates[official.id]?.map(\.id) == [doctor.id])
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Packages/TimeTugCore --filter DuplicateResolver 2>&1 | tail -10`
Expected: compile error (`DuplicateResolver` not defined).

- [ ] **Step 3: Implement** `Dedup/DuplicateResolver.swift`:

```swift
import Foundation

public struct DuplicateResolution: Sendable {
    /// Merged events, sorted by start then title.
    public var events: [CalendarEvent]
    /// Ambiguous pairs still waiting for a model verdict.
    public var pending: [AdjudicationRequest]
    /// Event id -> look-alike events kept separate (for a manual "Merge").
    public var candidates: [String: [CalendarEvent]]
    /// Pair keys of the lessons that decided a pair, so the store can refresh their `lastUsed`.
    public var usedLessonKeys: Set<String>
}

/// Turns raw events from every source into merged events. Pure and synchronous; a model is only
/// consulted through verdicts already in `verdicts` (nil means inference is off).
public enum DuplicateResolver {
    public static let maxGroupSize = 4

    private struct Pair: Hashable {
        let low: Int, high: Int
        init(_ a: Int, _ b: Int) { low = min(a, b); high = max(a, b) }
    }

    private struct MergeLink { let i: Int, j: Int, why: MergeProvenance }

    public static func resolve(
        events: [CalendarEvent], calendars: [CalendarInfo], lessons: LessonBook, verdicts: VerdictCache?
    ) -> DuplicateResolution {
        let infoByKey = Dictionary(calendars.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var merges: [MergeLink] = []
        var blocked = Set<Pair>()
        var pendingPairs: [(i: Int, j: Int, request: AdjudicationRequest)] = []
        var usedLessonKeys = Set<String>()

        for i in events.indices {
            for j in events.indices where j > i {
                let a = events[i], b = events[j]
                if DuplicateRules.isCandidate(a, b), let lesson = lessons.decision(a, b) {
                    usedLessonKeys.insert(lesson.pairKey)
                    if lesson.decision == .same { merges.append(MergeLink(i: i, j: j, why: .userConfirmed)) }
                    else { blocked.insert(Pair(i, j)) }
                    continue
                }
                switch DuplicateRules.decide(a, b) {
                case .merge: merges.append(MergeLink(i: i, j: j, why: .rule))
                case .separate: blocked.insert(Pair(i, j))
                case .ambiguous:
                    guard let verdicts else { continue }
                    let request = makeRequest(a, b, infoByKey: infoByKey, lessons: lessons)
                    guard let entry = verdicts.entry(for: request.id) else {
                        pendingPairs.append((i, j, request))
                        continue
                    }
                    switch entry.answer {
                    case .same:
                        merges.append(MergeLink(i: i, j: j, why: .inference(engineID: entry.engine.id, engineName: entry.engine.displayName)))
                    case .different: blocked.insert(Pair(i, j))
                    case .unsure: break
                    }
                }
            }
        }

        // Union merge links conservatively: never past the size cap, never across a blocked pair.
        var groupOf = Array(events.indices)
        var members = Dictionary(uniqueKeysWithValues: events.indices.map { ($0, [$0]) })
        var provenance: [Int: [MergeProvenance]] = [:]
        for link in merges {
            let gi = groupOf[link.i], gj = groupOf[link.j]
            if gi == gj { provenance[gi, default: []].append(link.why); continue }
            let left = members[gi] ?? [], right = members[gj] ?? []
            guard left.count + right.count <= maxGroupSize,
                  !left.contains(where: { x in right.contains { y in blocked.contains(Pair(x, y)) } }) else { continue }
            members[gi] = left + right
            members[gj] = nil
            for k in right { groupOf[k] = gi }
            provenance[gi, default: []] += (provenance[gj] ?? []) + [link.why]
            provenance[gj] = nil
        }

        let groups = members.values.map { $0.sorted() }.sorted { $0[0] < $1[0] }
        var output: [CalendarEvent] = []
        var outputIndex = Array(repeating: 0, count: events.count)
        for group in groups {
            for k in group { outputIndex[k] = output.count }
            output.append(merged(group.map { events[$0] }, provenance: provenance[groupOf[group[0]]] ?? []))
        }

        var candidates: [String: [CalendarEvent]] = [:]
        for i in events.indices {
            for j in events.indices where j > i {
                let oi = outputIndex[i], oj = outputIndex[j]
                guard oi != oj, DuplicateRules.isCandidate(events[i], events[j]) else { continue }
                if !(candidates[output[oi].id] ?? []).contains(where: { $0.id == output[oj].id }) {
                    candidates[output[oi].id, default: []].append(output[oj])
                }
                if !(candidates[output[oj].id] ?? []).contains(where: { $0.id == output[oi].id }) {
                    candidates[output[oj].id, default: []].append(output[oi])
                }
            }
        }

        var seen = Set<String>()
        let pending = pendingPairs
            .filter { outputIndex[$0.i] != outputIndex[$0.j] && seen.insert($0.request.id).inserted }
            .map(\.request)

        return DuplicateResolution(
            events: output.sorted { ($0.start, $0.title) < ($1.start, $1.title) },
            pending: pending, candidates: candidates, usedLessonKeys: usedLessonKeys)
    }

    private static func merged(_ group: [CalendarEvent], provenance: [MergeProvenance]) -> CalendarEvent {
        guard group.count > 1 else { return group[0] }
        // The richest copy is the primary so the official title and details win; ties keep the earliest.
        let primaryIndex = group.indices.max { l, r in
            let sl = DuplicateRules.detailScore(group[l]), sr = DuplicateRules.detailScore(group[r])
            return sl != sr ? sl < sr : l > r
        }!
        var result = group[primaryIndex]
        for (index, other) in group.enumerated() where index != primaryIndex {
            if other.calendarKey != result.calendarKey { result.additionalCalendarKeys.insert(other.calendarKey) }
            result.location = result.location ?? other.location
            result.notes = result.notes ?? other.notes
            result.url = result.url ?? other.url
            result.conferenceURL = result.conferenceURL ?? other.conferenceURL
        }
        result.mergedMembers = group.map { MergedMember($0) }
        result.mergeProvenance = strongest(provenance)
        return result
    }

    /// User decisions outrank model verdicts, which outrank rules.
    private static func strongest(_ list: [MergeProvenance]) -> MergeProvenance {
        if list.contains(.userConfirmed) { return .userConfirmed }
        return list.first { if case .inference = $0 { return true } else { return false } } ?? .rule
    }

    private static func makeRequest(
        _ a: CalendarEvent, _ b: CalendarEvent, infoByKey: [String: CalendarInfo], lessons: LessonBook
    ) -> AdjudicationRequest {
        let (first, second) = DuplicateRules.detailScore(a) >= DuplicateRules.detailScore(b) ? (a, b) : (b, a)
        return AdjudicationRequest(
            id: fingerprint(a, b),
            first: AdjudicationEvent(first, calendar: infoByKey[first.calendarKey]),
            second: AdjudicationEvent(second, calendar: infoByKey[second.calendarKey]),
            lessons: lessons.relevant(to: a, b))
    }

    /// Order-independent digest of everything the judgment depends on; an edited event gets a new one.
    private static func fingerprint(_ a: CalendarEvent, _ b: CalendarEvent) -> String {
        func part(_ e: CalendarEvent) -> String {
            [DuplicateRules.normalize(e.title), String(Int(e.start.timeIntervalSince1970)), String(Int(e.end.timeIntervalSince1970)),
             e.calendarKey, DuplicateRules.normalizedLocation(e.location) ?? "",
             DuplicateRules.normalize(String((e.notes ?? "").prefix(AdjudicationEvent.maxNotesLength))),
             DuplicateRules.emails(e).sorted().joined(separator: ","), String(e.otherAttendeeCount)].joined(separator: "|")
        }
        return Fingerprint.fnv1a([part(a), part(b)].sorted().joined(separator: "##"))
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --package-path Packages/TimeTugCore 2>&1 | tail -5`
Expected: all pass. The `DuplicateRules.emails` and `normalizedLocation` helpers are internal (not private), which this file relies on.

- [ ] **Step 5: Commit**

```bash
git add Packages/TimeTugCore
git commit -m "feat(core): duplicate resolver with conservative grouping and provenance

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: CalendarStore integration

**Files:**
- Modify: `Packages/TimeTugCore/Sources/TimeTugCore/Store/CalendarStore.swift`
- Modify: `Packages/TimeTugCore/Tests/TimeTugCoreTests/CalendarStoreTests.swift` (existing tests must keep passing)
- Create: `Packages/TimeTugCore/Tests/TimeTugCoreTests/CalendarStoreInferenceTests.swift`

**Interfaces:**
- Consumes: Tasks 1-5.
- Produces on `CalendarSnapshot`: `candidates: [String: [CalendarEvent]]`. `InferenceStatus { .disabled, .noEngine, .unavailable(reason:), .notOnDevice, .active(EngineInfo) }`. `DedupState { lessons: LessonBook, verdicts: VerdictCache }` (Codable). On `CalendarStore`: `init(sources:calendar:adjudicator:)`; `setInferenceEnabled(_:now:) -> CalendarSnapshot`; `inferenceStatus() -> InferenceStatus`; `resolvePending(now:) async -> CalendarSnapshot?` (nil when nothing changed); `unmerge(_:now:) -> CalendarSnapshot`; `merge(_:_:now:) -> CalendarSnapshot`; `forgetLessons(now:) -> CalendarSnapshot`; `state() -> DedupState`; `load(_:)`.

- [ ] **Step 1: Write the failing tests**

Create `CalendarStoreInferenceTests.swift`:

```swift
import Foundation
import Testing
@testable import TimeTugCore

private let now = date("2026-09-18T09:00:00Z")

final class FakeAdjudicator: DuplicateAdjudicator, @unchecked Sendable {
    static let engine = EngineInfo(id: "fake-ai", displayName: "Fake AI", isOnDevice: true)
    let availability: AdjudicatorAvailability
    private let answer: AdjudicationVerdict.Answer
    private let lock = NSLock()
    private var seen: [AdjudicationRequest] = []

    init(availability: AdjudicatorAvailability = .available(FakeAdjudicator.engine), answer: AdjudicationVerdict.Answer = .same) {
        self.availability = availability
        self.answer = answer
    }

    var requests: [AdjudicationRequest] { lock.withLock { seen } }

    func judge(_ requests: [AdjudicationRequest]) async -> [AdjudicationVerdict] {
        lock.withLock { seen += requests }
        return requests.map { AdjudicationVerdict(requestID: $0.id, answer: answer) }
    }
}

private let doctor = makeEvent("1", title: "Scott: Doctor", minutes: 60, calendarID: "personal", others: 0)
private let official = makeEvent("2", title: "Intermountain Health", minutes: 60, calendarID: "work",
                                 location: "1234 Main St", notes: "Bring insurance card")

private func makeStore(_ adjudicator: FakeAdjudicator?) async -> CalendarStore {
    let source = FakeSource()
    await source.set(events: .success([doctor, official]))
    return CalendarStore(sources: [source], calendar: utcCalendar, adjudicator: adjudicator)
}

@Test func inferenceIsOffByDefaultAndTheEngineIsNeverCalled() async {
    let engine = FakeAdjudicator()
    let store = await makeStore(engine)
    #expect(await store.inferenceStatus() == .disabled)
    #expect(await store.refresh(now: now, leadTime: 60).events.count == 2)
    #expect(await store.resolvePending(now: now) == nil)
    #expect(engine.requests.isEmpty)
}

@Test func enabledEngineMergesAfterResolvePendingWithoutBlockingRefresh() async {
    let engine = FakeAdjudicator()
    let store = await makeStore(engine)
    _ = await store.setInferenceEnabled(true, now: now)
    #expect(await store.refresh(now: now, leadTime: 60).events.count == 2)   // refresh never waits on the model
    let merged = await store.resolvePending(now: now)
    #expect(merged?.events.count == 1)
    #expect(merged?.events.first?.mergeProvenance == .inference(engineID: "fake-ai", engineName: "Fake AI"))
    #expect(engine.requests.count == 1)
    #expect(await store.resolvePending(now: now) == nil)                       // cached: no second call
    #expect(await store.refresh(now: now, leadTime: 60).events.count == 1)     // cache applied on refresh
}

@Test func unavailableOrOffDeviceEnginesFallBackToRulesOnly() async {
    let unavailable = FakeAdjudicator(availability: .unavailable(reason: "not eligible"))
    var store = await makeStore(unavailable)
    _ = await store.setInferenceEnabled(true, now: now)
    _ = await store.refresh(now: now, leadTime: 60)
    #expect(await store.inferenceStatus() == .unavailable(reason: "not eligible"))
    #expect(await store.resolvePending(now: now) == nil)
    #expect(unavailable.requests.isEmpty)

    let cloud = FakeAdjudicator(availability: .available(EngineInfo(id: "cloud", displayName: "Cloud", isOnDevice: false)))
    store = await makeStore(cloud)
    _ = await store.setInferenceEnabled(true, now: now)
    _ = await store.refresh(now: now, leadTime: 60)
    #expect(await store.inferenceStatus() == .notOnDevice)
    #expect(await store.resolvePending(now: now) == nil)
    #expect(cloud.requests.isEmpty)

    let none = await makeStore(nil)
    _ = await none.setInferenceEnabled(true, now: now)
    #expect(await none.inferenceStatus() == .noEngine)
}

@Test func turningInferenceOffIgnoresCachedVerdicts() async {
    let store = await makeStore(FakeAdjudicator())
    _ = await store.setInferenceEnabled(true, now: now)
    _ = await store.refresh(now: now, leadTime: 60)
    _ = await store.resolvePending(now: now)
    #expect(await store.setInferenceEnabled(false, now: now).events.count == 2)
}

@Test func unmergeSplitsAndRemembersAndManualMergeJoinsAgain() async {
    let store = await makeStore(FakeAdjudicator())
    _ = await store.setInferenceEnabled(true, now: now)
    _ = await store.refresh(now: now, leadTime: 60)
    let merged = await store.resolvePending(now: now)!.events[0]

    let split = await store.unmerge(merged, now: now)
    #expect(split.events.count == 2)
    #expect(await store.state().lessons.lessons.first?.decision == .different)
    #expect(await store.refresh(now: now, leadTime: 60).events.count == 2)     // survives refresh, engine not re-asked

    let a = split.events.first { $0.title == "Scott: Doctor" }!
    let b = split.events.first { $0.title == "Intermountain Health" }!
    let joined = await store.merge(a, b, now: now)
    #expect(joined.events.count == 1)
    #expect(joined.events[0].mergeProvenance == .userConfirmed)
}

@Test func lessonsWorkWithInferenceOffAndCanBeForgotten() async {
    let store = await makeStore(nil)
    let snapshot = await store.refresh(now: now, leadTime: 60)
    let joined = await store.merge(snapshot.events[0], snapshot.events[1], now: now)
    #expect(joined.events.count == 1)
    #expect(await store.forgetLessons(now: now).events.count == 2)
}

@Test func stateRoundTripsThroughLoad() async {
    let store = await makeStore(FakeAdjudicator())
    let snapshot = await store.refresh(now: now, leadTime: 60)
    _ = await store.merge(snapshot.events[0], snapshot.events[1], now: now)
    let state = await store.state()

    let fresh = await makeStore(nil)
    await fresh.load(state)
    #expect(await fresh.refresh(now: now, leadTime: 60).events.count == 1)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Packages/TimeTugCore --filter CalendarStoreInference 2>&1 | tail -10`
Expected: compile errors (`adjudicator:` argument, `setInferenceEnabled` missing).

- [ ] **Step 3: Implement.** In `CalendarStore.swift`:

Add to `CalendarSnapshot` an explicit initializer and the `candidates` field (replace the implicit memberwise use in `.empty`):

```swift
    /// Look-alike events kept separate (event id -> other events), for a manual "Merge".
    public let candidates: [String: [CalendarEvent]]

    public init(events: [CalendarEvent], calendars: [CalendarInfo], statuses: [String: SourceStatus],
                sourceNames: [String: String], fetchedAt: Date, candidates: [String: [CalendarEvent]] = [:]) {
        self.events = events
        self.calendars = calendars
        self.statuses = statuses
        self.sourceNames = sourceNames
        self.fetchedAt = fetchedAt
        self.candidates = candidates
    }
```

Add above the actor:

```swift
public enum InferenceStatus: Equatable, Sendable {
    case disabled
    case noEngine
    case unavailable(reason: String)
    case notOnDevice
    case active(EngineInfo)
}

/// What the app persists between launches so decisions and verdicts survive a relaunch.
public struct DedupState: Codable, Equatable, Sendable {
    public var lessons: LessonBook
    public var verdicts: VerdictCache
    public init(lessons: LessonBook = LessonBook(), verdicts: VerdictCache = VerdictCache()) {
        self.lessons = lessons
        self.verdicts = verdicts
    }
}
```

In the actor add state and change the initializer:

```swift
    private static let maxPendingPerPass = 20
    private let adjudicator: (any DuplicateAdjudicator)?
    private var inferenceEnabled = false
    private var lessons = LessonBook()
    private var verdicts = VerdictCache()
    private var pending: [AdjudicationRequest] = []
    private var lastWindow: DateInterval?

    public init(sources: [any CalendarSource], calendar: Calendar = .current,
                adjudicator: (any DuplicateAdjudicator)? = nil) {
        self.sources = sources
        self.calendar = calendar
        self.adjudicator = adjudicator
    }
```

In `refresh`, after the `for (sourceID, result) in results` loop, replace the `return CalendarSnapshot(...)` with:

```swift
        lastWindow = window
        return makeSnapshot(now: now)
```

Delete `merged(within:)` and add:

```swift
    private var activeEngine: EngineInfo? {
        guard inferenceEnabled, let adjudicator, case .available(let engine) = adjudicator.availability,
              engine.isOnDevice else { return nil }
        return engine
    }

    public func inferenceStatus() -> InferenceStatus {
        guard inferenceEnabled else { return .disabled }
        guard let adjudicator else { return .noEngine }
        switch adjudicator.availability {
        case .unavailable(let reason): return .unavailable(reason: reason)
        case .available(let engine): return engine.isOnDevice ? .active(engine) : .notOnDevice
        }
    }

    public func setInferenceEnabled(_ enabled: Bool, now: Date) -> CalendarSnapshot {
        inferenceEnabled = enabled
        return makeSnapshot(now: now)
    }

    /// Asks the engine about the pairs still waiting for a verdict (one bounded pass). Returns a new
    /// snapshot only when a verdict was recorded; call again until nil to drain a backlog.
    public func resolvePending(now: Date) async -> CalendarSnapshot? {
        guard let adjudicator, let engine = activeEngine, !pending.isEmpty else { return nil }
        let batch = Array(pending.prefix(Self.maxPendingPerPass))
        let returned = await adjudicator.judge(batch)
        let byID = Dictionary(batch.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = false
        for verdict in returned {
            guard let request = byID[verdict.requestID] else { continue }
            verdicts.store(verdict, engine: engine, end: max(request.first.end, request.second.end), now: now)
            changed = true
        }
        guard changed else { return nil }
        verdicts.prune(now: now)
        return makeSnapshot(now: now)
    }

    /// The user says this merged event is not one meeting: remember every cross-calendar pair in it.
    public func unmerge(_ event: CalendarEvent, now: Date) -> CalendarSnapshot {
        let parts = event.participants
        for (index, a) in parts.enumerated() {
            for b in parts[(index + 1)...] { lessons.record(a, b, decision: .different, now: now) }
        }
        return makeSnapshot(now: now)
    }

    /// The user says these two displayed events are one meeting.
    public func merge(_ a: CalendarEvent, _ b: CalendarEvent, now: Date) -> CalendarSnapshot {
        for x in a.participants { for y in b.participants { lessons.record(x, y, decision: .same, now: now) } }
        return makeSnapshot(now: now)
    }

    public func forgetLessons(now: Date) -> CalendarSnapshot {
        lessons = LessonBook()
        return makeSnapshot(now: now)
    }

    public func state() -> DedupState { DedupState(lessons: lessons, verdicts: verdicts) }

    public func load(_ state: DedupState) {
        lessons = state.lessons
        verdicts = state.verdicts
    }

    private func makeSnapshot(now: Date) -> CalendarSnapshot {
        let window = lastWindow ?? DateInterval(start: now, duration: 0)
        let calendars = sources.flatMap { lastCalendars[$0.id] ?? [] }
        let raw = sources.flatMap { source in
            (lastEvents[source.id] ?? []).filter { $0.end > window.start && $0.start < window.end }
        }
        var resolution = DuplicateResolver.resolve(
            events: raw, calendars: calendars, lessons: lessons, verdicts: activeEngine == nil ? nil : verdicts)
        lessons.touch(resolution.usedLessonKeys, now: now)
        pending = resolution.pending
        for index in resolution.events.indices where resolution.events[index].conferenceURL == nil {
            resolution.events[index].conferenceURL = ConferenceLinkDetector.detect(
                location: resolution.events[index].location, url: resolution.events[index].url,
                notes: resolution.events[index].notes)
        }
        return CalendarSnapshot(
            events: resolution.events, calendars: calendars, statuses: statuses,
            sourceNames: Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.displayName) }),
            fetchedAt: now, candidates: resolution.candidates)
    }
```

- [ ] **Step 4: Run all Core tests**

Run: `swift test --package-path Packages/TimeTugCore 2>&1 | tail -8`
Expected: all pass, including the pre-existing `CalendarStoreTests` (`duplicateKeepsFirstCopyButRecordsOtherCalendarKeys` and `duplicateFillsMissingFieldsFromLaterCopy` still hold: ties keep the first copy, the richer copy borrows details).

- [ ] **Step 5: Commit**

```bash
git add Packages/TimeTugCore
git commit -m "feat(core): resolver-backed CalendarStore with async pending verdicts and decisions

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

### Task 7: EventKit attendee, organizer and UID data

**Files:**
- Modify: `Packages/EventKitSource/Sources/EventKitSource/EventKitSource.swift` (the `map(_:)` function)

**Interfaces:**
- Consumes: `Attendee`, `Attendee.email(fromMailto:)` (Task 1). Parsing is already unit-tested in Core; EventKit types cannot be constructed in tests, so this task is verified by building and by the manual checklist.
- Produces: events carrying `attendees` (other people only; the current user is excluded because they appear on every copy and prove nothing), `organizerEmail` (nil when the organizer is the current user), `externalUID` (`calendarItemExternalIdentifier`).

- [ ] **Step 1: Implement.** In `map(_:)` add three arguments to the `CalendarEvent(...)` call, after `conferenceURL: nil`:

```swift
            conferenceURL: nil,   // CalendarStore fills this from location/url/notes
            attendees: attendees.filter { !$0.isCurrentUser }.map {
                Attendee(name: $0.name, email: Attendee.email(fromMailto: $0.url.absoluteString))
            },
            organizerEmail: event.organizer.flatMap {
                $0.isCurrentUser ? nil : Attendee.email(fromMailto: $0.url.absoluteString)
            },
            externalUID: event.calendarItemExternalIdentifier
```

(Remove the existing trailing comment on the `conferenceURL: nil` line so the comma placement is valid.) Emails are often absent, notably on iCloud calendars; `Attendee.email` returns nil for non-`mailto:` URLs and the rules degrade gracefully.

- [ ] **Step 2: Build**

Run: `swift build --package-path Packages/EventKitSource 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/EventKitSource
git commit -m "feat(eventkit): supply attendees, organizer and external UID for duplicate rules

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: AppleIntelligenceInference package

**Files:**
- Create: `Packages/AppleIntelligenceInference/Package.swift`
- Create: `Packages/AppleIntelligenceInference/Sources/AppleIntelligenceInference/PromptBuilder.swift`
- Create: `Packages/AppleIntelligenceInference/Sources/AppleIntelligenceInference/AppleIntelligence.swift`
- Test: `Packages/AppleIntelligenceInference/Tests/AppleIntelligenceInferenceTests/PromptBuilderTests.swift`

**Interfaces:**
- Consumes: `AdjudicationRequest`, `AdjudicationEvent`, `Lesson`, `DuplicateAdjudicator`, `EngineInfo`, `AdjudicatorAvailability`, `AdjudicationVerdict`.
- Produces: `PromptBuilder.instructions: String`, `PromptBuilder.prompt(for:timeZone:) -> String`; `AppleIntelligence.makeAdjudicator() -> (any DuplicateAdjudicator)?` (nil when the SDK or OS has no on-device Apple model API). The Foundation Models code compiles only where `FoundationModels` exists and runs only on macOS 26+.

- [ ] **Step 1: Create the package manifest** `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppleIntelligenceInference",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AppleIntelligenceInference", targets: ["AppleIntelligenceInference"])],
    dependencies: [.package(path: "../TimeTugCore")],
    targets: [
        .target(
            name: "AppleIntelligenceInference",
            dependencies: [.product(name: "TimeTugCore", package: "TimeTugCore")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AppleIntelligenceInferenceTests",
            dependencies: ["AppleIntelligenceInference", .product(name: "TimeTugCore", package: "TimeTugCore")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

- [ ] **Step 2: Write the failing prompt tests** `PromptBuilderTests.swift`:

```swift
import Foundation
import Testing
import TimeTugCore
@testable import AppleIntelligenceInference

private func event(_ title: String, location: String? = nil, notes: String? = nil,
                   calendar: String? = nil, account: String? = nil, names: [String] = []) -> AdjudicationEvent {
    var info: CalendarInfo?
    if let calendar { info = CalendarInfo(sourceID: "s", calendarID: "c", title: calendar, accountName: account) }
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let source = CalendarEvent(
        sourceEventID: "1", sourceID: "s", calendarID: "c", title: title, start: start,
        end: start.addingTimeInterval(3600), location: location, notes: notes,
        attendees: names.map { Attendee(name: $0, email: "\($0)@example.com") })
    return AdjudicationEvent(source, calendar: info)
}

private func request(lessons: [Lesson] = []) -> AdjudicationRequest {
    AdjudicationRequest(
        id: "r1",
        first: event("Intermountain Health", location: "1234 Main St", notes: "Bring card", calendar: "Work", account: "Exchange", names: ["Dr Lee"]),
        second: event("Scott: Doctor", calendar: "Personal", account: "iCloud"),
        lessons: lessons)
}

@Test func promptListsBothEntriesWithTheirDetails() {
    let prompt = PromptBuilder.prompt(for: request(), timeZone: TimeZone(identifier: "UTC")!)
    #expect(prompt.contains("Intermountain Health"))
    #expect(prompt.contains("Scott: Doctor"))
    #expect(prompt.contains("1234 Main St"))
    #expect(prompt.contains("Bring card"))
    #expect(prompt.contains("Work (Exchange)"))
    #expect(prompt.contains("Dr Lee"))
}

@Test func promptNeverContainsEmailAddresses() {
    let prompt = PromptBuilder.prompt(for: request(), timeZone: TimeZone(identifier: "UTC")!)
    #expect(!prompt.contains("@"))
}

@Test func promptOmitsMissingFieldsAndLessonsSectionWhenEmpty() {
    let prompt = PromptBuilder.prompt(for: request(), timeZone: TimeZone(identifier: "UTC")!)
    #expect(!prompt.contains("Earlier corrections"))
    #expect(prompt.components(separatedBy: "Location:").count == 2)   // only the first entry has one
}

@Test func promptIncludesLessonsAsOneLineEach() {
    var book = LessonBook()
    book.record(MergedMember(title: "Doctor", calendarKey: "s/a", contentKey: "k1", details: "bare"),
                MergedMember(title: "Clinic", calendarKey: "s/b", contentKey: "k2", details: "location"),
                decision: .same, now: Date(timeIntervalSince1970: 1_800_000_000))
    let prompt = PromptBuilder.prompt(for: request(lessons: book.lessons), timeZone: TimeZone(identifier: "UTC")!)
    #expect(prompt.contains("Earlier corrections"))
    #expect(prompt.contains("\"clinic\""))
    #expect(prompt.contains("the same appointment"))
}

@Test func instructionsAskForAConservativeAnswer() {
    #expect(PromptBuilder.instructions.contains("unsure"))
    #expect(PromptBuilder.instructions.contains("different people"))
}
```

- [ ] **Step 3: Run to verify failure**

Run: `swift test --package-path Packages/AppleIntelligenceInference 2>&1 | tail -8`
Expected: compile error (`PromptBuilder` not defined).

- [ ] **Step 4: Implement** `PromptBuilder.swift`:

```swift
import Foundation
import TimeTugCore

/// Builds the text the on-device model sees. Pure, so it is fully testable. Titles, times, place,
/// attendee names, calendar names and truncated notes only: Core already removed emails.
public enum PromptBuilder {
    public static let instructions = """
    You compare two calendar entries that come from different calendars and decide whether they \
    describe the same real-world appointment. Entries about different people or different places \
    are different appointments even at the same time. A short personal placeholder such as \
    "Scott: Doctor" can be the same appointment as a detailed entry such as "Intermountain Health" \
    when the details fit. If you cannot tell, answer unsure. Answer with exactly one word: same, \
    different or unsure.
    """

    public static func prompt(for request: AdjudicationRequest, timeZone: TimeZone = .current) -> String {
        var lines: [String] = []
        if !request.lessons.isEmpty {
            lines.append("Earlier corrections by the user (learn from them):")
            lines += request.lessons.map { "- " + describe($0) }
            lines.append("")
        }
        lines.append("Entry A (more detail):")
        lines += describe(request.first, timeZone: timeZone)
        lines.append("")
        lines.append("Entry B:")
        lines += describe(request.second, timeZone: timeZone)
        lines.append("")
        lines.append("Are A and B the same appointment? Answer same, different or unsure.")
        return lines.joined(separator: "\n")
    }

    private static func describe(_ event: AdjudicationEvent, timeZone: TimeZone) -> [String] {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = timeZone
        day.dateFormat = "yyyy-MM-dd HH:mm"
        let clock = DateFormatter()
        clock.locale = day.locale
        clock.timeZone = timeZone
        clock.dateFormat = "HH:mm"

        var lines = ["  Title: \(event.title)", "  Time: \(day.string(from: event.start)) to \(clock.string(from: event.end))"]
        if let calendar = event.calendarTitle {
            lines.append("  Calendar: " + [calendar, event.accountName.map { "(\($0))" }].compactMap { $0 }.joined(separator: " "))
        }
        if let location = event.location, !location.isEmpty { lines.append("  Location: \(location)") }
        if !event.attendeeNames.isEmpty { lines.append("  Attendees: " + event.attendeeNames.joined(separator: ", ")) }
        if let notes = event.notes, !notes.isEmpty { lines.append("  Notes: \(notes)") }
        return lines
    }

    private static func describe(_ lesson: Lesson) -> String {
        let verdict = lesson.decision == .same ? "the same appointment" : "different appointments"
        return "\"\(lesson.titleA)\" (\(lesson.signalsA)) and \"\(lesson.titleB)\" (\(lesson.signalsB)) were \(verdict)"
    }
}
```

- [ ] **Step 5: Run the prompt tests**

Run: `swift test --package-path Packages/AppleIntelligenceInference 2>&1 | tail -8`
Expected: 5 tests pass. (The "Dr Lee" attendee name contains no `@`; the email `Dr Lee@example.com` exists only on the source event and never reaches `AdjudicationEvent`.)

- [ ] **Step 6: Implement the adapter** `AppleIntelligence.swift`:

```swift
import Foundation
import OSLog
import TimeTugCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The one entry point the app calls.
public enum AppleIntelligence {
    /// nil when this SDK or OS has no on-device Apple model API. A non-nil adjudicator can still report
    /// `.unavailable` (Apple Intelligence off, unsupported hardware, model not ready).
    public static func makeAdjudicator() -> (any DuplicateAdjudicator)? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return FoundationModelsAdjudicator() }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct DuplicateJudgement {
    @Guide(description: "same if both entries are one real-world appointment, different if they are separate, unsure if you cannot tell",
           .anyOf(["same", "different", "unsure"]))
    var answer: String
}

@available(macOS 26.0, *)
struct FoundationModelsAdjudicator: DuplicateAdjudicator {
    static let engine = EngineInfo(id: "apple-intelligence", displayName: "Apple Intelligence", isOnDevice: true)
    private static let log = Logger(subsystem: "com.timetug.app", category: "dedup")

    var availability: AdjudicatorAvailability {
        switch SystemLanguageModel.default.availability {
        case .available: return .available(Self.engine)
        case .unavailable(let reason): return .unavailable(reason: String(describing: reason))
        }
    }

    func judge(_ requests: [AdjudicationRequest]) async -> [AdjudicationVerdict] {
        var verdicts: [AdjudicationVerdict] = []
        for request in requests {
            do {
                let session = LanguageModelSession(instructions: PromptBuilder.instructions)
                let response = try await session.respond(
                    to: PromptBuilder.prompt(for: request), generating: DuplicateJudgement.self,
                    options: GenerationOptions(temperature: 0))
                guard let answer = AdjudicationVerdict.Answer(rawValue: response.content.answer) else {
                    Self.log.error("Unexpected answer from the on-device model")
                    continue
                }
                verdicts.append(AdjudicationVerdict(requestID: request.id, answer: answer))
            } catch {
                // No verdict is cached, so the pair is retried on a later refresh. Titles are not logged.
                Self.log.error("On-device judgment failed: \(String(describing: error), privacy: .public)")
            }
        }
        return verdicts
    }
}
#endif
```

- [ ] **Step 7: Build and test against the installed SDK**

Run: `swift build --package-path Packages/AppleIntelligenceInference 2>&1 | tail -15 && swift test --package-path Packages/AppleIntelligenceInference 2>&1 | tail -5`
Expected: `Build complete!` and the prompt tests pass. Foundation Models is a new API: if the compiler rejects `@Guide(..., .anyOf(...))`, `GenerationOptions(temperature:)` or the `availability` cases, adjust to the installed SDK's exact spelling (check `SystemLanguageModel` and `LanguageModelSession` in the SDK's `FoundationModels.swiftinterface`); keep the behavior identical (one-word answer constrained to same/different/unsure, temperature 0, `.available` only when the model is ready).

- [ ] **Step 8: Commit**

```bash
git add Packages/AppleIntelligenceInference
git commit -m "feat: AppleIntelligenceInference package with prompt builder and Foundation Models adapter

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

### Task 9: App settings, persistence and status text

**Files:**
- Modify: `Apps/macOS/Sources/SettingsStore.swift`, `Apps/macOS/Sources/SettingsSearch.swift`, `Apps/macOS/Sources/AppModel.swift`
- Create: `Apps/macOS/Sources/DedupStateStore.swift`, `Apps/macOS/Sources/InferenceStatusText.swift`, `Apps/macOS/Sources/BetaBadge.swift`
- Test: `Apps/macOS/Tests/SettingsStoreTests.swift`, `Apps/macOS/Tests/SettingsSearchTests.swift`, create `Apps/macOS/Tests/DedupStateStoreTests.swift`, `Apps/macOS/Tests/InferenceStatusTextTests.swift`

**Interfaces:**
- Consumes: `DedupState`, `InferenceStatus` (Task 6).
- Produces: `SettingsStore.inferenceEnabled: Bool` (default false, key `dedupInference.v1`); `SettingsText.dedupInference`; catalog item id `dedup-inference` (pane `.calendars`); `DedupStateStore(url:)` with `load() -> DedupState`, `save(_:) -> Bool`, `defaultURL`; `InferenceStatusText.make(_:) -> String?`; `BetaBadge` view; `AppModel.inferenceStatus: InferenceStatus`, `AppModel.candidates: [String: [CalendarEvent]]`.

- [ ] **Step 1: Write the failing tests**

Append to `SettingsStoreTests.swift` (inside the class):

```swift
    func testInferenceIsOffByDefaultAndPersists() {
        let defaults = freshDefaults()
        XCTAssertFalse(SettingsStore(defaults: defaults).inferenceEnabled)
        SettingsStore(defaults: defaults).inferenceEnabled = true
        XCTAssertTrue(SettingsStore(defaults: defaults).inferenceEnabled)
        XCTAssertEqual(defaults.object(forKey: "dedupInference.v1") as? Bool, true)
    }
```

Append to `SettingsSearchTests.swift` (inside the class):

```swift
    func testDedupInferenceLivesInCalendarsAndIsFoundByAliases() {
        XCTAssertEqual(SettingsSearch.catalog.first { $0.id == "dedup-inference" }?.pane, .calendars)
        for query in ["duplicate", "merge", "apple intelligence", "beta"] {
            XCTAssertTrue(SettingsSearch.results(for: query, calendars: []).contains { $0.id == "dedup-inference" }, query)
        }
    }
```

Create `DedupStateStoreTests.swift`:

```swift
import TimeTugCore
import XCTest
@testable import TimeTug

final class DedupStateStoreTests: XCTestCase {
    private func tempURL() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TimeTugTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.appendingPathComponent("nested/dedup-state.json")
    }

    func testDefaultLocationIsApplicationSupportTimeTug() {
        let url = DedupStateStore.defaultURL
        XCTAssertEqual(url.lastPathComponent, "dedup-state.json")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "TimeTug")
    }

    func testMissingFileLoadsEmptyState() {
        XCTAssertEqual(DedupStateStore(url: tempURL()).load(), DedupState())
    }

    func testRoundTripsLessonsAndVerdicts() {
        let store = DedupStateStore(url: tempURL())
        var state = DedupState()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        state.lessons.record(MergedMember(title: "A", calendarKey: "s/x", contentKey: "k1", details: "bare"),
                             MergedMember(title: "B", calendarKey: "s/y", contentKey: "k2", details: "bare"),
                             decision: .same, now: now)
        state.verdicts.store(AdjudicationVerdict(requestID: "r", answer: .same),
                             engine: EngineInfo(id: "e", displayName: "E", isOnDevice: true),
                             end: now.addingTimeInterval(3600), now: now)
        XCTAssertTrue(store.save(state))
        XCTAssertEqual(store.load(), state)
    }

    func testCorruptFileLoadsEmptyState() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        XCTAssertEqual(DedupStateStore(url: url).load(), DedupState())
    }
}
```

Create `InferenceStatusTextTests.swift`:

```swift
import TimeTugCore
import XCTest
@testable import TimeTug

final class InferenceStatusTextTests: XCTestCase {
    func testOffShowsNothing() {
        XCTAssertNil(InferenceStatusText.make(.disabled))
    }

    func testActiveNamesTheEngine() {
        let engine = EngineInfo(id: "apple-intelligence", displayName: "Apple Intelligence", isOnDevice: true)
        XCTAssertEqual(InferenceStatusText.make(.active(engine)), "Using Apple Intelligence.")
    }

    func testEveryFallbackSaysRulesOnly() {
        for status in [InferenceStatus.noEngine, .unavailable(reason: "not eligible"), .notOnDevice] {
            XCTAssertTrue(InferenceStatusText.make(status)?.contains("rules only") == true, "\(status)")
        }
        XCTAssertTrue(InferenceStatusText.make(.unavailable(reason: "not eligible"))?.contains("not eligible") == true)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodegen generate --spec Apps/macOS/project.yml && xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test 2>&1 | grep -E "error:|Test Suite.*failed|TEST" | head`
Expected: compile errors (`inferenceEnabled`, `DedupStateStore`, `InferenceStatusText` missing).

- [ ] **Step 3: Implement**

`SettingsStore.swift`: add `private static let inferenceKey = "dedupInference.v1"`, and

```swift
    @Published var inferenceEnabled: Bool {
        didSet { defaults.set(inferenceEnabled, forKey: Self.inferenceKey) }
    }
```

and in `init` (after `popupCardStyle`): `self.inferenceEnabled = defaults.bool(forKey: Self.inferenceKey)` (absent key reads as false: opt-in).

`SettingsSearch.swift`: add `static let dedupInference = "Find duplicates with on-device intelligence"` to `SettingsText`, and this catalog entry after `skip-all-day`:

```swift
        .init(id: "dedup-inference", title: SettingsText.dedupInference,
              keywords: ["duplicate", "duplicates", "merge", "merged", "same meeting", "ai", "apple intelligence", "on-device", "beta", "inference"], pane: .calendars),
```

`AppModel.swift`: add

```swift
    /// State of the optional on-device duplicate finder, for the Calendars pane.
    @Published var inferenceStatus: InferenceStatus = .disabled
    /// Look-alike events kept separate (event id -> others), for the popup's manual "Merge".
    @Published var candidates: [String: [CalendarEvent]] = [:]
```

Create `InferenceStatusText.swift`:

```swift
import TimeTugCore

/// Words for the state of the on-device duplicate finder. nil means show nothing.
enum InferenceStatusText {
    static func make(_ status: InferenceStatus) -> String? {
        switch status {
        case .disabled: nil
        case .noEngine: "No on-device model is available on this Mac. Using rules only."
        case .unavailable(let reason): "The on-device model isn't available (\(reason)). Using rules only."
        case .notOnDevice: "That engine doesn't run on your device, so it isn't used. Using rules only."
        case .active(let engine): "Using \(engine.displayName)."
        }
    }
}
```

Create `BetaBadge.swift`:

```swift
import SwiftUI

/// Small "Beta" capsule shown next to experimental settings.
struct BetaBadge: View {
    var body: some View {
        Text("Beta")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Color.orange.opacity(0.15), in: Capsule())
            .accessibilityLabel("Beta feature")
    }
}
```

Create `DedupStateStore.swift` (same shape as `LedgerStore`, its own logger):

```swift
import Foundation
import OSLog
import TimeTugCore

/// Persists lessons and model verdicts as JSON so corrections survive a relaunch.
struct DedupStateStore {
    let url: URL
    private static let log = Logger(subsystem: "com.timetug.app", category: "dedup")

    /// `~/Library/Application Support/TimeTug/dedup-state.json`
    static var defaultURL: URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("TimeTug", isDirectory: true).appendingPathComponent("dedup-state.json")
    }

    init(url: URL = DedupStateStore.defaultURL) { self.url = url }

    /// Empty state for a missing or unreadable file (corruption is logged, never fatal).
    func load() -> DedupState {
        guard FileManager.default.fileExists(atPath: url.path) else { return DedupState() }
        do {
            return try JSONDecoder().decode(DedupState.self, from: Data(contentsOf: url))
        } catch {
            Self.log.error("Could not read dedup state: \(String(describing: error), privacy: .public)")
            return DedupState()
        }
    }

    /// False (and logged) when the file could not be written.
    @discardableResult
    func save(_ state: DedupState) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
            return true
        } catch {
            Self.log.error("Could not save dedup state: \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
```

- [ ] **Step 4: Run app tests**

Run: `xcodegen generate --spec Apps/macOS/project.yml && xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test 2>&1 | grep -E "error:|failed|Executed|TEST (SUCCEEDED|FAILED)" | tail -5`
Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Apps/macOS
git commit -m "feat(app): opt-in inference setting, persisted dedup state and status text

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 10: Settings UI and coordinator wiring

**Files:**
- Modify: `Apps/macOS/project.yml`, `Apps/macOS/Sources/CalendarsPane.swift`, `Apps/macOS/Sources/SettingsView.swift`, `Apps/macOS/Sources/AppCoordinator.swift`

**Interfaces:**
- Consumes: Tasks 6, 8, 9.
- Produces: the Beta toggle and status line in Calendars; `AppCoordinator.unmerge(_:)`, `AppCoordinator.merge(_:_:)` (used by Task 11); background resolution after each refresh; persistence after every state change.

No new pure logic lives here (it is UI and wiring over tested pieces), so verification is the app build, the existing app tests and the manual checklist (Task 12).

- [ ] **Step 1: Add the package to the app.** In `Apps/macOS/project.yml` add under `packages:`:

```yaml
  AppleIntelligenceInference:
    path: ../../Packages/AppleIntelligenceInference
```

and under `TimeTug: dependencies:`:

```yaml
      - package: AppleIntelligenceInference
        product: AppleIntelligenceInference
```

- [ ] **Step 2: Calendars pane control.** In `CalendarsPane.swift` add a property `let onForgetCorrections: () -> Void`, insert `duplicatesControl` in the body right after the `skipAllDay` toggle line, and add:

```swift
    private var duplicatesControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Toggle(SettingsText.dedupInference, isOn: $settings.inferenceEnabled)
                BetaBadge()
                Spacer(minLength: 0)
            }
            if let status = InferenceStatusText.make(model.inferenceStatus) {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
            Text("Off by default. Duplicates with matching details are always merged. When this is on, your Mac's on-device model also compares events with different titles. Nothing leaves your Mac.")
                .font(.footnote).foregroundStyle(.secondary)
            Button("Forget learned corrections", action: onForgetCorrections)
                .buttonStyle(.link).font(.footnote)
        }
        .settingsHighlight("dedup-inference", navigation: navigation)
    }
```

In `SettingsView.swift` add `let onForgetCorrections: () -> Void` after `onTestTug` and pass it: `CalendarsPane(settings: settings, model: model, navigation: navigation, onForgetCorrections: onForgetCorrections)`.

- [ ] **Step 3: Coordinator wiring.** In `AppCoordinator.swift`:

Add `import AppleIntelligenceInference` and properties:

```swift
    private let dedupStore = DedupStateStore()
```

Change `SettingsView(...)` construction to add `onForgetCorrections: { [weak self] in self?.forgetCorrections() }`.

Change the store construction in `init`:

```swift
        store = CalendarStore(sources: [eventKit], adjudicator: AppleIntelligence.makeAdjudicator())
```

In `start()`, before `await refresh()`, add:

```swift
        await store.load(dedupStore.load())
        _ = await store.setInferenceEnabled(settings.inferenceEnabled, now: Date())
        settings.$inferenceEnabled.dropFirst().sink { [weak self] enabled in
            Task { @MainActor in await self?.setInference(enabled) }
        }.store(in: &cancellables)
```

Split `refresh()` so applying a snapshot is reusable. Replace the first lines of `refresh()`:

```swift
    func refresh() async {
        apply(await store.refresh(now: Date(), leadTime: settings.takeover.leadTime))
        await resolvePending()
    }

    /// Publishes a snapshot to the model, ledger bookkeeping, timers and UI.
    private func apply(_ newSnapshot: CalendarSnapshot) {
        snapshot = newSnapshot
        model.calendars = snapshot.calendars
        model.statuses = snapshot.statuses
        model.sourceNames = snapshot.sourceNames
        model.candidates = snapshot.candidates
        if ledger.prune(now: Date()) { persistLedger() }
        if needsLaunchAcknowledge {
            // Meetings already underway at launch never take over (late fire is for wake-from-sleep).
            needsLaunchAcknowledge = false
            let count = ledger.acknowledgeInProgress(events: snapshot.events, now: Date(), grace: Self.launchGrace)
            TakeoverLog.acknowledgedOnLaunch(count: count)
            if count > 0 { persistLedger() }
        }
        rearm()
        updateUI()
    }

    /// Asks the on-device model about look-alike pairs off the refresh path; each verdict republishes.
    private func resolvePending() async {
        model.inferenceStatus = await store.inferenceStatus()
        while let updated = await store.resolvePending(now: Date()) { apply(updated) }
        await persistDedup()
    }

    private func setInference(_ enabled: Bool) async {
        apply(await store.setInferenceEnabled(enabled, now: Date()))
        await resolvePending()
    }

    func unmerge(_ event: CalendarEvent) {
        Task { @MainActor in
            apply(await store.unmerge(event, now: Date()))
            await persistDedup()
        }
    }

    func merge(_ a: CalendarEvent, _ b: CalendarEvent) {
        Task { @MainActor in
            apply(await store.merge(a, b, now: Date()))
            await persistDedup()
        }
    }

    private func forgetCorrections() {
        Task { @MainActor in
            apply(await store.forgetLessons(now: Date()))
            await persistDedup()
        }
    }

    private func persistDedup() async {
        dedupStore.save(await store.state())
    }
```

(Delete the old body of `refresh()` that `apply` now contains.) In `fire(_:)` change the `present` case lookup to `snapshot.events.first { $0.isSameMeeting(as: event) } ?? event`.

- [ ] **Step 4: Build and run the app tests**

Run: `xcodegen generate --spec Apps/macOS/project.yml && xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test 2>&1 | grep -E "error:|Executed|TEST (SUCCEEDED|FAILED)" | tail -5`
Expected: `TEST SUCCEEDED` (all previous app tests still pass).

- [ ] **Step 5: Commit**

```bash
git add Apps/macOS
git commit -m "feat(app): Beta duplicate-finder toggle and coordinator wiring

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

### Task 11: Merge badge and merge/unmerge actions in the popup

**Files:**
- Create: `Apps/macOS/Sources/MergeBadge.swift`
- Modify: `Apps/macOS/Sources/PopupRowModel.swift`, `Apps/macOS/Sources/DropdownView.swift`, `Apps/macOS/Sources/AppCoordinator.swift` (the `DropdownView(...)` construction)
- Test: create `Apps/macOS/Tests/MergeBadgeTests.swift`; modify `Apps/macOS/Tests/PopupLogicTests.swift`

**Interfaces:**
- Consumes: `MergeProvenance`, `CalendarEvent.mergedMembers`, `AppModel.candidates`, `AppCoordinator.unmerge/merge` (Task 10).
- Produces: `MergeBadge.text(_:) -> String?`; `PopupRowModel.mergeBadge: String?` and `PopupRowModel.isMerged: Bool`.

- [ ] **Step 1: Write the failing tests.** Create `MergeBadgeTests.swift`:

```swift
import TimeTugCore
import XCTest
@testable import TimeTug

final class MergeBadgeTests: XCTestCase {
    func testNoBadgeForPlainOrRuleMerges() {
        XCTAssertNil(MergeBadge.text(nil))
        XCTAssertNil(MergeBadge.text(.rule))
    }

    func testInferenceBadgeNamesTheEngine() {
        XCTAssertEqual(MergeBadge.text(.inference(engineID: "apple-intelligence", engineName: "Apple Intelligence")),
                       "Merged with Apple Intelligence")
    }

    func testUserConfirmedBadge() {
        XCTAssertEqual(MergeBadge.text(.userConfirmed), "Merged manually")
    }
}
```

Append inside `PopupLogicTests`:

```swift
    func testMergedRowsCarryBadgeAndFlag() {
        var merged = event("1", "Intermountain Health", at(10), at(11))
        merged.mergedMembers = [
            MergedMember(title: "Intermountain Health", calendarKey: "src/work", contentKey: "k1", details: "location"),
            MergedMember(title: "Scott: Doctor", calendarKey: "src/home", contentKey: "k2", details: "bare"),
        ]
        merged.mergeProvenance = .inference(engineID: "apple-intelligence", engineName: "Apple Intelligence")
        let row = rows([merged], now: at(9)).first!
        XCTAssertEqual(row.mergeBadge, "Merged with Apple Intelligence")
        XCTAssertTrue(row.isMerged)

        merged.mergeProvenance = .rule
        let ruleRow = rows([merged], now: at(9)).first!
        XCTAssertNil(ruleRow.mergeBadge)
        XCTAssertTrue(ruleRow.isMerged)                       // still offers "Not the same meeting"

        let plain = rows([event("2", "Standup", at(11), at(12))], now: at(9)).first!
        XCTAssertNil(plain.mergeBadge)
        XCTAssertFalse(plain.isMerged)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodegen generate --spec Apps/macOS/project.yml && xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test 2>&1 | grep -E "error:" | head -5`
Expected: compile errors (`MergeBadge`, `mergeBadge` missing).

- [ ] **Step 3: Implement.** Create `MergeBadge.swift`:

```swift
import TimeTugCore

/// Words for the merge indicator. Rule merges are silent; model and manual merges are labelled.
enum MergeBadge {
    static func text(_ provenance: MergeProvenance?) -> String? {
        guard let provenance else { return nil }
        switch provenance {
        case .rule: return nil
        case .inference(_, let engineName): return "Merged with \(engineName)"
        case .userConfirmed: return "Merged manually"
        }
    }
}
```

In `PopupRowModel.swift` add stored properties after `let end: Date`:

```swift
    var mergeBadge: String? = nil
    var isMerged = false
```

and in `rows(...)` pass them in the `PopupRowModel(...)` call (after `start: e.start, end: e.end`):

```swift
                start: e.start, end: e.end,
                mergeBadge: MergeBadge.text(e.mergeProvenance), isMerged: e.mergedMembers.count > 1)
```

In `DropdownView.swift`:

1. Add to `DropdownView`: `let onUnmerge: (CalendarEvent) -> Void` and `let onMerge: (CalendarEvent, CalendarEvent) -> Void` (after `onJoin`).
2. In the `EventCard(...)` call add `candidates: model.candidates[item.event.id] ?? [], onUnmerge: onUnmerge, onMerge: onMerge,` before `onJoin: onJoin`.
3. In `EventCard` add properties `let candidates: [CalendarEvent]`, `let onUnmerge: (CalendarEvent) -> Void`, `let onMerge: (CalendarEvent, CalendarEvent) -> Void` (before `onJoin`).
4. Under the `Text(row.metaText)...` line add the badge:

```swift
                    if let badge = row.mergeBadge {
                        Menu {
                            Button("Not the same meeting") { onUnmerge(event) }
                        } label: {
                            Label(badge, systemImage: mergeIcon)
                                .font(.system(size: 11)).foregroundStyle(secondaryColor)
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .accessibilityLabel("\(badge). Actions")
                    }
```

with, next to `barColor`:

```swift
    private var mergeIcon: String {
        if case .inference = event.mergeProvenance { return "sparkles" }
        return "checkmark.circle"
    }
```

5. After `.accessibilityLabel(accessibilityText)` on the card add:

```swift
        .contextMenu {
            if row.isMerged { Button("Not the same meeting") { onUnmerge(event) } }
            ForEach(candidates) { other in
                Button("Merge with \u{201C}\(other.title)\u{201D}") { onMerge(event, other) }
            }
        }
```

In `AppCoordinator.start()` extend the `DropdownView(...)` construction with:

```swift
                    onJoin: { [weak self] url in self?.statusItem?.join(url) },
                    onUnmerge: { [weak self] event in self?.unmerge(event) },
                    onMerge: { [weak self] a, b in self?.merge(a, b) }
```

- [ ] **Step 4: Run app tests**

Run: `xcodegen generate --spec Apps/macOS/project.yml && xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test 2>&1 | grep -E "error:|Executed|TEST (SUCCEEDED|FAILED)" | tail -5`
Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Apps/macOS
git commit -m "feat(app): merge badge with Not-the-same-meeting and manual Merge actions

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 12: Docs, CI and full verification

**Files:**
- Modify: `docs/superpowers/specs/2026-09-19-calendar-dedup-inference-design.md`, `docs/architecture.md`, `AGENTS.md`, `docs/PROGRESS.md`, `docs/manual-tests/macos-checklist.md`, `.github/workflows/ci.yml`
- Create: `docs/decisions/0009-duplicate-detection-and-on-device-inference.md`

- [ ] **Step 1: Spec touch-ups** (record what the plan decided). In the spec:
  - Section 1, after the pipeline list, add: "All-day events merge only on an exact match and are never sent to inference. A learned `same` lesson still requires the time gate; a learned `different` lesson applies always."
  - Section 2, replace "notes truncated to about 500 characters" ownership: "`AdjudicationEvent` (Core) truncates notes to 500 characters and carries attendee names only; the prompt builder cannot see emails."
  - Section 4, add: "`mergedMembers` lists every original copy including the primary; the ledger, guard, unmerge and manual merge all work from it."
  - Section 4b, add: "Settings > Calendars has a 'Forget learned corrections' button."

- [ ] **Step 2: ADR.** Create `docs/decisions/0009-duplicate-detection-and-on-device-inference.md`:

```markdown
# 0009: Duplicate detection with rules first and optional on-device inference

Status: accepted, 2026-09-19

## Context
The exact title+time merge misses real duplicates ("Scott: Doctor" vs "Intermountain Health") and cannot use shared people, places or conference links. Inference is platform specific and unproven, and a wrong merge hides a real appointment.

## Decision
- Core owns a deterministic pipeline (exact match, time gate of 30 min start / 60 min end, strong matches, vetoes) and only sends the leftover ambiguous pairs to a `DuplicateAdjudicator` protocol.
- Inference lives in per-platform packages behind that protocol (`Packages/AppleIntelligenceInference` first). It must be on-device. It is opt-in, default off, marked Beta; unavailable or off means rules only.
- Verdicts are asynchronous and cached; refresh and takeover never wait on a model, and a pending pair is simply not merged.
- Merges are non-destructive (`mergedMembers` keeps every copy) and badged by provenance; user merge/unmerge decisions become small bounded lessons that decide the exact pair next time and inform the model prompt.
- The takeover ledger and guard match on any member's content key so a late merge cannot re-fire a meeting.

## Consequences
- `CalendarEvent` gained attendees, organizer, external UID and merge data; EventKit supplies them (emails are often missing).
- A wrong AI merge is visible (badge) and reversible in one click.
- Other platforms add an adjudicator package; Core stays portable.
```

- [ ] **Step 3: Docs.** In `docs/architecture.md` extend the Core description (line 7 area, "merge/dedupe/last-good") with "duplicate rules, resolver, lessons and the adjudicator interface (ADR 0009)". In `AGENTS.md` add to Layout: ``- `Packages/AppleIntelligenceInference`: Apple on-device model adapter for duplicate detection (macOS 26+, compile-guarded). Only place with Foundation Models imports.`` and to Commands: ``- Inference package tests: `swift test --package-path Packages/AppleIntelligenceInference` ``. Append to `docs/PROGRESS.md` a dated entry: "2026-09-19: calendar dedup rules + optional on-device inference (ADR 0009). Core resolver, lessons, verdict cache, adjudicator protocol; AppleIntelligenceInference package; Beta toggle (default off); merge badge and Not-the-same-meeting / Merge actions. UNVERIFIED: real Foundation Models quality, EventKit attendee emails, popup menu behavior." Append to `docs/manual-tests/macos-checklist.md` a section "Duplicate detection (beta)" with these checkboxes: toggle is off by default and shows Beta; with it off, "Scott: Doctor" vs a detailed entry stay separate; with it on and Apple Intelligence available the pair merges and shows "Merged with Apple Intelligence"; "Not the same meeting" splits it and it stays split after relaunch; "Merge with..." on a separate look-alike merges it and shows "Merged manually"; on a Mac without Apple Intelligence the status line says rules only and nothing is merged by the model; a merged meeting takes over exactly once; "Forget learned corrections" resets decisions.

- [ ] **Step 4: CI.** In `.github/workflows/ci.yml`, in the `core` job after the "Build EventKitSource" step add:

```yaml
      - name: Test AppleIntelligenceInference
        run: swift test --package-path Packages/AppleIntelligenceInference
```

- [ ] **Step 5: Full verification**

Run:
```bash
swift test --package-path Packages/TimeTugCore 2>&1 | tail -3
swift test --package-path Packages/AppleIntelligenceInference 2>&1 | tail -3
swift build --package-path Packages/EventKitSource 2>&1 | tail -2
xcodegen generate --spec Apps/macOS/project.yml && xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)" | tail -3
```
Expected: every suite passes and the app tests report `TEST SUCCEEDED`. Report actual counts; anything that fails or that could not be run (for example no Apple Intelligence on this machine) is stated as unverified in `docs/PROGRESS.md`, not glossed over.

- [ ] **Step 6: Commit**

```bash
git add docs .github AGENTS.md
git commit -m "docs: ADR 0009, architecture, progress, manual checklist and CI for duplicate detection

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```
