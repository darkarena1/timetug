# TimeTug Core App Implementation Plan

> Public GitHub project: commit nothing private, no secrets. Task 13 (brand assets, README) was added after the initial plan; artwork is already in `artwork/`, `Apps/macOS/Resources/Assets.xcassets`, and `docs/ARTWORK_USAGE.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar app that reads Apple Calendar, lists today's events, and takes over every screen before qualifying meetings.

**Architecture:** A platform-neutral Swift package (`TimeTugCore`) holds the event model, takeover policy, scheduler, store and link detection. `EventKitSource` adapts Apple Calendar to Core's `CalendarSource` protocol. `Apps/macOS` is a thin AppKit/SwiftUI shell that owns all presentation. Dependencies point toward Core: `Apps/macOS -> EventKitSource -> TimeTugCore`, and the app also depends on Core directly.

**Tech Stack:** Swift 6.4 / Xcode 27, Swift Package Manager, Swift Testing (`import Testing`), SwiftUI + AppKit, EventKit, XcodeGen (app project generated from `Apps/macOS/project.yml`).

**Spec:** `docs/superpowers/specs/2026-09-18-timetug-core-design.md`

## Global Constraints

- Core (`Packages/TimeTugCore`) is pure Swift: it must not import AppKit, SwiftUI, EventKit or any UI framework, and must contain no display strings or menu bar mode enums.
- Core answers "what and when"; the macOS app answers "how it looks and where it lives".
- Dependency direction: `Apps/macOS -> EventKitSource -> TimeTugCore` and `Apps/macOS -> TimeTugCore`. Core never imports the others; the app is the composition root and owns source configuration UI and credential storage.
- Fetch window: local midnight today through next local midnight + lead time + 5 minute buffer (`CalendarStore.fetchBuffer = 300`).
- Display window: today only; an event after midnight appears in the dropdown only once inside its lead-time period.
- Takeover defaults: skip all-day, skip declined, skip events with no other attendees; optional "video link only" (default off). Per-calendar opt-in.
- Lead time is configurable; 0 means "meeting is starting now".
- Snooze options 1/5/10 minutes, capped at the meeting's end.
- Conference links: known-provider allowlist only; an event's own non-allowlisted http(s) `url` is still offered as Join; dial-in numbers ignored.
- macOS deployment target 14.0. App and `EventKitSource` build in Swift 5 language mode (AppKit/EventKit are not Swift 6 concurrency clean); `TimeTugCore` builds in Swift 6 mode.
- Every commit message ends with the trailer `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` (use a second `-m` argument).

## Spec deviations decided while planning

- `CalendarEvent` carries `otherAttendeeCount: Int` rather than an attendee list (only the count is needed).
- De-duplication key is `lowercased title + start + end` (catches the same meeting on several calendars), not source id.
- Detector tolerates HTML by scanning raw text for links (href values match naturally) and decoding `&amp;`; it does not strip tags.
- Dropdown is an `NSPopover` (allows greyed rows and a problems banner).
- If no calendars are opted in, the Settings window opens on launch (so a new user is never silently unprotected).

## File Structure

```
.gitignore
AGENTS.md
CLAUDE.md
docs/architecture.md
docs/decisions/0001-swift.md ... 0004-conference-link-allowlist.md
docs/manual-tests/macos-checklist.md
Packages/TimeTugCore/
  Package.swift
  Sources/TimeTugCore/
    Model/CalendarEvent.swift          # CalendarEvent, ResponseStatus, CalendarInfo
    Model/TakeoverSettings.swift       # shared Codable settings
    Sources/CalendarSource.swift       # protocol, SourceStatus, SourceError
    Detection/ConferenceLinkDetector.swift
    Takeover/TakeoverPolicy.swift
    Takeover/TakeoverLedger.swift      # fired/snoozed memory
    Takeover/Scheduler.swift           # ScheduledTakeover, Scheduler
    Takeover/TakeoverRequest.swift
    Store/CalendarStore.swift          # CalendarSnapshot, CalendarStore actor
    Agenda/DayAgenda.swift
  Tests/TimeTugCoreTests/ (Support.swift + one test file per source file)
Packages/EventKitSource/
  Package.swift
  Sources/EventKitSource/EventKitSource.swift
Apps/macOS/
  project.yml                          # XcodeGen spec (generated .xcodeproj is git-ignored)
  Sources/
    main.swift, AppDelegate.swift, AppCoordinator.swift, AppModel.swift
    StatusItemController.swift, TimeFormatting.swift
    DropdownView.swift
    OverlayController.swift, OverlayView.swift
    SettingsStore.swift, SettingsView.swift, SettingsWindowController.swift
  Tests/ (TimeFormattingTests.swift, SettingsStoreTests.swift)
```

---

### Task 1: Repo scaffold and Core data model

**Files:**
- Create: `.gitignore`, `AGENTS.md`, `CLAUDE.md`
- Create: `Packages/TimeTugCore/Package.swift`
- Create: `Packages/TimeTugCore/Sources/TimeTugCore/Model/CalendarEvent.swift`
- Create: `Packages/TimeTugCore/Sources/TimeTugCore/Model/TakeoverSettings.swift`
- Create: `Packages/TimeTugCore/Sources/TimeTugCore/Sources/CalendarSource.swift`
- Create: `Packages/TimeTugCore/Tests/TimeTugCoreTests/Support.swift`
- Test: `Packages/TimeTugCore/Tests/TimeTugCoreTests/ModelTests.swift`

**Interfaces:**
- Produces (used by every later task):
  - `enum ResponseStatus: String, Codable, Sendable { accepted, tentative, declined, pending, unknown }`
  - `struct CalendarInfo: Hashable, Sendable, Identifiable { sourceID, calendarID, title; var key: String; static func key(sourceID:calendarID:) -> String }`
  - `struct CalendarEvent: Identifiable, Hashable, Sendable` with `init(sourceEventID:sourceID:calendarID:title:start:end:isAllDay:otherAttendeeCount:responseStatus:location:notes:url:conferenceURL:)`, `var id: String`, `var calendarKey: String`
  - `struct TakeoverSettings: Codable, Equatable, Sendable` (`leadTime`, `takeoverCalendarKeys`, `hiddenCalendarKeys`, `requireConferenceLink`, `skipSoloEvents`, `skipDeclinedEvents`)
  - `protocol CalendarSource: Sendable`, `enum SourceStatus`, `enum SourceError`
  - Test helpers: `utcCalendar`, `date(_:)`, `makeEvent(...)`, `optedIn(_:)`

- [ ] **Step 1: Create scaffold files**

`.gitignore`:
```
.DS_Store
.build/
.swiftpm/
DerivedData/
*.xcodeproj
xcuserdata/
```

`Packages/TimeTugCore/Package.swift`:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TimeTugCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "TimeTugCore", targets: ["TimeTugCore"])],
    targets: [
        .target(name: "TimeTugCore"),
        .testTarget(name: "TimeTugCoreTests", dependencies: ["TimeTugCore"]),
    ]
)
```

`AGENTS.md`:
```markdown
# TimeTug: agent guide

TimeTug is a macOS menu bar app that takes over the screen before meetings. Read
`docs/superpowers/specs/2026-09-18-timetug-core-design.md` first, then `docs/architecture.md`.

## Layout
- `Packages/TimeTugCore`: pure Swift, platform-neutral logic. NO UI or Apple-only imports.
- `Packages/EventKitSource`: Apple Calendar adapter (macOS only).
- `Apps/macOS`: AppKit/SwiftUI shell. Generated Xcode project (XcodeGen).

## Rules
- Core answers "what and when". The app answers "how it looks and where it lives". If code needs a window, tray or pixel, it belongs in the app.
- Dependencies point toward Core: `Apps/macOS -> EventKitSource -> TimeTugCore`, and the app also depends on Core directly. The app is the composition root: it owns source configuration UI and credential storage. Source packages contain no UI.
- Time is always passed in (`now: Date`); never call `Date()` inside Core logic.
- Core has no display strings. Formatting belongs to the front end.
- Every Core behavior has a Swift Testing test. Write the failing test first.
- Record significant decisions in `docs/decisions/` (ADR, one file each).

## Commands
- Core tests: `swift test --package-path Packages/TimeTugCore`
- EventKitSource build: `swift build --package-path Packages/EventKitSource`
- Generate app project: `xcodegen generate --spec Apps/macOS/project.yml`
- Build app: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' build`
- App tests: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test`
- Window/status-item behavior is verified by hand: `docs/manual-tests/macos-checklist.md`.

## Gotchas
- App and EventKitSource use Swift 5 language mode; Core uses Swift 6.
- Generated `*.xcodeproj` is git-ignored; regenerate after editing `project.yml`.
- Calendar access needs the calendars entitlement and `NSCalendarsFullAccessUsageDescription`.
```

`CLAUDE.md`:
```markdown
See @AGENTS.md.
```

- [ ] **Step 2: Write the failing test and test helpers**

`Packages/TimeTugCore/Tests/TimeTugCoreTests/Support.swift`:
```swift
import Foundation
@testable import TimeTugCore

let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// Parses "2026-09-18T09:00:00Z".
func date(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso)!
}

func makeEvent(
    _ id: String = "e1",
    title: String = "Standup",
    start: String = "2026-09-18T10:00:00Z",
    minutes: Int = 30,
    calendarID: String = "cal",
    isAllDay: Bool = false,
    others: Int = 1,
    status: ResponseStatus = .accepted,
    location: String? = nil,
    notes: String? = nil,
    url: URL? = nil,
    conferenceURL: URL? = nil
) -> CalendarEvent {
    let startDate = date(start)
    return CalendarEvent(
        sourceEventID: id, sourceID: "fake", calendarID: calendarID, title: title,
        start: startDate, end: startDate.addingTimeInterval(TimeInterval(minutes * 60)),
        isAllDay: isAllDay, otherAttendeeCount: others, responseStatus: status,
        location: location, notes: notes, url: url, conferenceURL: conferenceURL
    )
}

/// Settings with the default test calendar ("fake/cal") opted in for takeovers.
func optedIn(_ configure: (inout TakeoverSettings) -> Void = { _ in }) -> TakeoverSettings {
    var settings = TakeoverSettings()
    settings.takeoverCalendarKeys = ["fake/cal"]
    configure(&settings)
    return settings
}
```

`Packages/TimeTugCore/Tests/TimeTugCoreTests/ModelTests.swift`:
```swift
import Foundation
import Testing
@testable import TimeTugCore

@Test func eventIdIncludesStartSoRecurringInstancesDiffer() {
    let a = makeEvent("series", start: "2026-09-18T10:00:00Z")
    let b = makeEvent("series", start: "2026-09-19T10:00:00Z")
    #expect(a.id != b.id)
}

@Test func calendarKeyCombinesSourceAndCalendar() {
    #expect(makeEvent(calendarID: "work").calendarKey == "fake/work")
    #expect(CalendarInfo.key(sourceID: "fake", calendarID: "work") == "fake/work")
}

@Test func settingsRoundTripThroughJSON() throws {
    var settings = TakeoverSettings()
    settings.leadTime = 300
    settings.takeoverCalendarKeys = ["a/b"]
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(TakeoverSettings.self, from: data) == settings)
}

@Test func settingsDefaults() {
    let settings = TakeoverSettings()
    #expect(settings.leadTime == 60)
    #expect(settings.skipSoloEvents && settings.skipDeclinedEvents)
    #expect(!settings.requireConferenceLink)
    #expect(settings.takeoverCalendarKeys.isEmpty)
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --package-path Packages/TimeTugCore`
Expected: FAIL to compile ("cannot find 'CalendarEvent' in scope").

