# Widgets and Control Center Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Next Up and Today desktop widgets and three Control Center toggles (Skip All Day Events, Use Intelligence, Disable Tug), with Disable Tug also in Settings.

**Architecture:** The app writes a merged-agenda snapshot into an App Group container; a sandboxed WidgetKit extension reads it and builds rolling timelines from pure Core functions. Three booleans live in a shared `UserDefaults` suite; Control Center intents (extension process) write the suite and post a Darwin notification, and the app re-reads the suite and applies the change.

**Tech Stack:** Swift (Core: Swift 6 / Swift Testing; app + widget: Swift 5 mode, XCTest), SwiftUI, WidgetKit, AppIntents, XcodeGen.

Spec: `docs/superpowers/specs/2026-09-19-widgets-and-controls-design.md`. Read it and `AGENTS.md` first.

## Global Constraints

- App group id: `YYA6ZKMD36.com.timetug.shared` (team-prefixed). Team id `YYA6ZKMD36` is public, not a secret.
- App stays on macOS 14 (`deploymentTarget.macOS: "14.0"`). Widgets work on macOS 14+. Controls need macOS 26 and are `#available(macOS 26.0, *)`-guarded.
- Core (`Packages/TimeTugCore`): pure Swift, no UI or Apple-only imports, no display strings, time always passed in as `now: Date`, never `Date()`. Every Core behavior has a Swift Testing test written first.
- Disable Tug turns off takeover and the pre-meeting popup only. Menu bar item, popover and widgets keep showing the agenda.
- Widgets read only the snapshot; they never touch EventKit.
- The app must run normally when the App Group container is unavailable (ad-hoc builds): snapshot write logs and skips.
- Persisted `TakeoverSettings` JSON: every new field decodes with `decodeIfPresent` and a default.
- Generated `*.xcodeproj` is git-ignored; run `xcodegen generate --spec Apps/macOS/project.yml` after editing `project.yml`.
- Commit messages end with `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.
- DeepSeek (`mcp__deepseek__chat_completion`) is used for text-only reviews only. Before every call scan the text for secrets (`sk-`, `ghp_`, `AKIA`, `BEGIN .* PRIVATE KEY`, `password=`, `token=`, `Authorization:`); never send env dumps or `.env` content. Verify any Critical/Important finding against the repo before acting.

## Deviations from the spec (decided while planning)

- `DEVELOPMENT_TEAM` is not written into `project.yml` (it would make Xcode attempt automatic provisioning for the ad-hoc CI build). Signed builds pass it on the command line; the group id is a literal string.
- Tapping a widget opens the join link when there is one; otherwise it just activates the app. There is no URL scheme for opening the popover (YAGNI).
- No extra menu bar indicator for a disabled Tug: the icon simply never turns to the colour puppy (the scheduler returns nothing), and the Settings toggle and Control Center toggle show the state.

## File Structure

Create:
- `Packages/TimeTugCore/Sources/TimeTugCore/Widget/WidgetSnapshot.swift`: `WidgetEvent`, `WidgetSnapshot` (model, builder, staleness).
- `Packages/TimeTugCore/Sources/TimeTugCore/Widget/WidgetTimeline.swift`: `changeDates`, `nextUp`, `today`.
- `Packages/TimeTugCore/Tests/TimeTugCoreTests/WidgetSnapshotTests.swift`, `WidgetTimelineTests.swift`.
- `Apps/macOS/Shared/AppGroup.swift`: group id and container URL (compiled into app and extension).
- `Apps/macOS/Shared/SharedSettings.swift`: shared-suite booleans.
- `Apps/macOS/Shared/SettingsChangeSignal.swift`: Darwin notification post and observer.
- `Apps/macOS/Shared/WidgetSnapshotStore.swift`: atomic snapshot file read/write.
- `Apps/macOS/Sources/InferenceAvailability.swift`: `InferenceStatus.isAvailableOnThisMac`.
- `Apps/macOS/Widgets/TimeTugWidgets.swift` (bundle), `AgendaProvider.swift`, `NextUpWidget.swift`, `TodayWidget.swift`, `WidgetSupport.swift` (colour, placeholder), `Controls.swift`, `Info.plist` (generated), `TimeTugWidgets.entitlements`.
- `Apps/macOS/Tests/SharedInfraTests.swift`, `InferenceAvailabilityTests.swift`.
- `docs/decisions/0010-widgets-app-group-and-snapshot.md`.

Modify: `Apps/macOS/project.yml`, `Apps/macOS/Sources/TimeTug.entitlements`, `TakeoverSettings.swift`, `TakeoverPolicy.swift`, `SettingsStore.swift`, `SettingsSearch.swift`, `TugRulesPane.swift`, `AppCoordinator.swift`, `Apps/macOS/Tests/SettingsStoreTests.swift`, `SettingsSearchTests.swift`, `scripts/ci/build-release.sh`, `scripts/release/sign-and-notarize.sh`, `scripts/release/verify-dmg.sh`, `AGENTS.md`, `docs/architecture.md`, `README.md`, `docs/manual-tests/macos-checklist.md`, `docs/PROGRESS.md`.

---

### Task 1: Extension scaffolding and signed round-trip spike

Proves, before anything else is built, that a Developer-ID-signed app can write into the team-prefixed group container and the embedded widget can read it. If this fails, STOP and report to the user; do not continue.

**Files:**
- Create: `Apps/macOS/Shared/AppGroup.swift`, `Apps/macOS/Widgets/TimeTugWidgets.swift`, `Apps/macOS/Widgets/TimeTugWidgets.entitlements`
- Modify: `Apps/macOS/project.yml`, `Apps/macOS/Sources/TimeTug.entitlements`, `Apps/macOS/Sources/AppCoordinator.swift` (temporary spike lines, removed in Task 8)

**Interfaces:**
- Produces: `AppGroup.identifier: String`, `AppGroup.containerURL: URL?` (used by Tasks 5, 9, 10). Target `TimeTugWidgets` embedded in `TimeTug`.

- [ ] **Step 1: Shared group constants**

`Apps/macOS/Shared/AppGroup.swift`:
```swift
import Foundation

/// Identifiers shared by the app and the widget extension. The id is team-prefixed so a
/// Developer ID build needs no provisioning profile for the group.
enum AppGroup {
    static let identifier = "YYA6ZKMD36.com.timetug.shared"

    /// nil when the app is not signed with a team identity that owns the group (ad-hoc builds).
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
```

- [ ] **Step 2: Entitlements**

`Apps/macOS/Widgets/TimeTugWidgets.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>YYA6ZKMD36.com.timetug.shared</string>
	</array>
</dict>
</plist>
```
Add to `Apps/macOS/Sources/TimeTug.entitlements`, inside the `<dict>` after the calendars key:
```xml
	<key>com.apple.security.application-groups</key>
	<array>
		<string>YYA6ZKMD36.com.timetug.shared</string>
	</array>
```
Note: `TimeTug.entitlements` is also generated from `project.yml` `entitlements.properties`; update that too (Step 4) or XcodeGen will overwrite this file.

- [ ] **Step 3: Spike widget**

`Apps/macOS/Widgets/TimeTugWidgets.swift` (temporary content; replaced in Task 9):
```swift
import SwiftUI
import WidgetKit

struct SpikeEntry: TimelineEntry { let date: Date; let text: String }

struct SpikeProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpikeEntry { SpikeEntry(date: .now, text: "placeholder") }
    func getSnapshot(in context: Context, completion: @escaping (SpikeEntry) -> Void) { completion(read()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SpikeEntry>) -> Void) {
        completion(Timeline(entries: [read()], policy: .after(.now.addingTimeInterval(300))))
    }
    private func read() -> SpikeEntry {
        let url = AppGroup.containerURL?.appendingPathComponent("spike.txt")
        let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "NO CONTAINER OR FILE"
        return SpikeEntry(date: .now, text: text)
    }
}

struct SpikeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TimeTugSpike", provider: SpikeProvider()) { entry in
            Text(entry.text).containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Spike")
    }
}

@main
struct TimeTugWidgetBundle: WidgetBundle {
    var body: some Widget { SpikeWidget() }
}
```

- [ ] **Step 4: project.yml**

In `Apps/macOS/project.yml` change the app target `sources` to `[Sources, Resources, Shared]`, add the dependency `- target: TimeTugWidgets` (XcodeGen embeds app extensions automatically), add to the app's `entitlements.properties` the `com.apple.security.application-groups: [YYA6ZKMD36.com.timetug.shared]` entry, and add this target before `TimeTugTests`:
```yaml
  TimeTugWidgets:
    type: app-extension
    platform: macOS
    sources: [Widgets, Shared]
    dependencies:
      - package: TimeTugCore
        product: TimeTugCore
    info:
      path: Widgets/Info.plist
      properties:
        CFBundleName: TimeTugWidgets
        CFBundleDisplayName: TimeTug
        CFBundleShortVersionString: "0.0.0-dev"
        CFBundleVersion: "1"
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    entitlements:
      path: Widgets/TimeTugWidgets.entitlements
      properties:
        com.apple.security.app-sandbox: true
        com.apple.security.application-groups: [YYA6ZKMD36.com.timetug.shared]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.timetug.app.widgets
