# Calendar connectors Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Plug the Phase 1 connector library into TimeTug: Google accounts and Apple Calendar (EventKit) both flow through the library abstraction into `CalendarStore`, managed from a new Accounts tab in Settings.

**Architecture:** A new `CalendarBridge` package (depends on `TimeTugCore` and `CalendarCore`) maps library types to TimeTug's and adapts a library source to Core's `CalendarSource`. Generic stores (`FileConnectionStore`, `FileSyncStateStore`) and an all-day helper live in `CalendarCore`. OS-specific code (Keychain, Network.framework loopback) lives in a new `CalendarApple` adapter package; `EventKitSource` becomes a library `CalendarSource` plus an `EventKitConnectorKind`. The app wires these with a `SourceReconciler` and an `AccountsController`.

**Tech Stack:** Swift 6 packages (Swift Testing), Swift 5 mode for `EventKitSource`, `CalendarApple` and the app (XCTest), XcodeGen, SwiftUI. Spec: `docs/superpowers/specs/2026-09-20-calendar-connectors-phase2-design.md` (read it for rationale).

## Global Constraints

- `TimeTugCore` stays pure Swift 6, no Apple-only imports, and **no dependency on `CalendarConnectors`** (swift-crypto needs Swift 6.2; `core-linux` runs `swift:6.0`).
- `CalendarCore` and `GoogleCalendar` stay free of Apple-only imports. The only library API additions: `SourceError.needsPermission`, `AllDay` / `CalendarDate`, `FileConnectionStore`, `FileSyncStateStore`, `AllDayConformance` (test support).
- `EventKitSource`, `CalendarApple` and the app are Swift 5 language mode; `CalendarBridge` is Swift 6.
- Stored calendar selections are `sourceID/calendarID` strings. EventKit's source id stays `"eventkit"`. The app and reconciler identify a source by the built source's `id`, never by computing `Connection.sourceID` (for Google they are equal; a test asserts it).
- All-day events are dates: connectors emit the library's canonical form (midnight of the first day in `timeZone`, exclusive end, non-nil zone); only the bridge converts to TimeTug's device-local form; no other code compensates.
- Library layering: OS-specific code only in separate adapter packages implementing library protocols. Generic code goes in `CalendarCore`.
- New `Codable` fields use `decodeIfPresent` with defaults. Core/library/bridge tests use Swift Testing and are written first; app tests are XCTest.
- No secrets in the repo: OAuth client values come from a git-ignored xcconfig; user credentials only in the Keychain.
- Commit trailer on every commit: `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.
- Work lands only via a pull request to `master` with CI green (never a local merge).

## File Structure

| Path | Responsibility |
|---|---|
| `Packages/TimeTugCore/.../Model/TimeTugCalendarEvent.swift` (new), `Model/CalendarInfo.swift` (renamed from `CalendarEvent.swift`) | TimeTug's event type after the rename; `CalendarInfo` and `ResponseStatus` stay together |
| `Packages/TimeTugCore/.../Store/CalendarStore.swift` | `setSources`, generation guard |
| `Packages/TimeTugCore/.../Model/TakeoverSettings.swift` | `removeCalendars` |
| `Packages/CalendarConnectors/Sources/CalendarCore/{AllDay,FileConnectionStore,FileSyncStateStore}.swift` | Generic all-day helper and file stores |
| `Packages/CalendarConnectors/Sources/CalendarTestSupport/AllDayConformance.swift` | Canonical-form checker for connector tests |
| `Packages/CalendarBridge/` (new) | `EventMapper`, `ConnectedSource` |
| `Packages/EventKitSource/` | Library `CalendarSource`, `EventKitConnectorKind`, pure mapping helpers, tests |
| `Packages/CalendarApple/` (new) | `KeychainCredentialStore`, `LoopbackAuthorizationInteraction` |
| `Apps/macOS/Sources/{SourceReconciler,AccountsController,AccountsPane,AccountStatusText,AppConnectors,GoogleOAuthSettings,AppSupportFiles}.swift` | App wiring and UI |

---

### Task 1: Rename `CalendarEvent` to `TimeTugCalendarEvent` (mechanical)

**Files:**
- Modify (by script): every Swift file under `Packages/` (except `Packages/CalendarConnectors`) and `Apps/` that uses the word `CalendarEvent`; docs `docs/architecture.md`, `docs/decisions/0002-core-source-app-boundaries.md`, `0006-takeover-ledger-persistence-and-fire-guard.md`, `0009-duplicate-detection-and-on-device-inference.md`
- Create: `Packages/TimeTugCore/Sources/TimeTugCore/Model/TimeTugCalendarEvent.swift`
- Rename: `Model/CalendarEvent.swift` to `Model/CalendarInfo.swift`

**Interfaces:**
- Produces: `public struct TimeTugCalendarEvent` (identical members to today's `CalendarEvent`). `CalendarInfo`, `ResponseStatus` unchanged. Historical plans/specs are left untouched.

- [ ] **Step 1: Baseline.** Run and note the test counts:
  `swift test --package-path Packages/TimeTugCore` (expect all pass)
  `swift build --package-path Packages/EventKitSource`
  `swift test --package-path Packages/AppleIntelligenceInference`

- [ ] **Step 2: Rename references.** From the repo root:

```bash
git grep -lw CalendarEvent -- Packages Apps \
  docs/architecture.md docs/decisions/0002-core-source-app-boundaries.md \
  docs/decisions/0006-takeover-ledger-persistence-and-fire-guard.md \
  docs/decisions/0009-duplicate-detection-and-on-device-inference.md \
  ':!Packages/CalendarConnectors' \
  | xargs perl -pi -e 's/\bCalendarEvent\b/TimeTugCalendarEvent/g'
```

- [ ] **Step 3: Split the model file.**

```bash
cd Packages/TimeTugCore/Sources/TimeTugCore/Model
git mv CalendarEvent.swift CalendarInfo.swift
python3 - <<'EOF'
s = open('CalendarInfo.swift').read()
i = s.index('public struct TimeTugCalendarEvent')
open('TimeTugCalendarEvent.swift', 'w').write('import Foundation\n\n' + s[i:])
open('CalendarInfo.swift', 'w').write(s[:i].rstrip() + '\n')
EOF
cd -
```

- [ ] **Step 4: Verify nothing was missed and nothing broke.**

```bash
git grep -nw CalendarEvent -- Packages Apps ':!Packages/CalendarConnectors'   # expect no output
swift test --package-path Packages/TimeTugCore
swift build --package-path Packages/EventKitSource
swift test --package-path Packages/AppleIntelligenceInference
xcodegen generate --spec Apps/macOS/project.yml
xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test
```
Expected: identical pass counts to Step 1; `git diff --stat` shows only renames (no logic changes; skim `git diff -w --word-diff` for anything that is not the identifier).

- [ ] **Step 5: Commit.**

```bash
git add -A Packages Apps docs
git commit -m "refactor: rename CalendarEvent to TimeTugCalendarEvent

Frees the name CalendarEvent for the connector library's generic event.
Names only; no behavior change.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Core: `setSources` and `removeCalendars`

**Files:**
- Modify: `Packages/TimeTugCore/Sources/TimeTugCore/Store/CalendarStore.swift`
- Modify: `Packages/TimeTugCore/Sources/TimeTugCore/Model/TakeoverSettings.swift`
- Create: `Packages/TimeTugCore/Tests/TimeTugCoreTests/CalendarStoreSourcesTests.swift`
- Create: `Packages/TimeTugCore/Tests/TimeTugCoreTests/TakeoverSettingsRemovalTests.swift`

**Interfaces:**
- Produces:
  - `CalendarStore.setSources(_ sources: [any CalendarSource])` (actor method, no `async` needed by callers beyond `await`)
  - `TakeoverSettings.removeCalendars(forSourceID: String)` and `TakeoverSettings.removeCalendars(whereSourceID: (String) -> Bool)`; a key's source id is the text before the first `/`.

- [ ] **Step 1: Write the failing settings tests.** `TakeoverSettingsRemovalTests.swift`:

```swift
import Testing
@testable import TimeTugCore

@Test func removeCalendarsForSourceDropsOnlyThatSourcesKeys() {
    var s = TakeoverSettings()
    s.takeoverCalendarKeys = ["google-1/a", "google-10/a", "eventkit/x"]
    s.hiddenCalendarKeys = ["google-1/b", "eventkit/y"]
    s.removeCalendars(forSourceID: "google-1")
    #expect(s.takeoverCalendarKeys == ["google-10/a", "eventkit/x"])
    #expect(s.hiddenCalendarKeys == ["eventkit/y"])
}

@Test func removeCalendarsForUnknownSourceChangesNothing() {
    var s = TakeoverSettings()
    s.takeoverCalendarKeys = ["eventkit/x"]
    s.removeCalendars(forSourceID: "google-1")
    #expect(s.takeoverCalendarKeys == ["eventkit/x"])
}

@Test func removeCalendarsWhereSourceMatchesPredicateUsesTextBeforeFirstSlash() {
    var s = TakeoverSettings()
    s.takeoverCalendarKeys = ["google-a/cal/with/slashes", "google-b/c", "eventkit/x"]
    s.removeCalendars(whereSourceID: { $0.hasPrefix("google-") && $0 != "google-b" })
    #expect(s.takeoverCalendarKeys == ["google-b/c", "eventkit/x"])
}
```

- [ ] **Step 2: Run them, expect a compile failure** (`removeCalendars` missing):
  `swift test --package-path Packages/TimeTugCore --filter TakeoverSettingsRemovalTests`

- [ ] **Step 3: Implement** in `TakeoverSettings.swift` (after `setShownInList`):

```swift
    /// Removes every stored calendar key whose source id (the text before the first "/") satisfies `isRemoved`.
    public mutating func removeCalendars(whereSourceID isRemoved: (String) -> Bool) {
        func sourceID(of key: String) -> String {
            key.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? key
        }
        takeoverCalendarKeys = takeoverCalendarKeys.filter { !isRemoved(sourceID(of: $0)) }
        hiddenCalendarKeys = hiddenCalendarKeys.filter { !isRemoved(sourceID(of: $0)) }
    }

    /// Forgets the Tug and visibility choices of one source (a removed account).
    public mutating func removeCalendars(forSourceID sourceID: String) {
        removeCalendars(whereSourceID: { $0 == sourceID })
    }
```

- [ ] **Step 4: Run, expect PASS.** Same command.

- [ ] **Step 5: Write the failing store tests.** `CalendarStoreSourcesTests.swift`:

```swift
import Foundation
import Testing
@testable import TimeTugCore

private let now = date("2026-09-18T10:00:00Z")

/// A source whose `events(in:)` waits until `release()` so a test can interleave `setSources`.
actor GateSource: CalendarSource {
    nonisolated let id: String
    nonisolated let displayName = "Gate"
    private var waiter: CheckedContinuation<Void, Never>?
    private var isOpen = false
    private(set) var started = false
    private let stored: [TimeTugCalendarEvent]

    init(id: String, events: [TimeTugCalendarEvent]) { self.id = id; stored = events }

    func calendars() async throws -> [CalendarInfo] { [] }
    func events(in interval: DateInterval) async throws -> [TimeTugCalendarEvent] {
        started = true
        if !isOpen { await withCheckedContinuation { waiter = $0 } }
        return stored
    }
    func release() { isOpen = true; waiter?.resume(); waiter = nil }
    nonisolated func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

@Test func setSourcesDropsRemovedSourceState() async {
    let a = FakeSource(id: "a"), b = FakeSource(id: "b")
    await a.set(events: .success([makeEvent("1")]))
    await b.set(events: .success([makeEvent("2", title: "Other", start: "2026-09-18T12:00:00Z")]))
    let store = CalendarStore(sources: [a, b], calendar: utcCalendar)
    _ = await store.refresh(now: now, leadTime: 60)
    await store.setSources([a])
    // setInferenceEnabled returns a snapshot built from cached state without refreshing.
    let snapshot = await store.setInferenceEnabled(false, now: now)
    #expect(snapshot.events.map(\.sourceEventID) == ["1"])
    #expect(Set(snapshot.statuses.keys) == ["a"])
    #expect(Set(snapshot.sourceNames.keys) == ["a"])
}

@Test func setSourcesAddsASourceForTheNextRefresh() async {
    let a = FakeSource(id: "a"), b = FakeSource(id: "b")
    await b.set(events: .success([makeEvent("2", title: "Other", start: "2026-09-18T12:00:00Z")]))
    let store = CalendarStore(sources: [a], calendar: utcCalendar)
    await store.setSources([a, b])
    let snapshot = await store.refresh(now: now, leadTime: 60)
    #expect(snapshot.events.map(\.sourceEventID) == ["2"])
    #expect(Set(snapshot.statuses.keys) == ["a", "b"])
}

@Test func refreshInFlightDuringSetSourcesDoesNotResurrectARemovedSource() async throws {
    let gate = GateSource(id: "eventkit", events: [makeEvent("1")])
    let store = CalendarStore(sources: [gate], calendar: utcCalendar)
    let refreshing = Task { await store.refresh(now: now, leadTime: 60) }
    for _ in 0..<400 {
        if await gate.started { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await gate.started)
    await store.setSources([])
    await gate.release()
    let snapshot = await refreshing.value
    #expect(snapshot.events.isEmpty)
    #expect(snapshot.statuses.isEmpty)
    // Toggled back on: nothing stale shows until its next refresh.
    await store.setSources([gate])
    #expect(await store.setInferenceEnabled(false, now: now).events.isEmpty)
}
```

- [ ] **Step 6: Run, expect compile failure** (`setSources` missing).

- [ ] **Step 7: Implement** in `CalendarStore.swift`:
  1. Change `private let sources: [any CalendarSource]` to `private var sources: [any CalendarSource]` and add `private var generation = 0` beside it.
  2. Add after `init`:

```swift
    /// Replaces the source set. Removed sources lose their cached events, calendars and status. Bumps the
    /// generation so a `refresh` that was suspended when this ran discards its results instead of restoring them.
    public func setSources(_ newSources: [any CalendarSource]) {
        let keep = Set(newSources.map(\.id))
        lastEvents = lastEvents.filter { keep.contains($0.key) }
        lastCalendars = lastCalendars.filter { keep.contains($0.key) }
        statuses = statuses.filter { keep.contains($0.key) }
        sources = newSources
        generation += 1
    }
```
  3. In `refresh`, capture before the task group: `let startedGeneration = generation` and `let current = sources`; iterate `for source in current`. Wrap the existing `for (sourceID, result) in results { ... }` loop in `if generation == startedGeneration { ... }`; keep `lastWindow = window` and `return makeSnapshot(now: now)` after it, outside the `if`.
  4. In `makeSnapshot`, add `let ids = Set(sources.map(\.id))` and pass `statuses: statuses.filter { ids.contains($0.key) }`.

- [ ] **Step 8: Run all Core tests:** `swift test --package-path Packages/TimeTugCore`. Expect all pass (previous count plus 6).

- [ ] **Step 9: Commit.**