- [ ] **Step 4: Write the model**

`Sources/TimeTugCore/Model/CalendarEvent.swift`:
```swift
import Foundation

public enum ResponseStatus: String, Codable, Sendable {
    case accepted, tentative, declined, pending, unknown
}

public struct CalendarInfo: Hashable, Sendable, Identifiable {
    public let sourceID: String
    public let calendarID: String
    public let title: String

    public init(sourceID: String, calendarID: String, title: String) {
        self.sourceID = sourceID
        self.calendarID = calendarID
        self.title = title
    }

    public var key: String { Self.key(sourceID: sourceID, calendarID: calendarID) }
    public var id: String { key }

    public static func key(sourceID: String, calendarID: String) -> String {
        "\(sourceID)/\(calendarID)"
    }
}

public struct CalendarEvent: Identifiable, Hashable, Sendable {
    public var sourceEventID: String
    public var sourceID: String
    public var calendarID: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var otherAttendeeCount: Int
    public var responseStatus: ResponseStatus
    public var location: String?
    public var notes: String?
    public var url: URL?
    public var conferenceURL: URL?

    public init(
        sourceEventID: String, sourceID: String, calendarID: String, title: String,
        start: Date, end: Date, isAllDay: Bool = false, otherAttendeeCount: Int = 0,
        responseStatus: ResponseStatus = .unknown, location: String? = nil,
        notes: String? = nil, url: URL? = nil, conferenceURL: URL? = nil
    ) {
        self.sourceEventID = sourceEventID
        self.sourceID = sourceID
        self.calendarID = calendarID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.otherAttendeeCount = otherAttendeeCount
        self.responseStatus = responseStatus
        self.location = location
        self.notes = notes
        self.url = url
        self.conferenceURL = conferenceURL
    }

    /// Unique per occurrence: recurring events share a source id but differ in start.
    public var id: String { "\(sourceID)/\(sourceEventID)/\(Int(start.timeIntervalSince1970))" }
    public var calendarKey: String { CalendarInfo.key(sourceID: sourceID, calendarID: calendarID) }
}
```

`Sources/TimeTugCore/Model/TakeoverSettings.swift`:
```swift
import Foundation

/// Shared, platform-neutral settings. Core defines the shape; each front end stores and edits it.
public struct TakeoverSettings: Codable, Equatable, Sendable {
    /// Seconds before start that the takeover fires. 0 means "starting now".
    public var leadTime: TimeInterval = 60
    /// `CalendarInfo.key` values allowed to trigger takeovers (opt-in).
    public var takeoverCalendarKeys: Set<String> = []
    /// `CalendarInfo.key` values hidden from the day list (default: none hidden).
    public var hiddenCalendarKeys: Set<String> = []
    public var requireConferenceLink = false
    public var skipSoloEvents = true
    public var skipDeclinedEvents = true

    public init() {}
}
```

`Sources/TimeTugCore/Sources/CalendarSource.swift`:
```swift
import Foundation

public enum SourceStatus: Equatable, Sendable {
    case ok
    case needsPermission
    case authExpired
    case failing(String)
}

/// Sources throw these to report a status the user can act on.
public enum SourceError: Error, Sendable {
    case needsPermission
    case authExpired
}

/// A calendar backend. Returns only Core's normalized model; source-specific types never leak.
public protocol CalendarSource: Sendable {
    var id: String { get }
    var displayName: String { get }
    func calendars() async throws -> [CalendarInfo]
    func events(in interval: DateInterval) async throws -> [CalendarEvent]
    /// Yields whenever the source's data may have changed.
    func changes() -> AsyncStream<Void>
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --package-path Packages/TimeTugCore`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add .gitignore AGENTS.md CLAUDE.md Packages
git commit -m "feat(core): scaffold repo and add event model, settings, source protocol" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: ConferenceLinkDetector

**Files:**
- Create: `Packages/TimeTugCore/Sources/TimeTugCore/Detection/ConferenceLinkDetector.swift`
- Test: `Packages/TimeTugCore/Tests/TimeTugCoreTests/ConferenceLinkDetectorTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `ConferenceLinkDetector.detect(location: String?, url: URL?, notes: String?) -> URL?`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import TimeTugCore

private func detect(location: String? = nil, url: String? = nil, notes: String? = nil) -> URL? {
    ConferenceLinkDetector.detect(location: location, url: url.flatMap(URL.init(string:)), notes: notes)
}

@Test func findsZoomInLocation() {
    #expect(detect(location: "https://acme.zoom.us/j/123456789?pwd=abc")?.host == "acme.zoom.us")
}

@Test func findsMeetInNotes() {
    #expect(detect(notes: "Join: https://meet.google.com/abc-defg-hij.")?.absoluteString
        == "https://meet.google.com/abc-defg-hij")
}

@Test func findsTeamsInsideHTMLWithEntities() {
    let notes = #"<p><a href="https://teams.microsoft.com/l/meetup-join/19%3ameeting?a=1&amp;b=2">Join</a></p>"#
    let result = detect(notes: notes)
    #expect(result?.host == "teams.microsoft.com")
    #expect(result?.query == "a=1&b=2")
}

@Test func unwrapsOutlookSafeLinks() {
    let wrapped = "https://nam02.safelinks.protection.outlook.com/?url=https%3A%2F%2Fteams.microsoft.com%2Fl%2Fmeetup-join%2F0&data=05"
    #expect(detect(notes: "Click \(wrapped) now")?.host == "teams.microsoft.com")
}

@Test func unwrapsGoogleRedirects() {
    let wrapped = "https://www.google.com/url?q=https://acme.zoom.us/j/1&sa=D"
    #expect(detect(notes: wrapped)?.host == "acme.zoom.us")
}

@Test func acceptsZoomMtgScheme() {
    #expect(detect(notes: "zoommtg://zoom.us/join?confno=123")?.scheme == "zoommtg")
}

@Test func ignoresNonProviderLinksInText() {
    #expect(detect(notes: "Agenda: https://docs.google.com/document/d/abc") == nil)
}

@Test func locationBeatsNotes() {
    let result = detect(location: "https://meet.google.com/aaa-bbbb-ccc",
                        notes: "https://acme.zoom.us/j/1")
    #expect(result?.host == "meet.google.com")
}

@Test func returnsFirstProviderLinkSkippingOthers() {
    let notes = "Doc https://docs.google.com/x then https://acme.zoom.us/j/9"
    #expect(detect(notes: notes)?.host == "acme.zoom.us")
}

@Test func eventURLFallbackWhenNotAllowlisted() {
    #expect(detect(url: "https://example.com/meeting/42")?.absoluteString == "https://example.com/meeting/42")
}

@Test func slackHuddleNeedsHuddlePath() {
    #expect(detect(notes: "https://app.slack.com/huddle/T1/C1") != nil)
    #expect(detect(notes: "https://app.slack.com/client/T1/C1") == nil)
}

@Test func noLinksReturnsNil() {
    #expect(detect(location: "Room 4", notes: "Bring laptop") == nil)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path Packages/TimeTugCore --filter ConferenceLinkDetectorTests`
Expected: FAIL to compile ("cannot find 'ConferenceLinkDetector'").

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Finds a video-conference join link in event text. Uses a known-provider allowlist so a
/// "Join" button never opens something like a shared document.
public enum ConferenceLinkDetector {
    struct Provider {
        let host: String
        var pathPrefix: String? = nil
    }

    /// Data, not logic: add providers here.
    static let providers: [Provider] = [
        Provider(host: "zoom.us"), Provider(host: "zoom.com"),
        Provider(host: "meet.google.com"),
        Provider(host: "teams.microsoft.com"), Provider(host: "teams.live.com"),
        Provider(host: "webex.com"),
        Provider(host: "gotomeet.me"), Provider(host: "gotomeeting.com"),
        Provider(host: "whereby.com"),
        Provider(host: "meet.jit.si"),
        Provider(host: "app.slack.com", pathPrefix: "/huddle"),
    ]