```
XcodeGen regenerates both entitlements files from `properties`; keep the XML files identical to it (regeneration is the source of truth).

- [ ] **Step 5: Temporary spike write in the app**

In `AppCoordinator.start()`, directly after `_ = await eventKit.requestAccess()` add (marked for removal):
```swift
        // SPIKE (Task 1): removed in Task 8.
        if let dir = AppGroup.containerURL {
            try? "app wrote this at \(Date())".write(to: dir.appendingPathComponent("spike.txt"), atomically: true, encoding: .utf8)
        }
```

- [ ] **Step 6: Build unsigned to prove it compiles**

Run:
```bash
xcodegen generate --spec Apps/macOS/project.yml
xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' build 2>&1 | tail -5
ls Apps/macOS/build 2>/dev/null; xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -showBuildSettings 2>/dev/null | grep -m1 " BUILT_PRODUCTS_DIR"
```
Expected: `** BUILD SUCCEEDED **`; `TimeTug.app/Contents/PlugIns/TimeTugWidgets.appex` exists in the products dir.

- [ ] **Step 7: Signed build and manual round trip (needs the user at the Mac)**

Run:
```bash
xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -configuration Release \
  -derivedDataPath build/spike CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=YYA6ZKMD36 \
  CODE_SIGN_IDENTITY="Developer ID Application: Scott O'Bryan (YYA6ZKMD36)" \
  OTHER_CODE_SIGN_FLAGS="--timestamp=none" build 2>&1 | tail -5
codesign -dv --entitlements - build/spike/Build/Products/Release/TimeTug.app 2>&1 | grep -A3 application-groups
rm -rf /Applications/TimeTug.app && cp -R build/spike/Build/Products/Release/TimeTug.app /Applications/ && open /Applications/TimeTug.app
sleep 5; ls ~/Library/Group\ Containers/YYA6ZKMD36.com.timetug.shared/ && cat ~/Library/Group\ Containers/YYA6ZKMD36.com.timetug.shared/spike.txt
pluginkit -mA | grep -i timetug
```
Expected: the app launches (not killed by AMFI), `spike.txt` exists, `pluginkit` lists `com.timetug.app.widgets`. Then ask the user to add the "Spike" widget (right-click desktop > Edit Widgets > TimeTug) and confirm it shows "app wrote this at …" rather than "NO CONTAINER OR FILE".

If the app is killed at launch, the group container is missing, or the widget shows NO CONTAINER: STOP. Report which. Fallbacks to try only with the user's agreement: sign with an Apple Development identity and a provisioning profile that enables the group.

- [ ] **Step 8: Commit**

```bash
git add Apps/macOS/Shared Apps/macOS/Widgets Apps/macOS/project.yml Apps/macOS/Sources/TimeTug.entitlements Apps/macOS/Sources/AppCoordinator.swift
git commit -m "feat: widget extension scaffolding and signed app-group round-trip spike

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Core `TakeoverSettings.disabled`

**Files:**
- Modify: `Packages/TimeTugCore/Sources/TimeTugCore/Model/TakeoverSettings.swift`, `.../Takeover/TakeoverPolicy.swift`
- Test: `Packages/TimeTugCore/Tests/TimeTugCoreTests/TakeoverPolicyTests.swift` (append), `SettingsRulesTests.swift` (append)

**Interfaces:**
- Produces: `TakeoverSettings.disabled: Bool` (default `false`, persisted, decoded with `decodeIfPresent`). When true, `TakeoverPolicy.qualifies` returns false, so `Scheduler.next`, `TakeoverGuard.evaluate` (`.suppress(.noLongerQualifies)`) and `MenuBarIconState.resolve` all stop producing takeovers with no further change. `DayAgenda` is unaffected.

- [ ] **Step 1: Write the failing tests**

Append to `TakeoverPolicyTests.swift`:
```swift
@Test func disabledSettingBlocksAnOtherwiseQualifyingEvent() {
    #expect(TakeoverPolicy.qualifies(makeEvent(), settings: optedIn()))
    #expect(!TakeoverPolicy.qualifies(makeEvent(), settings: optedIn { $0.disabled = true }))
}
```
Append to `SchedulerTests.swift`:
```swift
@Test func nothingIsScheduledWhileDisabled() {
    let next = Scheduler.next(events: [makeEvent()], settings: optedIn { $0.disabled = true },
                              ledger: TakeoverLedger(), now: date("2026-09-18T09:00:00Z"))
    #expect(next == nil)
}
```
Append to `TakeoverGuardTests.swift`:
```swift
@Test func guardSuppressesWhileDisabled() {
    let event = makeEvent()
    let decision = TakeoverGuard.evaluate(
        event: event, currentEvents: [event], settings: optedIn { $0.disabled = true },
        ledger: TakeoverLedger(), now: date("2026-09-18T09:59:30Z"), overlayVisible: false)
    #expect(decision == .suppress(.noLongerQualifies))
}
```
Append to `SettingsRulesTests.swift`:
```swift
@Test func disabledDefaultsToFalseWhenMissingFromSavedJSON() throws {
    let decoded = try JSONDecoder().decode(TakeoverSettings.self, from: Data("{}".utf8))
    #expect(decoded.disabled == false)
}

@Test func disabledRoundTripsThroughJSON() throws {
    var settings = TakeoverSettings()
    settings.disabled = true
    let decoded = try JSONDecoder().decode(TakeoverSettings.self, from: JSONEncoder().encode(settings))
    #expect(decoded.disabled)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Packages/TimeTugCore 2>&1 | tail -15`
Expected: compile error `value of type 'TakeoverSettings' has no member 'disabled'`.

- [ ] **Step 3: Implement**

In `TakeoverSettings.swift` add after `skipAllDayEvents`:
```swift
    /// Master switch: while true no takeover or pre-meeting popup fires. The agenda is unaffected.
    public var disabled = false
```
and in `init(from:)` after the `skipAllDayEvents` line:
```swift
        disabled = try c.decodeIfPresent(Bool.self, forKey: .disabled) ?? d.disabled
```
In `TakeoverPolicy.qualifies`, make this the first line of the function body:
```swift
        if settings.disabled { return false }
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --package-path Packages/TimeTugCore 2>&1 | tail -5`
Expected: all tests pass (previous count + 5).

- [ ] **Step 5: Commit**

```bash
git add Packages/TimeTugCore
git commit -m "feat(core): TakeoverSettings.disabled suppresses all takeovers

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Core `WidgetSnapshot`

**Files:**
- Create: `Packages/TimeTugCore/Sources/TimeTugCore/Widget/WidgetSnapshot.swift`
- Test: `Packages/TimeTugCore/Tests/TimeTugCoreTests/WidgetSnapshotTests.swift`

**Interfaces:**
- Produces:
  - `public struct WidgetEvent: Codable, Equatable, Sendable, Identifiable` with `id: String`, `title: String`, `start: Date`, `end: Date`, `isAllDay: Bool`, `colorHex: String?`, `joinURL: URL?`; memberwise `public init(id:title:start:end:isAllDay:colorHex:joinURL:)` (last two default to `nil`, `isAllDay` defaults to `false`). `start`/`end` are the times shown to the user (`CalendarEvent.shownStart` and `end`).
  - `public struct WidgetSnapshot: Codable, Equatable, Sendable` with `generatedAt: Date`, `events: [WidgetEvent]`, `public init(generatedAt:events:)`, `static let horizonDays = 3`, `static let maxAge: TimeInterval = 12 * 3600`, `func isStale(now: Date) -> Bool`, and
    `static func make(events: [CalendarEvent], calendars: [CalendarInfo], settings: TakeoverSettings, now: Date, calendar: Calendar) -> WidgetSnapshot`.

- [ ] **Step 1: Write the failing tests**

`WidgetSnapshotTests.swift`:
```swift
import Foundation
import Testing
@testable import TimeTugCore

private let now = date("2026-09-18T12:00:00Z")

private func make(_ events: [CalendarEvent], settings: TakeoverSettings = TakeoverSettings(),
                  calendars: [CalendarInfo] = []) -> WidgetSnapshot {
    WidgetSnapshot.make(events: events, calendars: calendars, settings: settings, now: now, calendar: utcCalendar)
}

@Test func snapshotSkipsAllDayEventsWhenSettingIsOn() {
    let allDay = makeEvent("a", start: "2026-09-18T00:00:00Z", minutes: 24 * 60, isAllDay: true)
    #expect(make([allDay]).events.isEmpty)
    var settings = TakeoverSettings()
    settings.skipAllDayEvents = false
    #expect(make([allDay], settings: settings).events.map(\.id) == [allDay.id])
}

@Test func snapshotHidesEventsOnHiddenCalendars() {
    var settings = TakeoverSettings()
    settings.setShownInList(false, forCalendar: "fake/cal")
    #expect(make([makeEvent()], settings: settings).events.isEmpty)
}