```bash
git add Packages/TimeTugCore
git commit -m "feat(core): CalendarStore.setSources and TakeoverSettings.removeCalendars

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

### Task 3: Library: `needsPermission`, `AllDay` helper, `AllDayConformance`, Google mapper on them

**Files:**
- Modify: `Packages/CalendarConnectors/Sources/CalendarCore/SourceTypes.swift`
- Create: `Packages/CalendarConnectors/Sources/CalendarCore/AllDay.swift`
- Create: `Packages/CalendarConnectors/Sources/CalendarTestSupport/AllDayConformance.swift`
- Modify: `Packages/CalendarConnectors/Sources/GoogleCalendar/GoogleEventMapper.swift`
- Create: `Packages/CalendarConnectors/Tests/CalendarCoreTests/AllDayTests.swift`
- Modify: `Packages/CalendarConnectors/Tests/GoogleCalendarTests/` (the mapper test file)

**Interfaces:**
- Produces (all `public` in `CalendarCore`):
  - `SourceError.needsPermission`
  - `struct CalendarDate: Hashable, Sendable { year, month, day; init(year:month:day:); func adding(days: Int) -> CalendarDate }`
  - `enum AllDay { static func startOfDay(_ d: CalendarDate, in zone: TimeZone) -> Date?; static func date(of instant: Date, in zone: TimeZone) -> CalendarDate; static func canonical(first: CalendarDate, endExclusive: CalendarDate, in zone: TimeZone) -> (start: Date, end: Date)?; static func dates(start: Date, end: Date, in zone: TimeZone) -> (first: CalendarDate, endExclusive: CalendarDate); static func endExclusive(afterLast last: CalendarDate) -> CalendarDate }`
  - `CalendarTestSupport.AllDayConformance.violations(_ event: CalendarEvent) -> [String]` (empty means canonical)

- [ ] **Step 1: Write failing tests.** `AllDayTests.swift`:

```swift
import Foundation
import Testing
@testable import CalendarCore

private func zone(_ id: String) -> TimeZone { TimeZone(identifier: id)! }
private func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

@Test func canonicalOneDayInNewYork() throws {
    let r = try #require(AllDay.canonical(
        first: CalendarDate(year: 2026, month: 9, day: 18), endExclusive: CalendarDate(year: 2026, month: 9, day: 19),
        in: zone("America/New_York")))
    #expect(r.start == iso("2026-09-18T04:00:00Z"))
    #expect(r.end == iso("2026-09-19T04:00:00Z"))
}

@Test func datesRoundTripInAnotherZone() throws {
    let tokyo = zone("Asia/Tokyo")
    let r = try #require(AllDay.canonical(
        first: CalendarDate(year: 2026, month: 9, day: 18), endExclusive: CalendarDate(year: 2026, month: 9, day: 20), in: tokyo))
    let d = AllDay.dates(start: r.start, end: r.end, in: tokyo)
    #expect(d.first == CalendarDate(year: 2026, month: 9, day: 18))
    #expect(d.endExclusive == CalendarDate(year: 2026, month: 9, day: 20))
}

@Test func startOfDayWhenMidnightDoesNotExist() throws {
    // Sao Paulo skipped 00:00 on 2018-11-04 (clocks jumped to 01:00).
    let start = try #require(AllDay.startOfDay(CalendarDate(year: 2018, month: 11, day: 4), in: zone("America/Sao_Paulo")))
    #expect(start == iso("2018-11-04T03:00:00Z"))
}

@Test func addingDaysCrossesMonthsAndLeapDays() {
    #expect(CalendarDate(year: 2026, month: 2, day: 28).adding(days: 1) == CalendarDate(year: 2026, month: 3, day: 1))
    #expect(CalendarDate(year: 2028, month: 2, day: 28).adding(days: 1) == CalendarDate(year: 2028, month: 2, day: 29))
    #expect(AllDay.endExclusive(afterLast: CalendarDate(year: 2026, month: 12, day: 31)) == CalendarDate(year: 2027, month: 1, day: 1))
}

@Test func needsPermissionIsADistinctError() {
    #expect(SourceError.needsPermission != SourceError.authExpired)
}
```

- [ ] **Step 2: Run, expect compile failure:** `swift test --package-path Packages/CalendarConnectors --filter AllDayTests`

- [ ] **Step 3: Implement.** In `SourceTypes.swift` add `case needsPermission` to `SourceError` with the doc comment `/// The OS or user has not granted access to a local data store (EventKit). Never thrown by network connectors.` If any `switch` over `SourceError` becomes non-exhaustive, add the case (Google code paths should treat it like `invalidResponse`-free "not applicable"; a `default` is not acceptable, handle explicitly).

Create `AllDay.swift`:

```swift
import Foundation

/// A calendar day without a time or zone.
public struct CalendarDate: Hashable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int
    public init(year: Int, month: Int, day: Int) { self.year = year; self.month = month; self.day = day }

    public func adding(days: Int) -> CalendarDate {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let base = utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        let moved = utc.date(byAdding: .day, value: days, to: base)!
        let c = utc.dateComponents([.year, .month, .day], from: moved)
        return CalendarDate(year: c.year!, month: c.month!, day: c.day!)
    }
}

/// Conversions between all-day dates and the library's canonical instants: `start` is the start of the first
/// day in `zone`, `end` the start of the day after the last (exclusive). Connectors call this instead of doing
/// date math themselves.
public enum AllDay {
    private static func calendar(_ zone: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }

    /// The start of `date` in `zone`. Built from noon so a zone whose midnight does not exist that day still
    /// yields a valid instant (the first moment of the day).
    public static func startOfDay(_ date: CalendarDate, in zone: TimeZone) -> Date? {
        let cal = calendar(zone)
        guard let noon = cal.date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: 12))
        else { return nil }
        return cal.startOfDay(for: noon)
    }

    public static func date(of instant: Date, in zone: TimeZone) -> CalendarDate {
        let c = calendar(zone).dateComponents([.year, .month, .day], from: instant)
        return CalendarDate(year: c.year!, month: c.month!, day: c.day!)
    }

    public static func canonical(first: CalendarDate, endExclusive: CalendarDate, in zone: TimeZone) -> (start: Date, end: Date)? {
        guard let start = startOfDay(first, in: zone), let end = startOfDay(endExclusive, in: zone) else { return nil }
        return (start, end)
    }

    /// The dates a canonical range covers, read in `zone`.
    public static func dates(start: Date, end: Date, in zone: TimeZone) -> (first: CalendarDate, endExclusive: CalendarDate) {
        (date(of: start, in: zone), date(of: end, in: zone))
    }

    /// For providers that report the last covered day: the exclusive end date.
    public static func endExclusive(afterLast last: CalendarDate) -> CalendarDate { last.adding(days: 1) }
}
```

- [ ] **Step 4: Run, expect PASS.** Same command.

- [ ] **Step 5: `AllDayConformance`** (test support, portable). Create `Sources/CalendarTestSupport/AllDayConformance.swift`:

```swift
import CalendarCore
import Foundation

/// Every connector's mapper tests run their all-day fixtures through this so no connector can emit a
/// provider-native form. An empty result means the event is canonical.
public enum AllDayConformance {
    public static func violations(_ event: CalendarEvent) -> [String] {
        guard event.isAllDay else { return [] }
        guard let zone = event.timeZone else { return ["all-day event has no timeZone"] }
        var found: [String] = []
        func isMidnight(_ instant: Date) -> Bool {
            AllDay.startOfDay(AllDay.date(of: instant, in: zone), in: zone) == instant
        }
        if !isMidnight(event.start) { found.append("start is not the start of a day in \(zone.identifier)") }
        if !isMidnight(event.end) { found.append("end is not the start of a day in \(zone.identifier)") }
        if event.end <= event.start { found.append("end is not after start") }
        return found
    }
}
```
Add `Tests/CalendarCoreTests/AllDayConformanceTests.swift` (imports `CalendarTestSupport`) with four tests: a canonical event returns `[]`; a missing `timeZone` reports one violation; `end` 23:59:59 reports a violation; `end == start` reports a violation; a non-all-day event returns `[]`. Build events with `CalendarEvent(eventID:calendarID:title:start:end:timeZone:isAllDay:)`.

- [ ] **Step 6: Move Google's mapper onto `AllDay`, keep behavior.** In `GoogleEventMapper.resolve` replace the all-day branch with:

```swift
        if let day = time.date {
            let parts = day.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3,
                  let date = AllDay.startOfDay(CalendarDate(year: parts[0], month: parts[1], day: parts[2]), in: calendarZone)
            else { return nil }
            return Resolved(date: date, zone: calendarZone, isAllDay: true)
        }
```
Also make the missing-title placeholder the connector's job: in `map`, change `title: dto.summary ?? ""` to `title: dto.summary ?? "(No title)"` (only nil is replaced, matching EventKit). Find the existing mapper tests (`grep -n "all-day\|allDay\|date" Packages/CalendarConnectors/Tests/GoogleCalendarTests/*Mapper*`), add `#expect(AllDayConformance.violations(event).isEmpty)` to each all-day test (import `CalendarTestSupport`), and update any test that asserted an empty title for a missing summary. Add one test: a Google all-day event in `Asia/Tokyo` maps to `[2026-09-17T15:00:00Z, 2026-09-18T15:00:00Z)` with `timeZone` Tokyo.

- [ ] **Step 7: Run the whole library suite:** `swift test --package-path Packages/CalendarConnectors`. Expect all pass (81 + new).

- [ ] **Step 8: Commit.**

```bash
git add Packages/CalendarConnectors
git commit -m "feat(calendar): needsPermission error, AllDay helper and conformance check

Google's mapper uses AllDay and names its own untitled-event placeholder.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Library: `FileConnectionStore` and `FileSyncStateStore`

**Files:**
- Create: `Packages/CalendarConnectors/Sources/CalendarCore/FileConnectionStore.swift`
- Create: `Packages/CalendarConnectors/Sources/CalendarCore/FileSyncStateStore.swift`
- Create: `Packages/CalendarConnectors/Tests/CalendarCoreTests/FileStoresTests.swift`

**Interfaces:**
- Consumes: `Connection`, `ConnectionID`, `SyncStateStore` from `Connection.swift`.
- Produces:
  - `public actor FileConnectionStore { enum LoadResult: Equatable, Sendable { case loaded([Connection]), missing, unreadable }; init(url: URL); func load() -> LoadResult; func connections() -> [Connection]; func save(_:) throws; func add(_:) throws; func remove(connectionID:) throws }`, `public enum FileStoreError: Error, Equatable { case unreadable }`
  - `public actor FileSyncStateStore: SyncStateStore { init(url: URL) }`

- [ ] **Step 1: Failing tests.** `FileStoresTests.swift`:

```swift
import Foundation
import Testing
@testable import CalendarCore

private func tempURL(_ name: String = "store.json") -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent(name)
}
private let alice = Connection(kindID: "google", connectionID: "c1", displayName: "alice@example.com", config: ["email": "alice@example.com"])
private let bob = Connection(kindID: "google", connectionID: "c2", displayName: "bob@example.com")

@Test func connectionStoreMissingFileIsMissing() async {
    #expect(await FileConnectionStore(url: tempURL()).load() == .missing)
}

@Test func connectionStoreRoundTripsAddReplaceRemove() async throws {
    let store = FileConnectionStore(url: tempURL())
    try await store.add(alice)
    try await store.add(bob)
    #expect(await store.connections() == [alice, bob])
    var renamed = alice; renamed.displayName = "alice2@example.com"
    try await store.add(renamed)
    #expect(await store.connections() == [renamed, bob])
    try await store.remove(connectionID: "c1")
    #expect(await store.load() == .loaded([bob]))
    try await store.remove(connectionID: "c1")   // idempotent
    #expect(await store.connections() == [bob])
}

@Test func connectionStoreUnreadableFileIsReportedAndNeverOverwritten() async throws {
    let url = tempURL()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: url)
    let store = FileConnectionStore(url: url)
    #expect(await store.load() == .unreadable)
    await #expect(throws: FileStoreError.unreadable) { try await store.add(alice) }
    #expect(try Data(contentsOf: url) == Data("not json".utf8))
}

@Test func syncStateRoundTripsAcrossInstancesAndRemoveAll() async {
    let url = tempURL("sync.json")
    let a = FileSyncStateStore(url: url)
    await a.setToken("t1", for: "c1", scope: "cal-a")
    await a.setToken("t2", for: "c1", scope: "cal-b")
    await a.setToken("t3", for: "c2", scope: "cal-a")
    let b = FileSyncStateStore(url: url)
    #expect(await b.token(for: "c1", scope: "cal-a") == "t1")
    await b.setToken(nil, for: "c1", scope: "cal-a")
    #expect(await b.token(for: "c1", scope: "cal-a") == nil)
    await b.removeAll(for: "c1")
    #expect(await FileSyncStateStore(url: url).token(for: "c1", scope: "cal-b") == nil)
    #expect(await FileSyncStateStore(url: url).token(for: "c2", scope: "cal-a") == "t3")
}

@Test func syncStateUnreadableFileMeansNoTokens() async throws {
    let url = tempURL("sync.json")
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("###".utf8).write(to: url)
    let store = FileSyncStateStore(url: url)
    #expect(await store.token(for: "c1", scope: "x") == nil)
    await store.setToken("t", for: "c1", scope: "x")
    #expect(await FileSyncStateStore(url: url).token(for: "c1", scope: "x") == "t")
}
```

- [ ] **Step 2: Run, expect compile failure:** `swift test --package-path Packages/CalendarConnectors --filter FileStoresTests`

- [ ] **Step 3: Implement.** `FileConnectionStore.swift`:

```swift
import Foundation

public enum FileStoreError: Error, Equatable {
    /// The file exists but cannot be read; it is left untouched so the user's data is never overwritten.
    case unreadable
}

/// Persists the non-secret `Connection` list as JSON. Portable; the host chooses the file location.
public actor FileConnectionStore {
    public enum LoadResult: Equatable, Sendable {
        case loaded([Connection])
        case missing
        case unreadable
    }

    private let url: URL
    public init(url: URL) { self.url = url }

    public func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Connection].self, from: data) else { return .unreadable }
        return .loaded(list)
    }

    /// The stored connections; empty when the file is missing or unreadable (check `load()` to tell them apart).
    public func connections() -> [Connection] {
        if case .loaded(let list) = load() { return list }
        return []
    }

    public func save(_ connections: [Connection]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(connections).write(to: url, options: .atomic)
    }

    /// Adds, or replaces the entry with the same `connectionID`.
    public func add(_ connection: Connection) throws {
        var list = try writable()
        if let index = list.firstIndex(where: { $0.connectionID == connection.connectionID }) {
            list[index] = connection
        } else {
            list.append(connection)
        }
        try save(list)
    }

    /// Removes a connection; a no-op when it is not stored.
    public func remove(connectionID: ConnectionID) throws {
        let list = try writable()
        guard list.contains(where: { $0.connectionID == connectionID }) else { return }
        try save(list.filter { $0.connectionID != connectionID })
    }

    private func writable() throws -> [Connection] {
        switch load() {
        case .loaded(let list): return list
        case .missing: return []
        case .unreadable: throw FileStoreError.unreadable
        }
    }
}
```

`FileSyncStateStore.swift`:

```swift
import Foundation