    /// Scans location, then url, then notes for an allowlisted link. If none is found but the
    /// event's own `url` is a web link, returns that (the invite put it there on purpose).
    public static func detect(location: String?, url: URL?, notes: String?) -> URL? {
        for text in [location, url?.absoluteString, notes] {
            if let text, let link = firstProviderLink(in: text) { return link }
        }
        if let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return url
        }
        return nil
    }

    static func firstProviderLink(in text: String) -> URL? {
        for candidate in candidates(in: text) {
            if let link = unwrap(candidate), isProvider(link) { return link }
        }
        return nil
    }

    static func candidates(in text: String) -> [String] {
        let decoded = text.replacingOccurrences(of: "&amp;", with: "&")
        guard let regex = try? NSRegularExpression(pattern: #"(?:https?|zoommtg)://[^\s<>"'\)\]]+"#) else {
            return []
        }
        let range = NSRange(decoded.startIndex..., in: decoded)
        return regex.matches(in: decoded, range: range).compactMap { match in
            Range(match.range, in: decoded).map {
                String(decoded[$0]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
            }
        }
    }

    /// Unwraps Outlook SafeLinks and Google redirect URLs (up to a few layers).
    static func unwrap(_ raw: String) -> URL? {
        var current = URL(string: raw)
        for _ in 0..<3 {
            guard let url = current, let host = url.host?.lowercased() else { break }
            let inner: String?
            if host.hasSuffix("safelinks.protection.outlook.com") {
                inner = queryValue(url, "url")
            } else if host == "www.google.com", url.path == "/url" {
                inner = queryValue(url, "q") ?? queryValue(url, "url")
            } else {
                break
            }
            guard let inner, let next = URL(string: inner) else { break }
            current = next
        }
        return current
    }

    static func isProvider(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "zoommtg" { return true }
        guard scheme == "http" || scheme == "https", let host = url.host?.lowercased() else { return false }
        return providers.contains { provider in
            (host == provider.host || host.hasSuffix("." + provider.host))
                && (provider.pathPrefix.map { url.path.hasPrefix($0) } ?? true)
        }
    }

    private static func queryValue(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/TimeTugCore --filter ConferenceLinkDetectorTests`
Expected: PASS (12 tests). If `findsTeamsInsideHTMLWithEntities` fails on the query, print `result` and fix the entity handling; do not weaken the assertion.

- [ ] **Step 5: Commit**

```bash
git add Packages/TimeTugCore
git commit -m "feat(core): add conference link detector" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: TakeoverPolicy

**Files:**
- Create: `Packages/TimeTugCore/Sources/TimeTugCore/Takeover/TakeoverPolicy.swift`
- Test: `Packages/TimeTugCore/Tests/TimeTugCoreTests/TakeoverPolicyTests.swift`

**Interfaces:**
- Consumes: `CalendarEvent`, `TakeoverSettings`, test helpers `makeEvent`, `optedIn`.
- Produces: `TakeoverPolicy.qualifies(_ event: CalendarEvent, settings: TakeoverSettings) -> Bool`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import TimeTugCore

@Test func qualifiesWhenOptedInAndDefaultsPass() {
    #expect(TakeoverPolicy.qualifies(makeEvent(), settings: optedIn()))
}

@Test func rejectsCalendarNotOptedIn() {
    #expect(!TakeoverPolicy.qualifies(makeEvent(calendarID: "family"), settings: optedIn()))
}

@Test func rejectsAllDay() {
    #expect(!TakeoverPolicy.qualifies(makeEvent(isAllDay: true), settings: optedIn()))
}

@Test func rejectsDeclinedByDefaultButAllowsWhenToggledOff() {
    let declined = makeEvent(status: .declined)
    #expect(!TakeoverPolicy.qualifies(declined, settings: optedIn()))
    #expect(TakeoverPolicy.qualifies(declined, settings: optedIn { $0.skipDeclinedEvents = false }))
}

@Test func rejectsSoloByDefaultButAllowsWhenToggledOff() {
    let solo = makeEvent(others: 0)
    #expect(!TakeoverPolicy.qualifies(solo, settings: optedIn()))
    #expect(TakeoverPolicy.qualifies(solo, settings: optedIn { $0.skipSoloEvents = false }))
}

@Test func requireConferenceLinkFiltersEventsWithoutOne() {
    let settings = optedIn { $0.requireConferenceLink = true }
    #expect(!TakeoverPolicy.qualifies(makeEvent(), settings: settings))
    let withLink = makeEvent(conferenceURL: URL(string: "https://meet.google.com/a-b-c"))
    #expect(TakeoverPolicy.qualifies(withLink, settings: settings))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path Packages/TimeTugCore --filter TakeoverPolicyTests`
Expected: FAIL to compile ("cannot find 'TakeoverPolicy'").

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Decides whether an event may take over the screen. Pure and platform-neutral.
public enum TakeoverPolicy {
    public static func qualifies(_ event: CalendarEvent, settings: TakeoverSettings) -> Bool {
        guard settings.takeoverCalendarKeys.contains(event.calendarKey) else { return false }
        if event.isAllDay { return false }
        if settings.skipDeclinedEvents, event.responseStatus == .declined { return false }
        if settings.skipSoloEvents, event.otherAttendeeCount == 0 { return false }
        if settings.requireConferenceLink, event.conferenceURL == nil { return false }
        return true
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/TimeTugCore --filter TakeoverPolicyTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/TimeTugCore
git commit -m "feat(core): add takeover policy" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: TakeoverLedger, Scheduler and TakeoverRequest

**Files:**
- Create: `Packages/TimeTugCore/Sources/TimeTugCore/Takeover/TakeoverLedger.swift`
- Create: `Packages/TimeTugCore/Sources/TimeTugCore/Takeover/Scheduler.swift`
- Create: `Packages/TimeTugCore/Sources/TimeTugCore/Takeover/TakeoverRequest.swift`
- Test: `Packages/TimeTugCore/Tests/TimeTugCoreTests/SchedulerTests.swift`

**Interfaces:**
- Consumes: `TakeoverPolicy.qualifies`, `CalendarEvent`, `TakeoverSettings`.
- Produces:
  - `struct TakeoverLedger: Equatable, Sendable` with `init()`, `mutating markFired(_:)`, `mutating snooze(_ event:, for: TimeInterval, now: Date)`, `mutating prune(now:)`, `internal func entry(for:) -> Entry?`
  - `struct ScheduledTakeover: Equatable, Sendable { event: CalendarEvent; fireAt: Date }`
  - `Scheduler.next(events:settings:ledger:now:) -> ScheduledTakeover?`
  - `struct TakeoverRequest: Equatable, Sendable { event, hasStarted: Bool, joinURL: URL?, snoozeOptions: [TimeInterval] }` and `static func make(for:now:) -> TakeoverRequest`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import TimeTugCore

private let tenAM = date("2026-09-18T10:00:00Z")

@Test func firesAtStartMinusLeadTime() {
    let event = makeEvent(start: "2026-09-18T10:00:00Z")
    let next = Scheduler.next(events: [event], settings: optedIn { $0.leadTime = 120 },
                              ledger: TakeoverLedger(), now: date("2026-09-18T09:00:00Z"))
    #expect(next?.fireAt == date("2026-09-18T09:58:00Z"))
    #expect(next?.event == event)
}

@Test func zeroLeadTimeFiresAtStart() {
    let next = Scheduler.next(events: [makeEvent()], settings: optedIn { $0.leadTime = 0 },
                              ledger: TakeoverLedger(), now: date("2026-09-18T09:00:00Z"))
    #expect(next?.fireAt == tenAM)
}

@Test func lateFireIsImmediateWhileMeetingInProgress() {
    let now = date("2026-09-18T10:05:00Z")
    let next = Scheduler.next(events: [makeEvent()], settings: optedIn(),
                              ledger: TakeoverLedger(), now: now)
    #expect(next?.fireAt == now)
}

@Test func endedMeetingsAreIgnored() {
    let next = Scheduler.next(events: [makeEvent()], settings: optedIn(),
                              ledger: TakeoverLedger(), now: date("2026-09-18T10:30:00Z"))
    #expect(next == nil)
}

@Test func firedEventsDoNotRepeat() {
    let event = makeEvent()
    var ledger = TakeoverLedger()
    ledger.markFired(event)
    #expect(Scheduler.next(events: [event], settings: optedIn(), ledger: ledger,
                           now: date("2026-09-18T09:59:30Z")) == nil)
}

@Test func rescheduledEventCountsAsNew() {
    var ledger = TakeoverLedger()
    ledger.markFired(makeEvent(start: "2026-09-18T10:00:00Z"))
    let moved = makeEvent(start: "2026-09-18T11:00:00Z")
    #expect(Scheduler.next(events: [moved], settings: optedIn(), ledger: ledger,
                           now: date("2026-09-18T09:00:00Z")) != nil)
}

@Test func snoozeRefiresAtSnoozeEnd() {
    let event = makeEvent(minutes: 60)
    var ledger = TakeoverLedger()
    let now = date("2026-09-18T09:59:00Z")
    ledger.markFired(event)
    ledger.snooze(event, for: 300, now: now)
    let next = Scheduler.next(events: [event], settings: optedIn(), ledger: ledger, now: now)
    #expect(next?.fireAt == date("2026-09-18T10:04:00Z"))
}

@Test func snoozeIsCappedAtMeetingEnd() {
    let event = makeEvent(minutes: 5)
    var ledger = TakeoverLedger()
    let now = date("2026-09-18T10:03:00Z")
    ledger.snooze(event, for: 600, now: now)
    // Capped at 10:05 == end, so nothing left to fire.
    #expect(Scheduler.next(events: [event], settings: optedIn(), ledger: ledger, now: now) == nil)
}

@Test func picksEarliestQualifyingEvent() {
    let later = makeEvent("late", start: "2026-09-18T11:00:00Z")
    let sooner = makeEvent("soon", start: "2026-09-18T10:00:00Z")
    let next = Scheduler.next(events: [later, sooner], settings: optedIn(),
                              ledger: TakeoverLedger(), now: date("2026-09-18T09:00:00Z"))
    #expect(next?.event == sooner)
}

@Test func nonQualifyingEventsAreSkipped() {
    let next = Scheduler.next(events: [makeEvent(calendarID: "family")], settings: optedIn(),
                              ledger: TakeoverLedger(), now: date("2026-09-18T09:00:00Z"))
    #expect(next == nil)
}

@Test func afterMidnightMeetingFiresBeforeMidnight() {
    let event = makeEvent(start: "2026-09-19T00:05:00Z")
    let next = Scheduler.next(events: [event], settings: optedIn { $0.leadTime = 600 },
                              ledger: TakeoverLedger(), now: date("2026-09-18T23:00:00Z"))
    #expect(next?.fireAt == date("2026-09-18T23:55:00Z"))
}

@Test func ledgerPrunesByEventEnd() {
    let done = makeEvent("done", start: "2026-09-18T08:00:00Z")
    let running = makeEvent("running", start: "2026-09-18T10:00:00Z")
    var ledger = TakeoverLedger()
    ledger.markFired(done)
    ledger.markFired(running)
    ledger.prune(now: date("2026-09-18T10:10:00Z"))
    #expect(ledger.entry(for: done) == nil)
    #expect(ledger.entry(for: running) != nil)
}

@Test func requestMarksStartedAndFiltersSnoozeOptions() {
    let event = makeEvent(minutes: 30, conferenceURL: URL(string: "https://meet.google.com/a-b-c"))
    let before = TakeoverRequest.make(for: event, now: date("2026-09-18T09:59:00Z"))
    #expect(!before.hasStarted)
    #expect(before.joinURL != nil)
    #expect(before.snoozeOptions == [60, 300, 600])

    let late = TakeoverRequest.make(for: event, now: date("2026-09-18T10:28:00Z"))
    #expect(late.hasStarted)
    #expect(late.snoozeOptions == [60])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path Packages/TimeTugCore --filter SchedulerTests`
Expected: FAIL to compile ("cannot find 'TakeoverLedger'").

- [ ] **Step 3: Implement**

`Takeover/TakeoverLedger.swift`:
```swift
import Foundation

/// Remembers which events already took over (or are snoozed) so a refresh never repeats one.
/// Keyed by `CalendarEvent.id`, which includes the start time, so a rescheduled event is new.
public struct TakeoverLedger: Equatable, Sendable {
    enum Entry: Equatable, Sendable {
        case fired
        case snoozed(until: Date)
    }

    private var entries: [String: Entry] = [:]
    private var endDates: [String: Date] = [:]

    public init() {}

    public mutating func markFired(_ event: CalendarEvent) {
        entries[event.id] = .fired
        endDates[event.id] = event.end
    }

    /// Re-arms the event `duration` from now, never past the meeting's end.
    public mutating func snooze(_ event: CalendarEvent, for duration: TimeInterval, now: Date) {
        entries[event.id] = .snoozed(until: min(now.addingTimeInterval(duration), event.end))
        endDates[event.id] = event.end
    }

    /// Drops entries for events that have ended (not wholesale, so midnight rollover is safe).
    public mutating func prune(now: Date) {
        for (id, end) in endDates where end <= now {
            entries[id] = nil
            endDates[id] = nil
        }
    }

    func entry(for event: CalendarEvent) -> Entry? { entries[event.id] }
}
```

`Takeover/Scheduler.swift`:
```swift
import Foundation

public struct ScheduledTakeover: Equatable, Sendable {
    public let event: CalendarEvent
    public let fireAt: Date
}

public enum Scheduler {
    /// The next takeover to arm, or nil. `fireAt` is never earlier than `now` (late fires are
    /// immediate while the meeting is still in progress).
    public static func next(
        events: [CalendarEvent], settings: TakeoverSettings, ledger: TakeoverLedger, now: Date
    ) -> ScheduledTakeover? {
        var best: ScheduledTakeover?
        for event in events where event.end > now && TakeoverPolicy.qualifies(event, settings: settings) {
            let fireAt: Date
            switch ledger.entry(for: event) {
            case .fired: continue
            case .snoozed(let until): fireAt = max(until, now)
            case nil: fireAt = max(event.start.addingTimeInterval(-settings.leadTime), now)
            }
            guard fireAt < event.end else { continue }
            if best == nil || fireAt < best!.fireAt {
                best = ScheduledTakeover(event: event, fireAt: fireAt)
            }
        }
        return best
    }
}
```

`Takeover/TakeoverRequest.swift`:
```swift
import Foundation

/// Everything a front end needs to render a takeover. Plain data: no display strings.
public struct TakeoverRequest: Equatable, Sendable {
    public static let snoozeChoices: [TimeInterval] = [60, 300, 600]

    public let event: CalendarEvent
    public let hasStarted: Bool
    public let joinURL: URL?
    /// Snooze durations (seconds) that still end before the meeting does.
    public let snoozeOptions: [TimeInterval]

    public static func make(for event: CalendarEvent, now: Date) -> TakeoverRequest {
        TakeoverRequest(
            event: event,
            hasStarted: now >= event.start,
            joinURL: event.conferenceURL,
            snoozeOptions: snoozeChoices.filter { now.addingTimeInterval($0) < event.end }
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/TimeTugCore --filter SchedulerTests`
Expected: PASS (13 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/TimeTugCore
git commit -m "feat(core): add scheduler, takeover ledger and takeover request" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: CalendarStore

**Files:**
- Create: `Packages/TimeTugCore/Sources/TimeTugCore/Store/CalendarStore.swift`
- Test: `Packages/TimeTugCore/Tests/TimeTugCoreTests/CalendarStoreTests.swift`
- Modify: `docs/superpowers/specs/2026-09-18-timetug-core-design.md` (dedupe wording, see Step 6)

**Interfaces:**
- Consumes: `CalendarSource`, `ConferenceLinkDetector.detect`, `SourceError`, `SourceStatus`.
- Produces:
  - `struct CalendarSnapshot: Sendable { events: [CalendarEvent]; calendars: [CalendarInfo]; statuses: [String: SourceStatus]; sourceNames: [String: String]; fetchedAt: Date; static let empty }`
  - `actor CalendarStore` with `init(sources: [any CalendarSource], calendar: Calendar = .current)`, `static let fetchBuffer: TimeInterval`, `func fetchWindow(now:leadTime:) -> DateInterval`, `func refresh(now:leadTime:) async -> CalendarSnapshot`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import TimeTugCore

actor FakeSource: CalendarSource {
    nonisolated let id: String
    nonisolated let displayName: String
    var calendarsResult: Result<[CalendarInfo], Error> = .success([])
    var eventsResult: Result<[CalendarEvent], Error> = .success([])
    private(set) var requestedIntervals: [DateInterval] = []

    init(id: String = "fake") {
        self.id = id
        self.displayName = "Fake \(id)"
    }

    func set(events: Result<[CalendarEvent], Error>) { eventsResult = events }
    func set(calendars: [CalendarInfo]) { calendarsResult = .success(calendars) }

    func calendars() async throws -> [CalendarInfo] { try calendarsResult.get() }
    func events(in interval: DateInterval) async throws -> [CalendarEvent] {
        requestedIntervals.append(interval)
        return try eventsResult.get()
    }
    nonisolated func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

private let now = date("2026-09-18T10:00:00Z")

@Test func fetchWindowSpansTodayPlusLeadTimeAndBuffer() async {
    let store = CalendarStore(sources: [], calendar: utcCalendar)
    let window = await store.fetchWindow(now: now, leadTime: 600)
    #expect(window.start == date("2026-09-18T00:00:00Z"))
    #expect(window.end == date("2026-09-19T00:15:00Z"))   // midnight + 600s + 300s buffer
}

@Test func refreshAsksSourcesForFetchWindow() async {
    let source = FakeSource()
    let store = CalendarStore(sources: [source], calendar: utcCalendar)
    _ = await store.refresh(now: now, leadTime: 60)
    #expect(await source.requestedIntervals.first?.end == date("2026-09-19T00:06:00Z"))
}

@Test func mergesSortsAndDedupesAcrossCalendars() async {
    let a = FakeSource(id: "a"), b = FakeSource(id: "b")
    let dup1 = makeEvent("1", title: "Design Review", start: "2026-09-18T11:00:00Z")
    var dup2 = makeEvent("9", title: "design review", start: "2026-09-18T11:00:00Z")
    dup2.sourceID = "b"
    let early = makeEvent("2", title: "Standup", start: "2026-09-18T09:00:00Z")
    await a.set(events: .success([dup1, early]))
    await b.set(events: .success([dup2]))
    let store = CalendarStore(sources: [a, b], calendar: utcCalendar)
    let snapshot = await store.refresh(now: now, leadTime: 60)
    #expect(snapshot.events.map(\.title) == ["Standup", "Design Review"])
}

@Test func fillsConferenceURLFromDetectorWhenSourceHasNone() async {
    let source = FakeSource()
    await source.set(events: .success([makeEvent(location: "https://acme.zoom.us/j/5")]))
    let store = CalendarStore(sources: [source], calendar: utcCalendar)
    let snapshot = await store.refresh(now: now, leadTime: 60)
    #expect(snapshot.events.first?.conferenceURL?.host == "acme.zoom.us")
}

@Test func keepsSourceSuppliedConferenceURL() async {
    let structured = URL(string: "https://meet.google.com/aaa-bbbb-ccc")
    let source = FakeSource()
    await source.set(events: .success([makeEvent(location: "https://acme.zoom.us/j/5", conferenceURL: structured)]))
    let store = CalendarStore(sources: [source], calendar: utcCalendar)
    #expect(await store.refresh(now: now, leadTime: 60).events.first?.conferenceURL == structured)
}

@Test func failingSourceKeepsLastGoodEventsAndReportsStatus() async {
    struct Boom: Error {}
    let source = FakeSource()
    await source.set(events: .success([makeEvent()]))
    let store = CalendarStore(sources: [source], calendar: utcCalendar)
    _ = await store.refresh(now: now, leadTime: 60)

    await source.set(events: .failure(Boom()))
    let snapshot = await store.refresh(now: now, leadTime: 60)
    #expect(snapshot.events.count == 1)
    if case .failing = snapshot.statuses["fake"] {} else { Issue.record("expected .failing") }
}

@Test func permissionAndAuthErrorsMapToStatuses() async {
    let source = FakeSource()
    let store = CalendarStore(sources: [source], calendar: utcCalendar)
    await source.set(events: .failure(SourceError.needsPermission))
    #expect(await store.refresh(now: now, leadTime: 60).statuses["fake"] == .needsPermission)
    await source.set(events: .failure(SourceError.authExpired))
    #expect(await store.refresh(now: now, leadTime: 60).statuses["fake"] == .authExpired)
}

@Test func oneFailingSourceDoesNotAffectAnother() async {
    let bad = FakeSource(id: "bad"), good = FakeSource(id: "good")
    await bad.set(events: .failure(SourceError.needsPermission))
    var event = makeEvent()
    event.sourceID = "good"
    await good.set(events: .success([event]))
    let store = CalendarStore(sources: [bad, good], calendar: utcCalendar)
    let snapshot = await store.refresh(now: now, leadTime: 60)
    #expect(snapshot.events.count == 1)
    #expect(snapshot.statuses["good"] == .ok)
}

@Test func dropsEventsOutsideFetchWindow() async {
    let yesterday = makeEvent("y", start: "2026-09-17T10:00:00Z")
    let source = FakeSource()
    await source.set(events: .success([yesterday, makeEvent("t")]))
    let store = CalendarStore(sources: [source], calendar: utcCalendar)
    #expect(await store.refresh(now: now, leadTime: 60).events.map(\.sourceEventID) == ["t"])
}

@Test func snapshotIncludesCalendarsAndSourceNames() async {
    let source = FakeSource()
    await source.set(calendars: [CalendarInfo(sourceID: "fake", calendarID: "cal", title: "Work")])
    let store = CalendarStore(sources: [source], calendar: utcCalendar)
    let snapshot = await store.refresh(now: now, leadTime: 60)
    #expect(snapshot.calendars.map(\.title) == ["Work"])
    #expect(snapshot.sourceNames["fake"] == "Fake fake")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path Packages/TimeTugCore --filter CalendarStoreTests`
Expected: FAIL to compile ("cannot find 'CalendarStore'").

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct CalendarSnapshot: Sendable {
    public let events: [CalendarEvent]
    public let calendars: [CalendarInfo]
    /// Keyed by `CalendarSource.id`.
    public let statuses: [String: SourceStatus]
    /// `CalendarSource.id` -> `displayName`, for front ends that show source problems.
    public let sourceNames: [String: String]
    public let fetchedAt: Date

    public static let empty = CalendarSnapshot(
        events: [], calendars: [], statuses: [:], sourceNames: [:], fetchedAt: .distantPast)
}

/// Merges events from all sources over the fetch window. A failing source keeps its last good
/// events so a network blip never causes a missed meeting.
public actor CalendarStore {
    /// Extra time past the lead time so events just after midnight are already loaded.
    public static let fetchBuffer: TimeInterval = 300

    private let sources: [any CalendarSource]
    private let calendar: Calendar
    private var lastEvents: [String: [CalendarEvent]] = [:]
    private var lastCalendars: [String: [CalendarInfo]] = [:]
    private var statuses: [String: SourceStatus] = [:]

    public init(sources: [any CalendarSource], calendar: Calendar = .current) {
        self.sources = sources
        self.calendar = calendar
    }

    /// Local midnight today through next local midnight + lead time + buffer.
    public func fetchWindow(now: Date, leadTime: TimeInterval) -> DateInterval {
        let dayStart = calendar.startOfDay(for: now)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        return DateInterval(start: dayStart, end: nextDayStart.addingTimeInterval(leadTime + Self.fetchBuffer))
    }

    public func refresh(now: Date, leadTime: TimeInterval) async -> CalendarSnapshot {
        let window = fetchWindow(now: now, leadTime: leadTime)

        let results = await withTaskGroup(
            of: (String, Result<([CalendarInfo], [CalendarEvent]), Error>).self
        ) { group in
            for source in sources {
                group.addTask {
                    do {
                        let calendars = try await source.calendars()
                        let events = try await source.events(in: window)
                        return (source.id, .success((calendars, events)))
                    } catch {
                        return (source.id, .failure(error))
                    }
                }
            }
            var collected: [(String, Result<([CalendarInfo], [CalendarEvent]), Error>)] = []
            for await result in group { collected.append(result) }
            return collected
        }

        for (sourceID, result) in results {
            switch result {
            case .success(let (calendars, events)):
                lastCalendars[sourceID] = calendars
                lastEvents[sourceID] = events
                statuses[sourceID] = .ok
            case .failure(let error):
                switch error {
                case SourceError.needsPermission: statuses[sourceID] = .needsPermission
                case SourceError.authExpired: statuses[sourceID] = .authExpired
                default: statuses[sourceID] = .failing(String(describing: error))
                }
            }
        }

        return CalendarSnapshot(
            events: merged(within: window),
            calendars: sources.flatMap { lastCalendars[$0.id] ?? [] },
            statuses: statuses,
            sourceNames: Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.displayName) }),
            fetchedAt: now
        )
    }

    private func merged(within window: DateInterval) -> [CalendarEvent] {
        var seen = Set<String>()
        var result: [CalendarEvent] = []
        for source in sources {
            for var event in lastEvents[source.id] ?? [] {
                guard event.end > window.start, event.start < window.end else { continue }
                let key = "\(event.title.lowercased())|\(event.start.timeIntervalSince1970)|\(event.end.timeIntervalSince1970)"
                guard seen.insert(key).inserted else { continue }
                if event.conferenceURL == nil {
                    event.conferenceURL = ConferenceLinkDetector.detect(
                        location: event.location, url: event.url, notes: event.notes)
                }
                result.append(event)
            }
        }
        return result.sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/TimeTugCore --filter CalendarStoreTests`
Expected: PASS (10 tests). Note: `swift-tools-version: 6.0` strict concurrency may flag the tuple-typed task group; if so, extract a `private struct SourceResult: Sendable` instead of the tuple.

- [ ] **Step 5: Run the whole Core suite**

Run: `swift test --package-path Packages/TimeTugCore`
Expected: PASS, no warnings about concurrency.

- [ ] **Step 6: Update the spec's dedupe wording and commit**

In `docs/superpowers/specs/2026-09-18-timetug-core-design.md`, replace `(by source event id + start + title)` with `(by lowercased title + start + end, so one meeting on several calendars appears once)`.

```bash
git add Packages/TimeTugCore docs
git commit -m "feat(core): add calendar store with merge, dedupe and last-good retention" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: DayAgenda

**Files:**
- Create: `Packages/TimeTugCore/Sources/TimeTugCore/Agenda/DayAgenda.swift`
- Test: `Packages/TimeTugCore/Tests/TimeTugCoreTests/DayAgendaTests.swift`

**Interfaces:**
- Consumes: `CalendarEvent`, `TakeoverSettings` (`hiddenCalendarKeys`, `leadTime`).
- Produces: `struct DayAgenda: Equatable, Sendable { enum State { past, current, upcoming }; struct Item: Equatable, Sendable, Identifiable { event; state }; items: [Item]; next: CalendarEvent? ; static let empty; static func make(events:settings:now:calendar:) -> DayAgenda }`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import TimeTugCore

private let now = date("2026-09-18T10:15:00Z")

private func agenda(_ events: [CalendarEvent], settings: TakeoverSettings = optedIn(),
                    at time: Date = now) -> DayAgenda {
    DayAgenda.make(events: events, settings: settings, now: time, calendar: utcCalendar)
}

@Test func marksPastCurrentUpcoming() {
    let past = makeEvent("p", start: "2026-09-18T09:00:00Z")       // ends 09:30
    let current = makeEvent("c", start: "2026-09-18T10:00:00Z")    // ends 10:30
    let upcoming = makeEvent("u", start: "2026-09-18T11:00:00Z")
    let result = agenda([past, current, upcoming])
    #expect(result.items.map(\.state) == [.past, .current, .upcoming])
}

@Test func nextIsFirstTimedEventStartingAfterNow() {
    let current = makeEvent("c", start: "2026-09-18T10:00:00Z")
    let allDay = makeEvent("a", start: "2026-09-18T00:00:00Z", minutes: 1440, isAllDay: true)
    let upcoming = makeEvent("u", start: "2026-09-18T11:00:00Z")
    #expect(agenda([allDay, current, upcoming]).next == upcoming)
}

@Test func nextIsNilWhenNothingRemains() {
    #expect(agenda([makeEvent(start: "2026-09-18T09:00:00Z")]).next == nil)
}

@Test func hiddenCalendarsAreExcluded() {
    let settings = optedIn { $0.hiddenCalendarKeys = ["fake/family"] }
    let result = agenda([makeEvent("a", calendarID: "family"), makeEvent("b")], settings: settings)
    #expect(result.items.map(\.event.sourceEventID) == ["b"])
}

@Test func includesEventsThatOverlapToday() {
    let overnight = makeEvent("n", start: "2026-09-17T23:30:00Z", minutes: 120)
    #expect(agenda([overnight]).items.count == 1)
}

@Test func excludesYesterdayAndFarTomorrow() {
    let yesterday = makeEvent("y", start: "2026-09-17T10:00:00Z")
    let tomorrow = makeEvent("t", start: "2026-09-19T10:00:00Z")
    #expect(agenda([yesterday, tomorrow]).items.isEmpty)
}

@Test func afterMidnightEventAppearsOnlyInsideLeadTime() {
    let event = makeEvent("m", start: "2026-09-19T00:05:00Z")
    let settings = optedIn { $0.leadTime = 600 }
    #expect(agenda([event], settings: settings, at: date("2026-09-18T23:40:00Z")).items.isEmpty)
    #expect(agenda([event], settings: settings, at: date("2026-09-18T23:56:00Z")).items.count == 1)
}

@Test func tomorrowsAllDayEventNeverSpillsIn() {
    let allDay = makeEvent("a", start: "2026-09-19T00:00:00Z", minutes: 1440, isAllDay: true)
    let settings = optedIn { $0.leadTime = 600 }
    #expect(agenda([allDay], settings: settings, at: date("2026-09-18T23:59:00Z")).items.isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path Packages/TimeTugCore --filter DayAgendaTests`
Expected: FAIL to compile ("cannot find 'DayAgenda'").

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Today's events as plain data for any front end. Presentation (greying, text) is the app's job.
public struct DayAgenda: Equatable, Sendable {
    public enum State: Equatable, Sendable { case past, current, upcoming }

    public struct Item: Equatable, Sendable, Identifiable {
        public let event: CalendarEvent
        public let state: State
        public var id: String { event.id }
    }

    public let items: [Item]
    /// First timed (non-all-day) event that has not started yet.
    public let next: CalendarEvent?

    public static let empty = DayAgenda(items: [], next: nil)

    public static func make(
        events: [CalendarEvent], settings: TakeoverSettings, now: Date, calendar: Calendar
    ) -> DayAgenda {
        let dayStart = calendar.startOfDay(for: now)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        let items = events
            .filter { !settings.hiddenCalendarKeys.contains($0.calendarKey) }
            .filter { event in
                if event.end > dayStart && event.start < nextDayStart { return true }
                // After-midnight events show only once inside their lead-time period.
                return !event.isAllDay
                    && event.start >= nextDayStart
                    && now >= event.start.addingTimeInterval(-settings.leadTime)
            }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
            .map { event -> Item in
                let state: State = event.end <= now ? .past : (event.start <= now ? .current : .upcoming)
                return Item(event: event, state: state)
            }

        let next = items.first { !$0.event.isAllDay && $0.event.start > now }?.event
        return DayAgenda(items: items, next: next)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path Packages/TimeTugCore`
Expected: PASS (whole Core suite).

- [ ] **Step 5: Commit**

```bash
git add Packages/TimeTugCore
git commit -m "feat(core): add day agenda view-state" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: EventKitSource

**Files:**
- Create: `Packages/EventKitSource/Package.swift`
- Create: `Packages/EventKitSource/Sources/EventKitSource/EventKitSource.swift`

**Interfaces:**
- Consumes: `CalendarSource`, `CalendarInfo`, `CalendarEvent`, `ResponseStatus`, `SourceError`.
- Produces: `public final class EventKitSource: CalendarSource` with `init()`, `func requestAccess() async -> Bool`, `id == "eventkit"`, `displayName == "Apple Calendar"`.

There is no automated test: `EKEventStore` needs user permission and real calendar data. It is verified manually in Task 8 (events appear in the popover). Keep the mapping logic in one small function.

- [ ] **Step 1: Package manifest**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EventKitSource",
    platforms: [.macOS(.v14)],
    products: [.library(name: "EventKitSource", targets: ["EventKitSource"])],
    dependencies: [.package(path: "../TimeTugCore")],
    targets: [
        .target(
            name: "EventKitSource",
            dependencies: [.product(name: "TimeTugCore", package: "TimeTugCore")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

- [ ] **Step 2: Implement**

```swift
import EventKit
import Foundation
import TimeTugCore

/// Apple Calendar via EventKit. Includes iCloud, Google and Exchange accounts the user has
/// added to macOS. EventKit types never leave this file.
public final class EventKitSource: CalendarSource, @unchecked Sendable {
    public let id = "eventkit"
    public let displayName = "Apple Calendar"
    private let store = EKEventStore()

    public init() {}

    /// Prompts for calendar access if undetermined. Returns whether access is granted.
    public func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    public func calendars() async throws -> [CalendarInfo] {
        try requireAccess()
        return store.calendars(for: .event).map {
            CalendarInfo(sourceID: id, calendarID: $0.calendarIdentifier, title: $0.title)
        }
    }

    public func events(in interval: DateInterval) async throws -> [CalendarEvent] {
        try requireAccess()
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        return store.events(matching: predicate).map(map)
    }

    public func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let token = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: store, queue: nil
            ) { _ in continuation.yield() }
            continuation.onTermination = { _ in NotificationCenter.default.removeObserver(token) }
        }
    }

    private func requireAccess() throws {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw SourceError.needsPermission
        }
    }

    private func map(_ event: EKEvent) -> CalendarEvent {
        let attendees = event.attendees ?? []
        let me = attendees.first { $0.isCurrentUser }
        let status: ResponseStatus
        switch me?.participantStatus {
        case .accepted: status = .accepted
        case .tentative: status = .tentative
        case .declined: status = .declined
        case .pending: status = .pending
        default: status = .unknown
        }
        return CalendarEvent(
            sourceEventID: event.eventIdentifier ?? event.calendarItemIdentifier,
            sourceID: id,
            calendarID: event.calendar.calendarIdentifier,
            title: event.title ?? "(No title)",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            otherAttendeeCount: attendees.filter { !$0.isCurrentUser }.count,
            responseStatus: status,
            location: event.location,
            notes: event.notes,
            url: event.url,
            conferenceURL: nil   // CalendarStore fills this from location/url/notes
        )
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build --package-path Packages/EventKitSource`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Packages/EventKitSource
git commit -m "feat(eventkit): add Apple Calendar source" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: macOS app shell, coordinator and scheduling loop

Result: a menu bar icon, calendar permission prompt, live refresh, and armed takeover timer that (for now) logs when it fires.

**Files:**
- Create: `Apps/macOS/project.yml`
- Create: `Apps/macOS/Sources/main.swift`, `AppDelegate.swift`, `AppModel.swift`, `AppCoordinator.swift`, `StatusItemController.swift`, `TimeFormatting.swift`, `SettingsStore.swift`
- Test: `Apps/macOS/Tests/TimeFormattingTests.swift`, `Apps/macOS/Tests/SettingsStoreTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1-7.
- Produces (used by Tasks 9-11):
  - `enum MenuBarDisplayMode: String, CaseIterable, Codable { iconOnly, nextMeeting, countdown }`
  - `@MainActor final class SettingsStore: ObservableObject` with `@Published var takeover: TakeoverSettings`, `@Published var menuBarMode: MenuBarDisplayMode`, `init(defaults: UserDefaults = .standard)`
  - `@MainActor final class AppModel: ObservableObject` with `@Published var agenda: DayAgenda`, `statuses: [String: SourceStatus]`, `sourceNames: [String: String]`, `calendars: [CalendarInfo]`
  - `enum TimeFormatting { static func compact(_ seconds: TimeInterval) -> String; static func clock(_ seconds: TimeInterval) -> String; static func statusTitle(mode:next:now:) -> String? }`
  - `AppCoordinator` with `start()`, `openSettings` hook, `fireTest()` (stubbed until Task 10/11)

- [ ] **Step 1: XcodeGen spec**

`Apps/macOS/project.yml`:
```yaml
name: TimeTug
options:
  bundleIdPrefix: com.timetug
  deploymentTarget:
    macOS: "14.0"
packages:
  TimeTugCore:
    path: ../../Packages/TimeTugCore
  EventKitSource:
    path: ../../Packages/EventKitSource
settings:
  base:
    SWIFT_VERSION: "5.0"
    CODE_SIGN_IDENTITY: "-"
    ENABLE_HARDENED_RUNTIME: YES
targets:
  TimeTug:
    type: application
    platform: macOS
    sources: [Sources]
    dependencies:
      - package: TimeTugCore
        product: TimeTugCore
      - package: EventKitSource
        product: EventKitSource
    info:
      path: Sources/Info.plist
      properties:
        CFBundleName: TimeTug
        LSUIElement: true
        NSCalendarsFullAccessUsageDescription: TimeTug reads your calendars to alert you before meetings start.
    entitlements:
      path: Sources/TimeTug.entitlements
      properties:
        com.apple.security.personal-information.calendars: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.timetug.app
  TimeTugTests:
    type: bundle.unit-test
    platform: macOS
    sources: [Tests]
    dependencies:
      - target: TimeTug
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
schemes:
  TimeTug:
    build:
      targets:
        TimeTug: all
    test:
      targets: [TimeTugTests]
```

- [ ] **Step 2: Write failing tests**

`Apps/macOS/Tests/TimeFormattingTests.swift`:
```swift
import Foundation
import TimeTugCore
import XCTest
@testable import TimeTug

final class TimeFormattingTests: XCTestCase {
    func testCompact() {
        XCTAssertEqual(TimeFormatting.compact(45), "45s")
        XCTAssertEqual(TimeFormatting.compact(60), "1m")
        XCTAssertEqual(TimeFormatting.compact(299), "4m")
        XCTAssertEqual(TimeFormatting.compact(3900), "1h 5m")
    }

    func testClock() {
        XCTAssertEqual(TimeFormatting.clock(245), "4:05")
        XCTAssertEqual(TimeFormatting.clock(5), "0:05")
        XCTAssertEqual(TimeFormatting.clock(-3), "0:00")
    }

    private func event(startingIn seconds: TimeInterval, from now: Date, title: String = "Design Review") -> CalendarEvent {
        CalendarEvent(sourceEventID: "1", sourceID: "s", calendarID: "c", title: title,
                      start: now.addingTimeInterval(seconds), end: now.addingTimeInterval(seconds + 1800))
    }

    func testStatusTitleIconOnlyIsNil() {
        let now = Date()
        XCTAssertNil(TimeFormatting.statusTitle(mode: .iconOnly, next: event(startingIn: 300, from: now), now: now))
    }

    func testStatusTitleCountdownOnly() {
        let now = Date()
        XCTAssertEqual(TimeFormatting.statusTitle(mode: .countdown, next: event(startingIn: 300, from: now), now: now), "4m")
    }

    func testStatusTitleNextMeetingTruncatesLongTitles() {
        let now = Date()
        let long = String(repeating: "x", count: 40)
        let title = TimeFormatting.statusTitle(mode: .nextMeeting, next: event(startingIn: 300, from: now, title: long), now: now)
        XCTAssertEqual(title, String(repeating: "x", count: 24) + "… · 4m")
    }

    func testStatusTitleNilWhenNoNextEvent() {
        XCTAssertNil(TimeFormatting.statusTitle(mode: .countdown, next: nil, now: Date()))
    }
}
```

`Apps/macOS/Tests/SettingsStoreTests.swift`:
```swift
import TimeTugCore
import XCTest
@testable import TimeTug

@MainActor
final class SettingsStoreTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "TimeTugTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testDefaultsWhenEmpty() {
        let store = SettingsStore(defaults: freshDefaults())
        XCTAssertEqual(store.takeover, TakeoverSettings())
        XCTAssertEqual(store.menuBarMode, .iconOnly)
    }

    func testPersistsChanges() {
        let defaults = freshDefaults()
        let store = SettingsStore(defaults: defaults)
        store.takeover.leadTime = 300
        store.takeover.takeoverCalendarKeys = ["eventkit/work"]
        store.menuBarMode = .countdown

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.takeover.leadTime, 300)
        XCTAssertEqual(reloaded.takeover.takeoverCalendarKeys, ["eventkit/work"])
        XCTAssertEqual(reloaded.menuBarMode, .countdown)
    }
}
```

- [ ] **Step 3: Implement formatting and settings store**

`Apps/macOS/Sources/TimeFormatting.swift`:
```swift
import Foundation
import TimeTugCore

/// macOS presentation text. Core supplies raw dates; wording and truncation live here.
enum TimeFormatting {
    /// "45s", "4m", "1h 5m".
    static func compact(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total >= 3600 { return "\(total / 3600)h \((total % 3600) / 60)m" }
        if total >= 60 { return "\(total / 60)m" }
        return "\(total)s"
    }

    /// "4:05".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Text next to the menu bar icon, or nil for icon-only / nothing upcoming.
    static func statusTitle(mode: MenuBarDisplayMode, next: CalendarEvent?, now: Date) -> String? {
        guard mode != .iconOnly, let next else { return nil }
        let remaining = compact(next.start.timeIntervalSince(now))
        switch mode {
        case .iconOnly: return nil
        case .countdown: return remaining
        case .nextMeeting:
            let title = next.title.count > 24 ? String(next.title.prefix(24)) + "…" : next.title
            return "\(title) · \(remaining)"
        }
    }
}
```

`Apps/macOS/Sources/SettingsStore.swift`:
```swift
import Foundation
import TimeTugCore

enum MenuBarDisplayMode: String, CaseIterable, Codable {
    case iconOnly, nextMeeting, countdown
}

/// Persists settings in UserDefaults. Core defines the shape; storage is the app's concern.
@MainActor
final class SettingsStore: ObservableObject {
    private static let takeoverKey = "takeoverSettings.v1"
    private static let modeKey = "menuBarMode.v1"
    private let defaults: UserDefaults

    @Published var takeover: TakeoverSettings {
        didSet { save() }
    }
    @Published var menuBarMode: MenuBarDisplayMode {
        didSet { defaults.set(menuBarMode.rawValue, forKey: Self.modeKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.takeover = defaults.data(forKey: Self.takeoverKey)
            .flatMap { try? JSONDecoder().decode(TakeoverSettings.self, from: $0) } ?? TakeoverSettings()
        self.menuBarMode = defaults.string(forKey: Self.modeKey)
            .flatMap(MenuBarDisplayMode.init(rawValue:)) ?? .iconOnly
    }

    private func save() {
        if let data = try? JSONEncoder().encode(takeover) {
            defaults.set(data, forKey: Self.takeoverKey)
        }
    }
}
```

- [ ] **Step 4: Implement shell files**

`Apps/macOS/Sources/AppModel.swift`:
```swift
import Foundation
import TimeTugCore

/// Observable state the SwiftUI views render.
@MainActor
final class AppModel: ObservableObject {
    @Published var agenda: DayAgenda = .empty
    @Published var calendars: [CalendarInfo] = []
    @Published var statuses: [String: SourceStatus] = [:]
    @Published var sourceNames: [String: String] = [:]
}
```

`Apps/macOS/Sources/main.swift`:
```swift
import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
```

`Apps/macOS/Sources/AppDelegate.swift`:
```swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        Task { await coordinator.start() }
    }
}
```

`Apps/macOS/Sources/StatusItemController.swift`:
```swift
import AppKit
import SwiftUI

/// Owns the menu bar item. Left click toggles the popover; right click shows Settings/Quit.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let onOpenSettings: () -> Void

    init(popoverContent: NSViewController, onOpenSettings: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        super.init()
        popover.behavior = .transient
        popover.contentViewController = popoverContent
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "alarm", accessibilityDescription: "TimeTug")
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    /// nil shows the icon only.
    func setTitle(_ text: String?) {
        let title = text.map { " " + $0 } ?? ""
        if item.button?.title != title { item.button?.title = title }
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else if let button = item.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit TimeTug", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func openSettings() { onOpenSettings() }
}
```

`Apps/macOS/Sources/AppCoordinator.swift`:
```swift
import AppKit
import Combine
import EventKitSource
import SwiftUI
import TimeTugCore

/// Wires sources, store, scheduler and the UI. Holds no presentation logic itself.
@MainActor
final class AppCoordinator {
    private static let periodicRefresh: TimeInterval = 300

    let settings = SettingsStore()
    let model = AppModel()

    private let eventKit = EventKitSource()
    private let store: CalendarStore
    private var snapshot = CalendarSnapshot.empty
    private var ledger = TakeoverLedger()
    private var fireTimer: Timer?
    private var tickTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var statusItem: StatusItemController?

    init() {
        store = CalendarStore(sources: [eventKit])
    }

    func start() async {
        statusItem = StatusItemController(
            popoverContent: NSHostingController(rootView: Text("TimeTug")),   // replaced in Task 9
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
        _ = await eventKit.requestAccess()
        observeSystemEvents()
        settings.$takeover.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.rearm(); self?.updateUI() }
        }.store(in: &cancellables)
        settings.$menuBarMode.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.updateUI() }
        }.store(in: &cancellables)

        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateUI() }
        }
        Timer.scheduledTimer(withTimeInterval: Self.periodicRefresh, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        await refresh()
        if settings.takeover.takeoverCalendarKeys.isEmpty { openSettings() }

        for await _ in eventKit.changes() { await refresh() }
    }

    func refresh() async {
        snapshot = await store.refresh(now: Date(), leadTime: settings.takeover.leadTime)
        model.calendars = snapshot.calendars
        model.statuses = snapshot.statuses
        model.sourceNames = snapshot.sourceNames
        ledger.prune(now: Date())
        rearm()
        updateUI()
    }

    /// Arms one timer for the next takeover. Skipped while an overlay is up (see Task 10).
    func rearm() {
        fireTimer?.invalidate()
        fireTimer = nil
        guard !isOverlayVisible,
              let next = Scheduler.next(events: snapshot.events, settings: settings.takeover,
                                        ledger: ledger, now: Date()) else { return }
        let timer = Timer(fire: next.fireAt, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fire(next.event) }
        }
        RunLoop.main.add(timer, forMode: .common)
        fireTimer = timer
    }

    private func fire(_ event: CalendarEvent) {
        ledger.markFired(event)
        present(TakeoverRequest.make(for: event, now: Date()))
    }

    func updateUI() {
        let now = Date()
        let agenda = DayAgenda.make(events: snapshot.events, settings: settings.takeover,
                                    now: now, calendar: .current)
        if agenda != model.agenda { model.agenda = agenda }
        statusItem?.setTitle(TimeFormatting.statusTitle(mode: settings.menuBarMode, next: agenda.next, now: now))
    }

    /// Timers alone are not trusted: recompute after wake, clock, timezone and day changes.
    private func observeSystemEvents() {
        let recompute: (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: recompute)
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange, .NSCalendarDayChanged] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main, using: recompute)
        }
    }

    // MARK: Stubs replaced in later tasks

    private var isOverlayVisible: Bool { false }
    private func present(_ request: TakeoverRequest) {
        print("TAKEOVER:", request.event.title)   // replaced in Task 10
    }
    func openSettings() {}                        // replaced in Task 11
}
```

- [ ] **Step 5: Generate project and run tests to verify they fail, then pass**

Run: `xcodegen generate --spec Apps/macOS/project.yml`
Expected: `Created project at .../Apps/macOS/TimeTug.xcodeproj`

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test`
Expected: `** TEST SUCCEEDED **` (7 tests). If it fails to compile, fix the code, not the tests.