@Test func snapshotCoversTodayThroughTheHorizonOnly() {
    let earlierToday = makeEvent("early", start: "2026-09-18T08:00:00Z")
    let inHorizon = makeEvent("in", start: "2026-09-20T10:00:00Z")
    let beyond = makeEvent("out", start: "2026-09-21T10:00:00Z")
    let yesterday = makeEvent("old", start: "2026-09-17T10:00:00Z")
    let ids = make([beyond, inHorizon, yesterday, earlierToday]).events.map(\.id)
    #expect(ids == [earlierToday.id, inHorizon.id])
}

@Test func snapshotSortsByStartThenTitle() {
    let b = makeEvent("b", title: "B", start: "2026-09-18T15:00:00Z")
    let a = makeEvent("a", title: "A", start: "2026-09-18T15:00:00Z")
    let early = makeEvent("e", title: "Z", start: "2026-09-18T13:00:00Z")
    #expect(make([b, a, early]).events.map(\.title) == ["Z", "A", "B"])
}

@Test func snapshotCarriesColourJoinLinkAndShownTimes() {
    let link = URL(string: "https://meet.google.com/aaa-bbbb-ccc")!
    var event = makeEvent("m", start: "2026-09-18T14:00:00Z", conferenceURL: link)
    event.displayStart = date("2026-09-18T13:30:00Z")
    let calendars = [CalendarInfo(sourceID: "fake", calendarID: "cal", title: "Work", colorHex: "#ff0000")]
    let widgetEvent = make([event], calendars: calendars).events[0]
    #expect(widgetEvent.colorHex == "#FF0000")
    #expect(widgetEvent.joinURL == link)
    #expect(widgetEvent.start == date("2026-09-18T13:30:00Z"))
    #expect(widgetEvent.end == event.end)
}

@Test func snapshotRoundTripsThroughJSON() throws {
    let snapshot = make([makeEvent()])
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    #expect(try decoder.decode(WidgetSnapshot.self, from: encoder.encode(snapshot)) == snapshot)
}

@Test func snapshotIsStaleAfterMaxAge() {
    let snapshot = WidgetSnapshot(generatedAt: now, events: [])
    #expect(!snapshot.isStale(now: now.addingTimeInterval(WidgetSnapshot.maxAge)))
    #expect(snapshot.isStale(now: now.addingTimeInterval(WidgetSnapshot.maxAge + 1)))
}
```
Note: `makeEvent` has no `displayStart` parameter, hence the `var` mutation above.

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Packages/TimeTugCore 2>&1 | tail -10`
Expected: compile errors `cannot find 'WidgetSnapshot' in scope`.

- [ ] **Step 3: Implement**

`WidgetSnapshot.swift`:
```swift
import Foundation

/// One event as a widget needs it. Times are the ones shown to the user.
public struct WidgetEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let colorHex: String?
    public let joinURL: URL?

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false,
                colorHex: String? = nil, joinURL: URL? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.colorHex = colorHex
        self.joinURL = joinURL
    }
}

/// The agenda a front end hands to widgets: today plus the next days, already merged, filtered and sorted.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// Days of events included, counting today.
    public static let horizonDays = 3
    /// A snapshot older than this is treated as missing by widgets.
    public static let maxAge: TimeInterval = 12 * 3600

    public var generatedAt: Date
    public var events: [WidgetEvent]

    public init(generatedAt: Date, events: [WidgetEvent]) {
        self.generatedAt = generatedAt
        self.events = events
    }

    public func isStale(now: Date) -> Bool {
        now.timeIntervalSince(generatedAt) > Self.maxAge
    }

    public static func make(
        events: [CalendarEvent], calendars: [CalendarInfo], settings: TakeoverSettings,
        now: Date, calendar: Calendar
    ) -> WidgetSnapshot {
        let dayStart = calendar.startOfDay(for: now)
        let horizonEnd = calendar.date(byAdding: .day, value: horizonDays, to: dayStart)!
        let colors = Dictionary(calendars.compactMap { info in info.colorHex.map { (info.key, $0) } },
                                uniquingKeysWith: { first, _ in first })
        let included = events
            .filter { !$0.allCalendarKeys.isSubset(of: settings.hiddenCalendarKeys) }
            .filter { !(settings.skipAllDayEvents && $0.isAllDay) }
            .filter { $0.end > dayStart && $0.shownStart < horizonEnd }
            .sorted { ($0.shownStart, $0.title) < ($1.shownStart, $1.title) }
            .map { event in
                WidgetEvent(id: event.id, title: event.title, start: event.shownStart, end: event.end,
                            isAllDay: event.isAllDay, colorHex: colors[event.calendarKey], joinURL: event.conferenceURL)
            }
        return WidgetSnapshot(generatedAt: now, events: included)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --package-path Packages/TimeTugCore 2>&1 | tail -5`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/TimeTugCore
git commit -m "feat(core): WidgetSnapshot model and builder

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Core `WidgetTimeline`

**Files:**
- Create: `Packages/TimeTugCore/Sources/TimeTugCore/Widget/WidgetTimeline.swift`
- Test: `Packages/TimeTugCore/Tests/TimeTugCoreTests/WidgetTimelineTests.swift`

**Interfaces:**
- Consumes: `WidgetSnapshot`, `WidgetEvent`, `DayAgenda.State` (`.past/.current/.upcoming`).
- Produces (all `public`, in `enum WidgetTimeline`):
  - `static func changeDates(snapshot: WidgetSnapshot, now: Date, calendar: Calendar, limit: Int) -> [Date]`: sorted, unique instants after `now` at which widget content changes (start and end of every timed event, plus each following local midnight within the horizon), capped at `limit`.
  - `struct NextUp: Equatable, Sendable { current: WidgetEvent?; upcoming: [WidgetEvent] }` and `static func nextUp(snapshot: WidgetSnapshot, now: Date, upcomingLimit: Int) -> NextUp`: `current` is the timed event in progress with the earliest start (nil if none); `upcoming` are timed events with `start > now`, sorted, at most `upcomingLimit`. All-day events never appear.
  - `struct TodayRow: Equatable, Sendable, Identifiable { event: WidgetEvent; state: DayAgenda.State; id: String { event.id } }` and `static func today(snapshot: WidgetSnapshot, now: Date, calendar: Calendar) -> [TodayRow]`: events overlapping today's local day, in snapshot order, with state from `now`.

- [ ] **Step 1: Write the failing tests**

`WidgetTimelineTests.swift`:
```swift
import Foundation
import Testing
@testable import TimeTugCore

private let now = date("2026-09-18T12:00:00Z")

private func event(_ id: String, _ start: String, minutes: Int = 30, allDay: Bool = false) -> WidgetEvent {
    let s = date(start)
    return WidgetEvent(id: id, title: id, start: s, end: s.addingTimeInterval(TimeInterval(minutes * 60)), isAllDay: allDay)
}

private func snapshot(_ events: [WidgetEvent]) -> WidgetSnapshot { WidgetSnapshot(generatedAt: now, events: events) }

@Test func changeDatesIncludeFutureStartsEndsAndMidnights() {
    let s = snapshot([event("a", "2026-09-18T13:00:00Z"), event("b", "2026-09-18T11:00:00Z")])
    let dates = WidgetTimeline.changeDates(snapshot: s, now: now, calendar: utcCalendar, limit: 20)
    #expect(dates.first == date("2026-09-18T13:00:00Z"))
    #expect(dates.contains(date("2026-09-18T13:30:00Z")))
    #expect(dates.contains(date("2026-09-19T00:00:00Z")))
    #expect(!dates.contains(date("2026-09-18T11:00:00Z")))
    #expect(!dates.contains(date("2026-09-18T11:30:00Z")))
    #expect(dates == dates.sorted())
    #expect(Set(dates).count == dates.count)
}

@Test func changeDatesRespectLimit() {
    let s = snapshot([event("a", "2026-09-18T13:00:00Z"), event("b", "2026-09-18T14:00:00Z")])
    #expect(WidgetTimeline.changeDates(snapshot: s, now: now, calendar: utcCalendar, limit: 2).count == 2)
}

@Test func changeDatesForEmptySnapshotAreJustMidnights() {
    let dates = WidgetTimeline.changeDates(snapshot: snapshot([]), now: now, calendar: utcCalendar, limit: 10)
    #expect(dates == [date("2026-09-19T00:00:00Z"), date("2026-09-20T00:00:00Z")])
}

@Test func changeDatesIgnoreAllDayEventBoundariesButKeepMidnights() {
    let s = snapshot([event("d", "2026-09-18T00:00:00Z", minutes: 24 * 60, allDay: true)])
    let dates = WidgetTimeline.changeDates(snapshot: s, now: now, calendar: utcCalendar, limit: 10)
    #expect(dates == [date("2026-09-19T00:00:00Z"), date("2026-09-20T00:00:00Z")])
}

@Test func nextUpFindsCurrentAndUpcoming() {
    let s = snapshot([event("now", "2026-09-18T11:45:00Z"), event("n1", "2026-09-18T13:00:00Z"),
                      event("n2", "2026-09-18T14:00:00Z"), event("n3", "2026-09-19T09:00:00Z"),
                      event("past", "2026-09-18T09:00:00Z")])
    let result = WidgetTimeline.nextUp(snapshot: s, now: now, upcomingLimit: 2)
    #expect(result.current?.id == "now")
    #expect(result.upcoming.map(\.id) == ["n1", "n2"])
}

@Test func nextUpIgnoresAllDayEvents() {
    let s = snapshot([event("d", "2026-09-18T00:00:00Z", minutes: 24 * 60, allDay: true)])
    #expect(WidgetTimeline.nextUp(snapshot: s, now: now, upcomingLimit: 3) == .init(current: nil, upcoming: []))
}

@Test func nextUpPicksEarliestStartedWhenMeetingsOverlap() {
    let s = snapshot([event("late", "2026-09-18T11:50:00Z"), event("early", "2026-09-18T11:40:00Z")])
    #expect(WidgetTimeline.nextUp(snapshot: s, now: now, upcomingLimit: 3).current?.id == "early")
}

@Test func todayCoversOnlyTodayAndAssignsStates() {
    let s = snapshot([event("past", "2026-09-18T09:00:00Z"), event("cur", "2026-09-18T11:45:00Z"),
                      event("up", "2026-09-18T15:00:00Z"), event("tomorrow", "2026-09-19T09:00:00Z")])
    let rows = WidgetTimeline.today(snapshot: s, now: now, calendar: utcCalendar)
    #expect(rows.map(\.event.id) == ["past", "cur", "up"])
    #expect(rows.map(\.state) == [.past, .current, .upcoming])
}

@Test func todayKeepsAllDayEventsAsCurrent() {
    let s = snapshot([event("d", "2026-09-18T00:00:00Z", minutes: 24 * 60, allDay: true)])
    #expect(WidgetTimeline.today(snapshot: s, now: now, calendar: utcCalendar).map(\.state) == [.current])
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path Packages/TimeTugCore 2>&1 | tail -10`
Expected: `cannot find 'WidgetTimeline' in scope`.