/// A `SyncStateStore` backed by one JSON file. A missing or unreadable file means "no tokens", so a source does
/// a full bootstrap; write failures leave the in-memory state (and the next launch re-bootstraps).
public actor FileSyncStateStore: SyncStateStore {
    private let url: URL
    private var storage: [ConnectionID: [String: String]]?

    public init(url: URL) { self.url = url }

    private func current() -> [ConnectionID: [String: String]] {
        if let storage { return storage }
        let loaded = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode([ConnectionID: [String: String]].self, from: $0) } ?? [:]
        storage = loaded
        return loaded
    }

    public func token(for connectionID: ConnectionID, scope: String) async -> String? {
        current()[connectionID]?[scope]
    }

    public func setToken(_ token: String?, for connectionID: ConnectionID, scope: String) async {
        var all = current()
        var scopes = all[connectionID] ?? [:]
        scopes[scope] = token
        all[connectionID] = scopes.isEmpty ? nil : scopes
        commit(all)
    }

    public func removeAll(for connectionID: ConnectionID) async {
        var all = current()
        all[connectionID] = nil
        commit(all)
    }

    private func commit(_ all: [ConnectionID: [String: String]]) {
        storage = all
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(all) { try? data.write(to: url, options: .atomic) }
    }
}
```
(`Connection` is `Hashable`, hence `Equatable`, so `LoadResult` synthesizes `Equatable`.)

- [ ] **Step 4: Run, expect PASS**, then the whole library suite: `swift test --package-path Packages/CalendarConnectors`.

- [ ] **Step 5: Commit.**

```bash
git add Packages/CalendarConnectors
git commit -m "feat(calendar): portable file-backed connection and sync-state stores

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

### Task 5: `CalendarBridge` package

**Files:**
- Create: `Packages/CalendarBridge/Package.swift`
- Create: `Packages/CalendarBridge/Sources/CalendarBridge/{EventMapper,ConnectedSource}.swift`
- Create: `Packages/CalendarBridge/Tests/CalendarBridgeTests/{EventMapperTests,ConnectedSourceTests}.swift`
- Modify: `Packages/TimeTugCore/Sources/TimeTugCore/Model/TimeTugCalendarEvent.swift` (doc comment only)

**Interfaces:**
- Consumes: library `CalendarCore` (`CalendarEvent`, `CalendarDescriptor`, `CalendarSource`, `CalendarChange`, `SourceError`, `AllDay`); Core (`TimeTugCalendarEvent`, `CalendarInfo`, `CalendarSource`, `SourceError`, `Attendee`, `ResponseStatus`).
- Produces:
  - `public struct EventMapper: Sendable { init(calendar: Calendar = .autoupdatingCurrent); func calendarInfo(_ d: CalendarDescriptor, sourceID: String) -> CalendarInfo; func event(_ e: CalendarCore.CalendarEvent, sourceID: String) -> TimeTugCalendarEvent? }`
  - `public final class ConnectedSource: TimeTugCore.CalendarSource, Sendable { init(_ source: any CalendarCore.CalendarSource, mapper: EventMapper = EventMapper()) }` with `id`/`displayName` forwarded from the wrapped source.
- Name clashes: both modules define `CalendarSource`, `SourceError`, `Attendee`, `ResponseStatus`. Always module-qualify them in this package (`CalendarCore.SourceError`, `TimeTugCore.Attendee`, ...).

- [ ] **Step 1: Package manifest.** `Packages/CalendarBridge/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CalendarBridge",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CalendarBridge", targets: ["CalendarBridge"])],
    dependencies: [.package(path: "../TimeTugCore"), .package(path: "../CalendarConnectors")],
    targets: [
        .target(name: "CalendarBridge", dependencies: [
            .product(name: "TimeTugCore", package: "TimeTugCore"),
            .product(name: "CalendarCore", package: "CalendarConnectors"),
        ]),
        .testTarget(name: "CalendarBridgeTests", dependencies: [
            "CalendarBridge",
            .product(name: "TimeTugCore", package: "TimeTugCore"),
            .product(name: "CalendarCore", package: "CalendarConnectors"),
        ]),
    ]
)
```

- [ ] **Step 2: Failing mapper tests.** `EventMapperTests.swift`:

```swift
import CalendarCore
import Foundation
import Testing
import TimeTugCore
@testable import CalendarBridge

private func zone(_ id: String) -> TimeZone { TimeZone(identifier: id)! }
private func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
private func mapper(in id: String = "America/New_York") -> EventMapper {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone(id)
    return EventMapper(calendar: calendar)
}
private func timed(_ configure: (inout CalendarCore.CalendarEvent) -> Void = { _ in }) -> CalendarCore.CalendarEvent {
    var e = CalendarCore.CalendarEvent(
        eventID: "e1", uid: "uid-1", calendarID: "cal", title: "Standup", notes: "n", location: "Room 1",
        start: iso("2026-09-18T14:00:00Z"), end: iso("2026-09-18T14:30:00Z"), url: URL(string: "https://x.test/e"))
    configure(&e)
    return e
}
private func allDay(first: (Int, Int, Int), endExclusive: (Int, Int, Int), zone id: String) -> CalendarCore.CalendarEvent {
    let z = zone(id)
    let r = AllDay.canonical(
        first: CalendarDate(year: first.0, month: first.1, day: first.2),
        endExclusive: CalendarDate(year: endExclusive.0, month: endExclusive.1, day: endExclusive.2), in: z)!
    return CalendarCore.CalendarEvent(eventID: "d", calendarID: "cal", title: "Holiday", start: r.start, end: r.end,
                                      timeZone: z, isAllDay: true)
}

@Test func mapsTimedEventFields() throws {
    let e = try #require(mapper().event(timed { $0.conference = ConferenceInfo(url: URL(string: "https://meet.example/x")!, provider: .meet) }, sourceID: "google-1"))
    #expect(e.sourceEventID == "e1" && e.sourceID == "google-1" && e.calendarID == "cal" && e.title == "Standup")
    #expect(e.start == iso("2026-09-18T14:00:00Z") && e.end == iso("2026-09-18T14:30:00Z") && !e.isAllDay)
    #expect(e.location == "Room 1" && e.notes == "n" && e.url == URL(string: "https://x.test/e"))
    #expect(e.conferenceURL == URL(string: "https://meet.example/x") && e.externalUID == "uid-1")
}

@Test func separatesSelfFromOtherAttendeesAndOrganizer() throws {
    let e = try #require(mapper().event(timed {
        $0.attendees = [
            CalendarCore.Attendee(name: "Me", email: "me@x.test", response: .accepted, isSelf: true),
            CalendarCore.Attendee(name: "Bo", email: "BO@x.test"),
        ]
        $0.organizer = CalendarCore.Attendee(name: "Bo", email: "bo@x.test", isOrganizer: true)
    }, sourceID: "s"))
    #expect(e.otherAttendeeCount == 1)
    #expect(e.attendees.map(\.email) == ["bo@x.test"])
    #expect(e.organizerEmail == "bo@x.test")
    #expect(e.responseStatus == .accepted)
}

@Test func organizerWhoIsSelfIsNotReported() throws {
    let e = try #require(mapper().event(timed { $0.organizer = CalendarCore.Attendee(email: "me@x.test", isSelf: true, isOrganizer: true) }, sourceID: "s"))
    #expect(e.organizerEmail == nil)
}

@Test func responseStatusMapping() throws {
    func status(_ configure: (inout CalendarCore.CalendarEvent) -> Void) throws -> TimeTugCore.ResponseStatus {
        try #require(mapper().event(timed(configure), sourceID: "s")).responseStatus
    }
    #expect(try status { $0.myResponse = .declined } == .declined)
    #expect(try status { $0.myResponse = .tentative } == .tentative)
    #expect(try status { $0.myResponse = .needsAction } == .pending)
    #expect(try status { $0.attendees = [CalendarCore.Attendee(email: "me@x.test", response: .declined, isSelf: true)] } == .declined)
    #expect(try status { _ in } == .unknown)
}

@Test func cancelledEventsAreDropped() {
    #expect(mapper().event(timed { $0.status = .cancelled }, sourceID: "s") == nil)
}

@Test func titlesPassThroughUnchangedIncludingEmpty() throws {
    #expect(try #require(mapper().event(timed { $0.title = "" }, sourceID: "s")).title == "")
}

@Test func allDayInTheDeviceZoneIsTheIdentity() throws {
    let source = allDay(first: (2026, 9, 18), endExclusive: (2026, 9, 19), zone: "America/New_York")
    let e = try #require(mapper().event(source, sourceID: "s"))
    #expect(e.isAllDay && e.start == source.start && e.end == source.end)
}

@Test func allDayFromAnotherZoneLandsOnTheSameLocalDates() throws {
    // Tokyo 2026-09-18 viewed on a New York device: local midnight of the 18th to local midnight of the 19th.
    let e = try #require(mapper().event(allDay(first: (2026, 9, 18), endExclusive: (2026, 9, 19), zone: "Asia/Tokyo"), sourceID: "s"))
    #expect(e.start == iso("2026-09-18T04:00:00Z") && e.end == iso("2026-09-19T04:00:00Z"))
    // And the reverse: a New York all-day event on a Tokyo device.
    let t = try #require(mapper(in: "Asia/Tokyo").event(allDay(first: (2026, 9, 18), endExclusive: (2026, 9, 19), zone: "America/New_York"), sourceID: "s"))
    #expect(t.start == iso("2026-09-17T15:00:00Z") && t.end == iso("2026-09-18T15:00:00Z"))
}

@Test func multiDayAllDayKeepsItsLength() throws {
    let e = try #require(mapper().event(allDay(first: (2026, 9, 18), endExclusive: (2026, 9, 21), zone: "Asia/Tokyo"), sourceID: "s"))
    #expect(e.start == iso("2026-09-18T04:00:00Z") && e.end == iso("2026-09-21T04:00:00Z"))
}

@Test func mapsCalendarDescriptors() {
    let d = CalendarDescriptor(id: "c", title: "Work", colorHex: "#abc", accountName: "me@x.test")
    let info = mapper().calendarInfo(d, sourceID: "google-1")
    #expect(info == CalendarInfo(sourceID: "google-1", calendarID: "c", title: "Work", accountName: "me@x.test", colorHex: "#AABBCC"))
}
```

- [ ] **Step 3: Run, expect compile failure:** `swift test --package-path Packages/CalendarBridge`

- [ ] **Step 4: Implement `EventMapper.swift`.**

```swift
import CalendarCore
import Foundation
import TimeTugCore

/// Maps the connector library's model to TimeTug's. The only place that knows both vocabularies.
public struct EventMapper: Sendable {
    private let calendar: Calendar

    /// `calendar` decides which day an all-day event falls on (the user's own calendar).
    public init(calendar: Calendar = .autoupdatingCurrent) { self.calendar = calendar }

    public func calendarInfo(_ d: CalendarDescriptor, sourceID: String) -> CalendarInfo {
        CalendarInfo(sourceID: sourceID, calendarID: d.id, title: d.title, accountName: d.accountName, colorHex: d.colorHex)
    }

    /// nil for cancelled events. Titles are never rewritten: each connector chooses its own placeholder.
    public func event(_ e: CalendarCore.CalendarEvent, sourceID: String) -> TimeTugCalendarEvent? {
        if e.status == .cancelled { return nil }
        let (start, end) = times(e)
        let others = e.attendees.filter { !$0.isSelf }
        return TimeTugCalendarEvent(
            sourceEventID: e.eventID, sourceID: sourceID, calendarID: e.calendarID, title: e.title,
            start: start, end: end, isAllDay: e.isAllDay, otherAttendeeCount: others.count,
            responseStatus: responseStatus(of: e), location: e.location, notes: e.notes, url: e.url,
            conferenceURL: e.conference?.url,
            attendees: others.map { TimeTugCore.Attendee(name: $0.name, email: $0.email) },
            organizerEmail: e.organizer.flatMap { $0.isSelf ? nil : $0.email },
            externalUID: e.uid)
    }

    /// INTERIM (Phase 2.5 deletes this): the library's all-day events are midnights in the event's own zone;
    /// TimeTug's agenda still expects device-local midnights of the same calendar dates. Identity when the zones match.
    private func times(_ e: CalendarCore.CalendarEvent) -> (Date, Date) {
        guard e.isAllDay, let zone = e.timeZone else { return (e.start, e.end) }
        let days = AllDay.dates(start: e.start, end: e.end, in: zone)
        let local = calendar.timeZone
        guard let start = AllDay.startOfDay(days.first, in: local),
              let end = AllDay.startOfDay(days.endExclusive, in: local) else { return (e.start, e.end) }
        return (start, end)
    }

    private func responseStatus(of e: CalendarCore.CalendarEvent) -> TimeTugCore.ResponseStatus {
        switch e.myResponse ?? e.attendees.first(where: \.isSelf)?.response {
        case .accepted: .accepted
        case .tentative: .tentative
        case .declined: .declined
        case .needsAction: .pending
        case nil: .unknown
        }
    }
}
```

- [ ] **Step 5: Run mapper tests, expect PASS.**

- [ ] **Step 6: Failing adapter tests.** `ConnectedSourceTests.swift`:

```swift
import CalendarCore
import Foundation
import Testing
import TimeTugCore
@testable import CalendarBridge

final class FakeLibrarySource: CalendarCore.CalendarSource, @unchecked Sendable {
    let id: String
    let displayName = "Fake"
    let capabilities = SourceCapabilities()
    var calendarsResult: Result<[CalendarDescriptor], Error> = .success([])
    var eventsResult: Result<[CalendarCore.CalendarEvent], Error> = .success([])
    let continuation: AsyncStream<CalendarChange>.Continuation
    private let stream: AsyncStream<CalendarChange>
    private let terminated = Flag()

    init(id: String = "src") {
        self.id = id
        (stream, continuation) = AsyncStream.makeStream(of: CalendarChange.self)
        continuation.onTermination = { [terminated] _ in terminated.set() }
    }
    var wasTerminated: Bool { terminated.value }

    func calendars() async throws -> [CalendarDescriptor] { try calendarsResult.get() }
    func events(in interval: DateInterval) async throws -> [CalendarCore.CalendarEvent] { try eventsResult.get() }
    func changes() -> AsyncStream<CalendarChange> { stream }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

private func thrown(_ body: () async throws -> Void) async -> Error? {
    do { try await body(); return nil } catch { return error }
}

@Test func forwardsIdentityAndMapsCalendarsAndEvents() async throws {
    let fake = FakeLibrarySource(id: "google-1")
    fake.calendarsResult = .success([CalendarDescriptor(id: "c", title: "Work", accountName: "me@x.test")])
    fake.eventsResult = .success([CalendarCore.CalendarEvent(eventID: "e", calendarID: "c", title: "T",
        start: Date(timeIntervalSince1970: 1_000), end: Date(timeIntervalSince1970: 2_000))])
    let source = ConnectedSource(fake)
    #expect(source.id == "google-1" && source.displayName == "Fake")
    #expect(try await source.calendars().map(\.key) == ["google-1/c"])
    let events = try await source.events(in: DateInterval(start: .distantPast, end: .distantFuture))
    #expect(events.map(\.sourceID) == ["google-1"] && events.map(\.title) == ["T"])
}

@Test func translatesPermissionAndAuthErrors() async {
    let fake = FakeLibrarySource()
    let source = ConnectedSource(fake)
    fake.calendarsResult = .failure(CalendarCore.SourceError.needsPermission)
    let permission = await thrown { _ = try await source.calendars() }
    guard case TimeTugCore.SourceError.needsPermission? = permission else { Issue.record("got \(String(describing: permission))"); return }
    fake.eventsResult = .failure(CalendarCore.SourceError.authExpired)
    let auth = await thrown { _ = try await source.events(in: DateInterval(start: .distantPast, end: .distantFuture)) }
    guard case TimeTugCore.SourceError.authExpired? = auth else { Issue.record("got \(String(describing: auth))"); return }
}

@Test func otherErrorsPropagateUntranslated() async {
    let fake = FakeLibrarySource()
    fake.eventsResult = .failure(CalendarCore.SourceError.server(status: 500))
    let error = await thrown { _ = try await ConnectedSource(fake).events(in: DateInterval(start: .distantPast, end: .distantFuture)) }
    #expect(error as? CalendarCore.SourceError == .server(status: 500))
}

@Test func everyLibraryChangeYieldsOnceIncludingSourceFailed() async {
    let fake = FakeLibrarySource()
    var iterator = ConnectedSource(fake).changes().makeAsyncIterator()
    fake.continuation.yield(.calendarsChanged)
    fake.continuation.yield(.eventsChanged(calendarIDs: ["c"]))
    fake.continuation.yield(.sourceFailed(.authExpired))
    for _ in 0..<3 { #expect(await iterator.next() != nil) }
}

@Test func cancellingTheConsumerEndsTheLibraryStream() async throws {
    let fake = FakeLibrarySource()
    let consumer = Task { for await _ in ConnectedSource(fake).changes() {} }
    try await Task.sleep(for: .milliseconds(50))
    consumer.cancel()
    for _ in 0..<200 where !fake.wasTerminated { try await Task.sleep(for: .milliseconds(10)) }
    #expect(fake.wasTerminated)
}
```