- [ ] **Step 6: Manual verification**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' -derivedDataPath build/DerivedData build && open build/DerivedData/Build/Products/Debug/TimeTug.app`
Expected: an alarm icon appears in the menu bar and macOS asks for calendar access; after allowing, no crash. Right click shows Settings…/Quit. (Add `build/` to `.gitignore`.)

- [ ] **Step 7: Commit**

```bash
echo "build/" >> .gitignore
git add .gitignore Apps
git commit -m "feat(macos): add menu bar shell, coordinator and scheduling loop" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 9: Dropdown popover

**Files:**
- Create: `Apps/macOS/Sources/DropdownView.swift`
- Modify: `Apps/macOS/Sources/AppCoordinator.swift` (popover content)

**Interfaces:**
- Consumes: `AppModel`, `DayAgenda`, `SourceStatus`.
- Produces: `DropdownView(model: AppModel, onOpenSettings: () -> Void)`.

Rendering only; no new logic to unit test (agenda rules are tested in Core). Verified manually.

- [ ] **Step 1: Implement the view**

```swift
import SwiftUI
import TimeTugCore

struct DropdownView: View {
    @ObservedObject var model: AppModel
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(problems, id: \.sourceID) { problem in
                ProblemRow(message: problem.message, showsPrivacyLink: problem.status == .needsPermission)
            }
            if model.agenda.items.isEmpty {
                Text("No events today")
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(model.agenda.items) { EventRow(item: $0) }
                    }
                }
                .frame(maxHeight: 420)
            }
            Divider()
            HStack {
                Spacer()
                Button("Settings…", action: onOpenSettings).buttonStyle(.link)
            }
            .padding(10)
        }
        .frame(width: 340)
    }

    private struct Problem { let sourceID: String; let status: SourceStatus; let message: String }

    private var problems: [Problem] {
        model.statuses.compactMap { sourceID, status in
            let name = model.sourceNames[sourceID] ?? sourceID
            switch status {
            case .ok: return nil
            case .needsPermission: return Problem(sourceID: sourceID, status: status, message: "\(name) access denied")
            case .authExpired: return Problem(sourceID: sourceID, status: status, message: "\(name) needs you to sign in again")
            case .failing(let reason): return Problem(sourceID: sourceID, status: status, message: "\(name) failed: \(reason)")
            }
        }
        .sorted { $0.sourceID < $1.sourceID }
    }
}