- [ ] **Step 3: Implement**

`WidgetTimeline.swift`:
```swift
import Foundation

/// Pure functions that turn a `WidgetSnapshot` into what a widget shows at a given instant.
public enum WidgetTimeline {
    public struct NextUp: Equatable, Sendable {
        public let current: WidgetEvent?
        public let upcoming: [WidgetEvent]
        public init(current: WidgetEvent?, upcoming: [WidgetEvent]) {
            self.current = current
            self.upcoming = upcoming
        }
    }

    public struct TodayRow: Equatable, Sendable, Identifiable {
        public let event: WidgetEvent
        public let state: DayAgenda.State
        public var id: String { event.id }
    }

    public static func changeDates(snapshot: WidgetSnapshot, now: Date, calendar: Calendar, limit: Int) -> [Date] {
        var dates = Set<Date>()
        for event in snapshot.events where !event.isAllDay {
            if event.start > now { dates.insert(event.start) }
            if event.end > now { dates.insert(event.end) }
        }
        let dayStart = calendar.startOfDay(for: now)
        for offset in 1..<WidgetSnapshot.horizonDays {
            if let midnight = calendar.date(byAdding: .day, value: offset, to: dayStart), midnight > now {
                dates.insert(midnight)
            }
        }
        return Array(dates.sorted().prefix(limit))
    }

    public static func nextUp(snapshot: WidgetSnapshot, now: Date, upcomingLimit: Int) -> NextUp {
        let timed = snapshot.events.filter { !$0.isAllDay }
        let current = timed.filter { $0.start <= now && $0.end > now }.min { $0.start < $1.start }
        let upcoming = timed.filter { $0.start > now }.sorted { ($0.start, $0.title) < ($1.start, $1.title) }
        return NextUp(current: current, upcoming: Array(upcoming.prefix(upcomingLimit)))
    }

    public static func today(snapshot: WidgetSnapshot, now: Date, calendar: Calendar) -> [TodayRow] {
        let dayStart = calendar.startOfDay(for: now)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        return snapshot.events
            .filter { $0.end > dayStart && $0.start < nextDayStart }
            .map { event in
                let state: DayAgenda.State = event.end <= now ? .past : (event.start <= now ? .current : .upcoming)
                return TodayRow(event: event, state: state)
            }
    }
}
```
Note: `DayAgenda.Item`'s memberwise init is internal, so `TodayRow` is its own type; `TodayRow` needs an explicit public init only if used outside Core (the widget only reads it).

- [ ] **Step 4: Run to verify pass**

Run: `swift test --package-path Packages/TimeTugCore 2>&1 | tail -5`
Expected: all pass.

- [ ] **Step 5: DeepSeek review of the Core diff (text only)**

Scan the diff for secrets, then send `git diff master -- Packages/TimeTugCore` to `mcp__deepseek__chat_completion` (`deepseek-v4-flash`, `thinking: {type: "disabled"}`, `max_tokens: 1500`) asking for logic bugs, midnight/DST edge cases and untested branches in `WidgetSnapshot.make`, `changeDates`, `nextUp`, `today`. Verify every finding against the code; fix real ones with a failing test first; note false positives.

- [ ] **Step 6: Commit**

```bash
git add Packages/TimeTugCore
git commit -m "feat(core): WidgetTimeline change dates, next-up and today content

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: Shared settings, change signal and snapshot store

**Files:**
- Create: `Apps/macOS/Shared/SharedSettings.swift`, `Apps/macOS/Shared/SettingsChangeSignal.swift`, `Apps/macOS/Shared/WidgetSnapshotStore.swift`
- Test: `Apps/macOS/Tests/SharedInfraTests.swift`

**Interfaces:**
- Consumes: `AppGroup` (Task 1), `WidgetSnapshot` (Task 3).
- Produces:
  - `struct SharedSettings` with `enum Key: String { case skipAllDay, useIntelligence, disableTug, inferenceAvailable }`, `init(defaults: UserDefaults)`, `static let appGroup: SharedSettings` (suite `AppGroup.identifier`, falling back to `.standard` if the suite cannot be created), `func bool(_ key: Key) -> Bool?` (nil when unset), `func set(_ value: Bool, for key: Key)`.
  - `enum SettingsChangeSignal { static func post(); final class Observer { init(handler: @escaping () -> Void) } }`. The handler may run on any thread.
  - `struct WidgetSnapshotStore { init(directory: URL? = AppGroup.containerURL); func write(_ snapshot: WidgetSnapshot) throws; func read() -> WidgetSnapshot?; enum StoreError: Error { case noContainer } }`, file name `agenda-snapshot.json`, ISO-8601 dates, atomic write.

- [ ] **Step 1: Write the failing tests**

`SharedInfraTests.swift`:
```swift
import TimeTugCore
import XCTest
@testable import TimeTug

final class SharedInfraTests: XCTestCase {
    private func freshSettings() -> SharedSettings {
        let name = "TimeTugShared-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return SharedSettings(defaults: defaults)
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testUnsetKeyIsNil() { XCTAssertNil(freshSettings().bool(.disableTug)) }

    func testSetAndReadBoolIncludingFalse() {
        let settings = freshSettings()
        settings.set(false, for: .skipAllDay)
        settings.set(true, for: .disableTug)
        XCTAssertEqual(settings.bool(.skipAllDay), false)
        XCTAssertEqual(settings.bool(.disableTug), true)
    }

    func testSnapshotRoundTrip() throws {
        let store = WidgetSnapshotStore(directory: try tempDir())
        let event = WidgetEvent(id: "e", title: "Sync", start: Date(timeIntervalSince1970: 1_800_000_000),
                                end: Date(timeIntervalSince1970: 1_800_001_800), colorHex: "#FF0000",
                                joinURL: URL(string: "https://meet.google.com/a"))
        let snapshot = WidgetSnapshot(generatedAt: Date(timeIntervalSince1970: 1_799_999_000), events: [event])
        try store.write(snapshot)
        XCTAssertEqual(store.read(), snapshot)
    }

    func testMissingOrCorruptSnapshotReadsAsNil() throws {
        let dir = try tempDir()
        let store = WidgetSnapshotStore(directory: dir)
        XCTAssertNil(store.read())
        try Data("not json".utf8).write(to: dir.appendingPathComponent("agenda-snapshot.json"))
        XCTAssertNil(store.read())
    }

    func testWriteWithoutContainerThrows() {
        XCTAssertThrowsError(try WidgetSnapshotStore(directory: nil).write(WidgetSnapshot(generatedAt: .now, events: [])))
    }

    func testChangeSignalReachesObserver() {
        let received = expectation(description: "signal")
        received.assertForOverFulfill = false
        let observer = SettingsChangeSignal.Observer { received.fulfill() }
        SettingsChangeSignal.post()
        wait(for: [received], timeout: 2)
        withExtendedLifetime(observer) {}
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodegen generate --spec Apps/macOS/project.yml && xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test 2>&1 | grep -E "error:|Test Suite 'All|Executed" | head`
Expected: compile errors for the missing types.

- [ ] **Step 3: Implement**

`SharedSettings.swift`:
```swift
import Foundation

/// The booleans Control Center toggles and the app both edit, stored in the App Group suite.
struct SharedSettings {
    enum Key: String {
        case skipAllDay = "shared.skipAllDay"
        case useIntelligence = "shared.useIntelligence"
        case disableTug = "shared.disableTug"
        /// Written by the app: false when on-device intelligence cannot run on this Mac.
        case inferenceAvailable = "shared.inferenceAvailable"
    }

    static let appGroup = SharedSettings(defaults: UserDefaults(suiteName: AppGroup.identifier) ?? .standard)

    let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    /// nil when the key has never been written.
    func bool(_ key: Key) -> Bool? {
        defaults.object(forKey: key.rawValue) as? Bool
    }

    func set(_ value: Bool, for key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }
}
```
`SettingsChangeSignal.swift`:
```swift
import Foundation

/// Cross-process nudge: the extension posts it after writing `SharedSettings`; the app re-reads the values.
/// The notification carries no payload, so there is no write/read race.
enum SettingsChangeSignal {
    static let name = "com.timetug.settings-changed"

    static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }

    /// The handler may be called on any thread.
    final class Observer {
        private let handler: () -> Void

        init(handler: @escaping () -> Void) {
            self.handler = handler
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
                { _, observer, _, _, _ in
                    guard let observer else { return }
                    Unmanaged<Observer>.fromOpaque(observer).takeUnretainedValue().handler()
                },
                SettingsChangeSignal.name as CFString, nil, .deliverImmediately)
        }

        deinit {
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(), nil, nil)
        }
    }
}
```
`WidgetSnapshotStore.swift`:
```swift
import Foundation
import TimeTugCore