- [ ] **Step 7: Implement `ConnectedSource.swift`.**

```swift
import CalendarCore
import Foundation
import TimeTugCore

/// Adapts a connector-library source to Core's `CalendarSource`, so `CalendarStore` never sees library types.
public final class ConnectedSource: TimeTugCore.CalendarSource, Sendable {
    private let source: any CalendarCore.CalendarSource
    private let mapper: EventMapper

    public init(_ source: any CalendarCore.CalendarSource, mapper: EventMapper = EventMapper()) {
        self.source = source
        self.mapper = mapper
    }

    public var id: String { source.id }
    public var displayName: String { source.displayName }

    public func calendars() async throws -> [CalendarInfo] {
        do { return try await source.calendars().map { mapper.calendarInfo($0, sourceID: id) } }
        catch { throw Self.translate(error) }
    }

    public func events(in interval: DateInterval) async throws -> [TimeTugCalendarEvent] {
        do { return try await source.events(in: interval).compactMap { mapper.event($0, sourceID: id) } }
        catch { throw Self.translate(error) }
    }

    /// Yields once for every library change. `.sourceFailed` yields too, so the next refresh surfaces the status.
    /// Cancelling the consumer cancels the inner task, which ends the library stream (and its polling).
    public func changes() -> AsyncStream<Void> {
        let source = source
        return AsyncStream { continuation in
            let task = Task {
                for await _ in source.changes() { continuation.yield() }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func translate(_ error: Error) -> Error {
        switch error as? CalendarCore.SourceError {
        case .needsPermission?: TimeTugCore.SourceError.needsPermission
        case .authExpired?: TimeTugCore.SourceError.authExpired
        default: error
        }
    }
}
```

- [ ] **Step 8: Document TimeTug's all-day form** on the type in `TimeTugCalendarEvent.swift` (above `isAllDay`): `/// All-day events use TimeTug's device-local form: start is the local midnight of the first day, end the local midnight after the last day (exclusive). Sources' own forms are converted by CalendarBridge.` Keep it a comment only.

- [ ] **Step 9: Run:** `swift test --package-path Packages/CalendarBridge` and `swift test --package-path Packages/TimeTugCore`. Expect PASS.

- [ ] **Step 10: Commit.**