private struct ProblemRow: View {
    let message: String
    let showsPrivacyLink: Bool

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.callout)
            Spacer()
            if showsPrivacyLink {
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                }
                .buttonStyle(.link)
            }
        }
        .padding(10)
        .background(.orange.opacity(0.12))
    }
}

private struct EventRow: View {
    let item: DayAgenda.Item

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Group {
                if item.event.isAllDay {
                    Text("All day")
                } else {
                    Text(item.event.start, style: .time)
                }
            }
            .font(.callout.monospacedDigit())
            .frame(width: 64, alignment: .leading)

            Text(item.event.title)
                .fontWeight(item.state == .current ? .semibold : .regular)
                .lineLimit(1)
            Spacer(minLength: 0)
            if item.state == .current {
                Circle().fill(.tint).frame(width: 7, height: 7)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(item.state == .past ? .secondary : .primary)
        .opacity(item.state == .past ? 0.55 : 1)
    }
}
```

- [ ] **Step 2: Use it as the popover content**

In `AppCoordinator.start()`, replace the placeholder `popoverContent:` argument:
```swift
popoverContent: NSHostingController(
    rootView: DropdownView(model: model, onOpenSettings: { [weak self] in self?.openSettings() })
),
```

- [ ] **Step 3: Build and manually verify**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' -derivedDataPath build/DerivedData build`
Expected: `** BUILD SUCCEEDED **`. Launch the app, left click the icon: today's events appear (all calendars visible, since none are hidden by default); ended events are greyed, the in-progress one is bold with a dot; with calendar access denied, an orange banner with "Open System Settings" appears.