/// Reads and writes the agenda snapshot in the App Group container. The app writes; widgets read.
struct WidgetSnapshotStore {
    enum StoreError: Error { case noContainer }

    static let fileName = "agenda-snapshot.json"

    let directory: URL?

    init(directory: URL? = AppGroup.containerURL) { self.directory = directory }

    private var fileURL: URL? { directory?.appendingPathComponent(Self.fileName) }

    func write(_ snapshot: WidgetSnapshot) throws {
        guard let fileURL else { throw StoreError.noContainer }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    func read() -> WidgetSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
```
`Shared` files that import `TimeTugCore` require the widget target to link it; it already does (Task 1).

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test 2>&1 | grep -E "error:|Executed|TEST (SUCCEEDED|FAILED)"`
Expected: `TEST SUCCEEDED`, the six new tests pass.

- [ ] **Step 5: Commit**

```bash
git add Apps/macOS/Shared Apps/macOS/Tests/SharedInfraTests.swift
git commit -m "feat(app): shared settings, change signal and snapshot store

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: SettingsStore uses the shared suite

**Files:**
- Modify: `Apps/macOS/Sources/SettingsStore.swift`
- Test: `Apps/macOS/Tests/SettingsStoreTests.swift` (append)

**Interfaces:**
- Consumes: `SharedSettings` (Task 5), `TakeoverSettings.disabled` (Task 2).
- Produces: `SettingsStore.init(defaults: UserDefaults = .standard, shared: SharedSettings? = nil)` where `nil` means `SharedSettings(defaults: defaults)` (keeps existing tests isolated); `let shared: SharedSettings`; `func reloadFromShared()`. Production passes `SharedSettings.appGroup` (Task 8). Behavior: shared values win over the JSON/legacy values on init; init seeds the suite from the loaded values (one-time migration of `takeoverSettings.v1`.skipAllDayEvents and `dedupInference.v1`); every change to `takeover` or `inferenceEnabled` mirrors into the suite; `reloadFromShared()` applies suite values that differ.

- [ ] **Step 1: Write the failing tests**

Append inside `SettingsStoreTests` (uses its `freshDefaults()`):
```swift
    func testInitSeedsSharedSuiteFromLegacyValues() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "dedupInference.v1")
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.inferenceEnabled)
        XCTAssertEqual(store.shared.bool(.useIntelligence), true)
        XCTAssertEqual(store.shared.bool(.skipAllDay), true)
        XCTAssertEqual(store.shared.bool(.disableTug), false)
    }

    func testSharedValuesWinOverSavedValuesOnInit() {
        let defaults = freshDefaults()
        let shared = SharedSettings(defaults: defaults)
        shared.set(true, for: .disableTug)
        shared.set(false, for: .skipAllDay)
        shared.set(true, for: .useIntelligence)
        let store = SettingsStore(defaults: defaults, shared: shared)
        XCTAssertTrue(store.takeover.disabled)
        XCTAssertFalse(store.takeover.skipAllDayEvents)
        XCTAssertTrue(store.inferenceEnabled)
    }

    func testChangesMirrorIntoSharedSuite() {
        let store = SettingsStore(defaults: freshDefaults())
        store.takeover.disabled = true
        store.takeover.skipAllDayEvents = false
        store.inferenceEnabled = true
        XCTAssertEqual(store.shared.bool(.disableTug), true)
        XCTAssertEqual(store.shared.bool(.skipAllDay), false)
        XCTAssertEqual(store.shared.bool(.useIntelligence), true)
    }

    func testReloadFromSharedAppliesExternalChanges() {
        let store = SettingsStore(defaults: freshDefaults())
        store.shared.set(true, for: .disableTug)
        store.shared.set(false, for: .skipAllDay)
        store.shared.set(true, for: .useIntelligence)
        store.reloadFromShared()
        XCTAssertTrue(store.takeover.disabled)
        XCTAssertFalse(store.takeover.skipAllDayEvents)
        XCTAssertTrue(store.inferenceEnabled)
    }

    func testDisabledPersistsAcrossReload() {
        let defaults = freshDefaults()
        SettingsStore(defaults: defaults).takeover.disabled = true
        XCTAssertTrue(SettingsStore(defaults: defaults).takeover.disabled)
    }
```
Note: in tests the suite and the store's defaults are the same object, so persistence assertions cover both.

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test -only-testing:TimeTugTests/SettingsStoreTests 2>&1 | grep -E "error:|TEST"`
Expected: compile error (`shared`/`reloadFromShared` missing).

- [ ] **Step 3: Implement**

Replace the class body parts in `SettingsStore.swift`:
- Add `let shared: SharedSettings` after `private let defaults`.
- Change `takeover`'s observer to `didSet { save(); mirrorToShared() }` and `inferenceEnabled`'s to `didSet { defaults.set(inferenceEnabled, forKey: Self.inferenceKey); shared.set(inferenceEnabled, for: .useIntelligence) }`.
- Replace `init`'s start and the takeover / inference lines:
```swift
    init(defaults: UserDefaults = .standard, shared: SharedSettings? = nil) {
        self.defaults = defaults
        let shared = shared ?? SharedSettings(defaults: defaults)
        self.shared = shared
        var loaded = defaults.data(forKey: Self.takeoverKey)
            .flatMap { try? JSONDecoder().decode(TakeoverSettings.self, from: $0) } ?? TakeoverSettings()
        if let skip = shared.bool(.skipAllDay) { loaded.skipAllDayEvents = skip }
        if let disabled = shared.bool(.disableTug) { loaded.disabled = disabled }
        self.takeover = loaded
        // ... menuBarMode, appearanceMode, popupCardStyle lines unchanged ...
        self.inferenceEnabled = shared.bool(.useIntelligence) ?? defaults.bool(forKey: Self.inferenceKey)
        // One-time migration: seed the suite so widgets and controls see current values.
        mirrorToShared()
        shared.set(inferenceEnabled, for: .useIntelligence)
    }
```
(Keep the other three `self.` assignments exactly as they are; only the takeover and inference lines change.)
- Add methods:
```swift
    /// Applies values a Control Center toggle wrote to the shared suite while the app was running.
    func reloadFromShared() {
        if let skip = shared.bool(.skipAllDay), skip != takeover.skipAllDayEvents { takeover.skipAllDayEvents = skip }
        if let disabled = shared.bool(.disableTug), disabled != takeover.disabled { takeover.disabled = disabled }
        if let intelligence = shared.bool(.useIntelligence), intelligence != inferenceEnabled { inferenceEnabled = intelligence }
    }

    private func mirrorToShared() {
        shared.set(takeover.skipAllDayEvents, for: .skipAllDay)
        shared.set(takeover.disabled, for: .disableTug)
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test 2>&1 | grep -E "error:|Executed|TEST (SUCCEEDED|FAILED)"`
Expected: `TEST SUCCEEDED` (all existing SettingsStore tests still pass).

- [ ] **Step 5: Commit**

