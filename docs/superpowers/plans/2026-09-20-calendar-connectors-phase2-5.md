# Calendar connectors Phase 2.5 (minimal bridge) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `TimeTugCore` uses the connector library's native event (wrapped with `sourceID` and merge state) and zone-aware all-day dates, `CalendarConnectors` has no external dependencies, and `CalendarBridge` shrinks to wrapping, cancelled-filtering and change/error translation.

**Architecture:** OAuth code moves to a new `CalendarOAuth` product with a `SHA256Hashing` seam (pure-Swift default, CryptoKit in `CalendarApple`), which removes swift-crypto. `TimeTugCalendarEvent` becomes `{ event: CalendarEvent, sourceID, merge/display state }` with forwarding accessors; Core deletes its own `Attendee`/`ResponseStatus`. All-day events belong to a local day by calendar date (`AllDay.dates` in the event's own zone).

**Tech Stack:** Swift 6 (packages; app and `EventKitSource`/`CalendarApple` in Swift 5 mode), Swift Testing (packages), XCTest (app), XcodeGen.

Spec: `docs/superpowers/specs/2026-09-20-calendar-connectors-phase2-5-design.md`. Read it and `AGENTS.md` first.

## Global Constraints

- `TimeTugCore` stays pure Swift 6 with no Apple-only imports; it may depend only on `CalendarCore` (which has no dependencies) and must keep building on `swift:6.0` Linux.
- The `CalendarConnectors` package has no external dependencies after Task 2 (tools version 6.0); library code imports nothing from TimeTug.
- All-day events belong to a day by calendar date, read in the event's own zone; never adjust to the viewer's zone.
- Time is always passed in (`now: Date`, `calendar: Calendar`); Core never calls `Date()`.
- Persisted formats do not change: takeover ledger, lesson and verdict keys of timed events, settings keys, widget snapshot schema.
- New behaviour gets a failing Swift Testing test first (XCTest in `Apps/macOS/Tests`). Core has no display strings.
- `TimeTugCore` and `CalendarCore` both define `CalendarSource` and `SourceError`: inside `TimeTugCore` the local declaration shadows the import; in other modules qualify (`CalendarCore.SourceError`).
- `xcodegen generate` rewrites `Apps/macOS/Sources/Info.plist` and `Apps/macOS/Widgets/Info.plist`: run `git checkout -- Apps/macOS/Sources/Info.plist Apps/macOS/Widgets/Info.plist` before committing; never commit them.
- Never run `pkill -x TimeTug` (it kills the user's own instance). The four `Package.resolved` files are tracked: regenerate them by building, do not hand-edit.
- Every commit message ends with `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`. Work only on branch `claude/calendar-phase2-5-slim-bridge`; land through a PR into `master` (never merge locally).
- Use the project index (`Q search "..."`, see `~/.claude/skills/index/SKILL.md`) for discovery before broad grepping; `Connection.swift`, `EventKitConnectorKind.swift` and a few docs are not indexed (secret-like names), so read those directly.

---

## Task 1: Move OAuth into a `CalendarOAuth` product

**Files:**
- Modify: `Packages/CalendarConnectors/Package.swift`
- Move (`git mv`): `Sources/CalendarCore/{OAuth,AccessTokenProvider,PKCE}.swift` to `Sources/CalendarOAuth/`; `Tests/CalendarCoreTests/{OAuthTests,PKCETests,AccessTokenProviderTests}.swift` to `Tests/CalendarOAuthTests/`
- Modify: `Sources/GoogleCalendar/{GoogleConnectorKind,GoogleAPIClient}.swift`, `Tests/GoogleCalendarTests/{SourceTests,ConnectorKindTests}.swift` (imports only)

**Interfaces:**
- Produces: product/target `CalendarOAuth` (depends on `CalendarCore`; still uses swift-crypto until Task 2) exposing the unchanged `OAuthConfig`, `OAuthTokens`, `OAuthClient`, `AuthorizationError`, `AccessTokenProvider`, `PKCE`.

- [ ] **Step 1: Baseline.** Run `swift test --package-path Packages/CalendarConnectors`. Expected: PASS (record the test count).
- [ ] **Step 2: Move files.**

```bash
cd Packages/CalendarConnectors
mkdir -p Sources/CalendarOAuth Tests/CalendarOAuthTests
git mv Sources/CalendarCore/OAuth.swift Sources/CalendarCore/AccessTokenProvider.swift Sources/CalendarCore/PKCE.swift Sources/CalendarOAuth/
git mv Tests/CalendarCoreTests/OAuthTests.swift Tests/CalendarCoreTests/PKCETests.swift Tests/CalendarCoreTests/AccessTokenProviderTests.swift Tests/CalendarOAuthTests/
```

- [ ] **Step 3: Manifest.** Replace the products, targets and test targets of `Packages/CalendarConnectors/Package.swift` with:

```swift
    products: [
        .library(name: "CalendarCore", targets: ["CalendarCore"]),
        .library(name: "CalendarOAuth", targets: ["CalendarOAuth"]),
        .library(name: "GoogleCalendar", targets: ["GoogleCalendar"]),
        .library(name: "CalendarTestSupport", targets: ["CalendarTestSupport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "5.0.0"),
    ],
    targets: [
        .target(name: "CalendarCore"),
        .target(name: "CalendarOAuth", dependencies: ["CalendarCore", .product(name: "Crypto", package: "swift-crypto")]),
        .target(name: "GoogleCalendar", dependencies: ["CalendarCore", "CalendarOAuth"]),
        .target(name: "CalendarTestSupport", dependencies: ["CalendarCore"]),
        .testTarget(name: "CalendarCoreTests", dependencies: ["CalendarCore", "CalendarTestSupport"]),
        .testTarget(name: "CalendarOAuthTests", dependencies: ["CalendarOAuth", "CalendarCore", "CalendarTestSupport"]),
        .testTarget(name: "GoogleCalendarTests", dependencies: ["GoogleCalendar", "CalendarOAuth", "CalendarCore", "CalendarTestSupport"]),
    ]
```

- [ ] **Step 4: Imports.** Add `import CalendarCore` at the top of the three moved sources (they use `SourceError`, `HTTPRequest`, `HTTPTransport`, `ConnectionID`, `CredentialStore`) and `@testable import CalendarOAuth` plus `import CalendarCore` (and `import CalendarTestSupport` where the test used it) to the three moved tests, replacing `@testable import CalendarCore` there. Add `import CalendarOAuth` to `GoogleConnectorKind.swift`, `GoogleAPIClient.swift`, `SourceTests.swift` and `ConnectorKindTests.swift`.
- [ ] **Step 5: Verify.** Run `swift test --package-path Packages/CalendarConnectors`. Expected: PASS with the same test count as Step 1. If a file needs an `internal` symbol from `CalendarCore` (compiler error "is internal"), make that symbol `public` only if it is part of the documented library API; otherwise move the test back.
- [ ] **Step 6: Commit.**

```bash
git add -A Packages/CalendarConnectors
git commit -m "refactor(connectors): move OAuth, token provider and PKCE into a CalendarOAuth product

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 2: `SHA256Hashing` with a pure-Swift default; remove swift-crypto

**Files:**
- Create: `Packages/CalendarConnectors/Sources/CalendarOAuth/SHA256Hashing.swift`
- Create: `Packages/CalendarConnectors/Tests/CalendarOAuthTests/SHA256Tests.swift`
- Modify: `Sources/CalendarOAuth/PKCE.swift`, `Sources/GoogleCalendar/GoogleConnectorKind.swift`, `Package.swift`
- Modify (regenerated): the four tracked `Packages/*/Package.resolved` files

**Interfaces:**
- Produces: `public protocol SHA256Hashing: Sendable { func sha256(_ data: Data) -> Data }`; `public struct PureSwiftSHA256: SHA256Hashing { public init() }`; `PKCE.challenge(for verifier: String, hasher: any SHA256Hashing = PureSwiftSHA256()) -> String`; `GoogleConnectorKind.init(config:transport:now:sleep:pollInterval:hasher:)` with `hasher: any SHA256Hashing = PureSwiftSHA256()` as the last parameter.

- [ ] **Step 1: Write the failing tests** (`SHA256Tests.swift`):

```swift
import Foundation
import Testing
@testable import CalendarOAuth

private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

@Test func sha256EmptyInput() {
    #expect(hex(PureSwiftSHA256().sha256(Data())) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
}

@Test func sha256Abc() {
    #expect(hex(PureSwiftSHA256().sha256(Data("abc".utf8))) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

@Test func sha256TwoBlockMessage() {
    let message = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
    #expect(hex(PureSwiftSHA256().sha256(Data(message.utf8))) == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
}

@Test func sha256MillionAs() {
    let data = Data(repeating: UInt8(ascii: "a"), count: 1_000_000)
    #expect(hex(PureSwiftSHA256().sha256(data)) == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
}

@Test func sha256PaddingBoundaries() {
    // 55, 56 and 64 bytes straddle the single-block padding limits.
    #expect(hex(PureSwiftSHA256().sha256(Data(repeating: 0x61, count: 55))) == "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318")
    #expect(hex(PureSwiftSHA256().sha256(Data(repeating: 0x61, count: 56))) == "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a")
    #expect(hex(PureSwiftSHA256().sha256(Data(repeating: 0x61, count: 64))) == "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb")
}

private struct FixedHasher: SHA256Hashing {
    func sha256(_ data: Data) -> Data { Data(repeating: 0xff, count: 32) }
}

@Test func pkceUsesTheInjectedHasher() {
    // 32 bytes of 0xff in base64url without padding.
    #expect(PKCE.challenge(for: "anything", hasher: FixedHasher()) == "__________________________________________8")
}

@Test func pkceDefaultMatchesRFC7636Vector() {
    #expect(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
}
```

The 55/56/64-byte digests above are standard published values; if a digest disagrees, verify it with `printf 'a%.0s' {1..55} | shasum -a 256` (and 56, 64) and correct the test constant, not the implementation.

- [ ] **Step 2: Run to verify failure.** `swift test --package-path Packages/CalendarConnectors --filter CalendarOAuthTests`. Expected: FAIL to compile ("cannot find 'PureSwiftSHA256'").
- [ ] **Step 3: Implement** `SHA256Hashing.swift`:

```swift
import Foundation

/// SHA-256 for PKCE's S256 challenge. The library ships `PureSwiftSHA256` so it needs no dependency; a host may
/// inject its own (CryptoKit on Apple platforms, swift-crypto elsewhere) through `GoogleConnectorKind.init`.
public protocol SHA256Hashing: Sendable {
    func sha256(_ data: Data) -> Data
}

/// A straightforward FIPS 180-4 SHA-256, checked against the NIST vectors. Only ever used on a public PKCE verifier.
public struct PureSwiftSHA256: SHA256Hashing {
    public init() {}

    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }

    public func sha256(_ data: Data) -> Data {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var message = [UInt8](data)
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) { message.append(UInt8((bitLength >> UInt64(shift)) & 0xff)) }

        var w = [UInt32](repeating: 0, count: 64)
        for chunk in stride(from: 0, to: message.count, by: 64) {
            for i in 0..<16 {
                let j = chunk + i * 4
                w[i] = UInt32(message[j]) << 24 | UInt32(message[j + 1]) << 16 | UInt32(message[j + 2]) << 8 | UInt32(message[j + 3])
            }
            for i in 16..<64 {
                let s0 = Self.rotr(w[i - 15], 7) ^ Self.rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = Self.rotr(w[i - 2], 17) ^ Self.rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let bigS1 = Self.rotr(e, 6) ^ Self.rotr(e, 11) ^ Self.rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ bigS1 &+ ch &+ Self.k[i] &+ w[i]
                let bigS0 = Self.rotr(a, 2) ^ Self.rotr(a, 13) ^ Self.rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = bigS0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }
        var out = Data()
        for word in h { for shift in stride(from: 24, through: 0, by: -8) { out.append(UInt8((word >> UInt32(shift)) & 0xff)) } }
        return out
    }
}
```

- [ ] **Step 4: Wire PKCE.** In `PKCE.swift` delete `import Crypto` and replace `challenge`:

```swift
    /// base64url(SHA-256(verifier)) without padding (RFC 7636, method S256).
    public static func challenge(for verifier: String, hasher: any SHA256Hashing = PureSwiftSHA256()) -> String {
        hasher.sha256(Data(verifier.utf8)).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
```

- [ ] **Step 5: Wire Google.** In `GoogleConnectorKind`: add `private let hasher: any SHA256Hashing`; add the last init parameter `hasher: any SHA256Hashing = PureSwiftSHA256()` and `self.hasher = hasher`; in `signIn` change the challenge to `PKCE.challenge(for: verifier, hasher: hasher)`.
- [ ] **Step 6: Remove swift-crypto.** In `Package.swift` delete the `dependencies:` array entry and the `Crypto` product dependency (the `CalendarOAuth` target becomes `dependencies: ["CalendarCore"]`). Then regenerate resolutions: `swift package --package-path Packages/CalendarConnectors resolve`, then `swift build --package-path Packages/CalendarBridge`, `Packages/CalendarApple`, `Packages/EventKitSource` (each updates its `Package.resolved`). Verify: `grep -l swift-crypto Packages/*/Package.resolved` prints nothing (if a file still lists it, delete that pin entry by regenerating with `swift package --package-path <pkg> resolve`).
- [ ] **Step 7: Verify.** `swift test --package-path Packages/CalendarConnectors`. Expected: PASS.
- [ ] **Step 8: Commit** (`git add -A Packages`; message: `feat(connectors): pure-Swift SHA-256 behind SHA256Hashing; drop swift-crypto`).

---

## Task 3: CryptoKit hasher in `CalendarApple`, injected by the app

**Files:**
- Create: `Packages/CalendarApple/Sources/CalendarApple/CryptoKitSHA256.swift`
- Create: `Packages/CalendarApple/Tests/CalendarAppleTests/CryptoKitSHA256Tests.swift`
- Modify: `Packages/CalendarApple/Package.swift`, `Apps/macOS/Sources/AppConnectors.swift`, `Apps/macOS/project.yml` (only if the app target must list the `CalendarOAuth` product)

**Interfaces:**
- Consumes: `SHA256Hashing` (Task 2).
- Produces: `public struct CryptoKitSHA256: SHA256Hashing { public init() }`.

- [ ] **Step 1: Failing test:**

```swift
import CalendarOAuth
import Foundation
import Testing
@testable import CalendarApple

@Test func cryptoKitHasherMatchesTheReferenceVectors() {
    let hasher = CryptoKitSHA256()
    #expect(hasher.sha256(Data("abc".utf8)).map { String(format: "%02x", $0) }.joined()
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    #expect(hasher.sha256(Data()) == PureSwiftSHA256().sha256(Data()))
}
```

- [ ] **Step 2: Manifest.** In `Packages/CalendarApple/Package.swift` add `.product(name: "CalendarOAuth", package: "CalendarConnectors")` to both the `CalendarApple` target and the test target dependencies.
- [ ] **Step 3: Run** `swift test --package-path Packages/CalendarApple --filter CryptoKitSHA256`. Expected: FAIL (cannot find `CryptoKitSHA256`).
- [ ] **Step 4: Implement:**

```swift
import CalendarOAuth
import CryptoKit
import Foundation

/// CryptoKit-backed SHA-256 for hosts on Apple platforms; inject it in place of the library's pure-Swift default.
public struct CryptoKitSHA256: SHA256Hashing {
    public init() {}
    public func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }
}
```

- [ ] **Step 5: App injection.** In `AppConnectors.swift` line 9 change the registration to `GoogleConnectorKind(config: google, hasher: CryptoKitSHA256())` and add `import CalendarApple` if it is not already imported there. If the app target fails to resolve `CalendarOAuth` types, add `- package: CalendarConnectors` / `product: CalendarOAuth` under the `TimeTug` target's dependencies in `project.yml` (mirror the existing `CalendarCore` and `GoogleCalendar` entries), then `xcodegen generate --spec Apps/macOS/project.yml` and restore the two Info.plists.
- [ ] **Step 6: Verify.** `swift test --package-path Packages/CalendarApple` PASS; the app build is verified in Task 7.
- [ ] **Step 7: Commit** (`feat(apple): CryptoKit SHA-256 hasher, injected for Google sign-in`).

---

## Task 4: `CalendarDate` ordering, the wrapper event and Core on the library's value types

**Files:**
- Modify: `Packages/CalendarConnectors/Sources/CalendarCore/AllDay.swift` (`CalendarDate: Comparable`), `Tests/CalendarCoreTests/AllDayTests.swift`
- Modify: `Packages/TimeTugCore/Package.swift`
- Rewrite: `Packages/TimeTugCore/Sources/TimeTugCore/Model/TimeTugCalendarEvent.swift`
- Modify: `Model/MergeTypes.swift` (delete `Attendee`), `Model/CalendarInfo.swift` (delete `ResponseStatus`), `Takeover/TakeoverPolicy.swift`, `Dedup/DuplicateRules.swift`, `Dedup/DuplicateResolver.swift`
- Test: create `Tests/TimeTugCoreTests/TimeTugCalendarEventTests.swift`; modify `Tests/TimeTugCoreTests/Support.swift` and the other Core tests that use `Attendee`, `.pending`, `.unknown` (`DuplicateRulesTests`, `ModelTests`, `AdjudicationTests`, `DuplicateResolverTests`)

**Interfaces:**
- Produces (used by Tasks 5-7):

```swift
public struct TimeTugCalendarEvent: Identifiable, Hashable, Sendable {
    public var event: CalendarCore.CalendarEvent
    public var sourceID: String
    public var conferenceURL: URL?
    public var otherAttendeeCount: Int
    public var responseStatus: CalendarCore.ResponseStatus?
    public var additionalCalendarKeys: Set<String>
    public var mergedMembers: [MergedMember]
    public var mergeProvenance: MergeProvenance?
    public var displayStart: Date?
    public init(event: CalendarCore.CalendarEvent, sourceID: String)
    // forwarding get/set: title, start, end, isAllDay, timeZone, location, notes, url, calendarID
    // computed get: sourceEventID, externalUID, attendees ([CalendarCore.Attendee], non-self), organizerEmail, shownStart, id, contentKey, calendarKey, allCalendarKeys, allContentKeys
    // isSameMeeting(as:)
}
extension CalendarDate: Comparable  // in CalendarCore
```

- [ ] **Step 1: Library ordering, test first** (append to `AllDayTests.swift`):

```swift
@Test func calendarDatesOrderChronologically() {
    #expect(CalendarDate(year: 2026, month: 9, day: 20) < CalendarDate(year: 2026, month: 9, day: 21))
    #expect(CalendarDate(year: 2026, month: 12, day: 31) < CalendarDate(year: 2027, month: 1, day: 1))
    #expect(!(CalendarDate(year: 2026, month: 9, day: 21) < CalendarDate(year: 2026, month: 9, day: 21)))
}
```

Run `swift test --package-path Packages/CalendarConnectors --filter calendarDatesOrder` (FAIL), then add to `AllDay.swift`:

```swift
extension CalendarDate: Comparable {
    public static func < (a: CalendarDate, b: CalendarDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}
```

Run again (PASS).

- [ ] **Step 2: Core manifest.** `Packages/TimeTugCore/Package.swift` becomes:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TimeTugCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "TimeTugCore", targets: ["TimeTugCore"])],
    dependencies: [.package(path: "../CalendarConnectors")],
    targets: [
        .target(name: "TimeTugCore", dependencies: [.product(name: "CalendarCore", package: "CalendarConnectors")]),
        .testTarget(name: "TimeTugCoreTests", dependencies: [
            "TimeTugCore", .product(name: "CalendarCore", package: "CalendarConnectors"),
        ]),
    ]
)
```

- [ ] **Step 3: Failing wrapper tests** (`TimeTugCalendarEventTests.swift`). They pin the derived fields and the unchanged key formulas:

```swift
import CalendarCore
import Foundation
import Testing
@testable import TimeTugCore

private func library(
    _ id: String = "e1", start: String = "2026-09-18T10:00:00Z", minutes: Int = 30,
    attendees: [CalendarCore.Attendee] = [], organizer: CalendarCore.Attendee? = nil,
    myResponse: CalendarCore.ResponseStatus? = nil, conference: URL? = nil
) -> CalendarCore.CalendarEvent {
    let s = date(start)
    return CalendarCore.CalendarEvent(
        eventID: id, uid: "uid-1", calendarID: "cal", title: "Standup", start: s,
        end: s.addingTimeInterval(TimeInterval(minutes * 60)), attendees: attendees, organizer: organizer,
        conference: conference.map { ConferenceInfo(url: $0, provider: .other) }, myResponse: myResponse)
}

@Test func forwardsAndSetsTheEventsFields() {
    var e = TimeTugCalendarEvent(event: library(), sourceID: "src")
    #expect(e.title == "Standup" && e.calendarID == "cal" && e.sourceEventID == "e1" && e.externalUID == "uid-1")
    e.start = date("2026-09-18T11:00:00Z")
    e.location = "Room 4"
    #expect(e.event.start == date("2026-09-18T11:00:00Z") && e.event.location == "Room 4")
}

@Test func derivesAttendeeCountResponseAndOrganizerFromTheEvent() {
    let me = CalendarCore.Attendee(email: "me@x.com", response: .tentative, isSelf: true)
    let other = CalendarCore.Attendee(email: "A@X.com", response: .accepted)
    let boss = CalendarCore.Attendee(email: "boss@x.com", isOrganizer: true)
    let e = TimeTugCalendarEvent(event: library(attendees: [me, other], organizer: boss), sourceID: "s")
    #expect(e.otherAttendeeCount == 1)
    #expect(e.attendees.map(\.email) == ["a@x.com"])
    #expect(e.responseStatus == .tentative)
    #expect(e.organizerEmail == "boss@x.com")
}

@Test func myResponseWinsAndSelfOrganizerIsHidden() {
    let me = CalendarCore.Attendee(email: "me@x.com", response: .needsAction, isSelf: true, isOrganizer: true)
    let e = TimeTugCalendarEvent(event: library(attendees: [me], organizer: me, myResponse: .accepted), sourceID: "s")
    #expect(e.responseStatus == .accepted)
    #expect(e.organizerEmail == nil)
    #expect(TimeTugCalendarEvent(event: library(), sourceID: "s").responseStatus == nil)
}

@Test func conferenceURLStartsFromTheEventAndIsSettable() {
    let url = URL(string: "https://meet.google.com/aaa-bbbb-ccc")!
    var e = TimeTugCalendarEvent(event: library(conference: url), sourceID: "s")
    #expect(e.conferenceURL == url)
    e.conferenceURL = nil
    #expect(e.event.conference?.url == url)
}

@Test func isSameMeetingMatchesByIdOrByAnyMergedContentKey() {
    let a = TimeTugCalendarEvent(event: library("e1"), sourceID: "src")
    let sameOccurrence = TimeTugCalendarEvent(event: library("e1"), sourceID: "src")
    let sameContentOtherID = TimeTugCalendarEvent(event: library("e9"), sourceID: "other")
    var merged = TimeTugCalendarEvent(event: library("m", start: "2026-09-18T12:00:00Z"), sourceID: "src")
    merged.mergedMembers = [MergedMember(title: "Standup", calendarKey: "src/cal", contentKey: a.contentKey,
                                         details: "bare", start: a.start, end: a.end)]
    #expect(a.isSameMeeting(as: sameOccurrence))
    #expect(a.isSameMeeting(as: sameContentOtherID))   // same title, start and end
    #expect(merged.isSameMeeting(as: a))                // a merged copy's content matches
    #expect(!a.isSameMeeting(as: TimeTugCalendarEvent(event: library("e2", start: "2026-09-18T15:00:00Z"), sourceID: "src")))
}

@Test func idAndContentKeyKeepTheirFormulas() {
    let e = TimeTugCalendarEvent(event: library(), sourceID: "src")
    let start = Int(date("2026-09-18T10:00:00Z").timeIntervalSince1970)
    let end = Int(date("2026-09-18T10:30:00Z").timeIntervalSince1970)
    #expect(e.id == "src/e1/\(start)")
    #expect(e.contentKey == "standup|\(start)|\(end)")
    #expect(e.calendarKey == "src/cal")
}
```

- [ ] **Step 4: Run** `swift test --package-path Packages/TimeTugCore --filter TimeTugCalendarEventTests`. Expected: FAIL (does not compile against the old struct).
- [ ] **Step 5: Rewrite the type** (`TimeTugCalendarEvent.swift`):

```swift
import CalendarCore
import Foundation

/// A library event as TimeTug sees it: the provider's event plus the source it came from and the state Core adds
/// (merged duplicates, the join link Core detects, the best attendance across copies). Times, all-day form and
/// attendees are the library's own; nothing is converted per refresh.
public struct TimeTugCalendarEvent: Identifiable, Hashable, Sendable {
    public var event: CalendarCore.CalendarEvent
    public var sourceID: String
    /// Starts from the provider's conference link; Core also fills it from detected links and merged copies.
    public var conferenceURL: URL?
    /// Non-self attendees; the merge step raises it to the largest count across a group.
    public var otherAttendeeCount: Int
    /// The account owner's response; nil when the provider does not say. The merge step keeps the best across a group.
    public var responseStatus: CalendarCore.ResponseStatus?
    /// Calendar keys of the other calendars where duplicate copies of this meeting appear.
    public var additionalCalendarKeys: Set<String>
    /// Every original copy folded into this event (including itself); empty when never merged.
    public var mergedMembers: [MergedMember]
    public var mergeProvenance: MergeProvenance?
    /// Where the range shown to the user starts when it differs from `start` (a merged meeting shows the
    /// longer copy's range while `start` is the tug time); nil means the same as `start`.
    public var displayStart: Date?

    public init(event: CalendarCore.CalendarEvent, sourceID: String) {
        self.event = event
        self.sourceID = sourceID
        self.conferenceURL = event.conference?.url
        self.otherAttendeeCount = event.attendees.filter { !$0.isSelf }.count
        self.responseStatus = event.myResponse ?? event.attendees.first(where: \.isSelf)?.response
        self.additionalCalendarKeys = []
        self.mergedMembers = []
        self.mergeProvenance = nil
        self.displayStart = nil
    }

    public var title: String { get { event.title } set { event.title = newValue } }
    public var start: Date { get { event.start } set { event.start = newValue } }
    public var end: Date { get { event.end } set { event.end = newValue } }
    /// All-day events use the library's canonical form: midnight of the first day in `timeZone`, `end` exclusive.
    public var isAllDay: Bool { get { event.isAllDay } set { event.isAllDay = newValue } }
    public var timeZone: TimeZone? { get { event.timeZone } set { event.timeZone = newValue } }
    public var location: String? { get { event.location } set { event.location = newValue } }
    public var notes: String? { get { event.notes } set { event.notes = newValue } }
    public var url: URL? { get { event.url } set { event.url = newValue } }
    public var calendarID: String { get { event.calendarID } set { event.calendarID = newValue } }

    public var sourceEventID: String { event.eventID }
    public var externalUID: String? { event.uid }
    /// Attendees other than the calendar owner.
    public var attendees: [CalendarCore.Attendee] { event.attendees.filter { !$0.isSelf } }
    public var organizerEmail: String? { event.organizer.flatMap { $0.isSelf ? nil : $0.email } }

    /// The start of the range to display: `displayStart` when set, else `start`.
    public var shownStart: Date { displayStart ?? start }

    /// Unique per occurrence: recurring events share a source id but differ in start.
    public var id: String { "\(sourceID)/\(sourceEventID)/\(Int(start.timeIntervalSince1970))" }
    /// Identity by content (title, start, end): survives a changed `sourceEventID`, matching the
    /// store's duplicate merge.
    public var contentKey: String {
        "\(title.lowercased())|\(Int(start.timeIntervalSince1970))|\(Int(end.timeIntervalSince1970))"
    }
    public var calendarKey: String { CalendarInfo.key(sourceID: sourceID, calendarID: calendarID) }
    /// This event's own calendar plus every calendar its duplicates appear on.
    public var allCalendarKeys: Set<String> { additionalCalendarKeys.union([calendarKey]) }

    /// Content keys of this event and every copy merged into it.
    public var allContentKeys: Set<String> { Set(mergedMembers.map(\.contentKey)).union([contentKey]) }

    /// True for the same occurrence or when any merged copy's content matches (an armed timer's
    /// event may since have been merged into another, or split back out).
    public func isSameMeeting(as other: TimeTugCalendarEvent) -> Bool {
        id == other.id || !allContentKeys.isDisjoint(with: other.allContentKeys)
    }
}
```

- [ ] **Step 6: Remove Core's duplicates and fix compile errors.** Delete `Attendee` from `MergeTypes.swift` and `ResponseStatus` from `CalendarInfo.swift` (keep `MergedMember`, `MergeProvenance`, `CalendarInfo`). Then:
  - `TakeoverPolicy.swift`: `event.responseStatus == .declined` still compiles (optional compare); add `import CalendarCore` only if the compiler asks.
  - `DuplicateRules.emails`: `Set((event.attendees.map(\.email) + [event.organizerEmail]).compactMap { $0 })` (the library `Attendee.init` already lowercases and trims; delete the `Attendee.normalizedEmail` call).
  - `DuplicateResolver.attendance`: change the parameter to `CalendarCore.ResponseStatus?` and the cases to `.accepted: 4`, `.tentative: 3`, `.needsAction: 2`, `nil: 1`, `.declined: 0`; add `import CalendarCore` at the top of the file. Its `group.map(\.responseStatus).max { attendance($0) < attendance($1) }` call keeps its shape (the result is `ResponseStatus??`; keep the existing `?? result.responseStatus` fallback but flatten with `.flatMap { $0 }` if the compiler complains about the double optional).
  - Any other file that names `Attendee` or `ResponseStatus`: `grep -rn "Attendee\|ResponseStatus\|\.pending\|\.unknown" Packages/TimeTugCore/Sources` and fix each (add `import CalendarCore`; `.pending` becomes `.needsAction`, `.unknown` becomes `nil`; `DuplicateRules.LocationRelation.unknown` is unrelated and stays).
- [ ] **Step 7: Update the test helper** (`Support.swift`): add `import CalendarCore`; keep `makeEvent`'s parameter list except `status: CalendarCore.ResponseStatus? = .accepted` and `attendees: [CalendarCore.Attendee] = []`; build the event:

```swift
    let startDate = date(start)
    let base = CalendarCore.CalendarEvent(
        eventID: id, uid: externalUID, calendarID: calendarID, title: title, notes: notes, location: location,
        start: startDate, end: startDate.addingTimeInterval(TimeInterval(minutes * 60)),
        timeZone: isAllDay ? TimeZone(identifier: "UTC")! : nil, isAllDay: isAllDay, attendees: attendees, url: url)
    var event = TimeTugCalendarEvent(event: base, sourceID: "fake")
    event.otherAttendeeCount = others
    event.responseStatus = status
    event.conferenceURL = conferenceURL
    return event
```

  Fix the other Core tests that name `Attendee(...)`, `.pending`, `.unknown` the same way (`Attendee(name:email:)` keeps its labels). An all-day `makeEvent` now carries a UTC zone; if an all-day test's `start` is not a UTC midnight, change it to one (e.g. `"2026-09-18T00:00:00Z"` with `minutes: 1440`).
- [ ] **Step 8: Verify.** `swift test --package-path Packages/TimeTugCore`. Expected: PASS (all previous Core tests plus the new ones). The `id`/`contentKey` test and the existing `TakeoverLedgerTests` prove the keys are unchanged for timed events.
- [ ] **Step 9: Commit** (`refactor(core): TimeTugCalendarEvent wraps the library event; adopt library Attendee and ResponseStatus`).

---

## Task 5: Zone-aware all-day in Core (agenda, widget, store window)

**Files:**
- Create: `Packages/TimeTugCore/Sources/TimeTugCore/Model/TimeTugCalendarEvent+AllDay.swift`
- Modify: `Agenda/DayAgenda.swift`, `Widget/WidgetSnapshot.swift`, `Store/CalendarStore.swift`
- Test: create `Tests/TimeTugCoreTests/AllDayDatesTests.swift`; extend `DayAgendaTests.swift`, `WidgetSnapshotTests.swift`, `CalendarStoreTests.swift`

**Interfaces:**
- Consumes: Task 4's wrapper; `AllDay.dates(start:end:in:)`, `AllDay.date(of:in:)`, `AllDay.startOfDay(_:in:)`, `CalendarDate` (Comparable).
- Produces: `TimeTugCalendarEvent.allDayDates: (first: CalendarDate, endExclusive: CalendarDate)?` (nil unless `isAllDay` with a non-nil `timeZone`); `func covers(_ date: CalendarDate) -> Bool` (`first <= date < endExclusive`, false for timed events); `CalendarStore.sourceQueryMargin: TimeInterval` (26 hours).

- [ ] **Step 1: Failing tests.** First add a shared helper and calendar constructor to `Tests/TimeTugCoreTests/Support.swift` (it already has `import CalendarCore` from Task 4):

```swift
func calendar(in zone: String) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: zone)!
    return c
}

/// A canonical all-day event: `first` to `endExclusive` (calendar dates) in `zone`.
func makeAllDay(_ id: String = "d", zone: String, first: CalendarDate, endExclusive: CalendarDate,
                title: String = "Holiday") -> TimeTugCalendarEvent {
    let tz = TimeZone(identifier: zone)!
    let range = AllDay.canonical(first: first, endExclusive: endExclusive, in: tz)!
    let base = CalendarCore.CalendarEvent(
        eventID: id, calendarID: "cal", title: title, start: range.start, end: range.end, timeZone: tz, isAllDay: true)
    return TimeTugCalendarEvent(event: base, sourceID: "fake")
}

func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDate { CalendarDate(year: y, month: m, day: d) }
```

Create `AllDayDatesTests.swift`:

```swift
import CalendarCore
import Foundation
import Testing
@testable import TimeTugCore

@Test func allDayDatesAreReadInTheEventsOwnZone() {
    let e = makeAllDay(zone: "Asia/Tokyo", first: day(2026, 9, 21), endExclusive: day(2026, 9, 22))
    #expect(e.allDayDates?.first == day(2026, 9, 21))
    #expect(e.covers(day(2026, 9, 21)))
    #expect(!e.covers(day(2026, 9, 22)))
    #expect(!e.covers(day(2026, 9, 20)))
}

@Test func multiDayAllDayCoversEveryDayButNotTheExclusiveEnd() {
    let e = makeAllDay(zone: "America/Los_Angeles", first: day(2026, 9, 21), endExclusive: day(2026, 9, 24))
    #expect(e.covers(day(2026, 9, 23)))
    #expect(!e.covers(day(2026, 9, 24)))
}

@Test func allDayDatesSurviveAMissingMidnight() {
    // Sao Paulo skipped local midnight on 2018-11-04 (DST began at 00:00); the noon-based start of day still works.
    let e = makeAllDay(zone: "America/Sao_Paulo", first: day(2018, 11, 4), endExclusive: day(2018, 11, 5))
    #expect(e.allDayDates?.first == day(2018, 11, 4))
    #expect(e.allDayDates?.endExclusive == day(2018, 11, 5))
    #expect(e.covers(day(2018, 11, 4)))
}

@Test func timedEventsHaveNoAllDayDates() {
    let e = makeEvent()
    #expect(e.allDayDates == nil)
    #expect(!e.covers(day(2026, 9, 18)))
}
```

Add to `DayAgendaTests.swift` (uses that file's private `agenda(...)`-style call; these call `DayAgenda.make` directly):

```swift
private let la = calendar(in: "America/Los_Angeles")

// The first test below fails against the old instant-based rule; the second and third are regression guards that
// pin behaviour that must not change (exclusive end date, skipAllDayEvents).

private func laAgenda(_ events: [TimeTugCalendarEvent], at time: String) -> DayAgenda {
    DayAgenda.make(events: events, settings: optedIn { $0.skipAllDayEvents = false }, now: date(time), calendar: la)
}

@Test func allDayEventStaysOnItsOwnDateForAViewerInAnotherZone() {
    let tokyoSep21 = makeAllDay(zone: "Asia/Tokyo", first: day(2026, 9, 21), endExclusive: day(2026, 9, 22))
    // 10:00Z on Sep 21 is 03:00 in Los Angeles: still Sep 21 there.
    let onTheDay = laAgenda([tokyoSep21], at: "2026-09-21T10:00:00Z")
    #expect(onTheDay.items.map(\.state) == [.current])
    // 10:00Z on Sep 20 is Sep 20 in Los Angeles: not shown (the Tokyo event's instants begin at 15:00Z on Sep 20,
    // which the old instant rule would have shown as today's).
    #expect(laAgenda([tokyoSep21], at: "2026-09-20T10:00:00Z").items.isEmpty)
}

@Test func allDayEventEndingAtLocalMidnightIsNotShownOnTheExclusiveEndDate() {
    let twoDays = makeAllDay(zone: "America/Los_Angeles", first: day(2026, 9, 19), endExclusive: day(2026, 9, 21))
    #expect(laAgenda([twoDays], at: "2026-09-20T18:00:00Z").items.count == 1)   // Sep 20 in LA
    #expect(laAgenda([twoDays], at: "2026-09-21T18:00:00Z").items.isEmpty)      // Sep 21 in LA
}

@Test func allDayItemsAreHiddenWhenSkipAllDayIsOn() {
    let holiday = makeAllDay(zone: "America/Los_Angeles", first: day(2026, 9, 21), endExclusive: day(2026, 9, 22))
    let result = DayAgenda.make(events: [holiday], settings: optedIn(), now: date("2026-09-21T18:00:00Z"), calendar: la)
    #expect(result.items.isEmpty)
}
```

Add to `WidgetSnapshotTests.swift`:

```swift
@Test func snapshotShowsAnAllDayEventOnItsOwnDatesInTheViewersMidnights() {
    let la = calendar(in: "America/Los_Angeles")
    let tokyoSep21 = makeAllDay(zone: "Asia/Tokyo", first: day(2026, 9, 21), endExclusive: day(2026, 9, 22))
    var settings = TakeoverSettings()
    settings.skipAllDayEvents = false
    func snapshot(_ time: String) -> WidgetSnapshot {
        WidgetSnapshot.make(events: [tokyoSep21], calendars: [], settings: settings, now: date(time), calendar: la)
    }
    let events = snapshot("2026-09-21T18:00:00Z").events
    #expect(events.count == 1)
    #expect(events[0].isAllDay)
    #expect(events[0].start == AllDay.startOfDay(day(2026, 9, 21), in: la.timeZone))
    #expect(events[0].end == AllDay.startOfDay(day(2026, 9, 22), in: la.timeZone))
    #expect(snapshot("2026-09-19T18:00:00Z").events.count == 1)   // Sep 19 + 3-day horizon reaches Sep 21
    #expect(snapshot("2026-09-18T18:00:00Z").events.isEmpty)      // horizon ends before Sep 21
}
```

Add to `CalendarStoreTests.swift` and update the existing `refreshAsksSourcesForFetchWindow` (its expected end becomes `date("2026-09-19T00:06:00Z").addingTimeInterval(CalendarStore.sourceQueryMargin)`):

```swift
@Test func sourcesAreQueriedWithAZoneMargin() async {
    let source = FakeSource()
    let store = CalendarStore(sources: [source], calendar: utcCalendar)
    _ = await store.refresh(now: now, leadTime: 600)
    let window = await store.fetchWindow(now: now, leadTime: 600)
    let requested = await source.requestedIntervals.first
    #expect(requested?.start == window.start.addingTimeInterval(-CalendarStore.sourceQueryMargin))
    #expect(requested?.end == window.end.addingTimeInterval(CalendarStore.sourceQueryMargin))
}

@Test func farZoneAllDayEventOnTodaysDateIsKept() async {
    // Viewer in UTC+14, calendar in UTC-11: the event's instants start after the viewer's day window ends.
    let kiritimati = calendar(in: "Pacific/Kiritimati")
    let midway = makeAllDay(zone: "Pacific/Midway", first: day(2026, 9, 18), endExclusive: day(2026, 9, 19))
    let source = FakeSource()
    await source.set(events: .success([midway]))
    let store = CalendarStore(sources: [source], calendar: kiritimati)
    let snapshot = await store.refresh(now: date("2026-09-18T02:00:00Z"), leadTime: 60)   // Sep 18 16:00 there
    #expect(snapshot.events.map(\.sourceEventID) == ["d"])
}
```

Add `import CalendarCore` to `WidgetSnapshotTests.swift` (it names `AllDay`); `DayAgendaTests.swift` and `CalendarStoreTests.swift` use only the helpers and need no import.

- [ ] **Step 2: Run.** `swift test --package-path Packages/TimeTugCore --filter "AllDayDates|DayAgenda|WidgetSnapshot|CalendarStore"`. Expected: FAIL (missing `allDayDates`/`covers`, wrong results).
- [ ] **Step 3: Implement the helper** (`TimeTugCalendarEvent+AllDay.swift`):

```swift
import CalendarCore
import Foundation

extension TimeTugCalendarEvent {
    /// The first covered date and the exclusive end date, read in the event's own zone (never the viewer's), so an
    /// all-day event stays on the dates it was created for. nil for timed events and for an all-day event without a zone.
    public var allDayDates: (first: CalendarDate, endExclusive: CalendarDate)? {
        guard isAllDay, let zone = timeZone else { return nil }
        return AllDay.dates(start: start, end: end, in: zone)
    }

    public func covers(_ date: CalendarDate) -> Bool {
        guard let dates = allDayDates else { return false }
        return dates.first <= date && date < dates.endExclusive
    }
}
```

- [ ] **Step 4: `DayAgenda.make`.** Add `import CalendarCore`. Compute `let today = AllDay.date(of: dayStart, in: calendar.timeZone)` once; replace the overlap filter with:

```swift
            .filter { event in
                if let dates = event.allDayDates {
                    return dates.first <= today && today < dates.endExclusive
                }
                if event.end > dayStart && event.start < nextDayStart { return true }
                // After-midnight events show only once inside their lead-time period.
                return !event.isAllDay
                    && event.start >= nextDayStart
                    && now >= event.start.addingTimeInterval(-settings.leadTime)
            }
```

  (an all-day event without a zone falls through to the instant rules, as before), and compute the state with dates for all-day items:

```swift
                let state: State
                if let dates = event.allDayDates {
                    state = dates.endExclusive <= today ? .past : (dates.first <= today ? .current : .upcoming)
                } else {
                    state = event.end <= now ? .past : (event.start <= now ? .current : .upcoming)
                }
```

  Sorting stays `($0.start, $0.title)`. (Note: mixed all-day and timed items still sort by instant; keep that.)
- [ ] **Step 5: `WidgetSnapshot.make`.** Add `import CalendarCore`. Replace the `included` pipeline with:

```swift
        let today = AllDay.date(of: dayStart, in: calendar.timeZone)
        let horizon = AllDay.date(of: horizonEnd, in: calendar.timeZone)
        let included = events
            .filter { !$0.allCalendarKeys.isSubset(of: settings.hiddenCalendarKeys) }
            .filter { !(settings.skipAllDayEvents && $0.isAllDay) }
            .filter { event in
                if let dates = event.allDayDates { return dates.endExclusive > today && dates.first < horizon }
                return event.end > dayStart && event.shownStart < horizonEnd
            }
            .map { event -> WidgetEvent in
                var start = event.shownStart, end = event.end
                if let dates = event.allDayDates,
                   let localStart = AllDay.startOfDay(dates.first, in: calendar.timeZone),
                   let localEnd = AllDay.startOfDay(dates.endExclusive, in: calendar.timeZone) {
                    (start, end) = (localStart, localEnd)   // the snapshot is a view model: local midnights for the same dates
                }
                return WidgetEvent(id: event.id, title: event.title, start: start, end: end, isAllDay: event.isAllDay,
                                   colorHex: colors[event.calendarKey], joinURL: event.conferenceURL)
            }
            .sorted { ($0.start, $0.title, $0.id) < ($1.start, $1.title, $1.id) }
```

- [ ] **Step 6: `CalendarStore`.** Add `import CalendarCore`; add `public static let sourceQueryMargin: TimeInterval = 26 * 3600` (comment: the widest gap between two zones, so an all-day event on one of today's dates in a far zone is still fetched). In `refresh`, query sources with `let queryWindow = DateInterval(start: window.start.addingTimeInterval(-Self.sourceQueryMargin), end: window.end.addingTimeInterval(Self.sourceQueryMargin))` and `source.events(in: queryWindow)`. Replace the raw filter in `makeSnapshot` with:

```swift
        let firstDate = AllDay.date(of: window.start, in: calendar.timeZone)
        let lastDate = AllDay.date(of: window.end.addingTimeInterval(-1), in: calendar.timeZone)
        let raw = sources.flatMap { source in
            (lastEvents[source.id] ?? []).filter { event in
                if let dates = event.allDayDates { return dates.endExclusive > firstDate && dates.first <= lastDate }
                return event.end > window.start && event.start < window.end
            }
        }
```

  `fetchWindow` itself is unchanged (its tests and the coordinator rely on it).
- [ ] **Step 7: Verify.** `swift test --package-path Packages/TimeTugCore`. Expected: PASS.
- [ ] **Step 8: Commit** (`feat(core): all-day events by calendar date in agenda, widget snapshot and store`).

---

## Task 6: Shrink the bridge; fix the inference tests

**Files:**
- Modify: `Packages/CalendarBridge/Sources/CalendarBridge/EventMapper.swift`, `ConnectedSource.swift` (only if `mapper` construction changes)
- Modify: `Packages/CalendarBridge/Package.swift` (no change expected), `Tests/CalendarBridgeTests/EventMapperTests.swift`, `ConnectedSourceTests.swift`
- Modify: `Packages/AppleIntelligenceInference/Tests/AppleIntelligenceInferenceTests/PromptBuilderTests.swift` (and its `Package.swift` if it now needs `CalendarCore`)

**Interfaces:**
- Consumes: `TimeTugCalendarEvent.init(event:sourceID:)` (Task 4).
- Produces: `EventMapper()` (no `calendar:` parameter); `EventMapper.calendarInfo(_:sourceID:) -> CalendarInfo`; `EventMapper.event(_:sourceID:) -> TimeTugCalendarEvent?` (nil for `.cancelled`).

- [ ] **Step 1: Failing bridge tests.** Replace `EventMapperTests.swift` with tests for: `event` returns nil for a cancelled event; it wraps the library event unchanged (`mapped.event == source`, including an all-day event from another zone, whose `start`/`end` must equal the input's, which proves there is no conversion); `sourceID` is set; `calendarInfo` copies id, title, account and colour. Keep the existing `calendarInfo` and cancellation tests as they are, drop the ones about local-midnight conversion (`allDayFromAnotherZoneLandsOnTheSameLocalDates`, `multiDayAllDayKeepsItsLength`) and the attendee/response mapping tests (those behaviours moved into the Task 4 wrapper tests). Example:

```swift
@Test func allDayEventsPassThroughUnchanged() throws {
    let tz = TimeZone(identifier: "Asia/Tokyo")!
    let range = AllDay.canonical(first: CalendarDate(year: 2026, month: 9, day: 21),
                                 endExclusive: CalendarDate(year: 2026, month: 9, day: 22), in: tz)!
    let source = CalendarCore.CalendarEvent(eventID: "h", calendarID: "c", title: "Holiday",
        start: range.start, end: range.end, timeZone: tz, isAllDay: true)
    let mapped = try #require(EventMapper().event(source, sourceID: "google-1"))
    #expect(mapped.event == source)
    #expect(mapped.sourceID == "google-1")
}
```

- [ ] **Step 2: Run** `swift test --package-path Packages/CalendarBridge`. Expected: FAIL (the old mapper converts, and `EventMapper()` compiles but the equality assertion fails).
- [ ] **Step 3: Implement.** `EventMapper.swift` becomes:

```swift
import CalendarCore
import Foundation
import TimeTugCore

/// Maps the connector library's model to TimeTug's. The library event is carried as is (times, all-day form and
/// attendees are used natively); only the source id and Core's own state are added.
public struct EventMapper: Sendable {
    public init() {}

    public func calendarInfo(_ d: CalendarDescriptor, sourceID: String) -> CalendarInfo {
        CalendarInfo(sourceID: sourceID, calendarID: d.id, title: d.title, accountName: d.accountName, colorHex: d.colorHex)
    }

    /// nil for cancelled events. Titles are never rewritten: each connector chooses its own placeholder.
    public func event(_ e: CalendarCore.CalendarEvent, sourceID: String) -> TimeTugCalendarEvent? {
        e.status == .cancelled ? nil : TimeTugCalendarEvent(event: e, sourceID: sourceID)
    }
}
```

  Update `ConnectedSourceTests.swift` for the new event shape (compile fixes only). Search the app for `EventMapper(calendar:` (`grep -rn "EventMapper(" Apps Packages`): none is expected outside tests.
- [ ] **Step 4: Inference tests.** `PromptBuilderTests.swift` builds `TimeTugCalendarEvent`s and uses `Attendee`: add `import CalendarCore`, then change the construction to `TimeTugCalendarEvent(event: CalendarCore.CalendarEvent(...), sourceID: ...)`. If the test target needs `CalendarCore`, add `.product(name: "CalendarCore", package: "CalendarConnectors")` and `.package(path: "../CalendarConnectors")` to `Packages/AppleIntelligenceInference/Package.swift` (test target only).
- [ ] **Step 5: EventKit conformance test.** In `Packages/EventKitSource/Package.swift` add `.product(name: "CalendarTestSupport", package: "CalendarConnectors")` to the test target's dependencies, then add to `Tests/EventKitSourceTests/EventKitMappingTests.swift` (adapt the call to `EventKitMapping.canonicalAllDay(start:end:calendar:)` as that file's existing tests do):

```swift
@Test func canonicalAllDayPassesTheConformanceCheck() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let (start, end) = EventKitMapping.canonicalAllDay(
        start: calendar.date(from: DateComponents(year: 2026, month: 9, day: 21))!,
        end: calendar.date(from: DateComponents(year: 2026, month: 9, day: 22))!, calendar: calendar)
    let event = CalendarEvent(eventID: "a", calendarID: "c", title: "Holiday", start: start, end: end,
                              timeZone: calendar.timeZone, isAllDay: true)
    #expect(AllDayConformance.violations(event).isEmpty)
}
```

  with `import CalendarTestSupport` and `import CalendarCore` at the top of the file. Expected: PASS (EventKit already emits the canonical form).
- [ ] **Step 6: Verify.** `swift test --package-path Packages/CalendarBridge` and `swift test --package-path Packages/AppleIntelligenceInference` and `swift test --package-path Packages/EventKitSource`. Expected: PASS.
- [ ] **Step 7: Commit** (`refactor(bridge): wrap library events without converting; minimal EventMapper`).

---

## Task 7: App target and tests

**Files:**
- Modify: `Apps/macOS/Sources/AppCoordinator.swift:353` (sample event), `Apps/macOS/Sources/PopupRowModel.swift` (only if it fails to compile), and the app tests: `Apps/macOS/Tests/{PopupLogicTests,TimeFormattingTests,MenuBarIconStateTests,TakeoverTextTests,LedgerStoreTests}.swift`
- Modify (if needed): `Apps/macOS/project.yml`

**Interfaces:**
- Consumes: the wrapper (Task 4); `EventMapper()` (Task 6).

- [ ] **Step 1: Build to find breaks.** `xcodegen generate --spec Apps/macOS/project.yml && git checkout -- Apps/macOS/Sources/Info.plist Apps/macOS/Widgets/Info.plist`, then `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' build 2>&1 | tail -40`. Expected: errors only at the construction sites listed above (`TimeTugCalendarEvent(sourceEventID:...)`, `ResponseStatus`, `.unknown`).
- [ ] **Step 2: Fix the sample event** in `AppCoordinator.swift` (the "Sample meeting" for Test tug):

```swift
        var sample = TimeTugCalendarEvent(
            event: CalendarCore.CalendarEvent(
                eventID: "test", calendarID: "test", title: "Sample meeting", start: start, end: end),
            sourceID: "test")
        sample.otherAttendeeCount = 1
        sample.conferenceURL = URL(string: "https://meet.google.com/aaa-bbbb-ccc")
```

  using the local names for start/end already present at that site (read the existing lines 350-357 and keep their values); add `import CalendarCore`.
- [ ] **Step 3: Fix the app tests' helpers** the same way: each `TimeTugCalendarEvent(sourceEventID: ..., sourceID: ..., calendarID: ..., title: ..., start: ..., end: ..., isAllDay: ..., otherAttendeeCount: ..., responseStatus: ...)` becomes a `CalendarCore.CalendarEvent(eventID:calendarID:title:start:end:timeZone:isAllDay:)` (with `timeZone: TimeZone(identifier: "UTC")` when `isAllDay`) wrapped by `TimeTugCalendarEvent(event:sourceID:)`, then set `otherAttendeeCount` / `responseStatus` on the variable. In `MenuBarIconStateTests`, the `response: ResponseStatus = .unknown` parameter becomes `response: CalendarCore.ResponseStatus? = nil`. Add `import CalendarCore` to each.
- [ ] **Step 4: Run app tests.** `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test 2>&1 | tail -30`. Expected: `** TEST SUCCEEDED **` (all existing app tests). If a popup or overlay test asserted all-day local-midnight behaviour, change its fixture to the canonical form (UTC zone, UTC midnights) rather than the assertion.
- [ ] **Step 5: Build the widget extension too** (it is part of the `TimeTug` scheme's dependencies; a successful `build` in Step 1/4 covers it). Confirm `TimeTugWidgets` compiled with `xcodebuild ... -scheme TimeTug build 2>&1 | grep -i "TimeTugWidgets" | head`.
- [ ] **Step 6: Commit** the source and test changes (plus `project.yml` if edited); never the Info.plists.

---

## Task 8: CI, ADR and docs

**Files:**
- Modify: `.github/workflows/ci.yml` (header comment and the two Linux jobs), `docs/decisions/0012-calendar-connector-library.md`, `AGENTS.md`, `docs/architecture.md`, `docs/PROGRESS.md`

- [ ] **Step 1: CI.** Change the `core-linux` job to test both packages on `swift:6.0`:

```yaml
      - name: Test TimeTugCore
        run: swift test --package-path Packages/TimeTugCore
      - name: Test CalendarConnectors
        run: swift test --package-path Packages/CalendarConnectors
```

  Delete the `connectors-linux` job and its header comment lines; update the `core-linux` header line to say it proves Core and the connector library stay portable (still allowed to fail).
- [ ] **Step 2: ADR 0012.** Add a "Phase 2.5" section: Core now depends on `CalendarCore` (superseding the Phase 2 note); the library has no external dependencies (`CalendarOAuth` product, `SHA256Hashing` seam with a pure-Swift default, CryptoKit in `CalendarApple`); wrapper `TimeTugCalendarEvent`; all-day by calendar date in the event's own zone; all-day `id`/`contentKey` inputs are now canonical instants (accepted: all-day events never take over or merge); fetch window widened by 26 hours for sources.
- [ ] **Step 3: AGENTS.md and architecture.** Update the layout lines (connector library products; bridge is minimal; `CalendarApple` also holds `CryptoKitSHA256`), the dependency rule sentence (Core -> `CalendarCore`), the CI paragraph (`connectors-linux` removed), and the Gotchas line that says Core does not depend on the library. Keep wording free of the words that trip the secret scanner ("secret", "token", "password" with an equals sign or colon).
- [ ] **Step 4: Verify docs.** `grep -rn "connectors-linux\|swift-crypto" AGENTS.md docs .github | grep -v "docs/superpowers"` prints nothing stale (ADR history lines about the earlier decision are fine if worded as history).
- [ ] **Step 5: Progress log.** Add a short "Calendar connectors Phase 2.5" entry to `docs/PROGRESS.md` (branch, what changed, what needs manual checks).
- [ ] **Step 6: Commit** (`docs: Phase 2.5 ADR, CI and agent guide`).

---

## Task 9: Whole-branch verification

- [ ] **Step 1:** Run every gate: `swift test --package-path Packages/TimeTugCore`, `.../CalendarConnectors`, `.../CalendarBridge`, `.../CalendarApple`, `.../EventKitSource`, `.../AppleIntelligenceInference`, then the app tests from Task 7. Expected: all PASS.
- [ ] **Step 2: Linux portability check, if Docker is available:** `docker run --rm -v "$PWD":/w -w /w swift:6.0 sh -c "swift test --package-path Packages/TimeTugCore && swift test --package-path Packages/CalendarConnectors"`. Expected: PASS. If Docker is unavailable, say so in the PR (CI's `core-linux` is the check).
- [ ] **Step 3: Persisted-key check.** `git diff master -- Packages/TimeTugCore/Tests/TimeTugCoreTests/TakeoverLedgerTests.swift Packages/TimeTugCore/Tests/TimeTugCoreTests/LessonBookTests.swift` shows no changed expected key strings.
- [ ] **Step 4: Whole-branch DeepSeek review** with the `deepseek-review` skill (changed source files via `--files`, spec and ADR via `--context`); verify each finding against the code.
- [ ] **Step 5: Push and open the PR into `master`** (`gh pr create --base master`), body listing the tests run, the accepted all-day key note, and the manual checks (Accounts tab still lists calendars, all-day events appear on the right dates in the popup and widget). Do not merge until the owner says so.