- [ ] **Step 4: Commit**

```bash
git add Apps
git commit -m "feat(macos): add today's-events dropdown popover" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 10: Takeover overlay

**Files:**
- Create: `Apps/macOS/Sources/OverlayController.swift`, `Apps/macOS/Sources/OverlayView.swift`
- Modify: `Apps/macOS/Sources/AppCoordinator.swift` (replace the `isOverlayVisible` / `present` stubs, add `fireTest`)

**Interfaces:**
- Consumes: `TakeoverRequest`, `TakeoverLedger.snooze`, `TimeFormatting.compact/clock`.
- Produces:
  - `OverlayController.Actions { join, snooze(TimeInterval), dismiss }`
  - `OverlayController.show(_:actions:)`, `hide()`, `isVisible`
  - `AppCoordinator.fireTest()` (used by Task 11)

- [ ] **Step 1: Overlay views**

`OverlayView.swift`:
```swift
import SwiftUI
import TimeTugCore

struct OverlayView: View {
    let request: TakeoverRequest
    let onJoin: () -> Void
    let onSnooze: (TimeInterval) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 24) {
                Text(request.event.title)
                    .font(.system(size: 56, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Text(request.event.start, style: .time)
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    countdown(now: context.date)
                }
                if request.joinURL != nil {
                    Button(action: onJoin) {
                        Text("Join").font(.system(size: 28, weight: .semibold)).padding(.horizontal, 48).padding(.vertical, 10)
                    }
                    .keyboardShortcut(.defaultAction)   // Return
                    .controlSize(.extraLarge)
                    .buttonStyle(.borderedProminent)
                }
                HStack(spacing: 12) {
                    ForEach(request.snoozeOptions, id: \.self) { seconds in
                        Button("Snooze \(Int(seconds / 60))m") { onSnooze(seconds) }
                    }
                    Button("Dismiss", action: onDismiss)
                        .keyboardShortcut(.cancelAction)   // Esc
                }
                .controlSize(.large)
            }
            .foregroundStyle(.white)
            .padding(60)
        }
        .preferredColorScheme(.dark)
    }

    private func countdown(now: Date) -> some View {
        let remaining = request.event.start.timeIntervalSince(now)
        let text = remaining > 0
            ? "Starts in \(TimeFormatting.clock(remaining))"
            : (remaining > -60 ? "Starting now" : "Started \(TimeFormatting.compact(-remaining)) ago")
        return Text(text)
            .font(.system(size: 40, weight: .medium).monospacedDigit())
            .foregroundStyle(remaining > 0 ? .white : .orange)
    }
}