```bash
git add Packages/CalendarBridge Packages/TimeTugCore
git commit -m "feat(bridge): CalendarBridge maps library events to TimeTug and adapts sources

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: `EventKitSource` on the library abstraction, plus `EventKitConnectorKind`

**Files:**
- Modify: `Packages/EventKitSource/Package.swift`
- Modify (rewrite): `Packages/EventKitSource/Sources/EventKitSource/EventKitSource.swift`
- Create: `Packages/EventKitSource/Sources/EventKitSource/EventKitMapping.swift`
- Create: `Packages/EventKitSource/Sources/EventKitSource/EventKitConnectorKind.swift`
- Create: `Packages/EventKitSource/Tests/EventKitSourceTests/{EventKitMappingTests,EventKitConnectorKindTests}.swift`

**Interfaces:**
- Consumes: `CalendarCore` (`CalendarSource`, `CalendarEvent`, `CalendarDescriptor`, `CalendarChange`, `SourceError`, `ConnectorKind`, `Connection`, `Platform`, `AuthorizationMethod`, `Attendee`, `ResponseStatus`, `AttendeeRole`). EventKit's all-day rule (floating dates, end-of-day `endDate`) is its own function, not `AllDay`.
- Produces:
  - `public final class EventKitSource: CalendarCore.CalendarSource` with `public static let sourceID = "eventkit"`, `public func requestAccess() async -> Bool`
  - `public struct EventKitConnectorKind: ConnectorKind` (`kindID "eventkit"`, `.macOS`, `.system`), `public static let connection: Connection`, `init(source: EventKitSource = EventKitSource())`
  - internal `enum EventKitMapping` (`canonicalAllDay(start:end:calendar:)`, `response(_:)`, `role(_:)`, `email(fromMailto:)`, `hex(from:)`)
- `EventKitSource` no longer depends on `TimeTugCore`.

- [ ] **Step 1: Manifest.** Replace `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EventKitSource",
    platforms: [.macOS(.v14)],
    products: [.library(name: "EventKitSource", targets: ["EventKitSource"])],
    dependencies: [.package(path: "../CalendarConnectors")],
    targets: [
        .target(
            name: "EventKitSource",
            dependencies: [.product(name: "CalendarCore", package: "CalendarConnectors")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "EventKitSourceTests",
            dependencies: ["EventKitSource", .product(name: "CalendarCore", package: "CalendarConnectors")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

- [ ] **Step 2: Failing mapping tests.** `EventKitMappingTests.swift`:

```swift
import CalendarCore
import EventKit
import Foundation
import Testing
@testable import EventKitSource

private func newYork() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}
private func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

@Test func allDayOneDayEndingAtEndOfDayBecomesExclusiveNextMidnight() {
    let r = EventKitMapping.canonicalAllDay(start: iso("2026-09-18T04:00:00Z"), end: iso("2026-09-19T03:59:59Z"), calendar: newYork())
    #expect(r.start == iso("2026-09-18T04:00:00Z") && r.end == iso("2026-09-19T04:00:00Z"))
}

@Test func allDayMultiDayEndingAtEndOfDay() {
    let r = EventKitMapping.canonicalAllDay(start: iso("2026-09-18T04:00:00Z"), end: iso("2026-09-21T03:59:59Z"), calendar: newYork())
    #expect(r.end == iso("2026-09-21T04:00:00Z"))
}

@Test func allDayAlreadyExclusiveEndIsKept() {
    let r = EventKitMapping.canonicalAllDay(start: iso("2026-09-18T04:00:00Z"), end: iso("2026-09-20T04:00:00Z"), calendar: newYork())
    #expect(r.end == iso("2026-09-20T04:00:00Z"))
}

@Test func allDayZeroLengthCoversOneDay() {
    let r = EventKitMapping.canonicalAllDay(start: iso("2026-09-18T04:00:00Z"), end: iso("2026-09-18T04:00:00Z"), calendar: newYork())
    #expect(r.end == iso("2026-09-19T04:00:00Z"))
}

@Test func allDayAcrossFallBackDay() {
    // 2026-11-01 is 25 hours long in New York: midnight EDT (04:00Z) to midnight EST (05:00Z next day).
    let r = EventKitMapping.canonicalAllDay(start: iso("2026-11-01T04:00:00Z"), end: iso("2026-11-02T04:59:59Z"), calendar: newYork())
    #expect(r.start == iso("2026-11-01T04:00:00Z") && r.end == iso("2026-11-02T05:00:00Z"))
}

@Test func participantStatusMapping() {
    #expect(EventKitMapping.response(.accepted) == .accepted)
    #expect(EventKitMapping.response(.tentative) == .tentative)
    #expect(EventKitMapping.response(.declined) == .declined)
    #expect(EventKitMapping.response(.pending) == .needsAction)
    #expect(EventKitMapping.response(.unknown) == nil)
}

@Test func mailtoAndHexHelpers() {
    #expect(EventKitMapping.email(fromMailto: "mailto:Bo@X.test?subject=hi") == "bo@x.test")
    #expect(EventKitMapping.email(fromMailto: "https://x.test") == nil)
    #expect(EventKitMapping.hex(from: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)) == "#FF0000")
}
```

- [ ] **Step 3: Run, expect compile failure:** `swift test --package-path Packages/EventKitSource`

- [ ] **Step 4: `EventKitMapping.swift`.**

```swift
import CalendarCore
import CoreGraphics
import EventKit
import Foundation

/// Pure conversions used by `EventKitSource`, kept free of `EKEventStore` so they are unit-testable.
enum EventKitMapping {
    /// EventKit reports all-day events as floating device-local dates whose `endDate` is normally the end of the
    /// last day (23:59:59). Returns the library's canonical form: start-of-day of the first day and the start of
    /// the day after the last, in `calendar`'s zone. `end <= start` covers one day; an `end` already at a
    /// midnight after `start` is taken as exclusive.
    static func canonicalAllDay(start: Date, end: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let first = calendar.startOfDay(for: start)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: first) ?? first.addingTimeInterval(86_400)
        if end <= start { return (first, nextDay) }
        let endDay = calendar.startOfDay(for: end)
        if end == endDay { return (first, max(endDay, nextDay)) }
        let after = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay.addingTimeInterval(86_400)
        return (first, max(after, nextDay))
    }

    /// nil for statuses the library has no value for (unknown, delegated, in process, ...).
    static func response(_ status: EKParticipantStatus) -> ResponseStatus? {
        switch status {
        case .accepted: .accepted
        case .tentative: .tentative
        case .declined: .declined
        case .pending: .needsAction
        default: nil
        }
    }

    static func role(_ participant: EKParticipant) -> AttendeeRole {
        if participant.participantType == .resource || participant.participantType == .room { return .resource }
        return participant.participantRole == .optional ? .optional : .required
    }

    static func email(fromMailto urlString: String?) -> String? {
        guard let urlString, urlString.lowercased().hasPrefix("mailto:") else { return nil }
        let rest = String(urlString.dropFirst("mailto:".count))
        let address = rest.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
        let trimmed = address?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    static func hex(from color: CGColor?) -> String? {
        guard let color, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let c = color.converted(to: space, intent: .defaultIntent, options: nil),
              let comps = c.components, comps.count >= 3 else { return nil }
        let v = comps.prefix(3).map { Int((min(max($0, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", v[0], v[1], v[2])
    }
}
```

- [ ] **Step 5: Run mapping tests, expect PASS.**

- [ ] **Step 6: Rewrite `EventKitSource.swift`.**

```swift
import CalendarCore
import EventKit
import Foundation

/// Apple Calendar via EventKit (includes iCloud, Google and Exchange accounts added to macOS). EventKit types
/// never leave this module. Its id is the constant "eventkit" (existing stored calendar keys start with
/// `eventkit/`), which deliberately differs from `Connection.sourceID`; hosts identify sources by `source.id`.
public final class EventKitSource: CalendarCore.CalendarSource, @unchecked Sendable {
    public static let sourceID = "eventkit"
    public let id = EventKitSource.sourceID
    public let displayName = "Apple Calendar"
    public var capabilities: SourceCapabilities { SourceCapabilities(providesConference: false, syncKind: .notification) }
    private let store = EKEventStore()

    public init() {}

    /// Prompts for calendar access if undetermined. Returns whether access is granted.
    public func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    public func calendars() async throws -> [CalendarDescriptor] {
        try requireAccess()
        return store.calendars(for: .event).map {
            let account = $0.source?.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return CalendarDescriptor(
                id: $0.calendarIdentifier, title: $0.title, colorHex: EventKitMapping.hex(from: $0.cgColor),
                accessRole: $0.allowsContentModifications ? .writer : .reader,
                accountName: (account?.isEmpty ?? true) ? nil : account)
        }
    }

    public func events(in interval: DateInterval) async throws -> [CalendarEvent] {
        try requireAccess()
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        return store.events(matching: predicate).map(map)
    }

    public func changes() -> AsyncStream<CalendarChange> {
        AsyncStream { continuation in
            let token = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: store, queue: nil
            ) { _ in continuation.yield(.calendarsChanged) }
            continuation.onTermination = { _ in NotificationCenter.default.removeObserver(token) }
        }
    }

    private func requireAccess() throws {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw SourceError.needsPermission }
    }

    private func attendee(_ p: EKParticipant, isOrganizer: Bool) -> Attendee {
        Attendee(name: p.name, email: EventKitMapping.email(fromMailto: p.url.absoluteString), role: EventKitMapping.role(p),
                 response: EventKitMapping.response(p.participantStatus) ?? .needsAction,
                 isSelf: p.isCurrentUser, isOrganizer: isOrganizer)
    }

    private func map(_ event: EKEvent) -> CalendarEvent {
        let attendees = (event.attendees ?? []).map { attendee($0, isOrganizer: false) }
        let me = (event.attendees ?? []).first { $0.isCurrentUser }
        var start = event.startDate ?? Date(), end = event.endDate ?? start
        var zone = event.timeZone ?? .current
        if event.isAllDay {
            // Floating device-local dates: normalize to the canonical form in the device zone.
            let calendar = Calendar.current
            (start, end) = EventKitMapping.canonicalAllDay(start: start, end: end, calendar: calendar)
            zone = calendar.timeZone
        }
        return CalendarEvent(
            eventID: event.eventIdentifier ?? event.calendarItemIdentifier,
            uid: event.calendarItemExternalIdentifier,
            calendarID: event.calendar.calendarIdentifier,
            title: event.title ?? "(No title)",
            notes: event.notes, location: event.location, start: start, end: end, timeZone: zone,
            isAllDay: event.isAllDay, status: event.status == .tentative ? .tentative : .confirmed,
            availability: event.availability == .free ? .free : .busy,
            attendees: attendees, organizer: event.organizer.map { attendee($0, isOrganizer: true) },
            url: event.url, myResponse: me.flatMap { EventKitMapping.response($0.participantStatus) })
    }
}
```
Note: a canceled EventKit status is deliberately still `.confirmed` (unchanged behavior: TimeTug did not filter it before).

- [ ] **Step 7: `EventKitConnectorKind.swift`** and its test.

```swift
import CalendarCore
import Foundation

/// Apple Calendar as a connector kind. Access is a system permission, so `authorize` neither uses the
/// interaction nor the credential store, and the returned `Connection` is synthesized (hosts do not persist it).
public struct EventKitConnectorKind: ConnectorKind {
    public static let kindID = "eventkit"
    /// `sourceID` here would be "eventkit-this-mac"; hosts key EventKit by `EventKitSource.sourceID` ("eventkit").
    public static let connection = Connection(kindID: kindID, connectionID: "this-mac", displayName: "Apple Calendar")

    public var id: String { Self.kindID }
    public var displayName: String { "Apple Calendar" }
    public var supportedPlatforms: Platform { .macOS }
    public var authorization: AuthorizationMethod { .system }
    private let source: EventKitSource

    public init(source: EventKitSource = EventKitSource()) { self.source = source }

    public func authorize(using interaction: any AuthorizationInteraction, credentials: any CredentialStore) async throws -> Connection {
        guard await source.requestAccess() else { throw SourceError.needsPermission }
        return Self.connection
    }

    public func reauthorize(
        _ connection: Connection, using interaction: any AuthorizationInteraction, credentials: any CredentialStore
    ) async throws -> Connection {
        try await authorize(using: interaction, credentials: credentials)
    }

    public func makeSource(for connection: Connection, credentials: any CredentialStore, syncState: any SyncStateStore) throws -> any CalendarSource {
        source
    }
}
```
`EventKitConnectorKindTests.swift`: `#expect(kind.id == "eventkit")`; `if case .system = kind.authorization {} else { Issue.record(...) }`; `#expect(kind.supportedPlatforms.contains(.macOS))`; `let s = try kind.makeSource(for: EventKitConnectorKind.connection, credentials: InMemoryCredentialStore(), syncState: InMemorySyncStateStore()); #expect(s.id == "eventkit")`; `#expect(EventKitConnectorKind.connection.sourceID == "eventkit-this-mac")` (documents the exception).

- [ ] **Step 8: Run:** `swift test --package-path Packages/EventKitSource`. Expect PASS. (Do not call `requestAccess` in tests.)

- [ ] **Step 9: Commit.**

```bash
git add Packages/EventKitSource
git commit -m "feat(eventkit): EventKitSource speaks the library abstraction; add EventKitConnectorKind

All-day events are normalized to the canonical form at the connector.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

### Task 7: `CalendarApple` adapter package (Keychain store, loopback authorization)

**Files:**
- Create: `Packages/CalendarApple/Package.swift`
- Create: `Packages/CalendarApple/Sources/CalendarApple/{KeychainCredentialStore,LoopbackRequest,LoopbackAuthorizationInteraction}.swift`
- Create: `Packages/CalendarApple/Tests/CalendarAppleTests/{KeychainCredentialStoreTests,LoopbackTests}.swift`

**Interfaces:**
- Consumes: `CalendarCore` (`CredentialStore`, `ConnectionID`, `AuthorizationInteraction`, `OAuthRedirectSession`, `CredentialField`).
- Produces:
  - `public struct KeychainCredentialStore: CredentialStore { init(service: String); struct KeychainError: Error, Equatable { status: OSStatus } }`
  - `public struct LoopbackAuthorizationInteraction: AuthorizationInteraction { typealias OpenURL = @Sendable (URL) async -> Bool; init(openURL: @escaping OpenURL, promptCredentials: (@Sendable ([CredentialField]) async throws -> [String: String])? = nil, timeout: Duration = .seconds(300)) }`; `public enum LoopbackError: Error, Equatable { case couldNotOpenBrowser, timedOut, cancelled, credentialPromptUnavailable, listenerFailed(String) }`
  - internal `enum LoopbackRequest { static func redirectURL(from: Data, port: UInt16) -> URL? }`

- [ ] **Step 1: Manifest.** `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CalendarApple",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CalendarApple", targets: ["CalendarApple"])],
    dependencies: [.package(path: "../CalendarConnectors")],
    targets: [
        .target(name: "CalendarApple", dependencies: [.product(name: "CalendarCore", package: "CalendarConnectors")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "CalendarAppleTests", dependencies: ["CalendarApple", .product(name: "CalendarCore", package: "CalendarConnectors")],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
```

- [ ] **Step 2: Failing Keychain test.** `KeychainCredentialStoreTests.swift` (skips when the Keychain is unavailable, e.g. a locked CI keychain):

```swift
import Foundation
import Testing
@testable import CalendarApple

private func makeStore() -> KeychainCredentialStore {
    KeychainCredentialStore(service: "com.timetug.tests.\(UUID().uuidString)")
}
private func keychainAvailable() async -> Bool {
    let store = makeStore()
    do {
        try await store.setSecrets(["probe": "1"], for: "probe")
        try await store.removeSecrets(for: "probe")
        return true
    } catch { return false }
}

@Test(.enabled(if: await keychainAvailable())) func setGetOverwriteRemove() async throws {
    let store = makeStore()
    #expect(try await store.secrets(for: "c1") == nil)
    try await store.setSecrets(["refresh_token": "r1"], for: "c1")
    #expect(try await store.secrets(for: "c1") == ["refresh_token": "r1"])
    try await store.setSecrets(["refresh_token": "r2", "extra": "x"], for: "c1")
    #expect(try await store.secrets(for: "c1") == ["refresh_token": "r2", "extra": "x"])
    try await store.removeSecrets(for: "c1")
    #expect(try await store.secrets(for: "c1") == nil)
    try await store.removeSecrets(for: "c1")   // idempotent
}

@Test(.enabled(if: await keychainAvailable())) func connectionsAreIsolated() async throws {
    let store = makeStore()
    try await store.setSecrets(["a": "1"], for: "c1")
    try await store.setSecrets(["a": "2"], for: "c2")
    #expect(try await store.secrets(for: "c1") == ["a": "1"])
    try await store.removeSecrets(for: "c1")
    try await store.removeSecrets(for: "c2")
}
```

- [ ] **Step 3: Implement `KeychainCredentialStore.swift`.**

```swift
import CalendarCore
import Foundation
import Security

/// A `CredentialStore` in the macOS Keychain: one generic-password item per connection (account =
/// `connectionID`), whose data is the JSON of that connection's secrets. `service` namespaces the app's items.
public struct KeychainCredentialStore: CredentialStore {
    public struct KeychainError: Error, Equatable { public let status: OSStatus }

    private let service: String
    public init(service: String) { self.service = service }

    private func query(_ connectionID: ConnectionID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: connectionID]
    }

    public func secrets(for connectionID: ConnectionID) async throws -> [String: String]? {
        var q = query(connectionID)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    public func setSecrets(_ secrets: [String: String], for connectionID: ConnectionID) async throws {
        let data = try JSONEncoder().encode(secrets)
        var status = SecItemUpdate(query(connectionID) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(connectionID)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func removeSecrets(for connectionID: ConnectionID) async throws {
        let status = SecItemDelete(query(connectionID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
```

- [ ] **Step 4: Run Keychain tests.** `swift test --package-path Packages/CalendarApple --filter KeychainCredentialStoreTests`. Expect PASS (or "skipped" where the keychain is unavailable).

- [ ] **Step 5: Failing loopback tests.** `LoopbackTests.swift`:

```swift
import CalendarCore
import Foundation
import Testing
@testable import CalendarApple

@Test func redirectURLParsesOAuthRedirectsOnly() {
    let ok = Data("GET /?code=abc&state=xyz HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8)
    #expect(LoopbackRequest.redirectURL(from: ok, port: 5000)?.absoluteString == "http://127.0.0.1:5000/?code=abc&state=xyz")
    let denied = Data("GET /?error=access_denied&state=xyz HTTP/1.1\r\n\r\n".utf8)
    #expect(LoopbackRequest.redirectURL(from: denied, port: 5000) != nil)
    #expect(LoopbackRequest.redirectURL(from: Data("GET /favicon.ico HTTP/1.1\r\n\r\n".utf8), port: 5000) == nil)
    #expect(LoopbackRequest.redirectURL(from: Data("POST /?code=a HTTP/1.1\r\n\r\n".utf8), port: 5000) == nil)
    #expect(LoopbackRequest.redirectURL(from: Data("garbage".utf8), port: 5000) == nil)
}

private func interaction(timeout: Duration = .seconds(5), opened: @escaping @Sendable (URL) -> Void = { _ in }) -> LoopbackAuthorizationInteraction {
    LoopbackAuthorizationInteraction(openURL: { url in opened(url); return true }, timeout: timeout)
}

@Test func sessionReceivesTheRedirectOnLoopback() async throws {
    let session = try await interaction().beginOAuthRedirect()
    #expect(session.redirectURI.host == "127.0.0.1" && session.redirectURI.port != nil)
    let waiting = Task { try await session.authorize(at: URL(string: "https://accounts.example/auth")!) }
    try await Task.sleep(for: .milliseconds(100))
    let (body, response) = try await URLSession.shared.data(from: URL(string: session.redirectURI.absoluteString + "/?code=abc&state=xyz")!)
    #expect((response as? HTTPURLResponse)?.statusCode == 200)
    #expect(String(decoding: body, as: UTF8.self).contains("close this window"))
    let received = try await waiting.value
    #expect(URLComponents(url: received, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "code" }?.value == "abc")
    await session.close()
}

@Test func redirectArrivingBeforeAuthorizeWaitsIsNotLost() async throws {
    let session = try await interaction().beginOAuthRedirect()
    _ = try await URLSession.shared.data(from: URL(string: session.redirectURI.absoluteString + "/?code=early&state=s")!)
    let received = try await session.authorize(at: URL(string: "https://accounts.example/auth")!)
    #expect(received.query?.contains("code=early") == true)
    await session.close()
}

@Test func authorizeTimesOut() async throws {
    let session = try await interaction(timeout: .milliseconds(200)).beginOAuthRedirect()
    await #expect(throws: LoopbackError.timedOut) { try await session.authorize(at: URL(string: "https://accounts.example/auth")!) }
    await session.close()
}

@Test func closeFreesThePortAndIsIdempotent() async throws {
    let session = try await interaction().beginOAuthRedirect()
    await session.close()
    await session.close()
    await #expect(throws: (any Error).self) {
        _ = try await URLSession.shared.data(from: URL(string: session.redirectURI.absoluteString + "/?code=x&state=y")!)
    }
}

@Test func promptCredentialsIsUnavailableUnlessInjected() async {
    await #expect(throws: LoopbackError.credentialPromptUnavailable) {
        _ = try await interaction().promptCredentials([CredentialField(key: "u", label: "User")])
    }
}
```

- [ ] **Step 6: Implement `LoopbackRequest.swift`.**

```swift
import Foundation

enum LoopbackRequest {
    /// The full URL of an OAuth redirect: a `GET` whose target's query has `code` or `error`. Anything else
    /// (favicon, probes) is nil so the listener keeps waiting.
    static func redirectURL(from data: Data, port: UInt16) -> URL? {
        guard let text = String(data: data, encoding: .utf8),
              let line = text.components(separatedBy: "\r\n").first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let components = URLComponents(string: "http://127.0.0.1:\(port)\(parts[1])"),
              let items = components.queryItems,
              items.contains(where: { $0.name == "code" || $0.name == "error" }) else { return nil }
        return components.url
    }
}
```

- [ ] **Step 7: Implement `LoopbackAuthorizationInteraction.swift`.**

```swift
import CalendarCore
import Foundation
import Network

public enum LoopbackError: Error, Equatable {
    case couldNotOpenBrowser, timedOut, cancelled, credentialPromptUnavailable
    case listenerFailed(String)
}

/// OAuth via a loopback redirect: listens on 127.0.0.1 (ephemeral port), hands the authorization URL to the
/// host's `openURL` (TimeTug passes NSWorkspace) and returns the redirect it receives. Swap it for your own
/// `AuthorizationInteraction` on other hosts.
public struct LoopbackAuthorizationInteraction: AuthorizationInteraction {
    public typealias OpenURL = @Sendable (URL) async -> Bool
    public typealias PromptCredentials = @Sendable ([CredentialField]) async throws -> [String: String]

    private let openURL: OpenURL
    private let prompt: PromptCredentials?
    private let timeout: Duration

    public init(openURL: @escaping OpenURL, promptCredentials: PromptCredentials? = nil, timeout: Duration = .seconds(300)) {
        self.openURL = openURL
        self.prompt = promptCredentials
        self.timeout = timeout
    }

    public func beginOAuthRedirect() async throws -> any OAuthRedirectSession {
        try await LoopbackSession.start(openURL: openURL, timeout: timeout)
    }

    public func promptCredentials(_ fields: [CredentialField]) async throws -> [String: String] {
        guard let prompt else { throw LoopbackError.credentialPromptUnavailable }
        return try await prompt(fields)
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func run(_ body: () -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}

final class LoopbackSession: OAuthRedirectSession, @unchecked Sendable {
    private(set) var redirectURI = URL(string: "http://127.0.0.1")!
    private var port: UInt16 = 0
    private let listener: NWListener
    private let openURL: LoopbackAuthorizationInteraction.OpenURL
    private let timeout: Duration
    private let queue = DispatchQueue(label: "com.timetug.calendarapple.loopback")
    private let lock = NSLock()
    private var pending: CheckedContinuation<URL, Error>?
    private var received: Result<URL, Error>?

    private init(listener: NWListener, openURL: @escaping LoopbackAuthorizationInteraction.OpenURL, timeout: Duration) {
        self.listener = listener
        self.openURL = openURL
        self.timeout = timeout
    }

    static func start(openURL: @escaping LoopbackAuthorizationInteraction.OpenURL, timeout: Duration) async throws -> LoopbackSession {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        let listener: NWListener
        do { listener = try NWListener(using: parameters) } catch { throw LoopbackError.listenerFailed(String(describing: error)) }
        let session = LoopbackSession(listener: listener, openURL: openURL, timeout: timeout)
        listener.newConnectionHandler = { [weak session] connection in session?.accept(connection) }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let once = Once()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let raw = listener.port?.rawValue { once.run { continuation.resume(returning: raw) } }
                case .failed(let error):
                    once.run { continuation.resume(throwing: LoopbackError.listenerFailed(String(describing: error))) }
                case .cancelled:
                    once.run { continuation.resume(throwing: LoopbackError.cancelled) }
                default: break
                }
            }
            listener.start(queue: session.queue)
        }
        session.port = port
        session.redirectURI = URL(string: "http://127.0.0.1:\(port)")!
        return session
    }

    func authorize(at authorizationURL: URL) async throws -> URL {
        guard await openURL(authorizationURL) else { throw LoopbackError.couldNotOpenBrowser }
        let timeout = timeout
        return try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask { try await self.waitForRedirect() }
            group.addTask { try await Task.sleep(for: timeout); throw LoopbackError.timedOut }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    func close() async {
        listener.cancel()
        deliver(.failure(LoopbackError.cancelled))
    }

    private func deliver(_ result: Result<URL, Error>) {
        lock.lock(); defer { lock.unlock() }
        if let pending {
            self.pending = nil
            pending.resume(with: result)
        } else if received == nil {
            received = result
        }
    }

    private func waitForRedirect() async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                lock.lock()
                if let early = received {
                    received = nil
                    lock.unlock()
                    continuation.resume(with: early)
                } else {
                    pending = continuation
                    lock.unlock()
                }
            }
        } onCancel: {
            self.deliver(.failure(LoopbackError.cancelled))
        }
    }

    private static let page = """
    <!doctype html><meta charset="utf-8"><title>TimeTug</title>\
    <body style="font-family:-apple-system,sans-serif;text-align:center;margin-top:20vh">\
    <h2>You're signed in</h2><p>You can close this window and return to TimeTug.</p></body>
    """

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { connection.cancel(); return }
            let redirect = data.flatMap { LoopbackRequest.redirectURL(from: $0, port: self.port) }
            let status = redirect == nil ? "404 Not Found" : "200 OK"
            let body = redirect == nil ? "" : Self.page
            let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data((head + body).utf8), contentContext: .finalMessage, isComplete: true,
                            completion: .contentProcessed { _ in connection.cancel() })
            if let redirect { self.deliver(.success(redirect)) }
        }
    }
}
```
(The `deliver` cancellation after `close()` may race with an already-delivered redirect: `received == nil` guard keeps the first result. If `received` holds a cancellation from a `close()` before `waitForRedirect`, the wait throws `.cancelled`, which is the intent.)

- [ ] **Step 8: Run all:** `swift test --package-path Packages/CalendarApple`. Expect PASS. If `requiredLocalEndpoint` with `.any` port fails to bind on this OS, fall back to `NWListener(using: .tcp, on: .any)` and reject non-loopback peers by checking `connection.endpoint` in `accept` (record the change in the commit message).

- [ ] **Step 9: Commit.**

```bash
git add Packages/CalendarApple
git commit -m "feat(apple): CalendarApple adapters, Keychain credential store and loopback OAuth interaction

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: App: `SourceReconciler` and `AccountsController`

**Files:**
- Create: `Apps/macOS/Sources/SourceReconciler.swift`
- Create: `Apps/macOS/Sources/AccountsController.swift`
- Create: `Apps/macOS/Tests/{SourceReconcilerTests,AccountsControllerTests}.swift`
- Modify: `Apps/macOS/Sources/SettingsStore.swift` (add `eventKitEnabled`), `Apps/macOS/Tests/SettingsStoreTests.swift`
- Modify: `Apps/macOS/project.yml` (packages and dependencies; done in Task 9 Step 1 if this task cannot build yet, but do it here so the tests run)

**Interfaces:**
- Consumes: `ConnectedSource` (Task 5), library `ConnectorRegistry`/`ConnectorKind`/`Connection`/`FileConnectionStore`/`CredentialStore`/`SyncStateStore`/`AuthorizationInteraction` (Tasks 3-4), `TakeoverSettings.removeCalendars(whereSourceID:)` (Task 2), `CalendarStore.setSources` (Task 2).
- Produces:
  - `SettingsStore.eventKitEnabled: Bool` (`@Published`, key `eventKitEnabled.v1`, default `true`)
  - `@MainActor final class SourceReconciler { struct Update { let sources: [any CalendarSource]; let failures: [ConnectionID: String] }; init(buildAccount: @escaping (Connection) throws -> any CalendarSource, buildEventKit: @escaping () -> any CalendarSource, onChange: @escaping @MainActor () async -> Void); func reconcile(connections: [Connection], eventKitEnabled: Bool) -> Update; func rebuild(_ connection: Connection, connections: [Connection], eventKitEnabled: Bool) -> Update; func sourceID(forConnection id: ConnectionID) -> String?; func stop() }`
  - `@MainActor final class AccountsController: ObservableObject` (see Step 6)

- [ ] **Step 1: Project wiring so app tests can import the packages.** In `Apps/macOS/project.yml` add under `packages:`:

```yaml
  CalendarConnectors:
    path: ../../Packages/CalendarConnectors
  CalendarBridge:
    path: ../../Packages/CalendarBridge
  CalendarApple:
    path: ../../Packages/CalendarApple
```
and to both the `TimeTug` and `TimeTugTests` targets' `dependencies:` (tests need them for `@testable` use of library types):

```yaml
      - package: CalendarConnectors
        product: CalendarCore
      - package: CalendarConnectors
        product: GoogleCalendar
      - package: CalendarBridge
        product: CalendarBridge
      - package: CalendarApple
        product: CalendarApple
```
(`TimeTugTests` also gets `TimeTugCore` if it does not have it transitively; keep whatever builds.) Regenerate: `xcodegen generate --spec Apps/macOS/project.yml`, then `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' build`. Expect success (nothing uses the packages yet).

- [ ] **Step 2: Failing settings test** in `SettingsStoreTests.swift` (follow the file's existing setup for a throwaway `UserDefaults` suite):

```swift
    func testEventKitEnabledDefaultsToTrueAndPersists() {
        let defaults = UserDefaults(suiteName: "SettingsStoreTests.eventKit.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.eventKitEnabled)
        store.eventKitEnabled = false
        XCTAssertFalse(SettingsStore(defaults: defaults).eventKitEnabled)
    }
```
Implement in `SettingsStore`: `private static let eventKitKey = "eventKitEnabled.v1"`, `@Published var eventKitEnabled: Bool { didSet { defaults.set(eventKitEnabled, forKey: Self.eventKitKey) } }`, and in `init`: `self.eventKitEnabled = defaults.object(forKey: Self.eventKitKey) as? Bool ?? true` (before `mirrorToShared()`). Run the app tests for this class (`-only-testing:TimeTugTests/SettingsStoreTests`).

- [ ] **Step 3: Failing reconciler tests.** `SourceReconcilerTests.swift`:

```swift
import CalendarCore
import TimeTugCore
import XCTest
@testable import TimeTug

final class FakeCoreSource: TimeTugCore.CalendarSource, @unchecked Sendable {
    let id: String
    let displayName: String
    let continuation: AsyncStream<Void>.Continuation
    private let stream: AsyncStream<Void>
    private(set) var listenerStarted = 0
    init(id: String) {
        self.id = id
        displayName = id
        (stream, continuation) = AsyncStream.makeStream(of: Void.self)
    }
    func calendars() async throws -> [CalendarInfo] { [] }
    func events(in interval: DateInterval) async throws -> [TimeTugCalendarEvent] { [] }
    func changes() -> AsyncStream<Void> { listenerStarted += 1; return stream }
}

@MainActor
final class SourceReconcilerTests: XCTestCase {
    private let a = Connection(kindID: "google", connectionID: "1", displayName: "a@x.test")
    private let b = Connection(kindID: "google", connectionID: "2", displayName: "b@x.test")
    private var built: [String: FakeCoreSource] = [:]
    private var changeCount = 0

    private func makeReconciler(failing: Set<ConnectionID> = []) -> SourceReconciler {
        SourceReconciler(
            buildAccount: { [unowned self] c in
                if failing.contains(c.connectionID) { throw TimeTugCore.SourceError.authExpired }
                let s = FakeCoreSource(id: c.sourceID)   // library rule: google source id == Connection.sourceID
                built[c.connectionID] = s
                return s
            },
            buildEventKit: { FakeCoreSource(id: "eventkit") },
            onChange: { [unowned self] in changeCount += 1 })
    }

    func testBuildsEventKitFirstThenAccountsAndKeysBySourceID() {
        let r = makeReconciler()
        let update = r.reconcile(connections: [a, b], eventKitEnabled: true)
        XCTAssertEqual(update.sources.map(\.id), ["eventkit", "google-1", "google-2"])
        XCTAssertEqual(r.sourceID(forConnection: "1"), a.sourceID)
    }

    func testEventKitDisabledIsLeftOut() {
        XCTAssertEqual(makeReconciler().reconcile(connections: [a], eventKitEnabled: false).sources.map(\.id), ["google-1"])
    }

    func testUnchangedSourcesKeepTheirInstanceAndListener() async {
        let r = makeReconciler()
        _ = r.reconcile(connections: [a], eventKitEnabled: false)
        let first = built["1"]!
        let update = r.reconcile(connections: [a, b], eventKitEnabled: false)
        XCTAssertTrue(update.sources.first { $0.id == "google-1" } as AnyObject === first)
        await Task.yield()
        XCTAssertEqual(first.listenerStarted, 1)
    }

    func testRemovedSourceStopsItsListener() async throws {
        let r = makeReconciler()
        _ = r.reconcile(connections: [a], eventKitEnabled: false)
        let source = built["1"]!
        _ = r.reconcile(connections: [], eventKitEnabled: false)
        source.continuation.yield()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(changeCount, 0)
    }

    func testAChangeFromASourceTriggersOnChange() async throws {
        let r = makeReconciler()
        _ = r.reconcile(connections: [a], eventKitEnabled: false)
        try await Task.sleep(for: .milliseconds(50))
        built["1"]!.continuation.yield()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(changeCount, 1)
    }

    func testFailingBuildIsReportedAndDoesNotStopOthers() {
        let update = makeReconciler(failing: ["1"]).reconcile(connections: [a, b], eventKitEnabled: false)
        XCTAssertEqual(update.sources.map(\.id), ["google-2"])
        XCTAssertNotNil(update.failures["1"])
    }

    func testRebuildReplacesTheInstanceAndRestartsTheListener() async throws {
        let r = makeReconciler()
        _ = r.reconcile(connections: [a], eventKitEnabled: false)
        let old = built["1"]!
        old.continuation.finish()   // like a source whose stream ended after .sourceFailed
        let update = r.rebuild(a, connections: [a], eventKitEnabled: false)
        let new = built["1"]!
        XCTAssertFalse(old === new)
        XCTAssertTrue(update.sources.first as AnyObject === new)
        try await Task.sleep(for: .milliseconds(50))
        new.continuation.yield()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(changeCount, 1)
    }
}
```

- [ ] **Step 4: Implement `SourceReconciler.swift`.**

```swift
import CalendarCore
import Foundation
import TimeTugCore

/// Decides which sources exist (EventKit if enabled, then one per stored account), keeps each running source's
/// change listener alive, and replaces sources when asked. Sources are identified by their own `id`.
@MainActor
final class SourceReconciler {
    struct Update {
        let sources: [any TimeTugCore.CalendarSource]
        /// Build errors by connection id, for the Accounts pane.
        let failures: [ConnectionID: String]
    }

    private struct Entry {
        let source: any TimeTugCore.CalendarSource
        let listener: Task<Void, Never>
    }

    private static let eventKitKey = "\u{0}eventkit"
    private let buildAccount: (Connection) throws -> any TimeTugCore.CalendarSource
    private let buildEventKit: () -> any TimeTugCore.CalendarSource
    private let onChange: @MainActor () async -> Void
    private var entries: [String: Entry] = [:]   // keyed by connection id, or `eventKitKey`

    init(
        buildAccount: @escaping (Connection) throws -> any TimeTugCore.CalendarSource,
        buildEventKit: @escaping () -> any TimeTugCore.CalendarSource,
        onChange: @escaping @MainActor () async -> Void
    ) {
        self.buildAccount = buildAccount
        self.buildEventKit = buildEventKit
        self.onChange = onChange
    }

    func sourceID(forConnection id: ConnectionID) -> String? { entries[id]?.source.id }

    func reconcile(connections: [Connection], eventKitEnabled: Bool) -> Update {
        apply(connections: connections, eventKitEnabled: eventKitEnabled, rebuilding: nil)
    }

    /// After a successful re-sign-in: builds a fresh source for `connection` and restarts its listener (a source's
    /// change stream ends after `.sourceFailed`, so an unchanged id would otherwise never poll again).
    func rebuild(_ connection: Connection, connections: [Connection], eventKitEnabled: Bool) -> Update {
        apply(connections: connections, eventKitEnabled: eventKitEnabled, rebuilding: connection.connectionID)
    }

    func stop() {
        entries.values.forEach { $0.listener.cancel() }
        entries = [:]
    }

    private func apply(connections: [Connection], eventKitEnabled: Bool, rebuilding: ConnectionID?) -> Update {
        var wanted: [String] = []
        var failures: [ConnectionID: String] = [:]
        if eventKitEnabled {
            wanted.append(Self.eventKitKey)
            if entries[Self.eventKitKey] == nil { entries[Self.eventKitKey] = start(buildEventKit()) }
        }
        for connection in connections {
            let key = connection.connectionID
            if key == rebuilding { entries[key]?.listener.cancel(); entries[key] = nil }
            if entries[key] == nil {
                do { entries[key] = start(try buildAccount(connection)) }
                catch { failures[key] = String(describing: error); continue }
            }
            wanted.append(key)
        }
        for key in entries.keys where !wanted.contains(key) {
            entries[key]?.listener.cancel()
            entries[key] = nil
        }
        return Update(sources: wanted.compactMap { entries[$0]?.source }, failures: failures)
    }

    private func start(_ source: any TimeTugCore.CalendarSource) -> Entry {
        let onChange = onChange
        let listener = Task { @MainActor in
            for await _ in source.changes() { await onChange() }
        }
        return Entry(source: source, listener: listener)
    }
}
```
(Because `entries[key] == nil` after a failed build in an earlier call, the next `reconcile` retries it.)

- [ ] **Step 5: Run reconciler tests** (`xcodegen generate ...` then `xcodebuild ... test -only-testing:TimeTugTests/SourceReconcilerTests`). Expect PASS.

- [ ] **Step 6: Failing controller tests.** `AccountsControllerTests.swift`. Test doubles (library side, in the test file):

```swift
import CalendarCore
import TimeTugCore
import XCTest
@testable import TimeTug

private struct NoInteraction: AuthorizationInteraction {
    func beginOAuthRedirect() async throws -> any OAuthRedirectSession { throw CalendarCore.SourceError.invalidResponse("unused") }
    func promptCredentials(_ fields: [CredentialField]) async throws -> [String: String] { [:] }
}

private final class FakeKind: ConnectorKind, @unchecked Sendable {
    let id = "google"
    let displayName = "Google"
    let supportedPlatforms = Platform.macOS
    let authorization = AuthorizationMethod.oauth
    var nextEmail = "a@x.test"
    var nextConnectionID = "1"
    var reauthorizeError: Error?
    private(set) var reauthorized = 0
    func authorize(using interaction: any AuthorizationInteraction, credentials: any CredentialStore) async throws -> Connection {
        let c = Connection(kindID: id, connectionID: nextConnectionID, displayName: nextEmail, config: ["email": nextEmail])
        try await credentials.setSecrets(["refresh_token": "r-\(nextConnectionID)"], for: c.connectionID)
        return c
    }
    func reauthorize(_ connection: Connection, using interaction: any AuthorizationInteraction, credentials: any CredentialStore) async throws -> Connection {
        if let reauthorizeError { throw reauthorizeError }
        reauthorized += 1
        return connection
    }
    func makeSource(for connection: Connection, credentials: any CredentialStore, syncState: any SyncStateStore) throws -> any CalendarCore.CalendarSource {
        fatalError("controller tests build core sources through the reconciler closure")
    }
}
```
Fixture (`@MainActor` `setUp`): temp `FileConnectionStore`, `InMemoryCredentialStore`, `InMemorySyncStateStore`, a `SettingsStore(defaults: throwaway suite)`, a `[[String]]` log of `applySources` calls, a `SourceReconciler` built with closures returning `FakeCoreSource(id: c.sourceID)` (reuse `FakeCoreSource` from the reconciler tests), registry containing the `FakeKind`, and `AccountsController(registry:connectionStore:credentials:syncState:interaction:settings:reconciler:applySources:)` where `applySources` records `sources.map(\.id)`. Tests:

  - `testAddPersistsAppliesAndTracksTheAccount`: `await controller.addAccount(kindID: "google")`; `controller.accounts.map(\.connectionID) == ["1"]`; `connectionStore.connections()` has it; last applied ids == `["eventkit", "google-1"]`.
  - `testAddingTheSameAccountTwiceIsRejectedAndItsSecretsAreDiscarded`: add twice with a new `nextConnectionID = "2"` but the same email; second call leaves one account, sets `errorMessage`, and `credentials.secrets(for: "2") == nil`.
  - `testRemoveDeletesConnectionSelectionsSecretsAndSyncState`: add account; set `settings.takeover.takeoverCalendarKeys = ["google-1/c", "eventkit/x"]`, hidden `["google-1/d"]`, `syncState.setToken("t", for: "1", scope: "s")`; `await controller.removeAccount(connectionID: "1")`; accounts empty; store empty; keys == `["eventkit/x"]`, hidden empty; secrets nil; token nil; last applied ids == `["eventkit"]`.
  - `testRemoveIsIdempotent`: calling `removeAccount` twice does not throw or change other selections.
  - `testKeychainFailureDuringRemovalDoesNotUndoIt`: a `CredentialStore` whose `removeSecrets` throws; after `removeAccount` the account is gone and `errorMessage != nil`.
  - `testLaunchSweepRemovesOrphanedAccountSelectionsButNeverEventKit`: pre-store account `"1"`; settings keys `["google-1/c", "google-9/c", "eventkit/x"]`; `await controller.start()`; keys == `["google-1/c", "eventkit/x"]`.
  - `testLaunchSweepIsSkippedWhenTheAccountFileIsUnreadable`: write garbage to the store's URL; `start()`; keys unchanged; `errorMessage != nil`.
  - `testReauthorizeRebuildsTheSource`: add account; make the reconciler's builder count builds; `await controller.reauthorize(connectionID: "1")`; `kind.reauthorized == 1`; builder count == 2.
  - `testEventKitToggleKeepsSelectionsAndChangesTheSourceSet`: `await controller.setEventKitEnabled(false)`; last applied ids has no `"eventkit"`, `settings.eventKitEnabled == false`, `takeoverCalendarKeys` still contains `"eventkit/x"`; toggling on restores it.

  For the EventKit toggle to not prompt in tests, the controller receives `requestEventKitAccess: () async -> Void` (a closure) instead of talking to `EventKitConnectorKind` directly; tests pass `{}`.

- [ ] **Step 7: Implement `AccountsController.swift`.**

```swift
import CalendarCore
import Foundation
import TimeTugCore

/// Owns the user's accounts: add, remove, re-sign-in and the Apple Calendar switch. It persists changes, keeps
/// the source set current through the reconciler and forgets a removed account's calendar selections.
@MainActor
final class AccountsController: ObservableObject {
    @Published private(set) var accounts: [Connection] = []
    @Published private(set) var isWorking = false
    @Published private(set) var buildFailures: [ConnectionID: String] = [:]
    @Published var errorMessage: String?

    private let registry: ConnectorRegistry
    private let connectionStore: FileConnectionStore
    private let credentials: any CredentialStore
    private let syncState: any SyncStateStore
    private let interaction: any AuthorizationInteraction
    private let settings: SettingsStore
    private let reconciler: SourceReconciler
    private let applySources: ([any TimeTugCore.CalendarSource]) async -> Void
    private let requestEventKitAccess: () async -> Void
    private var addTask: Task<Void, Never>?

    init(
        registry: ConnectorRegistry, connectionStore: FileConnectionStore, credentials: any CredentialStore,
        syncState: any SyncStateStore, interaction: any AuthorizationInteraction, settings: SettingsStore,
        reconciler: SourceReconciler, applySources: @escaping ([any TimeTugCore.CalendarSource]) async -> Void,
        requestEventKitAccess: @escaping () async -> Void
    ) {
        self.registry = registry
        self.connectionStore = connectionStore
        self.credentials = credentials
        self.syncState = syncState
        self.interaction = interaction
        self.settings = settings
        self.reconciler = reconciler
        self.applySources = applySources
        self.requestEventKitAccess = requestEventKitAccess
    }

    /// Account kinds offered by `+` (system-permission kinds such as Apple Calendar are a switch, not an account).
    var availableKinds: [any ConnectorKind] {
        registry.kinds(for: .current).filter { if case .system = $0.authorization { false } else { true } }
    }

    /// The key of this account's status in `CalendarSnapshot.statuses`.
    func statusKey(for connection: Connection) -> String {
        reconciler.sourceID(forConnection: connection.connectionID) ?? connection.sourceID
    }

    func start() async {
        switch await connectionStore.load() {
        case .loaded(let list):
            accounts = list
            sweepOrphanedSelections()
        case .missing:
            accounts = []
            sweepOrphanedSelections()
        case .unreadable:
            accounts = []
            errorMessage = "Your saved accounts could not be read, so none were loaded. Nothing was deleted."
        }
        if settings.eventKitEnabled { await requestEventKitAccess() }
        await reconcileAndApply()
    }

    func addAccount(kindID: String) async {
        guard !isWorking, let kind = registry.kind(id: kindID) else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let connection = try await kind.authorize(using: interaction, credentials: credentials)
            if accounts.contains(where: { $0.kindID == connection.kindID && $0.displayName == connection.displayName }) {
                try? await credentials.removeSecrets(for: connection.connectionID)
                errorMessage = "\(connection.displayName) is already added."
                return
            }
            try await connectionStore.add(connection)
            accounts.append(connection)
            await reconcileAndApply()
        } catch is CancellationError {
            // The user cancelled the sign-in.
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// Starts `addAccount` as a cancellable task (the pane's Cancel button calls `cancelAdd`).
    func beginAddAccount(kindID: String) {
        addTask = Task { await addAccount(kindID: kindID) }
    }
    func cancelAdd() { addTask?.cancel() }

    /// Order matters so an interruption never leaves a half-removed account that looks alive: the stored connection
    /// goes first (it is what makes the account exist), the source is then stopped through the reconciler, the
    /// calendar selections are forgotten, and secrets and sync state are deleted last, best effort.
    func removeAccount(connectionID: ConnectionID) async {
        guard let connection = accounts.first(where: { $0.connectionID == connectionID }) else { return }
        let sourceID = statusKey(for: connection)
        do { try await connectionStore.remove(connectionID: connectionID) }
        catch { errorMessage = Self.describe(error); return }
        accounts.removeAll { $0.connectionID == connectionID }
        await reconcileAndApply()
        settings.takeover.removeCalendars(forSourceID: sourceID)
        await syncState.removeAll(for: connectionID)
        do { try await credentials.removeSecrets(for: connectionID) }
        catch { errorMessage = "The account was removed, but its saved sign-in could not be deleted: \(Self.describe(error))" }
    }

    func reauthorize(connectionID: ConnectionID) async {
        guard let connection = accounts.first(where: { $0.connectionID == connectionID }),
              let kind = registry.kind(id: connection.kindID) else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let updated = try await kind.reauthorize(connection, using: interaction, credentials: credentials)
            if let index = accounts.firstIndex(where: { $0.connectionID == connectionID }) { accounts[index] = updated }
            try await connectionStore.add(updated)
            let update = reconciler.rebuild(updated, connections: accounts, eventKitEnabled: settings.eventKitEnabled)
            buildFailures = update.failures
            await applySources(update.sources)
        } catch is CancellationError {
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// Turning it off hides the calendars but keeps their stored selections, so turning it back on is lossless.
    func setEventKitEnabled(_ enabled: Bool) async {
        settings.eventKitEnabled = enabled
        if enabled { await requestEventKitAccess() }
        await reconcileAndApply()
    }

    private func reconcileAndApply() async {
        let update = reconciler.reconcile(connections: accounts, eventKitEnabled: settings.eventKitEnabled)
        buildFailures = update.failures
        await applySources(update.sources)
    }

    /// Drops stored selections of account-based sources that no stored account owns (an interrupted removal).
    /// Never runs on an unreadable file and never touches Apple Calendar (`eventkit/...`) keys.
    private func sweepOrphanedSelections() {
        let prefixes = availableKinds.map { "\($0.id)-" }
        let known = Set(accounts.map { statusKey(for: $0) } + accounts.map(\.sourceID))
        settings.takeover.removeCalendars(whereSourceID: { id in
            prefixes.contains { id.hasPrefix($0) } && !known.contains(id)
        })
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case CalendarCore.SourceError.authExpired: "Sign-in was not completed."
        case let e as CalendarCore.SourceError: "Sign-in failed (\(e))."
        default: error.localizedDescription
        }
    }
}
```
Note for `sweepOrphanedSelections` at launch: `statusKey` falls back to `connection.sourceID` before the reconciler has run, which equals the source id for Google.

- [ ] **Step 8: Run:** regenerate the project and run `-only-testing:TimeTugTests/AccountsControllerTests`, `SourceReconcilerTests`, `SettingsStoreTests`, then the full app suite. Expect PASS.

- [ ] **Step 9: Commit.**

```bash
git add Apps/macOS Packages
git commit -m "feat(app): SourceReconciler and AccountsController; eventKitEnabled setting

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

### Task 9: Wire the app: registry, Google config, `AppCoordinator`

**Files:**
- Create: `Apps/macOS/Sources/{AppConnectors,GoogleOAuthSettings,AppSupportFiles}.swift`
- Create: `Apps/macOS/Tests/{GoogleOAuthSettingsTests,AppConnectorsTests}.swift`
- Modify: `Apps/macOS/Sources/AppCoordinator.swift`, `Apps/macOS/Sources/Info.plist`, `Apps/macOS/project.yml`, `Apps/macOS/Config/Signing.xcconfig`, `.gitignore`, `scripts/dev/link-signing.sh`

**Interfaces:**
- Consumes: Tasks 2-8.
- Produces:
  - `enum GoogleOAuthSettings { static func config(from info: [String: Any]?) -> GoogleOAuthConfig?; static func config(bundle: Bundle = .main) -> GoogleOAuthConfig? }` (nil when either key is missing, empty or an unexpanded `$(...)`)
  - `enum AppConnectors { static func makeRegistry(google: GoogleOAuthConfig?, eventKit: EventKitSource) -> ConnectorRegistry }`
  - `enum AppSupportFiles { static func url(_ name: String) -> URL }` (`~/Library/Application Support/TimeTug/<name>`)
  - `AppCoordinator.accounts: AccountsController` (Task 10 passes it to Settings)

- [ ] **Step 1: Failing tests.**

`GoogleOAuthSettingsTests.swift`:

```swift
import XCTest
@testable import TimeTug

final class GoogleOAuthSettingsTests: XCTestCase {
    func testReadsBothKeys() {
        let config = GoogleOAuthSettings.config(from: ["TimeTugGoogleClientID": "id.apps", "TimeTugGoogleClientSecret": "s"])
        XCTAssertEqual(config?.clientID, "id.apps")
        XCTAssertEqual(config?.clientSecret, "s")
    }
    func testMissingEmptyOrUnexpandedValuesDisableGoogle() {
        XCTAssertNil(GoogleOAuthSettings.config(from: nil))
        XCTAssertNil(GoogleOAuthSettings.config(from: ["TimeTugGoogleClientID": "id"]))
        XCTAssertNil(GoogleOAuthSettings.config(from: ["TimeTugGoogleClientID": "", "TimeTugGoogleClientSecret": ""]))
        XCTAssertNil(GoogleOAuthSettings.config(from: ["TimeTugGoogleClientID": "$(GOOGLE_OAUTH_CLIENT_ID)", "TimeTugGoogleClientSecret": "s"]))
    }
}
```

`AppConnectorsTests.swift`:

```swift
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
```
Run; expect compile failure.

- [ ] **Step 2: Implement the small files.**

`GoogleOAuthSettings.swift`:

```swift
import Foundation
import GoogleCalendar

/// The Google Desktop OAuth client, injected at build time from the git-ignored GoogleOAuth.xcconfig into
/// Info.plist. Without it (CI, fresh checkouts) Google is not offered and everything else works.
enum GoogleOAuthSettings {
    static func config(from info: [String: Any]?) -> GoogleOAuthConfig? {
        func value(_ key: String) -> String? {
            guard let raw = (info?[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty, !raw.hasPrefix("$(") else { return nil }
            return raw
        }
        guard let id = value("TimeTugGoogleClientID"), let secret = value("TimeTugGoogleClientSecret") else { return nil }
        return GoogleOAuthConfig(clientID: id, clientSecret: secret)
    }

    static func config(bundle: Bundle = .main) -> GoogleOAuthConfig? { config(from: bundle.infoDictionary) }
}
```

`AppConnectors.swift`:

```swift
import CalendarCore
import EventKitSource
import GoogleCalendar

enum AppConnectors {
    static func makeRegistry(google: GoogleOAuthConfig?, eventKit: EventKitSource) -> ConnectorRegistry {
        var registry = ConnectorRegistry()
        registry.register(EventKitConnectorKind(source: eventKit))
        if let google { registry.register(GoogleConnectorKind(config: google)) }
        return registry
    }
}
```

`AppSupportFiles.swift`:

```swift
import Foundation

/// Files under `~/Library/Application Support/TimeTug/`, matching `LedgerStore`'s location rule.
enum AppSupportFiles {
    static func url(_ name: String) -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("TimeTug", isDirectory: true).appendingPathComponent(name)
    }
}
```

- [ ] **Step 3: OAuth client plumbing.**
  1. `Apps/macOS/project.yml`, `TimeTug` target `info.properties`: add `TimeTugGoogleClientID: $(GOOGLE_OAUTH_CLIENT_ID)` and `TimeTugGoogleClientSecret: $(GOOGLE_OAUTH_CLIENT_SECRET)`. Mirror both keys in `Apps/macOS/Sources/Info.plist` (`<key>..</key><string>$(GOOGLE_OAUTH_CLIENT_ID)</string>`) because that file is checked in beside the generated one.
  2. `Apps/macOS/Config/Signing.xcconfig`: after `#include? "Local.xcconfig"` add a comment and `#include? "GoogleOAuth.xcconfig"` (git-ignored; defines `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET`; a missing file leaves them empty).
  3. `.gitignore`: add `Apps/macOS/Config/GoogleOAuth.xcconfig` under the signing entry.
  4. `scripts/dev/link-signing.sh`: view the whole file, then refactor it into a function so a second file can be linked without the early `exit 0` skipping it:

```bash
link_one() {   # link_one SRC DEST
  local src="$1" dest="$2"
  if [ ! -f "$src" ]; then
    [ -L "$dest" ] && rm -f "$dest"
    return 0
  fi
  [ "$(readlink "$dest" 2>/dev/null || true)" = "$src" ] || ln -sfn "$src" "$dest"
}
CONFIG_DIR="$(cd "$(dirname "$0")/../.." && pwd)/Apps/macOS/Config"
link_one "${TIMETUG_SIGNING_XCCONFIG:-${HOME:-/nonexistent}/.config/timetug/signing.xcconfig}" "$CONFIG_DIR/Local.xcconfig"
link_one "${TIMETUG_GOOGLE_XCCONFIG:-${HOME:-/nonexistent}/.config/timetug/google-oauth.xcconfig}" "$CONFIG_DIR/GoogleOAuth.xcconfig"
```
  keep the file's header comment and update it to mention the second file. Run `bash -n scripts/dev/link-signing.sh` and run the script once with both env vars pointing at nonexistent files (expect no output, exit 0).

- [ ] **Step 4: Run the two new test classes.** `xcodegen generate --spec Apps/macOS/project.yml`, then `xcodebuild ... test -only-testing:TimeTugTests/GoogleOAuthSettingsTests -only-testing:TimeTugTests/AppConnectorsTests`. Expect PASS.

- [ ] **Step 5: `AppCoordinator` wiring.** Edit `Apps/macOS/Sources/AppCoordinator.swift`:
  1. Imports: add `CalendarApple`, `CalendarBridge`, `CalendarCore` (module-qualify `TimeTugCore.CalendarSource`/`SourceError` where a name is ambiguous).
  2. Keep `private let eventKit = EventKitSource()`. In `init`, build the store empty: `store = CalendarStore(sources: [], adjudicator: AppleIntelligence.makeAdjudicator())`.
  3. Add a lazily built controller (uses `self`, so `lazy`):

```swift
    private lazy var registry = AppConnectors.makeRegistry(google: GoogleOAuthSettings.config(), eventKit: eventKit)
    private let credentials = KeychainCredentialStore(service: "com.timetug.app.credentials")
    private let syncState = FileSyncStateStore(url: AppSupportFiles.url("sync-state.json"))
    private lazy var reconciler = SourceReconciler(
        buildAccount: { [unowned self] connection in
            guard let kind = registry.kind(id: connection.kindID) else { throw CalendarCore.SourceError.invalidResponse("unknown account type") }
            return ConnectedSource(try kind.makeSource(for: connection, credentials: credentials, syncState: syncState))
        },
        buildEventKit: { [unowned self] in ConnectedSource(eventKit) },
        onChange: { [weak self] in await self?.refresh() })
    lazy var accounts = AccountsController(
        registry: registry, connectionStore: FileConnectionStore(url: AppSupportFiles.url("accounts.json")),
        credentials: credentials, syncState: syncState,
        interaction: LoopbackAuthorizationInteraction(openURL: { url in await MainActor.run { NSWorkspace.shared.open(url) } }),
        settings: settings, reconciler: reconciler,
        applySources: { [weak self] sources in
            await self?.store.setSources(sources)
            await self?.refresh()
        },
        requestEventKitAccess: { [unowned self] in _ = await eventKit.requestAccess() })
```
  4. In `start()`: remove `_ = await eventKit.requestAccess()`. Keep the order that everything else (observers, sinks, dedup load) runs first, then replace `await refresh()` and the trailing `for await _ in eventKit.changes() { await refresh() }` with:

```swift
        await accounts.start()   // requests Apple Calendar access if enabled, builds the sources and refreshes
        if settings.takeover.takeoverCalendarKeys.isEmpty { openSettings(pane: .calendars) }
```
  (`accounts.start()` ends in `applySources`, which refreshes; delete the separate `await refresh()`.) The change loops now live in the reconciler.
  5. Pass `accounts` to `SettingsView` in the `settingsWindow` closure once Task 10 adds the parameter.
  6. Build: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' build`. Fix ambiguity errors by module-qualifying.

- [ ] **Step 7: Full app suite and a smoke launch.** Run `xcodebuild ... test` (expect PASS) and launch the built app once (`open` the product from DerivedData); confirm the popup still shows Apple Calendar events and the menu bar item appears. Quit it.

- [ ] **Step 8: Commit.**

```bash
git add Apps scripts .gitignore
git commit -m "feat(app): wire connectors into AppCoordinator; Google OAuth client from a git-ignored xcconfig

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 10: Accounts pane, settings navigation and search

**Files:**
- Create: `Apps/macOS/Sources/{AccountStatusText,AccountsPane}.swift`
- Create: `Apps/macOS/Tests/AccountStatusTextTests.swift`
- Modify: `Apps/macOS/Sources/{SettingsNavigation,SettingsView,SettingsSearch,AppCoordinator}.swift`, `Apps/macOS/Tests/SettingsSearchTests.swift`

**Interfaces:**
- Consumes: `AccountsController` (Task 8), `AppModel.statuses`, `SettingsStore.eventKitEnabled`.
- Produces: `SettingsPane.accounts`; `enum AccountStatusText { static func make(_ status: SourceStatus?) -> String }`; `AccountsPane(accounts:settings:model:navigation:)`; `SettingsText.accounts`, `SettingsText.appleCalendar`.

- [ ] **Step 1: Failing tests.** `AccountStatusTextTests.swift`:

```swift
import TimeTugCore
import XCTest
@testable import TimeTug

final class AccountStatusTextTests: XCTestCase {
    func testStatusWording() {
        XCTAssertEqual(AccountStatusText.make(.ok), "Connected")
        XCTAssertEqual(AccountStatusText.make(.authExpired), "Sign in again")
        XCTAssertEqual(AccountStatusText.make(.needsPermission), "Calendar access is off")
        XCTAssertEqual(AccountStatusText.make(.failing("boom")), "Can't reach this calendar right now")
        XCTAssertEqual(AccountStatusText.make(nil), "Connecting…")
    }
}
```
Add to `SettingsSearchTests.swift`:

```swift
    func testAccountsIsFoundByProviderAndSignInWords() {
        XCTAssertTrue(ids("google").contains("accounts"))
        XCTAssertTrue(ids("sign in").contains("accounts"))
        XCTAssertTrue(ids("apple calendar").contains("accounts"))
    }
```
Run; expect compile failures / failing tests.

- [ ] **Step 2: Implement text and navigation.**
  - `AccountStatusText.swift`:

```swift
import TimeTugCore

enum AccountStatusText {
    static func make(_ status: SourceStatus?) -> String {
        switch status {
        case .ok?: "Connected"
        case .authExpired?: "Sign in again"
        case .needsPermission?: "Calendar access is off"
        case .failing?: "Can't reach this calendar right now"
        case nil: "Connecting…"
        }
    }
}
```
  - `SettingsNavigation.swift`: `case general, accounts, calendars, tugRules`; title `"Accounts"`; `systemImage: "person.crop.circle"`; `iconColor: Color(red: 0.20, green: 0.70, blue: 0.40)`.
  - `SettingsSearch.swift`: add `static let accounts = "Accounts"` and `static let appleCalendar = "Apple Calendar"` to `SettingsText`, and this catalog entry (first in the array):

```swift
        .init(id: "accounts", title: SettingsText.accounts,
              keywords: ["google", "account", "accounts", "sign in", "add account", "remove account", "apple calendar", "eventkit", "icloud", "connect"], pane: .accounts),
```
  - `SettingsView.swift`: add `let accounts: AccountsController` and, in `detail`, `case .accounts: AccountsPane(accounts: accounts, settings: settings, model: model, navigation: navigation)`. Update `AppCoordinator`'s `SettingsView(...)` call with `accounts: accounts`.
  - Run `AccountStatusTextTests` and `SettingsSearchTests`; expect PASS.

- [ ] **Step 3: `AccountsPane.swift`.**

```swift
import AppKit
import CalendarCore
import SwiftUI
import TimeTugCore

struct AccountsPane: View {
    @ObservedObject var accounts: AccountsController
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: AppModel
    @ObservedObject var navigation: SettingsNavigation
    @State private var selection: ConnectionID?
    @State private var pendingRemoval: Connection?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose where TimeTug reads your calendars from.")
                .font(.callout).foregroundStyle(.secondary)
            list
            controls
            if accounts.isWorking { waitingRow }
            if let message = accounts.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.orange)
            }
        }
        .padding(16)
        .settingsHighlight("accounts", navigation: navigation)
        .confirmationDialog(
            "Remove \(pendingRemoval?.displayName ?? "this account")?", isPresented: removalBinding, titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let connection = pendingRemoval {
                    selection = nil
                    Task { await accounts.removeAccount(connectionID: connection.connectionID) }
                }
                pendingRemoval = nil
            }
        } message: {
            Text("Its calendars will no longer appear and their Tug and visibility choices are forgotten.")
        }
    }

    private var removalBinding: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }

    private var list: some View {
        List(selection: $selection) {
            appleCalendarRow
            ForEach(accounts.accounts) { connection in
                accountRow(connection).tag(connection.connectionID)
            }
        }
        .listStyle(.bordered)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appleCalendarRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar").frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(SettingsText.appleCalendar) (this Mac)")
                Text(settings.eventKitEnabled ? AccountStatusText.make(model.statuses["eventkit"]) : "Off")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if settings.eventKitEnabled, model.statuses["eventkit"] == .needsPermission {
                Button("Open System Settings") { Self.openCalendarPrivacySettings() }.buttonStyle(.link)
            }
            Toggle("Enabled", isOn: Binding(
                get: { settings.eventKitEnabled },
                set: { enabled in Task { await accounts.setEventKitEnabled(enabled) } }))
                .labelsHidden()
                .toggleStyle(ContrastCheckboxStyle())
                .accessibilityLabel("Use \(SettingsText.appleCalendar)")
        }
        .padding(.vertical, 4)
    }

    private func accountRow(_ connection: Connection) -> some View {
        let status = model.statuses[accounts.statusKey(for: connection)]
        let failure = accounts.buildFailures[connection.connectionID]
        return HStack(spacing: 10) {
            Image(systemName: "person.crop.circle").frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.displayName)
                Text(failure == nil ? AccountStatusText.make(status) : "Can't start this account")
                    .font(.caption).foregroundStyle(status == .authExpired || failure != nil ? .orange : .secondary)
            }
            Spacer()
            if status == .authExpired || failure != nil {
                Button("Sign in again") { Task { await accounts.reauthorize(connectionID: connection.connectionID) } }
                    .disabled(accounts.isWorking)
            }
        }
        .padding(.vertical, 4)
    }

    private var controls: some View {
        HStack(spacing: 0) {
            Menu {
                if accounts.availableKinds.isEmpty {
                    Text("No account types are available in this build")
                }
                ForEach(accounts.availableKinds, id: \.id) { kind in
                    Button(kind.displayName) { accounts.beginAddAccount(kindID: kind.id) }
                }
            } label: {
                Image(systemName: "plus").frame(width: 24, height: 20)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .fixedSize()
            .disabled(accounts.isWorking)
            .accessibilityLabel("Add account")
            Divider().frame(height: 16).padding(.horizontal, 4)
            Button {
                pendingRemoval = accounts.accounts.first { $0.connectionID == selection }
            } label: {
                Image(systemName: "minus").frame(width: 24, height: 20)
            }
            .buttonStyle(.borderless)
            .disabled(selection == nil || accounts.isWorking || !accounts.accounts.contains { $0.connectionID == selection })
            .accessibilityLabel("Remove account")
            Spacer()
        }
    }

    private var waitingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Waiting for your browser…").font(.callout)
            Button("Cancel") { accounts.cancelAdd() }.buttonStyle(.link)
        }
    }

    private static func openCalendarPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}