```bash
git add Apps/macOS/Sources/SettingsStore.swift Apps/macOS/Tests/SettingsStoreTests.swift
git commit -m "feat(app): SettingsStore mirrors skip-all-day, intelligence and disable-tug into the shared suite

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: Disable Tug in Settings

**Files:**
- Modify: `Apps/macOS/Sources/SettingsSearch.swift`, `Apps/macOS/Sources/TugRulesPane.swift`
- Test: `Apps/macOS/Tests/SettingsSearchTests.swift` (append)

**Interfaces:**
- Consumes: `TakeoverSettings.disabled` (Task 2).
- Produces: `SettingsText.disableTug`, search catalog id `"disable-tug"` on the Tug Rules pane.

- [ ] **Step 1: Write the failing test**

Append inside `SettingsSearchTests`:
```swift
    func testDisableTugIsSearchable() {
        XCTAssertEqual(ids("disable tug").first, "disable-tug")
        XCTAssertTrue(ids("pause").contains("disable-tug"))
        XCTAssertEqual(SettingsSearch.catalog.first { $0.id == "disable-tug" }?.pane, .tugRules)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test -only-testing:TimeTugTests/SettingsSearchTests 2>&1 | grep -E "error:|TEST|failed"`
Expected: test fails (no such item).

- [ ] **Step 3: Implement**

In `SettingsSearch.swift` add to `SettingsText`: `static let disableTug = "Disable Tug"`, and add as the first catalog entry:
```swift
        .init(id: "disable-tug", title: SettingsText.disableTug,
              keywords: ["pause", "off", "mute", "stop", "do not disturb", "focus", "takeover", "take over", "tug"], pane: .tugRules),
```
In `TugRulesPane.swift` add as the first child of the `Form`:
```swift
            VStack(alignment: .leading, spacing: 4) {
                Toggle(SettingsText.disableTug, isOn: $settings.takeover.disabled)
                    .settingsHighlight("disable-tug", navigation: navigation)
                Text("Pauses takeovers and pre-meeting popups. Your agenda and widgets keep working.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
```

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)"`
Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Apps/macOS/Sources/SettingsSearch.swift Apps/macOS/Sources/TugRulesPane.swift Apps/macOS/Tests/SettingsSearchTests.swift
git commit -m "feat(app): Disable Tug toggle in Settings

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: Coordinator wiring (snapshot, reload, signal, availability)

**Files:**
- Create: `Apps/macOS/Sources/InferenceAvailability.swift`
- Modify: `Apps/macOS/Sources/AppCoordinator.swift`
- Test: `Apps/macOS/Tests/InferenceAvailabilityTests.swift`

**Interfaces:**
- Consumes: `WidgetSnapshot.make`, `WidgetSnapshotStore`, `SettingsChangeSignal.Observer`, `SharedSettings`, `SettingsStore.shared/reloadFromShared` (Tasks 3, 5, 6).
- Produces: `extension InferenceStatus { var isAvailableOnThisMac: Bool }` (false for `.noEngine`, `.unavailable`, `.notOnDevice`; true for `.disabled` and `.active`, since a user-disabled feature says nothing about hardware).

- [ ] **Step 1: Write the failing test**

`InferenceAvailabilityTests.swift`:
```swift
import TimeTugCore
import XCTest
@testable import TimeTug

final class InferenceAvailabilityTests: XCTestCase {
    func testOnlyDefinitiveUnavailabilityIsFalse() {
        XCTAssertTrue(InferenceStatus.disabled.isAvailableOnThisMac)
        XCTAssertFalse(InferenceStatus.noEngine.isAvailableOnThisMac)
        XCTAssertFalse(InferenceStatus.unavailable(reason: "x").isAvailableOnThisMac)
        XCTAssertFalse(InferenceStatus.notOnDevice.isAvailableOnThisMac)
    }
}
```
(`.active` needs an `EngineInfo`; skip it here.)

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test -only-testing:TimeTugTests/InferenceAvailabilityTests 2>&1 | grep -E "error:|TEST"`
Expected: compile error, no `isAvailableOnThisMac`.

- [ ] **Step 3: Implement the helper**

`InferenceAvailability.swift`:
```swift
import TimeTugCore

extension InferenceStatus {
    /// False only when on-device intelligence definitively cannot run here. A user-disabled feature
    /// (`.disabled`) says nothing about the hardware, so it counts as available.
    var isAvailableOnThisMac: Bool {
        switch self {
        case .disabled, .active: true
        case .noEngine, .unavailable, .notOnDevice: false
        }
    }
}
```

- [ ] **Step 4: Wire the coordinator**

Edits to `AppCoordinator.swift` (add `import WidgetKit` and `import OSLog` if absent):
1. `let settings = SettingsStore(shared: .appGroup)`.
2. New properties:
```swift
    private let snapshotStore = WidgetSnapshotStore()
    private var lastWidgetEvents: [WidgetEvent]?
    private var widgetReloadTask: Task<Void, Never>?
    private var settingsSignal: SettingsChangeSignal.Observer?
    private static let widgetLog = Logger(subsystem: "com.timetug.app", category: "widgets")
```
3. Remove the SPIKE block from Task 1.
4. In `start()`, after the existing `settings.$menuBarMode` sink, add:
```swift
        settingsSignal = SettingsChangeSignal.Observer { [weak self] in
            DispatchQueue.main.async { self?.settings.reloadFromShared() }
        }
```
and change the existing `settings.$takeover` sink body to also call `self?.publishWidgetSnapshot()`:
```swift
        settings.$takeover.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.rearm(); self?.updateUI(); self?.publishWidgetSnapshot() }
        }.store(in: &cancellables)
```
5. At the end of `apply(_:)`, after `updateUI()`, add `publishWidgetSnapshot()`.
6. In `resolvePending()`, after each of the two `model.inferenceStatus = await store.inferenceStatus()` lines call `publishInferenceAvailability()`.
7. New methods:
```swift
    /// Writes the agenda snapshot for widgets; reloads their timelines only when the events changed.
    private func publishWidgetSnapshot() {
        let widgetSnapshot = WidgetSnapshot.make(
            events: snapshot.events, calendars: snapshot.calendars, settings: settings.takeover,
            now: Date(), calendar: .current)
        do {
            try snapshotStore.write(widgetSnapshot)
        } catch {
            Self.widgetLog.error("widget snapshot not written: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard widgetSnapshot.events != lastWidgetEvents else { return }
        lastWidgetEvents = widgetSnapshot.events
        widgetReloadTask?.cancel()
        widgetReloadTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func publishInferenceAvailability() {
        settings.shared.set(model.inferenceStatus.isAvailableOnThisMac, for: .inferenceAvailable)
    }
```

- [ ] **Step 5: Build and test**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)"`
Expected: `TEST SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add Apps/macOS
git commit -m "feat(app): publish widget snapshot, apply Control Center changes, expose intelligence availability

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 9: Next Up and Today widgets

**Files:**
- Modify: `Apps/macOS/Widgets/TimeTugWidgets.swift` (replace the spike)
- Create: `Apps/macOS/Widgets/AgendaProvider.swift`, `Apps/macOS/Widgets/WidgetSupport.swift`, `Apps/macOS/Widgets/NextUpWidget.swift`, `Apps/macOS/Widgets/TodayWidget.swift`

**Interfaces:**
- Consumes: `WidgetSnapshotStore`, `WidgetTimeline`, `WidgetSnapshot`, `WidgetEvent` (Tasks 3-5).
- Produces: `NextUpWidget`, `TodayWidget` (both `Widget`), `TimeTugWidgetBundle` (`@main`); Task 10 adds controls to the bundle.

Rendering is verified by build and by hand (WidgetKit views have no unit test seam here); the logic they call is fully tested in Core.

- [ ] **Step 1: Provider and entry**

`AgendaProvider.swift`:
```swift
import TimeTugCore
import WidgetKit

struct AgendaEntry: TimelineEntry {
    let date: Date
    /// nil when the app has not written a snapshot yet.
    let snapshot: WidgetSnapshot?
}

struct AgendaProvider: TimelineProvider {
    func placeholder(in context: Context) -> AgendaEntry {
        AgendaEntry(date: .now, snapshot: .sample(now: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (AgendaEntry) -> Void) {
        let stored = WidgetSnapshotStore().read()
        completion(AgendaEntry(date: .now, snapshot: context.isPreview && stored == nil ? .sample(now: .now) : stored))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AgendaEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshotStore().read()
        var dates = [now]
        if let snapshot {
            dates += WidgetTimeline.changeDates(snapshot: snapshot, now: now, calendar: .current, limit: 40)
        }
        let entries = dates.map { AgendaEntry(date: $0, snapshot: snapshot) }
        // The app reloads timelines when events change; this is the safety net if it is not running.
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
    }
}

extension WidgetSnapshot {
    /// Gallery and placeholder content.
    static func sample(now: Date) -> WidgetSnapshot {
        func event(_ title: String, _ offset: TimeInterval, _ minutes: Int) -> WidgetEvent {
            WidgetEvent(id: title, title: title, start: now.addingTimeInterval(offset),
                        end: now.addingTimeInterval(offset + Double(minutes) * 60), colorHex: "#4C8DF6")
        }
        return WidgetSnapshot(generatedAt: now, events: [
            event("Design review", 900, 30), event("1:1", 5400, 30), event("Planning", 10800, 60),
        ])
    }
}
```

- [ ] **Step 2: Support views**

`WidgetSupport.swift`:
```swift
import SwiftUI

extension Color {
    /// Accepts the "#RRGGBB" form Core normalizes to; falls back to the accent colour.
    init(hex: String?) {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) else {
            self = .accentColor
            return
        }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

struct OpenAppPlaceholder: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar.badge.clock").font(.title2)
            Text("Open TimeTug to load your meetings")
                .font(.caption).multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
    }
}
```

- [ ] **Step 3: Next Up widget**

`NextUpWidget.swift`:
```swift
import SwiftUI
import TimeTugCore
import WidgetKit

struct NextUpWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.timetug.widget.nextUp", provider: AgendaProvider()) { entry in
            NextUpView(entry: entry).containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Next Up")
        .description("Your current or next meeting, and what follows.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NextUpView: View {
    let entry: AgendaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.isStale(now: entry.date) {
            content(WidgetTimeline.nextUp(snapshot: snapshot, now: entry.date, upcomingLimit: 4))
        } else {
            OpenAppPlaceholder()
        }
    }

    @ViewBuilder
    private func content(_ result: WidgetTimeline.NextUp) -> some View {
        let hero = result.current ?? result.upcoming.first
        let rest = result.current == nil ? Array(result.upcoming.dropFirst()) : result.upcoming
        if let hero {
            HStack(alignment: .top, spacing: 12) {
                heroView(hero, isCurrent: result.current != nil)
                if family == .systemMedium, !rest.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(rest.prefix(3)) { row($0) }
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(hero.joinURL)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle").font(.title2)
                Text("No more meetings").font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }

    private func heroView(_ event: WidgetEvent, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isCurrent ? "NOW" : "NEXT UP").font(.caption2.weight(.semibold)).foregroundStyle(Color(hex: event.colorHex))
            Text(event.title).font(.headline).lineLimit(3)
            Spacer(minLength: 0)
            if isCurrent {
                Text("Ends \(Text(event.end, style: .time))").font(.caption)
            } else {
                Text(event.start, style: .relative).font(.title3.monospacedDigit())
                Text(event.start, style: .time).font(.caption).foregroundStyle(.secondary)
            }
            if event.joinURL != nil {
                Label("Join", systemImage: "video.fill").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ event: WidgetEvent) -> some View {
        let label = HStack(spacing: 6) {
            Capsule().fill(Color(hex: event.colorHex)).frame(width: 3, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title).font(.caption.weight(.medium)).lineLimit(1)
                Text(event.start, style: .time).font(.caption2).foregroundStyle(.secondary)
            }
        }
        return Group {
            if let url = event.joinURL { Link(destination: url) { label } } else { label }
        }
    }
}
```
Note: `Text(event.start, style: .relative)` renders e.g. "15 min"; the "NEXT UP" caption gives the "in" context.

- [ ] **Step 4: Today widget**

`TodayWidget.swift`:
```swift
import SwiftUI
import TimeTugCore
import WidgetKit

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.timetug.widget.today", provider: AgendaProvider()) { entry in
            TodayView(entry: entry).containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Today's meetings in order.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TodayView: View {
    let entry: AgendaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.isStale(now: entry.date) {
            content(WidgetTimeline.today(snapshot: snapshot, now: entry.date, calendar: .current))
        } else {
            OpenAppPlaceholder()
        }
    }

    @ViewBuilder
    private func content(_ rows: [WidgetTimeline.TodayRow]) -> some View {
        // Hide finished meetings first when space is short, so the rest of the day stays visible.
        let capacity = family == .systemLarge ? 8 : 3
        let visible = rows.count > capacity ? rows.filter { $0.state != .past } : rows
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.date, format: .dateTime.weekday(.wide).month().day())
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if visible.isEmpty {
                Spacer()
                Text("Nothing on today").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(visible.prefix(capacity)) { rowView($0) }
                if visible.count > capacity {
                    Text("+\(visible.count - capacity) more").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func rowView(_ row: WidgetTimeline.TodayRow) -> some View {
        let event = row.event
        let label = HStack(spacing: 8) {
            Capsule().fill(Color(hex: event.colorHex)).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title).font(.callout.weight(row.state == .current ? .semibold : .regular)).lineLimit(1)
                if event.isAllDay {
                    Text("All day").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("\(Text(event.start, style: .time)) – \(Text(event.end, style: .time))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if row.state == .current { Circle().fill(Color(hex: event.colorHex)).frame(width: 7, height: 7) }
        }
        .opacity(row.state == .past ? 0.45 : 1)
        return Group {
            if let url = event.joinURL, row.state != .past { Link(destination: url) { label } } else { label }
        }
    }
}
```

- [ ] **Step 5: Real bundle**

Replace `TimeTugWidgets.swift` entirely:
```swift
import SwiftUI
import WidgetKit

@main
struct TimeTugWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextUpWidget()
        TodayWidget()
    }
}
```

- [ ] **Step 6: Build**

Run:
```bash
xcodegen generate --spec Apps/macOS/project.yml
xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```
Expected: `** BUILD SUCCEEDED **`. Fix compile errors in place.

- [ ] **Step 7: Manual check (needs the user)**

Repeat the Task 1 Step 7 signed build. Ask the user to add Next Up (small, medium) and Today (medium, large) and confirm: real meetings show, colours match calendars, past meetings dim in Today, the countdown ticks, and a widget advances by itself when a meeting starts/ends. Fix anything that looks wrong.

- [ ] **Step 8: Commit**

```bash
git add Apps/macOS/Widgets
git commit -m "feat(widgets): Next Up and Today widgets

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 10: Control Center controls (macOS 26)

**Files:**
- Create: `Apps/macOS/Widgets/Controls.swift`
- Modify: `Apps/macOS/Widgets/TimeTugWidgets.swift`, `Apps/macOS/Sources/AppCoordinator.swift`

**Interfaces:**
- Consumes: `SharedSettings`, `SettingsChangeSignal` (Task 5); app-written `.inferenceAvailable` (Task 8).
- Produces: `SkipAllDayControl`, `UseIntelligenceControl`, `DisableTugControl` (kinds `com.timetug.control.skipAllDay` / `.useIntelligence` / `.disableTug`).

- [ ] **Step 1: Controls**

`Controls.swift`:
```swift
import AppIntents
import SwiftUI
import WidgetKit

// MARK: Intents (run in the extension process; the app is told through a Darwin notification)

@available(macOS 26.0, *)
struct SetSkipAllDayIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Skip All Day Events"
    @Parameter(title: "Skip All Day Events") var value: Bool

    func perform() async throws -> some IntentResult {
        SharedSettings.appGroup.set(value, for: .skipAllDay)
        SettingsChangeSignal.post()
        return .result()
    }
}

@available(macOS 26.0, *)
struct SetUseIntelligenceIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Use Intelligence"
    @Parameter(title: "Use Intelligence") var value: Bool

    func perform() async throws -> some IntentResult {
        SharedSettings.appGroup.set(value, for: .useIntelligence)
        SettingsChangeSignal.post()
        return .result()
    }
}

@available(macOS 26.0, *)
struct SetDisableTugIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Disable Tug"
    @Parameter(title: "Disable Tug") var value: Bool

    func perform() async throws -> some IntentResult {
        SharedSettings.appGroup.set(value, for: .disableTug)
        SettingsChangeSignal.post()
        return .result()
    }
}

// MARK: Value providers

@available(macOS 26.0, *)
struct BoolValueProvider: ControlValueProvider {
    let key: SharedSettings.Key
    let defaultValue: Bool

    var previewValue: Bool { defaultValue }
    func currentValue() async throws -> Bool { SharedSettings.appGroup.bool(key) ?? defaultValue }
}

@available(macOS 26.0, *)
struct IntelligenceState: Hashable {
    let isOn: Bool
    let isAvailable: Bool
}

@available(macOS 26.0, *)
struct IntelligenceValueProvider: ControlValueProvider {
    var previewValue: IntelligenceState { IntelligenceState(isOn: false, isAvailable: true) }
    func currentValue() async throws -> IntelligenceState {
        let settings = SharedSettings.appGroup
        return IntelligenceState(isOn: settings.bool(.useIntelligence) ?? false,
                                 isAvailable: settings.bool(.inferenceAvailable) ?? true)
    }
}

// MARK: Controls

@available(macOS 26.0, *)
struct SkipAllDayControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.timetug.control.skipAllDay", provider: BoolValueProvider(key: .skipAllDay, defaultValue: true)
        ) { isOn in
            ControlWidgetToggle("Skip All Day Events", isOn: isOn, action: SetSkipAllDayIntent()) { on in
                Label(on ? "On" : "Off", systemImage: "calendar.badge.minus")
            }
        }
        .displayName("Skip All Day Events")
        .description("Hide all-day events from TimeTug's list and widgets.")
    }
}

@available(macOS 26.0, *)
struct UseIntelligenceControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.timetug.control.useIntelligence", provider: IntelligenceValueProvider()) { state in
            ControlWidgetToggle("Use Intelligence", isOn: state.isOn, action: SetUseIntelligenceIntent()) { on in
                Label(state.isAvailable ? (on ? "On" : "Off") : "Unavailable", systemImage: "sparkles")
            }
            .disabled(!state.isAvailable)
        }
        .displayName("Use Intelligence")
        .description("Find duplicate meetings with on-device Apple Intelligence.")
    }
}

@available(macOS 26.0, *)
struct DisableTugControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.timetug.control.disableTug", provider: BoolValueProvider(key: .disableTug, defaultValue: false)
        ) { isOn in
            ControlWidgetToggle("Disable Tug", isOn: isOn, action: SetDisableTugIntent()) { on in
                Label(on ? "Tug off" : "Tug on", systemImage: on ? "bell.slash.fill" : "bell.fill")
            }
        }
        .displayName("Disable Tug")
        .description("Pause takeovers and pre-meeting popups.")
    }
}
```

- [ ] **Step 2: Add them to the bundle**

Replace the body of `TimeTugWidgetBundle` in `TimeTugWidgets.swift`:
```swift
    var body: some Widget {
        NextUpWidget()
        TodayWidget()
        if #available(macOS 26.0, *) {
            SkipAllDayControl()
            UseIntelligenceControl()
            DisableTugControl()
        }
    }
```
If the compiler rejects `if #available` in `WidgetBundle`, split into `TimeTugWidgetBundle` (`@main`, widgets only, 14.0) plus a second `@available(macOS 26.0, *) struct TimeTugControlsBundle: WidgetBundle` and have the `@main` bundle's body use `@WidgetBundleBuilder` with `buildLimitedAvailability`; verify against the SDK swiftinterface before choosing.

- [ ] **Step 3: Keep controls in sync when Settings changes them**

In `AppCoordinator.publishWidgetSnapshot()`, immediately before the `guard widgetSnapshot.events != lastWidgetEvents` line, add:
```swift
        if #available(macOS 26.0, *) { ControlCenter.shared.reloadAllControls() }
```
and in `publishInferenceAvailability()` append the same line. Add `import WidgetKit` if not already present (already added in Task 8).

- [ ] **Step 4: Build**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"`
Expected: `** BUILD SUCCEEDED **`. (Controls compile against the macOS 26+ SDK, present locally and on the `macos-26` runner.)

- [ ] **Step 5: Manual check (needs the user, macOS 26)**

Signed build as in Task 1 Step 7. In Control Center (or menu bar Controls) add the three TimeTug controls. Confirm: flipping Disable Tug on stops a test takeover (Settings > Tug Rules > Test tug still works because it bypasses the policy; use a real upcoming meeting) and the Settings toggle flips live; flipping Skip All Day hides/shows an all-day event in the popover within a second or two; Use Intelligence flips the Calendars pane toggle, and shows Unavailable and disabled on a Mac without on-device intelligence; changing a setting in the app updates the control's state.

- [ ] **Step 6: Commit**

```bash
git add Apps/macOS
git commit -m "feat(widgets): Control Center toggles for skip all-day, intelligence and disable tug

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 11: Release scripts, docs, ADR and final review

**Files:**
- Modify: `scripts/ci/build-release.sh`, `scripts/release/sign-and-notarize.sh`, `scripts/release/verify-dmg.sh`, `AGENTS.md`, `docs/architecture.md`, `README.md`, `docs/manual-tests/macos-checklist.md`, `docs/PROGRESS.md`, `docs/superpowers/specs/2026-09-19-widgets-and-controls-design.md`
- Create: `docs/decisions/0010-widgets-app-group-and-snapshot.md`

- [ ] **Step 1: Stamp and re-sign the extension in `build-release.sh`**

Read the file around lines 55-78. The stamp block edits the app's `Info.plist` and re-signs the app ad hoc. Extend it so the appex is stamped with the same version/build and re-signed before the app:
```bash
APPEX="$APP/Contents/PlugIns/TimeTugWidgets.appex"
[ -d "$APPEX" ] || { echo "error: widget extension missing at $APPEX" >&2; exit 1; }
```
placed before the stamping block; inside the existing `if [ "$current" != "$VERSION" ]` / build-number branches also `Set` the same keys on `$APPEX/Contents/Info.plist`; and in the `if [ "$changed" = 1 ]` block sign the appex first:
```bash
  codesign --force --sign - --options runtime \
    --entitlements Apps/macOS/Widgets/TimeTugWidgets.entitlements "$APPEX"
```
before the existing app `codesign`. Finish with `codesign --verify --strict --deep "$APP"` in place of the current `--strict` verify.

- [ ] **Step 2: Sign the extension in `sign-and-notarize.sh`**

In the `app` mode branch (step "2. Re-sign"), before the app `codesign` command add:
```bash
  APPEX="$APP_PATH/Contents/PlugIns/TimeTugWidgets.appex"
  [ -d "$APPEX" ] || { echo "error: widget extension missing at $APPEX" >&2; exit 1; }
  codesign --force --sign "$IDENTITY" --keychain "$KEYCHAIN" --options runtime --timestamp \
    --entitlements Apps/macOS/Widgets/TimeTugWidgets.entitlements "$APPEX"
```
(inside-out: the appex is signed before the app that contains it), and change the verify to `codesign --verify --strict --deep --verbose=2 "$APP_PATH"`.

- [ ] **Step 3: Check the appex in the DMG**

In `verify-dmg.sh` after the `TimeTug.app/Contents/MacOS/TimeTug is executable` check add:
```bash
check "TimeTugWidgets.appex is embedded" test -d "$mnt/TimeTug.app/Contents/PlugIns/TimeTugWidgets.appex"
```

- [ ] **Step 4: Validate scripts**

Run: `bash -n scripts/ci/build-release.sh scripts/release/sign-and-notarize.sh scripts/release/verify-dmg.sh && shellcheck scripts/ci/build-release.sh scripts/release/*.sh 2>&1 | tail -5`
Then `scripts/ci/build-release.sh` locally if it works without secrets (see `docs/release.md`), and `scripts/release/verify-dmg.sh` against a local unsigned DMG per `docs/release.md`. Expected: build succeeds with the appex present and `codesign --verify --deep` passes.

- [ ] **Step 5: ADR 0010**

`docs/decisions/0010-widgets-app-group-and-snapshot.md`, in the format of ADR 0009 (Status accepted 2026-09-19; Context, Decision, Consequences). Decision bullets: widgets are a sandboxed WidgetKit extension that reads an app-written `agenda-snapshot.json` in App Group `YYA6ZKMD36.com.timetug.shared` (not EventKit, so dedup/Intelligence/all-day settings match the popover and there is one permission prompt); three booleans in the shared suite, extension intents write them and post a Darwin notification, the app re-reads (no payload, no race); Core owns `WidgetSnapshot`/`WidgetTimeline`; `TakeoverSettings.disabled` is enforced in `TakeoverPolicy.qualifies`; controls are macOS 26 only behind `#available`; reloads are diffed and debounced. Consequences: widgets need a team-signed build (ad-hoc builds skip the snapshot and show the placeholder), the extension must be signed inside-out in release, the snapshot goes stale if the app is not running (12 h limit, hourly timeline safety reload), and no widget tap-to-open-popup.

- [ ] **Step 6: Update the other docs**

- `AGENTS.md`: add `Apps/macOS/Widgets` and `Apps/macOS/Shared` to Layout; add gotchas: widgets need a team-signed build (`CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=YYA6ZKMD36 CODE_SIGN_IDENTITY="Developer ID Application: ..."`, see `docs/manual-tests`), the group container path `~/Library/Group Containers/YYA6ZKMD36.com.timetug.shared/`, and that Disable Tug is enforced in Core.
- `docs/architecture.md`: modules list gains WidgetSnapshot/WidgetTimeline and the widget extension; Flow gains "app -> WidgetSnapshot -> group container -> widget timelines".
- `README.md`: features list gains widgets and Control Center controls (macOS 26) and Disable Tug.
- `docs/manual-tests/macos-checklist.md`: new section "Widgets and controls (needs a team-signed build)" with checkboxes: add each widget and size; real meetings and calendar colours; rolling advance at start/end without reloading; past dimming in Today; placeholder when the snapshot file is deleted; Join link opens; each of the three controls flips the matching Settings toggle and behaves as in Task 10 Step 5; toggling in Settings updates the control; ad-hoc build runs normally with no widgets loading.
- `docs/PROGRESS.md`: add a "Widgets and controls" section with this plan's tasks and status, the branch, and how to resume.
- Spec: append a "Changes during planning" list with the three deviations at the top of this plan.

- [ ] **Step 7: Full verification**

Run:
```bash
swift test --package-path Packages/TimeTugCore 2>&1 | tail -3
swift test --package-path Packages/AppleIntelligenceInference 2>&1 | tail -3
swift build --package-path Packages/EventKitSource 2>&1 | tail -2
xcodegen generate --spec Apps/macOS/project.yml
xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)"
```
Expected: all pass.

- [ ] **Step 8: DeepSeek final review**

Scan for secrets, then send `git diff master -- Apps/macOS/Shared Apps/macOS/Widgets Apps/macOS/Sources scripts` (text only, `deepseek-v4-pro`, thinking disabled, `max_tokens: 1500`) asking for concurrency, cross-process, and signing-script bugs. Verify each Critical/Important finding by hand; report false positives.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: release signing for the widget extension, ADR 0010 and docs for widgets and controls

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```