struct DimCoverView: View {
    let title: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            Text(title).font(.system(size: 40, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
        }
    }
}
```

`OverlayController.swift`:
```swift
import AppKit
import SwiftUI
import TimeTugCore

/// A borderless window per display at a high level so it covers full-screen apps.
@MainActor
final class OverlayController {
    struct Actions {
        let join: () -> Void
        let snooze: (TimeInterval) -> Void
        let dismiss: () -> Void
    }

    private final class OverlayWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    private var windows: [NSWindow] = []
    private var request: TakeoverRequest?
    private var actions: Actions?
    private var screenObserver: NSObjectProtocol?

    var isVisible: Bool { !windows.isEmpty }

    func show(_ request: TakeoverRequest, actions: Actions) {
        self.request = request
        self.actions = actions
        rebuild()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }

    func hide() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        request = nil
        actions = nil
        closeWindows()
    }

    private func closeWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func rebuild() {
        closeWindows()
        guard let request, let actions else { return }
        for (index, screen) in NSScreen.screens.enumerated() {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless,
                                       backing: .buffered, defer: false)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: index == 0
                ? AnyView(OverlayView(request: request, onJoin: actions.join,
                                      onSnooze: actions.snooze, onDismiss: actions.dismiss))
                : AnyView(DimCoverView(title: request.event.title)))
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            if index == 0 { window.makeKey() }
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 2: Wire it into the coordinator**

In `AppCoordinator`, add `private let overlay = OverlayController()` and replace the "Stubs replaced in later tasks" `isOverlayVisible` and `present` with:
```swift
    private var isOverlayVisible: Bool { overlay.isVisible }

    private func present(_ request: TakeoverRequest) {
        let event = request.event
        overlay.show(request, actions: .init(
            join: { [weak self] in
                if let url = request.joinURL { NSWorkspace.shared.open(url) }
                self?.closeOverlay()
            },
            snooze: { [weak self] seconds in
                self?.ledger.snooze(event, for: seconds, now: Date())
                self?.closeOverlay()
            },
            dismiss: { [weak self] in self?.closeOverlay() }
        ))
    }

    private func closeOverlay() {
        overlay.hide()
        rearm()
    }

    /// Settings' "Test takeover" button: a sample event that never touches the ledger.
    func fireTest() {
        let now = Date()
        let sample = CalendarEvent(
            sourceEventID: "test", sourceID: "test", calendarID: "test", title: "Sample meeting",
            start: now.addingTimeInterval(settings.takeover.leadTime),
            end: now.addingTimeInterval(settings.takeover.leadTime + 1800),
            otherAttendeeCount: 1, conferenceURL: URL(string: "https://meet.google.com/aaa-bbbb-ccc"))
        overlay.show(TakeoverRequest.make(for: sample, now: now), actions: .init(
            join: { [weak self] in self?.overlay.hide() },
            snooze: { [weak self] _ in self?.overlay.hide() },
            dismiss: { [weak self] in self?.overlay.hide() }
        ))
    }
```
Delete the old `print("TAKEOVER:")` stub. Keep the `openSettings()` stub for Task 11.

- [ ] **Step 3: Build**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' -derivedDataPath build/DerivedData build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual verification**

Temporarily call `fireTest()` at the end of `start()`, launch, and confirm: a black cover on every display, Join opens the Meet URL and closes the overlay, Return joins, Esc dismisses, Snooze closes it. Unplug or plug in a display while shown and confirm it rebuilds. Remove the temporary `fireTest()` call before committing.

- [ ] **Step 5: Commit**