```
  Compile fixes to expect: `ContrastCheckboxStyle` and `settingsHighlight` exist in the app (used by `CalendarsPane`); `SourceStatus` is `Equatable`. If `Text` is not allowed directly inside `Menu`, use `Button("...") {}.disabled(true)`.

- [ ] **Step 4: Build, run the app suite, and check the pane by eye.** `xcodebuild ... test` (expect PASS). Launch the app; open Settings: sidebar order General, Accounts, Calendars, Tug Rules; the Apple Calendar row shows Connected with its checkbox; `+` shows "No account types are available in this build" when `GoogleOAuth.xcconfig` is absent, or "Google" when present. Toggle the checkbox off and on: Calendars pane loses and regains the Apple calendars with selections intact.

- [ ] **Step 5: Commit.**

```bash
git add Apps
git commit -m "feat(app): Accounts pane with +/- and an Apple Calendar switch

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 11: Docs, CI and manual checklist

**Files:**
- Modify: `.github/workflows/ci.yml`, `AGENTS.md`, `docs/architecture.md`, `docs/decisions/0012-calendar-connector-library.md`, `docs/manual-tests/macos-checklist.md`

- [ ] **Step 1: CI.** In the `core` job replace `swift build --package-path Packages/EventKitSource` with `swift test --package-path Packages/EventKitSource` and add two steps: `swift test --package-path Packages/CalendarBridge` and `swift test --package-path Packages/CalendarApple`. Update the header comment's `core` line to list them. `connectors-linux` needs no change (the new file stores are in `CalendarCore` and run there).