```bash
git add Apps
git commit -m "feat(macos): add multi-display takeover overlay" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 11: Settings window

**Files:**
- Create: `Apps/macOS/Sources/SettingsView.swift`, `Apps/macOS/Sources/SettingsWindowController.swift`
- Modify: `Apps/macOS/Sources/AppCoordinator.swift` (`openSettings`)

**Interfaces:**
- Consumes: `SettingsStore`, `AppModel.calendars`, `AppCoordinator.fireTest()`.
- Produces: `SettingsWindowController.show()`.

- [ ] **Step 1: Implement the settings view**

`SettingsView.swift`:
```swift
import ServiceManagement
import SwiftUI
import TimeTugCore

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: AppModel
    let onTestTakeover: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Takeover") {
                Stepper(value: leadMinutes, in: 0...30) {
                    Text(settings.takeover.leadTime == 0
                         ? "Lead time: at start"
                         : "Lead time: \(Int(settings.takeover.leadTime / 60)) min before")
                }
                Toggle("Only events with a video link", isOn: $settings.takeover.requireConferenceLink)
                Toggle("Skip events with no other attendees", isOn: $settings.takeover.skipSoloEvents)
                Toggle("Skip declined events", isOn: $settings.takeover.skipDeclinedEvents)
                Button("Test takeover", action: onTestTakeover)
            }

            Section("Calendars") {
                if model.calendars.isEmpty {
                    Text("No calendars found. Check calendar access in System Settings.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.calendars) { calendar in
                    HStack {
                        Text(calendar.title)
                        Spacer()
                        Toggle("Takeover", isOn: membership(\.takeoverCalendarKeys, calendar.key))
                        Toggle("Show in list", isOn: shown(calendar.key))
                    }
                    .toggleStyle(.checkbox)
                }
                Text("Takeover is opt-in per calendar. Calendars are shown in the list by default.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Menu bar") {
                Picker("Next to the icon", selection: $settings.menuBarMode) {
                    Text("Icon only").tag(MenuBarDisplayMode.iconOnly)
                    Text("Next meeting").tag(MenuBarDisplayMode.nextMeeting)
                    Text("Countdown only").tag(MenuBarDisplayMode.countdown)
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        if enabled { try? SMAppService.mainApp.register() }
                        else { try? SMAppService.mainApp.unregister() }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
    }

    private var leadMinutes: Binding<Int> {
        Binding(
            get: { Int(settings.takeover.leadTime / 60) },
            set: { settings.takeover.leadTime = TimeInterval($0 * 60) }
        )
    }

    private func membership(_ keyPath: WritableKeyPath<TakeoverSettings, Set<String>>, _ key: String) -> Binding<Bool> {
        Binding(
            get: { settings.takeover[keyPath: keyPath].contains(key) },
            set: { on in
                if on { settings.takeover[keyPath: keyPath].insert(key) }
                else { settings.takeover[keyPath: keyPath].remove(key) }
            }
        )
    }

    /// "Show in list" is the inverse of membership in `hiddenCalendarKeys`.
    private func shown(_ key: String) -> Binding<Bool> {
        let hidden = membership(\.hiddenCalendarKeys, key)
        return Binding(get: { !hidden.wrappedValue }, set: { hidden.wrappedValue = !$0 })
    }
}
```

`SettingsWindowController.swift`:
```swift
import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let content: () -> SettingsView

    init(content: @escaping () -> SettingsView) { self.content = content }

    func show() {
        if window == nil {
            let created = NSWindow(contentViewController: NSHostingController(rootView: content()))
            created.title = "TimeTug Settings"
            created.styleMask = [.titled, .closable]
            created.isReleasedWhenClosed = false
            window = created
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 2: Wire `openSettings`**

In `AppCoordinator`, add:
```swift
    private lazy var settingsWindow = SettingsWindowController { [unowned self] in
        SettingsView(settings: settings, model: model, onTestTakeover: { [weak self] in self?.fireTest() })
    }
```
and replace the stub with `func openSettings() { settingsWindow.show() }`.

- [ ] **Step 3: Build and run all tests**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Manual verification**

Launch with a fresh defaults domain (`defaults delete com.timetug.app`). Expected: Settings opens automatically (no calendars opted in); calendars listed with two checkboxes each; opting a calendar in and setting lead time 1 min then creating a test event 2 minutes out on that calendar with another attendee produces a takeover 1 minute before start; "Test takeover" shows the overlay; menu bar modes change the title text; right-click Settings… opens the window.

- [ ] **Step 5: Commit**

```bash
git add Apps
git commit -m "feat(macos): add settings window" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 12: Docs (architecture, ADRs, manual checklist)

**Files:**
- Create: `docs/architecture.md`
- Create: `docs/decisions/0001-swift-and-native-stack.md`, `0002-core-source-app-boundaries.md`, `0003-current-day-window-with-lead-buffer.md`, `0004-conference-link-allowlist.md`
- Create: `docs/manual-tests/macos-checklist.md`

- [ ] **Step 1: Write `docs/architecture.md`**

```markdown
# Architecture

Read `docs/superpowers/specs/2026-09-18-timetug-core-design.md` for the full design. This is the map.

## Modules
- `Packages/TimeTugCore`: pure Swift. `CalendarEvent` model, `CalendarSource` protocol, `CalendarStore`
  (merge/dedupe/last-good), `TakeoverPolicy`, `TakeoverLedger` + `Scheduler`, `ConferenceLinkDetector`,
  `DayAgenda`, `TakeoverRequest`, `TakeoverSettings`.
- `Packages/EventKitSource`: Apple Calendar adapter. Only place EventKit is imported.
- `Apps/macOS`: menu bar item, popover, overlay windows, settings, wiring (`AppCoordinator`).

## Flow
EventKit -> `CalendarStore.refresh` (fetch window) -> `CalendarSnapshot` -> `Scheduler.next` -> one timer
-> `TakeoverRequest` -> `OverlayController`. `DayAgenda.make` feeds the popover and the status title.

## Adding a calendar source
Implement `CalendarSource` in a new package under `Packages/`, return only Core's model, throw
`SourceError` for permission/auth problems, and register the source in `AppCoordinator`. Never import
UI frameworks; never leak source-specific types.

## Adding a platform front end
Depend on `TimeTugCore` only. Decide for yourself whether a status bar exists and what it shows, how
the takeover looks, and where settings live.
```

- [ ] **Step 2: Write the four ADRs** (each: Status, Context, Decision, Consequences; 10-20 lines, drawn from the spec's decision table and the rationale in the design conversation: Swift over Rust/Tauri; Core/Source/App one-way boundaries with presentation in the native app; current-day display window plus lead+buffer fetch; provider allowlist rather than any-URL).

- [ ] **Step 3: Write `docs/manual-tests/macos-checklist.md`**

```markdown
# macOS manual checklist
Run before a release, and after touching overlay, status item or scheduling code.

- [ ] First launch with no opted-in calendars opens Settings.
- [ ] Denying calendar access shows the orange banner with a working "Open System Settings" link.
- [ ] Popover: ended events greyed, in-progress bold with dot, all-day shows "All day".
- [ ] Takeover fires at lead time on every connected display; lead time 0 fires at start.
- [ ] Join opens the link and closes the overlay; Return joins; Esc dismisses; Snooze re-fires later.
- [ ] Overlay covers a full-screen app and follows display plug/unplug.
- [ ] Sleep the Mac through a meeting start; on wake with the meeting in progress the overlay appears with "Started N ago".
- [ ] Changing the system clock/timezone recomputes the schedule.
- [ ] A meeting at 12:05 AM with a 10 min lead fires at 11:55 PM and does not repeat after midnight.
- [ ] Declined, solo, all-day and non-opted-in events never take over.
- [ ] Menu bar modes: icon only, next meeting (long titles truncated), countdown only.
- [ ] Launch at login toggle works.
```

- [ ] **Step 4: Commit**

```bash
git add docs
git commit -m "docs: add architecture map, ADRs and macOS manual checklist" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 13: Brand assets, README and public-repo hygiene

The artwork is already copied into the repo (committed before this task): `artwork/Branding/`, `artwork/GitHub/`, `Apps/macOS/Resources/Assets.xcassets/` (AppIcon, MenuBarTemplate, MenuBarColor) and `docs/ARTWORK_USAGE.md`. Read `docs/ARTWORK_USAGE.md` first. The repo will be published publicly on GitHub, so nothing private may be committed.

**Files:**
- Modify: `Apps/macOS/project.yml` (add the `Resources` source and app icon setting)
- Modify: `Apps/macOS/Sources/StatusItemController.swift` (use the `MenuBarTemplate` asset)
- Create: `README.md`
- Modify: `AGENTS.md` (artwork pointers)

**Interfaces:**
- Consumes: asset names `AppIcon`, `MenuBarTemplate`, `MenuBarColor`; `StatusItemController.init` from Task 8.
- Produces: none.

- [ ] **Step 1: Add the asset catalog to the app target**

In `Apps/macOS/project.yml`, change the `TimeTug` target's `sources` to `[Sources, Resources]` and add under that target's `settings.base`:
```yaml
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
```

- [ ] **Step 2: Use the template menu bar icon**

In `StatusItemController.init`, replace the SF Symbol line
`button.image = NSImage(systemSymbolName: "alarm", accessibilityDescription: "TimeTug")` with:
```swift
            let image = NSImage(named: "MenuBarTemplate")
                ?? NSImage(systemSymbolName: "alarm", accessibilityDescription: "TimeTug")
            image?.isTemplate = true            // the OS tints it for light/dark menu bars
            image?.accessibilityDescription = "TimeTug"
            button.image = image
```
Do not use `MenuBarColor` yet: a "meeting soon" color state is a possible follow-up, not part of this plan.

- [ ] **Step 3: Build and verify**

Run: `xcodegen generate --spec Apps/macOS/project.yml`, then `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' -derivedDataPath build/DerivedData build`
Expected: `** BUILD SUCCEEDED **` with no asset catalog warnings. Confirm the built app bundle contains `Assets.car` and an `AppIcon` (`ls build/DerivedData/Build/Products/Debug/TimeTug.app/Contents/Resources`). Launch it: the menu bar shows the dog icon, tinted correctly in both light and dark menu bars.

- [ ] **Step 4: Write `README.md`**

Use this structure (plain, accurate to what the plan built; do not claim features that are not implemented):
```markdown
<p align="center">
  <img src="artwork/GitHub/timetug-readme-banner.png" alt="TimeTug: a tug when time needs your attention">
</p>

# TimeTug

A tug when time needs your attention. TimeTug lives in your macOS menu bar, lists today's meetings,
and takes over every screen shortly before a meeting starts, so you don't hyperfocus through it.

## Features
- Reads Apple Calendar (iCloud, Google and Exchange accounts added to macOS) via EventKit
- Full-screen takeover on every display at a configurable lead time (0 = "starting now"), with Join, Snooze and Dismiss
- Detects Zoom, Meet, Teams, Webex and similar links for a one-click Join
- Per-calendar opt-in for takeovers; skips all-day, declined and solo events by default
- Menu bar: icon only (default), next meeting, or countdown

## Build
Requires macOS 14+ and Xcode 27.
    xcodegen generate --spec Apps/macOS/project.yml
    xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' build
Core logic tests: `swift test --package-path Packages/TimeTugCore`

## Architecture
`Packages/TimeTugCore` (portable logic), `Packages/EventKitSource` (Apple Calendar), `Apps/macOS` (the app).
See `docs/architecture.md`. Agents and contributors: read `AGENTS.md`.

## Status
Early development. No license has been chosen yet.
```
(Indent the two build commands as a fenced ```bash block in the real file.)

- [ ] **Step 5: Public-repo hygiene check**

Run: `git ls-files | grep -Ei '\.(env|pem|p12|key)$|secret|credential' ; grep -RIn --exclude-dir=.git --exclude-dir=.build --exclude-dir=build --exclude=*.png -E 'BEGIN [A-Z ]*PRIVATE KEY|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}' .`
Expected: no output. Also confirm `.gitignore` covers `.superpowers/`, `build/`, `*.xcodeproj`, `.build/`.

- [ ] **Step 6: Add artwork pointers to `AGENTS.md`**

Append under Layout: `- \`artwork/\`: brand images (see \`docs/ARTWORK_USAGE.md\`); the app's asset catalog is \`Apps/macOS/Resources/Assets.xcassets\`. Do not use the app icon for the menu bar; use the \`MenuBarTemplate\` template image.`

- [ ] **Step 7: Commit**

```bash
git add README.md AGENTS.md Apps/macOS/project.yml Apps/macOS/Sources/StatusItemController.swift
git commit -m "feat(macos): use brand app icon and menu bar template image; add README" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- Lead-time takeover, lead time 0 = starting now: Tasks 4, 8, 10, 11.
- Per-calendar opt-in + default filters + video-link toggle: Tasks 3, 11.
- Dropdown with greyed past events, opted-in/visibility split: Tasks 6, 9, 11.
- Menu bar modes (icon default, next meeting, countdown), right-click settings: Tasks 8, 11.
- Sources isolated behind `CalendarSource`; open-source layout: Tasks 1, 7, 12.
- Current-day window + lead/buffer fetch, after-midnight display rule and no-repeat pruning: Tasks 4, 5, 6.
- Sleep/wake/clock/timezone/day-change recompute, late fire, snooze cap, failure isolation, last-good: Tasks 4, 5, 8.
- Conference detection (structured + allowlist fallback, unwrapping, url fallback): Tasks 2, 5.
- Overlay: per-display, high level, Join/Snooze/Dismiss, keyboard, started-late text, display changes: Task 10. Reduce-motion: the overlay uses no animation, so nothing to suppress.
- AI-first practices (AGENTS.md, ADRs, tests, manual checklist): Tasks 1, 12.
- Settings incl. launch at login and test button: Task 11.

**Known gaps to accept or handle later:** snapshot tests for overlay layouts (spec said "if cheap"; deferred); EventKitSource has no automated test (needs real permissions); zero-length events (end == start) never fire at lead time 0.

**Type consistency check:** `CalendarEvent.id`/`calendarKey`, `TakeoverLedger.entry(for:)` (internal, used only via `@testable`), `Scheduler.next(events:settings:ledger:now:)`, `TakeoverRequest.make(for:now:)`, `CalendarStore.refresh(now:leadTime:)`, `DayAgenda.make(events:settings:now:calendar:)`, `MenuBarDisplayMode` are used identically across tasks.