- [ ] **Step 2: AGENTS.md and architecture.** In `AGENTS.md`: update the `CalendarConnectors` layout line (TimeTug now uses it through `CalendarBridge`; add `FileConnectionStore`, `FileSyncStateStore`, `AllDay`), add layout lines for `Packages/CalendarBridge` and `Packages/CalendarApple`, add test commands `swift test --package-path Packages/CalendarBridge`, `Packages/CalendarApple`, `Packages/EventKitSource`, and a note that Google needs `Apps/macOS/Config/GoogleOAuth.xcconfig` (or `~/.config/timetug/google-oauth.xcconfig`, linked by `link-signing.sh`) defining `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET`. In `docs/architecture.md` update the connector bullet the same way.

- [ ] **Step 3: ADR 0012.** Append a "Phase 2" section: the bridge package and why Core does not depend on the library (swift-crypto vs swift:6.0), the layering rule (generic in `CalendarCore`, OS code in `CalendarApple`/`EventKitSource` adapters), the all-day rule (connector to canonical, bridge to TimeTug-native, interim until Phase 2.5), EventKit's constant source id and the rule to key by `source.id`, removal order, and Phase 2.5's goal (minimal bridge; dependency-free `CalendarCore` by moving OAuth into `CalendarOAuth`).

- [ ] **Step 4: Manual checklist.** In `docs/manual-tests/macos-checklist.md` change the sidebar-order line to "General, Accounts, Calendars, Tug Rules" and append:

```markdown
- [ ] Settings > Accounts lists "Apple Calendar (this Mac)" with an enable checkbox and a `+ −` bar. Turning the checkbox off removes the Apple calendars from Calendars and the popup; turning it back on restores them with their Tug/Show choices intact.
- [ ] With Calendar access denied in System Settings, the Apple Calendar row says "Calendar access is off" and "Open System Settings" opens the Calendars privacy pane.
- [ ] (Needs the Google client) `+` > Google opens the browser; after signing in the account appears with its email as status "Connected" and its calendars appear in Calendars under that email. Cancel during "Waiting for your browser…" leaves nothing behind.
- [ ] Adding a second Google account works; adding the same account again says it is already added and leaves no extra Keychain item.
- [ ] Select an account and `−`, confirm: its calendars and their Tug/Show choices disappear, the Keychain item (service com.timetug.app.credentials) is gone, and relaunching does not bring it back.
- [ ] Relaunch: Google accounts reconnect with no browser and no prompt.
- [ ] Revoke TimeTug at myaccount.google.com/permissions: within a minute the account shows "Sign in again"; clicking it and signing in as the same account restores it and edits made in Google appear within about a minute (the change listener restarted). Signing in as a different account is refused.
- [ ] Edit an event's title in Google Calendar: the popup shows the new title within about a minute.
- [ ] An all-day event created in Google in another time zone (for example a Tokyo calendar) appears on the same calendar date in the popup here, and an Apple all-day event created in another zone still appears on its date.
- [ ] A meeting present in both Apple Calendar and a direct Google account merges into one popup entry.
```

- [ ] **Step 5: Whole-branch verification.**

```bash
swift test --package-path Packages/TimeTugCore
swift test --package-path Packages/CalendarConnectors
swift test --package-path Packages/CalendarBridge
swift test --package-path Packages/CalendarApple
swift test --package-path Packages/EventKitSource
swift test --package-path Packages/AppleIntelligenceInference
xcodegen generate --spec Apps/macOS/project.yml
xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test
```
Expected: all pass. Also run the Linux job locally if Docker is available: `docker run --rm -v "$PWD":/w -w /w swift:6.2 swift test --package-path Packages/CalendarConnectors` and `swift:6.0 ... Packages/TimeTugCore`.

- [ ] **Step 6: Commit and open the PR** (push and `gh pr create --base master`; never a local merge). The PR description lists the manual checklist items that need a Google client and states that the Google entry is hidden in builds without one.

```bash
git add -A .github AGENTS.md docs
git commit -m "docs+ci: Phase 2 docs, ADR update, manual checklist, bridge and adapter tests in CI

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```
