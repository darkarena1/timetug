# Direct and App Store builds, shared state, one running instance: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship TimeTug as a downloaded (Developer ID, Sparkle) build and a Mac App Store build from one codebase, with all state in the team App Group and exactly one TimeTug running at a time (newest wins).

**Architecture:** Move preferences, files and credentials into the App Group first (while the direct build is still unsandboxed and can read the old locations), then sandbox both builds, then split one XcodeGen template into a direct and an App Store target that differ only in the updater, bundle IDs and entitlements, then add a lock-file based single-instance check with a quiet collision notice. Pure logic (version order, arbitration decision, notice text, migrations) is unit tested; the rest is verified by hand on a team-signed build.

**Tech Stack:** Swift 5 (app layer), XCTest (`Apps/macOS/Tests`), Swift Testing (`Packages/CalendarApple`), XcodeGen (`Apps/macOS/project.yml`), Sparkle 2.10.0, App Sandbox, App Groups, data-protection Keychain, Darwin notifications, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-06-app-store-and-direct-builds-design.md`

## Global Constraints

- App Group id is `YYA6ZKMD36.com.timetug.shared` (`AppGroup.identifier`). Team id is `YYA6ZKMD36`.
- Direct bundle IDs: app `com.timetug.app`, widget `com.timetug.app.widgets`. App Store bundle IDs: app `com.timetug.app.store`, widget `com.timetug.app.store.widgets`. Product name is `TimeTug` for both.
- This work does not choose or bump a version or cut a release; Scott decides the version when he makes the release. Never reuse the burned tag `v1.2.0`.
- Sparkle is linked, imported and started only in the direct build (`#if !APPSTORE`); the App Store build has no Sparkle dependency and no `SU*` Info.plist keys. Sparkle stays in the app layer only, never in Core.
- Ad-hoc builds (CI, no team) have no group container and no keychain group: every group path falls back to the old location or the legacy keychain, and must still run and pass tests.
- Core and the connector library stay unchanged. App-layer files import only Foundation, AppKit, SwiftUI, OSLog, Darwin and the existing app dependencies. `scripts/ci/check-architecture.sh` must keep passing.
- Known per-build state (not shared): the global shortcut (KeyboardShortcuts uses `UserDefaults.standard`), launch at login (`SMAppService`), Sparkle's own keys.
- Instance order: the build number (`CFBundleVersion`, a UTC timestamp shared by betas, releases and App Store uploads) decides which copy is newer. The version string is not used: a beta is named after the release it follows (`1.4.1-beta.<timestamp>` is built after `v1.4.1`), so semantic version order would rank it wrongly. A missing or unparseable build counts as 0. A locally built copy (version ending `-dev`) always outranks a stamped one, so a developer's own build replaces the installed app.
- Tests first: write the failing test, run it, then implement. App tests: `xcodegen generate --spec Apps/macOS/project.yml` then `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test -only-testing:TimeTugTests/<Class>`. `xcodegen` rewrites the checked-in Info.plists; restore them with `git checkout` before committing unless a task changes them on purpose.
- Commits end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Each phase is its own pull request to `master` (squash-merged, never merged locally), branched from an up-to-date `master` after the previous phase merged. Every merge to `master` publishes a beta to Sparkle users, so phase order is the order users receive the changes: do not merge phase 2 before phase 1 has shipped as a beta.
- Never print or commit secrets, certificates, provisioning profiles, `.p8` keys. CI secrets are repository or environment secrets only.

## Review Focus

- An existing user upgrading keeps every account: files are copied (never moved or overwritten) into the group, and a failed write of a credential to the shared keychain must not delete the legacy item (Tasks 1, 3).
- A second build starting for the first time must not overwrite group data written by the other build: group files and group defaults that already exist win (Tasks 1, 2).
- Two copies started at the same moment: exactly one gets the lock; the other exits; nobody runs twice (Tasks 10, 11).
- The holder's record is missing, unreadable or has an unparseable version while the lock is held: the newcomer exits instead of running a second copy (Tasks 9, 11).
- A stale or spoofed yield request (requester not newer than the holder) must not make the running copy quit (Task 11); a beta built after its release (same base version, later build number) must win over that release (Task 9).

---

## Phase 1: State moves into the App Group (ships in the direct build, still unsandboxed)

### Task 1: Files live in the group container

**Files:**
- Modify: `Apps/macOS/Sources/AppSupportFiles.swift`
- Modify: `Apps/macOS/Sources/LedgerStore.swift` (the `defaultURL` property)
- Modify: `Apps/macOS/Sources/DedupStateStore.swift` (the `defaultURL` property)
- Modify: `Apps/macOS/Sources/AppDelegate.swift`
- Create: `Apps/macOS/Tests/AppSupportFilesTests.swift`

**Interfaces:**
- Produces: `AppSupportFiles.names: [String]`; `legacyDirectory(fileManager:) -> URL`; `directory(groupContainer: URL?, legacy: URL) -> URL`; `url(_ name: String) -> URL`; `migrateLegacyFiles(from:to:fileManager:) -> [String]` (names copied); `migrateIfNeeded()`.

- [ ] **Step 1: Write the failing tests**

Create `Apps/macOS/Tests/AppSupportFilesTests.swift`:

```swift
import XCTest
@testable import TimeTug

final class AppSupportFilesTests: XCTestCase {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AppSupportFilesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func write(_ text: String, _ name: String, in dir: URL) throws {
        try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func read(_ name: String, in dir: URL) -> String? {
        try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
    }

    func testDirectoryUsesGroupContainerWhenPresent() {
        let group = URL(fileURLWithPath: "/tmp/group")
        let legacy = URL(fileURLWithPath: "/tmp/legacy")
        XCTAssertEqual(AppSupportFiles.directory(groupContainer: group, legacy: legacy).path, "/tmp/group/TimeTug")
    }

    func testDirectoryFallsBackToLegacyWithoutGroup() {
        let legacy = URL(fileURLWithPath: "/tmp/legacy")
        XCTAssertEqual(AppSupportFiles.directory(groupContainer: nil, legacy: legacy), legacy)
    }

    func testMigrationCopiesKnownFilesAndLeavesLegacyInPlace() throws {
        let legacy = try tempDirectory(), destination = try tempDirectory().appendingPathComponent("TimeTug")
        try write("A", "accounts.json", in: legacy)
        try write("L", "takeover-ledger.json", in: legacy)
        try write("X", "unrelated.txt", in: legacy)
        let copied = AppSupportFiles.migrateLegacyFiles(from: legacy, to: destination)
        XCTAssertEqual(Set(copied), ["accounts.json", "takeover-ledger.json"])
        XCTAssertEqual(read("accounts.json", in: destination), "A")
        XCTAssertEqual(read("takeover-ledger.json", in: destination), "L")
        XCTAssertNil(read("unrelated.txt", in: destination))
        XCTAssertEqual(read("accounts.json", in: legacy), "A")
    }

    func testMigrationNeverOverwritesAnExistingGroupFile() throws {
        let legacy = try tempDirectory(), destination = try tempDirectory()
        try write("old", "accounts.json", in: legacy)
        try write("new", "accounts.json", in: destination)
        XCTAssertEqual(AppSupportFiles.migrateLegacyFiles(from: legacy, to: destination), [])
        XCTAssertEqual(read("accounts.json", in: destination), "new")
    }

    func testMigrationIsANoOpWithoutLegacyFilesOrWhenFoldersAreTheSame() throws {
        let legacy = try tempDirectory(), destination = try tempDirectory()
        XCTAssertEqual(AppSupportFiles.migrateLegacyFiles(from: legacy, to: destination), [])
        try write("A", "accounts.json", in: legacy)
        XCTAssertEqual(AppSupportFiles.migrateLegacyFiles(from: legacy, to: legacy), [])
    }

    func testMigrationCopiesOnlyWhatIsMissingOnASecondRun() throws {
        let legacy = try tempDirectory(), destination = try tempDirectory()
        try write("A", "accounts.json", in: legacy)
        XCTAssertEqual(AppSupportFiles.migrateLegacyFiles(from: legacy, to: destination), ["accounts.json"])
        try write("S", "sync-state.json", in: legacy)
        XCTAssertEqual(AppSupportFiles.migrateLegacyFiles(from: legacy, to: destination), ["sync-state.json"])
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodegen generate --spec Apps/macOS/project.yml && xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test -only-testing:TimeTugTests/AppSupportFilesTests`
Expected: build FAILS ("type 'AppSupportFiles' has no member 'directory'" and similar).

- [ ] **Step 3: Replace `AppSupportFiles.swift`**

```swift
import Foundation
import OSLog

/// Where TimeTug keeps its files. A team-signed build uses `<App Group container>/TimeTug/`, shared by every TimeTug
/// build and companion app of the team; an ad-hoc build (no group container) keeps using
/// `~/Library/Application Support/TimeTug/`.
enum AppSupportFiles {
    /// Everything this folder holds; these are copied into the group container once.
    static let names = ["accounts.json", "sync-state.json", "takeover-ledger.json", "dedup-state.json"]
    private static let log = Logger(subsystem: "com.timetug.app", category: "migration")

    static func legacyDirectory(fileManager: FileManager = .default) -> URL {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("TimeTug", isDirectory: true)
    }

    static func directory(groupContainer: URL? = AppGroup.containerURL, legacy: URL = legacyDirectory()) -> URL {
        groupContainer?.appendingPathComponent("TimeTug", isDirectory: true) ?? legacy
    }

    static func url(_ name: String) -> URL { directory().appendingPathComponent(name) }

    /// Copies each known file that exists in `legacy` and not yet in `destination`; never overwrites, never deletes the
    /// original. A failed copy is logged and retried on the next launch. Returns the names copied.
    @discardableResult
    static func migrateLegacyFiles(from legacy: URL, to destination: URL, fileManager: FileManager = .default) -> [String] {
        guard legacy.standardizedFileURL != destination.standardizedFileURL else { return [] }
        var copied: [String] = []
        for name in names {
            let source = legacy.appendingPathComponent(name)
            let target = destination.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path), !fileManager.fileExists(atPath: target.path) else { continue }
            let partial = destination.appendingPathComponent(name + ".partial")
            do {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                try? fileManager.removeItem(at: partial)
                try fileManager.copyItem(at: source, to: partial)
                try fileManager.moveItem(at: partial, to: target)
                copied.append(name)
            } catch {
                log.error("Could not copy \(name, privacy: .public) into the App Group: \(String(describing: error), privacy: .public)")
            }
        }
        return copied
    }

    static func migrateIfNeeded() {
        migrateLegacyFiles(from: legacyDirectory(), to: directory())
    }
}
```

- [ ] **Step 4: Point the two stores at it**

In `LedgerStore.swift` replace the whole `static var defaultURL: URL { ... }` body with:

```swift
    /// `AppSupportFiles.url("takeover-ledger.json")`
    static var defaultURL: URL { AppSupportFiles.url("takeover-ledger.json") }
```

In `DedupStateStore.swift` replace its `defaultURL` the same way with `AppSupportFiles.url("dedup-state.json")` (keep the doc comment accurate).

- [ ] **Step 5: Migrate at launch**

Replace `AppDelegate.swift` with:

```swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        AppSupportFiles.migrateIfNeeded()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        Task { await coordinator.start() }
    }
}
```

- [ ] **Step 6: Run the new tests and the whole app suite**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test`
Expected: PASS, including `LedgerStoreTests` and `DedupStateStoreTests` (fix any test that asserted the old default path).

- [ ] **Step 7: Commit**

```bash
git checkout Apps/macOS/Sources/Info.plist Apps/macOS/Widgets/Info.plist
git add Apps/macOS/Sources Apps/macOS/Tests
git commit -m "Keep TimeTug's files in the App Group container, copying the old ones once

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 2: Preferences live in the group suite

**Files:**
- Create: `Apps/macOS/Sources/GroupDefaults.swift`
- Create: `Apps/macOS/Tests/GroupDefaultsTests.swift`
- Modify: `Apps/macOS/Sources/AppCoordinator.swift` (`settings`)
- Modify: `Apps/macOS/Sources/BrowserPreferringPresenter.swift` (line 16 default)
- Modify: `Apps/macOS/Sources/AppDelegate.swift`

**Interfaces:**
- Consumes: `AppGroup.identifier`; the `SettingsStore` keys `takeoverSettings.v1`, `menuBarMode.v1`, `appearanceMode.v1`, `popupCardStyle.v1`, `dedupInference.v1`, `eventKitEnabled.v1`; `BrowserPreferringPresenter.defaultsKey` (`oauth.useBrowser.v1`).
- Produces: `GroupDefaults.suite: UserDefaults`; `GroupDefaults.keys: [String]`; `GroupDefaults.migrate(from: UserDefaults, to: UserDefaults)`.

- [ ] **Step 1: Write the failing tests**

Create `Apps/macOS/Tests/GroupDefaultsTests.swift`:

```swift
import XCTest
@testable import TimeTug

final class GroupDefaultsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "GroupDefaultsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testCopiesKnownKeysThatAreMissingFromTheGroup() {
        let source = freshDefaults(), group = freshDefaults()
        source.set("countdown", forKey: "menuBarMode.v1")
        source.set(false, forKey: "eventKitEnabled.v1")
        GroupDefaults.migrate(from: source, to: group)
        XCTAssertEqual(group.string(forKey: "menuBarMode.v1"), "countdown")
        XCTAssertEqual(group.object(forKey: "eventKitEnabled.v1") as? Bool, false)
    }

    func testNeverOverwritesAValueAlreadyInTheGroup() {
        let source = freshDefaults(), group = freshDefaults()
        source.set("countdown", forKey: "menuBarMode.v1")
        group.set("iconOnly", forKey: "menuBarMode.v1")
        GroupDefaults.migrate(from: source, to: group)
        XCTAssertEqual(group.string(forKey: "menuBarMode.v1"), "iconOnly")
    }

    func testIgnoresUnknownKeys() {
        let source = freshDefaults(), group = freshDefaults()
        source.set("x", forKey: "SULastCheckTime")
        GroupDefaults.migrate(from: source, to: group)
        XCTAssertNil(group.object(forKey: "SULastCheckTime"))
    }

    func testRunsOncePerSource() {
        let source = freshDefaults(), group = freshDefaults()
        GroupDefaults.migrate(from: source, to: group)
        source.set("countdown", forKey: "menuBarMode.v1")
        GroupDefaults.migrate(from: source, to: group)
        XCTAssertNil(group.object(forKey: "menuBarMode.v1"))
    }

    func testSameStoreIsANoOp() {
        let defaults = freshDefaults()
        defaults.set("countdown", forKey: "menuBarMode.v1")
        GroupDefaults.migrate(from: defaults, to: defaults)
        XCTAssertEqual(defaults.string(forKey: "menuBarMode.v1"), "countdown")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodegen generate --spec Apps/macOS/project.yml && xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test -only-testing:TimeTugTests/GroupDefaultsTests`
Expected: build FAILS ("cannot find 'GroupDefaults' in scope").

- [ ] **Step 3: Implement**

Create `Apps/macOS/Sources/GroupDefaults.swift`:

```swift
import Foundation

/// The preferences every TimeTug build shares, stored in the App Group suite. Sparkle's keys, the beta opt-in and the
/// global shortcut stay in each build's own `UserDefaults.standard`.
enum GroupDefaults {
    static let suite = UserDefaults(suiteName: AppGroup.identifier) ?? .standard

    /// The keys that move. Keep in step with `SettingsStore` and `BrowserPreferringPresenter.defaultsKey`.
    static let keys = [
        "takeoverSettings.v1", "menuBarMode.v1", "appearanceMode.v1", "popupCardStyle.v1",
        "dedupInference.v1", "eventKitEnabled.v1", "oauth.useBrowser.v1",
    ]
    private static let migratedKey = "groupDefaultsMigrated.v1"

    /// Copies each known key from `source` that the group does not have yet. Runs once per source (the flag lives in
    /// `source`, so a second build with its own old values still gets its turn without ever overwriting the group).
    static func migrate(from source: UserDefaults, to group: UserDefaults) {
        guard source !== group, !source.bool(forKey: migratedKey) else { return }
        for key in keys where group.object(forKey: key) == nil {
            if let value = source.object(forKey: key) { group.set(value, forKey: key) }
        }
        source.set(true, forKey: migratedKey)
    }
}
```

- [ ] **Step 4: Wire it in**

In `AppCoordinator.swift` change `let settings = SettingsStore(shared: .appGroup)` to:

```swift
    let settings = SettingsStore(defaults: GroupDefaults.suite, shared: .appGroup)
```

In `BrowserPreferringPresenter.swift` change the default closure's `UserDefaults.standard.bool(...)` to `GroupDefaults.suite.bool(...)`.

In `AppDelegate.applicationWillFinishLaunching`, after `AppSupportFiles.migrateIfNeeded()` add:

```swift
        GroupDefaults.migrate(from: .standard, to: GroupDefaults.suite)
```

Leave `UpdateController.betaKey` on `UserDefaults.standard`: it is Sparkle's channel choice and exists only in the direct build.

- [ ] **Step 5: Run the whole app suite**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git checkout Apps/macOS/Sources/Info.plist Apps/macOS/Widgets/Info.plist
git add Apps/macOS/Sources Apps/macOS/Tests
git commit -m "Store preferences in the App Group suite, copying known keys once

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 3: Credentials in the shared keychain group (BLOCKED; deferred until a Developer ID profile exists)

**Status (2026-10-07):** the code was written and tried, then parked on the branch `app-store/keychain-group-wip` (`MigratingCredentialStore`, `KeychainCredentialStore.accessGroup`, `AppCredentials`, 9 passing tests). It does not ship in Phase 1.

**Why blocked:** `kSecAttrAccessGroup` with the app group id fails with `errSecMissingEntitlement` (-34018), sandboxed or not. The explicit `keychain-access-groups` entitlement is needed, it is a restricted entitlement, and it needs a provisioning profile. The Developer ID release pipeline signs without one. Only `application-groups` works profile-less (team-prefixed id). ADR 0019 records this.

**What changed in the code since this task was written:** `CredentialStore` now has `secrets`, `setSecrets`, `removeSecrets`, `credentialSnapshot` and `updateRefreshToken(_:for:expectedRevision:)`, and `KeychainCredentialStore` is an actor with per-credential revisions. The parked branch predates that and must be rebased onto it. One process is the credential authority, so sharing a keychain group needs Phase 4 (single instance) first.

**Until then:** each build keeps its own keychain item and signs in once. To unblock: add a Developer ID provisioning profile (with Keychain Sharing) to the release pipeline (`sign-app.sh`, the release workflow secrets), rebase `app-store/keychain-group-wip`, and write this task fresh against the current protocol. Do not do this before the Apple team question below is settled, because the group id and access group are team-prefixed.

Push the branch, open a PR to `master` titled "App Group state: files, preferences, credentials", wait for CI, squash-merge. Let the resulting beta reach your own Mac (Settings > Software Update > Beta updates) and confirm your accounts survive before starting phase 2.

---

## Phase 2: Sandbox both builds

### Task 4: Enable the sandbox in the direct build

**Files:**
- Modify: `Apps/macOS/project.yml` (main app entitlements and Info properties)
- Modify: `scripts/release/sign-app.sh` (only if the check in Step 4 shows the XPC services lose their entitlements)
- Modify: `docs/manual-tests/macos-checklist.md`
- Create: `docs/decisions/0019-shared-state-and-sandbox.md (created in PR #58, extended in PR #59)`

**Interfaces:**
- Consumes: Tasks 1 and 2 (state already in the group; Task 3 is deferred).
- Produces: a sandboxed, Sparkle-capable direct build; the manual checklist section "Sandbox"; the ADR that Tasks 6 and 13 extend.

- [ ] **Step 1: Turn on the sandbox**

In `project.yml`, `TimeTug` target `entitlements.properties`, add:

```yaml
        com.apple.security.app-sandbox: true
        com.apple.security.network.client: true
        com.apple.security.network.server: true
        com.apple.security.temporary-exception.mach-lookup.global-name:
          - com.timetug.app-spks
          - com.timetug.app-spki
```

(Done in PR #59. The ids must be literal: the release pipeline re-signs with the raw checked-in entitlements file, which does not expand `$(PRODUCT_BUNDLE_IDENTIFIER)`, and the variable made a sandboxed to sandboxed Sparkle update fail. The same applies to the App Store target's own bundle id.)

(`network.server` is for the OAuth loopback `NWListener` in `CalendarApple/LoopbackAuthorizationInteraction.swift`; the two `mach-lookup` names are Sparkle's installer-launcher and status services.) In the `info.properties` of the same target add `SUEnableInstallerLauncherService: true`. Before relying on these names, read Sparkle 2.10.0's "Sandboxing" documentation and correct any key that differs; note the source in the ADR.

- [ ] **Step 2: Build team-signed and run the sandbox checklist**

Append this section to `docs/manual-tests/macos-checklist.md` (and run every line on a team-signed build):

```markdown
## Sandbox
Watch denials while testing: `log stream --style compact --predicate 'eventMessage CONTAINS "deny(" AND eventMessage CONTAINS "TimeTug"'`. Expected output: nothing.
- [ ] Launches, shows the menu bar icon, no denial in the log.
- [ ] Apple Calendar: access prompt appears once; events show.
- [ ] Google sign-in (loopback redirect) completes and events show.
- [ ] Microsoft sign-in completes and events show.
- [ ] iCloud and Other CalDAV sign-in complete.
- [ ] iCal link account added and polled.
- [ ] A takeover appears for a test event (Settings > Test Tug) and its Join button opens the browser.
- [ ] Widgets and the Control Center controls update from the app.
- [ ] Settings changes survive quitting and relaunching; accounts survive too.
- [ ] Launch at login toggle works.
- [ ] Settings > Software Update > Check for Updates reaches a test appcast (see Step 3).
```

Fix each failure at its cause: a missing entitlement goes in `project.yml`; a path that assumed the real home directory goes through `AppSupportFiles`. Do not add `temporary-exception` file entitlements to make a failure go away. Record each fix in the ADR.

- [ ] **Step 3: Verify a Sparkle update from the unsandboxed 1.x to the sandboxed build**

1. Install the latest stable 1.x DMG (unsandboxed) into `/Applications`.
2. Build this version with a higher build number, sign it exactly like `beta.yml` does (`scripts/release/sign-app.sh`), zip it (`scripts/release/make-update-zip.sh`) and sign the zip (Sparkle `sign_update`, fetched by `scripts/release/fetch-sparkle-tools.sh`).
3. Serve a one-item appcast (`python3 -m http.server`) and launch the installed 1.x with `defaults write com.timetug.app SUFeedURL http://localhost:8000/appcast.xml`.
4. Click Check for Updates and install. Expected: the update installs, the new build launches sandboxed, and accounts and settings are intact. If it fails, stop: betas ship to real users on every merge, and the phase must not merge until this works. Reset the override afterwards with `defaults delete com.timetug.app SUFeedURL`.

- [ ] **Step 4: Check the signing script preserves the XPC services' entitlements**

Run: `scripts/ci/build-release.sh && scripts/release/sign-app.sh` (with the signing environment your local `release.yml` dry run uses, or read the script for the variables), then:
`codesign -d --entitlements :- dist/TimeTug.app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/*.xpc 2>&1 | head`
Expected: the services are signed with the hardened runtime. `sign-app.sh` already signs them with `--preserve-metadata=entitlements` (line 58); confirm and change nothing if so. Then run `scripts/release/verify-dmg.sh` on a DMG built from the result and add `com.apple.security.app-sandbox` to its checks (read the script and add the assertion in its existing style).

- [ ] **Step 5: Write ADR 0019**

Create `docs/decisions/0019-shared-state-and-sandbox.md (created in PR #58, extended in PR #59)` in the style of ADR 0010 (Status, Context, Decision, Consequences): Context = App Store needs the sandbox and a second app must share data; Decision = both builds sandboxed, all state in the group (files and suite now; keychain group once Task 3 is unblocked), separate bundle IDs, the per-build exceptions listed in Global Constraints, the entitlement list from Step 1 with its Sparkle source, and the outcome of this task's checklist; Consequences = users move to the sandbox container on upgrade (their data is already in the group), the global shortcut is per build.

- [ ] **Step 6: Run affected tests, commit, PR**

Run: `scripts/dev/affected-tests.sh --run` (Expected: PASS).

```bash
git checkout Apps/macOS/Sources/Info.plist Apps/macOS/Widgets/Info.plist
git add Apps/macOS docs scripts
git commit -m "Sandbox the app; keep Sparkle working inside it

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Open the phase 2 PR to `master`, wait for CI, squash-merge, and let the beta reach your Mac; confirm the in-app update from the previous beta works before phase 3.

---

## Phase 3: Direct and App Store targets

### Task 5: An updater seam for builds without Sparkle

**Files:**
- Create: `Apps/macOS/Sources/Distribution.swift`
- Create: `Apps/macOS/Sources/SparkleUpdater.swift`
- Modify: `Apps/macOS/Sources/UpdateController.swift` (move `SparkleUpdater` out; add `isAvailable`)
- Modify: `Apps/macOS/Sources/AppCoordinator.swift` (the `updates` property)
- Modify: `Apps/macOS/Sources/GeneralPane.swift` (line 30)
- Modify: `Apps/macOS/Sources/StatusItemController.swift` (`makeMenu`, `showMenu`)
- Modify: `Apps/macOS/Sources/SettingsSearch.swift` (update entries)
- Modify: `Apps/macOS/Tests/UpdateControllerTests.swift`, `Apps/macOS/Tests/StatusMenuTests.swift`, `Apps/macOS/Tests/SettingsSearchTests.swift`

**Interfaces:**
- Produces: `enum Distribution: String, Codable { case direct, appStore }` with `static var current`, `var supportsInAppUpdates: Bool`, `var label: String` ("downloaded" / "App Store"); `UpdateController.init(driver:defaults:currentVersion:isAvailable:)` (`isAvailable` defaults to `Distribution.current.supportsInAppUpdates`) and `let isAvailable: Bool`; `StatusItemController.makeMenu(target:about:checkForUpdates:settings:includesUpdates:)`; `SettingsSearch` entries omit the three update ids when updates are unavailable.

- [ ] **Step 1: Write the failing tests**

Add to `UpdateControllerTests.swift`:

```swift
    func testAvailabilityIsInjectable() {
        XCTAssertTrue(UpdateController(driver: FakeDriver(), defaults: freshDefaults(), currentVersion: "1", isAvailable: true).isAvailable)
        XCTAssertFalse(UpdateController(driver: FakeDriver(), defaults: freshDefaults(), currentVersion: "1", isAvailable: false).isAvailable)
    }

    func testDistributionLabelsAndUpdateSupport() {
        XCTAssertTrue(Distribution.direct.supportsInAppUpdates)
        XCTAssertFalse(Distribution.appStore.supportsInAppUpdates)
        XCTAssertEqual(Distribution.direct.label, "downloaded")
        XCTAssertEqual(Distribution.appStore.label, "App Store")
    }
```

Read `StatusMenuTests.swift` and `SettingsSearchTests.swift`, then add one test to each in their existing style: the menu built with `includesUpdates: false` has no item titled "Check for Updates…" and still has "About TimeTug", "Settings…" and "Quit TimeTug"; the search entries built for "updates unavailable" contain none of `software-update`, `automatic-updates`, `beta-updates`. (Add a `static func entries(includingUpdates: Bool)` to `SettingsSearch` for this; today's `static` entries list stays as `entries(includingUpdates: true)`.)

- [ ] **Step 2: Run to verify they fail**

Run: `xcodegen generate --spec Apps/macOS/project.yml && xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test -only-testing:TimeTugTests/UpdateControllerTests -only-testing:TimeTugTests/StatusMenuTests -only-testing:TimeTugTests/SettingsSearchTests`
Expected: build FAILS (missing `Distribution`, `isAvailable`, `includesUpdates`, `entries(includingUpdates:)`).

- [ ] **Step 3: Implement**

Create `Apps/macOS/Sources/Distribution.swift`:

```swift
import Foundation

/// How this build reached the Mac. The App Store build sets the `APPSTORE` compilation condition.
enum Distribution: String, Codable {
    case direct, appStore

    static var current: Distribution {
        #if APPSTORE
        .appStore
        #else
        .direct
        #endif
    }

    /// The App Store updates its own apps; Sparkle is not allowed there.
    var supportsInAppUpdates: Bool { self == .direct }

    /// How the build is named to the user ("another copy of TimeTug (App Store 2.0.0)").
    var label: String { self == .appStore ? "App Store" : "downloaded" }
}
```

Create `Apps/macOS/Sources/SparkleUpdater.swift` by moving the whole `SparkleUpdater` class out of `UpdateController.swift` verbatim and wrapping the file:

```swift
#if !APPSTORE
import Foundation
import Sparkle

// ... the SparkleUpdater class exactly as it is in UpdateController.swift today ...
#endif
```

In `UpdateController.swift` delete `import Sparkle` and the moved class. Add the stored property and initializer parameter:

```swift
    let isAvailable: Bool
    // in init, as a new last parameter with a default:
    //   isAvailable: Bool = Distribution.current.supportsInAppUpdates
    // and in the body:  self.isAvailable = isAvailable
```

In `AppCoordinator.swift` replace the `updates` property with:

```swift
    let updates = UpdateController(
        driver: AppCoordinator.makeUpdaterDriver(),
        currentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")

    private static func makeUpdaterDriver() -> UpdaterDriving {
        #if APPSTORE
        return NoOpUpdater()
        #else
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return NoOpUpdater() }
        return SparkleUpdater(includeBetas: { UserDefaults.standard.bool(forKey: UpdateController.betaKey) })
        #endif
    }
```

In `GeneralPane.swift` line 30 wrap the section: `if updates.isAvailable { UpdatesSection(updates: updates, navigation: navigation) }` (keep any surrounding modifiers on the same expression). In `StatusItemController.makeMenu` add the parameter `includesUpdates: Bool = true` and add the "Check for Updates…" item only when it is true; in `showMenu` pass `includesUpdates: Distribution.current.supportsInAppUpdates`. In `SettingsSearch.swift` add `entries(includingUpdates:)` as described and make the search read `entries(includingUpdates: Distribution.current.supportsInAppUpdates)`.

- [ ] **Step 4: Run the whole app suite**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git checkout Apps/macOS/Sources/Info.plist Apps/macOS/Widgets/Info.plist
git add Apps/macOS
git commit -m "Hide Software Update when the build has no in-app updater

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 6: The App Store target and widget

**Files:**
- Modify: `Apps/macOS/project.yml`
- Create: `Apps/macOS/AppStore/Info.plist` and `Apps/macOS/AppStore/Widgets-Info.plist` (generated by XcodeGen, then checked in like the direct plists)
- Create: `Apps/macOS/AppStore/TimeTugStore.entitlements` and `Apps/macOS/AppStore/TimeTugStoreWidgets.entitlements` (generated)
- Modify: `.github/workflows/ci.yml` (a new job)
- Modify: `AGENTS.md` (Commands, Gotchas: four generated plists)

**Interfaces:**
- Consumes: `Distribution` (Task 5), the sandbox entitlements (Task 4).
- Produces: schemes `TimeTug` (direct, unchanged) and `TimeTug-AppStore`; product `TimeTug.app` for both; the `APPSTORE` condition on the store targets only.

- [ ] **Step 1: Turn the app and widget targets into templates**

In `project.yml` replace the `targets: TimeTug:` and `TimeTugWidgets:` blocks with templates plus overrides. Keep the packages, `configFiles`, `settings` and `TimeTugTests` blocks as they are. The dependency list and Info properties are today's values; only the commented lines differ:

```yaml
targetTemplates:
  TimeTugAppBase:
    type: application
    platform: macOS
    sources:
      - path: Sources
        excludes: ["Info.plist", "*.entitlements"]
      - Resources
      - Shared
    dependencies:
      - package: TimeTugCore
        product: TimeTugCore
      - package: EventKitSource
        product: EventKitSource
      - package: AppleIntelligenceInference
        product: AppleIntelligenceInference
      - package: CalendarConnectors
        product: CalendarCore
      - package: CalendarConnectors
        product: GoogleCalendar
      - package: CalendarConnectors
        product: MicrosoftCalendar
      - package: CalendarConnectors
        product: CalDAVCalendar
      - package: CalendarConnectors
        product: ICalSubscription
      - package: CalendarBridge
        product: CalendarBridge
      - package: CalendarApple
        product: CalendarApple
      - package: KeyboardShortcuts
        product: KeyboardShortcuts
    info:
      properties:
        CFBundleName: TimeTug
        CFBundleShortVersionString: "0.0.0-dev"
        CFBundleVersion: "2"
        LSUIElement: true
        LSApplicationCategoryType: public.app-category.productivity
        ITSAppUsesNonExemptEncryption: false
        NSCalendarsFullAccessUsageDescription: TimeTug reads your calendars to alert you before meetings start.
        NSContactsUsageDescription: TimeTug looks up meeting attendees in Contacts to recognize the same meeting across your calendars.
        TimeTugGoogleClientID: $(GOOGLE_OAUTH_CLIENT_ID)
        TimeTugGoogleClientSecret: $(GOOGLE_OAUTH_CLIENT_SECRET)
        TimeTugMicrosoftClientID: $(MICROSOFT_OAUTH_CLIENT_ID)
    entitlements:
      properties:
        com.apple.security.app-sandbox: true
        com.apple.security.network.client: true
        com.apple.security.network.server: true
        com.apple.security.personal-information.calendars: true
        com.apple.security.personal-information.addressbook: true
        com.apple.security.application-groups: [YYA6ZKMD36.com.timetug.shared]
        keychain-access-groups: [YYA6ZKMD36.com.timetug.shared]
    settings:
      base:
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        PRODUCT_NAME: TimeTug
  TimeTugWidgetsBase:
    type: app-extension
    platform: macOS
    sources:
      - path: Widgets
        excludes: ["Info.plist", "*.entitlements"]
      - Shared
    dependencies:
      - package: TimeTugCore
        product: TimeTugCore
    info:
      properties:
        CFBundleName: TimeTugWidgets
        CFBundleDisplayName: TimeTug
        CFBundleShortVersionString: "0.0.0-dev"
        CFBundleVersion: "2"
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    entitlements:
      properties:
        com.apple.security.app-sandbox: true
        com.apple.security.application-groups: [YYA6ZKMD36.com.timetug.shared]

targets:
  TimeTug:
    templates: [TimeTugAppBase]
    dependencies:
      - target: TimeTugWidgets
      - package: Sparkle
        product: Sparkle
    info:
      path: Sources/Info.plist
      properties:
        SUFeedURL: https://darkarena1.github.io/timetug/appcast.xml
        SUPublicEDKey: QZXAO2hdupCAJzVJV0wqKHw3VPTjLDhQPGjJZDBlkzo=
        SUEnableAutomaticChecks: true
        SUEnableInstallerLauncherService: true
    entitlements:
      path: Sources/TimeTug.entitlements
      properties:
        com.apple.security.temporary-exception.mach-lookup.global-name:
          - $(PRODUCT_BUNDLE_IDENTIFIER)-spks
          - $(PRODUCT_BUNDLE_IDENTIFIER)-spki
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.timetug.app
  TimeTugWidgets:
    templates: [TimeTugWidgetsBase]
    info:
      path: Widgets/Info.plist
    entitlements:
      path: Widgets/TimeTugWidgets.entitlements
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.timetug.app.widgets
  TimeTug-AppStore:
    templates: [TimeTugAppBase]
    dependencies:
      - target: TimeTugWidgets-AppStore
    info:
      path: AppStore/Info.plist
    entitlements:
      path: AppStore/TimeTugStore.entitlements
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.timetug.app.store
        SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) APPSTORE"
  TimeTugWidgets-AppStore:
    templates: [TimeTugWidgetsBase]
    info:
      path: AppStore/Widgets-Info.plist
    entitlements:
      path: AppStore/TimeTugStoreWidgets.entitlements
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.timetug.app.store.widgets
  # TimeTugTests stays as it is and hosts the direct TimeTug target.
```

Keep the existing `TimeTugTests` target (move it under `targets:` unchanged). Run `xcodegen generate --spec Apps/macOS/project.yml` and fix any schema complaint (XcodeGen reports the key). The existing `TimeTug` scheme and `-scheme TimeTug` commands must work unchanged.

- [ ] **Step 2: Verify both targets build and differ as intended**

Run:
```bash
xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' -derivedDataPath build/direct build
xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug-AppStore -destination 'platform=macOS' -derivedDataPath build/store build
codesign -d --entitlements :- build/store/Build/Products/Debug/TimeTug.app 2>&1 | grep -c "mach-lookup"
ls build/store/Build/Products/Debug/TimeTug.app/Contents/Frameworks 2>/dev/null | grep -c Sparkle
/usr/libexec/PlistBuddy -c "Print :SUFeedURL" build/store/Build/Products/Debug/TimeTug.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" build/store/Build/Products/Debug/TimeTug.app/Contents/Info.plist
```
Expected: both builds succeed; the two `grep -c` print `0`; `SUFeedURL` is "Does Not Exist"; the bundle id is `com.timetug.app.store`. Then run the full app tests on the direct scheme (Expected: PASS).

- [ ] **Step 3: Check the shared state really is shared (by hand, team-signed)**

Build both team-signed (`Local.xcconfig` present), copy one under a different name so both can sit in `/Applications` (`TimeTug.app` and `TimeTug Store.app`), run the direct one, add an iCal link account and change the menu bar mode, quit it, run the store one. Expected: the same account and setting appear, with no new sign-in. This proves files, the suite and the keychain group are shared across bundle IDs; if the account is missing, the keychain group entitlement or profile for `com.timetug.app.store` is wrong (portal step in Scott's checklist below).

- [ ] **Step 4: Add a CI job that builds the store target**

In `.github/workflows/ci.yml` add, after the `app` job, and add it to the header comment's job list:

```yaml
  app-store-build:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v7
      - name: Select newest Xcode
        run: scripts/ci/select-xcode.sh
      - name: Install XcodeGen
        run: brew install xcodegen
      - name: Generate Xcode project
        run: xcodegen generate --spec Apps/macOS/project.yml
      - name: Build the App Store target (unsigned)
        run: |
          set -o pipefail
          xcodebuild \
            -project Apps/macOS/TimeTug.xcodeproj \
            -scheme TimeTug-AppStore \
            -destination 'platform=macOS' \
            -derivedDataPath build/DerivedData-store \
            CODE_SIGNING_ALLOWED=NO \
            build
      - name: The App Store build has no Sparkle
        run: |
          app=build/DerivedData-store/Build/Products/Debug/TimeTug.app
          test ! -e "$app/Contents/Frameworks/Sparkle.framework"
          ! /usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$app/Contents/Info.plist" 2>/dev/null
```

- [ ] **Step 5: Update `AGENTS.md`**

In the Layout section, change the `Apps/macOS` line to mention the two targets (`TimeTug` direct and `TimeTug-AppStore`, one template, `APPSTORE` condition, `Distribution`). In Gotchas change "the two checked-in Info.plists" to "the four checked-in Info.plists (`Sources`, `Widgets`, `AppStore`, `AppStore/Widgets-Info`)" and add the three new generated entitlements files. In Commands add the store build command from Step 2.

- [ ] **Step 6: Commit**

```bash
git checkout Apps/macOS/Sources/Info.plist Apps/macOS/Widgets/Info.plist
git add Apps/macOS .github AGENTS.md
git commit -m "Add the App Store app and widget targets from one XcodeGen template

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

(After a regenerate the four plists may differ only if you changed properties on purpose; commit the new `AppStore/*` ones, and restore the direct pair as shown.)

### Task 7: Archive and upload the App Store build

**Files:**
- Create: `scripts/release/build-appstore.sh`
- Create: `scripts/release/tests/test-build-appstore.sh`
- Create: `.github/workflows/appstore.yml`
- Modify: `docs/release.md` (new section "App Store")

**Interfaces:**
- Consumes: the `TimeTug-AppStore` scheme (Task 6), `scripts/ci/compute-versions.sh` for the build number.
- Produces: `scripts/release/build-appstore.sh` with env `APP_VERSION` (`X.Y.Z`, no suffix), `BUILD_NUMBER`, `DESTINATION` (`export` or `upload`), `TEAM_ID` (default `YYA6ZKMD36`), and for `upload` `ASC_KEY_PATH`, `ASC_KEY_ID`, `ASC_ISSUER_ID`; a manually dispatched workflow `App Store`.

- [ ] **Step 1: Write the failing test of the script's input checks**

Create `scripts/release/tests/test-build-appstore.sh`, in the style of the other tests in that folder (read one first):

```bash
#!/usr/bin/env bash
# Tests the input validation of scripts/release/build-appstore.sh (no Xcode, no secrets).
set -uo pipefail
cd "$(dirname "$0")/../../.."
script=scripts/release/build-appstore.sh
fail=0
expect_fail() { # expect_fail <label> <expected message fragment> <env assignments...>
  local label="$1" fragment="$2"; shift 2
  out="$(env "$@" DRY_RUN=1 "$script" 2>&1)" && { echo "FAIL $label: expected an error"; fail=1; return; }
  case "$out" in *"$fragment"*) echo "ok   $label" ;; *) echo "FAIL $label: got: $out"; fail=1 ;; esac
}
expect_fail "beta suffix refused" "App Store versions must be X.Y.Z" APP_VERSION=2.0.0-beta.1 BUILD_NUMBER=20261006010101
expect_fail "missing version" "APP_VERSION is required" BUILD_NUMBER=20261006010101
expect_fail "missing build number" "BUILD_NUMBER is required" APP_VERSION=2.0.0
expect_fail "upload needs a key" "ASC_KEY_PATH is required for upload" APP_VERSION=2.0.0 BUILD_NUMBER=20261006010101 DESTINATION=upload
out="$(APP_VERSION=2.0.0 BUILD_NUMBER=20261006010101 DESTINATION=export DRY_RUN=1 "$script" 2>&1)" || { echo "FAIL valid input: $out"; fail=1; }
exit "$fail"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash scripts/release/tests/test-build-appstore.sh`
Expected: FAIL (the script does not exist).

- [ ] **Step 3: Write the script**

Create `scripts/release/build-appstore.sh` (mode 755):

```bash
#!/usr/bin/env bash
# Archive the App Store target and export it, or upload it to App Store Connect.
#
# Environment:
#   APP_VERSION     X.Y.Z, no suffix (the App Store rejects pre-release versions; betas go to TestFlight as X.Y.Z too)
#   BUILD_NUMBER    CFBundleVersion; must increase on every upload (scripts/ci/compute-versions.sh makes one)
#   DESTINATION     export (default: writes dist/appstore/TimeTug.pkg) or upload (sends it to App Store Connect)
#   TEAM_ID         default YYA6ZKMD36
#   ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID   App Store Connect API key, required for upload
#   DRY_RUN=1       validate the inputs and stop
# The Apple Distribution and Mac Installer certificates and the two App Store provisioning profiles (app and
# widget) must already be installed in the keychain / ~/Library/MobileDevice/Provisioning Profiles.
set -euo pipefail
cd "$(dirname "$0")/../.."

: "${APP_VERSION:?APP_VERSION is required}"
: "${BUILD_NUMBER:?BUILD_NUMBER is required}"
DESTINATION="${DESTINATION:-export}"
TEAM_ID="${TEAM_ID:-YYA6ZKMD36}"
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: App Store versions must be X.Y.Z, got '$APP_VERSION'" >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "error: BUILD_NUMBER must be digits, got '$BUILD_NUMBER'" >&2; exit 1; }
case "$DESTINATION" in export|upload) ;; *) echo "error: DESTINATION must be export or upload" >&2; exit 1 ;; esac
if [ "$DESTINATION" = upload ]; then
  : "${ASC_KEY_PATH:?ASC_KEY_PATH is required for upload}"
  : "${ASC_KEY_ID:?ASC_KEY_ID is required for upload}"
  : "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required for upload}"
fi
[ -z "${DRY_RUN:-}" ] || { echo "inputs ok"; exit 0; }

BUILD_DIR="${BUILD_DIR:-build}"
OUT="dist/appstore"
rm -rf "$BUILD_DIR/appstore.xcarchive" "$OUT"
mkdir -p "$OUT"
xcodegen generate --spec Apps/macOS/project.yml

xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug-AppStore -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$BUILD_DIR/appstore.xcarchive" \
  MARKETING_VERSION="$APP_VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Distribution" DEVELOPMENT_TEAM="$TEAM_ID" \
  archive

cat > "$BUILD_DIR/ExportOptions-AppStore.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>installerSigningCertificate</key><string>3rd Party Mac Developer Installer</string>
  <key>provisioningProfiles</key><dict>
    <key>com.timetug.app.store</key><string>TimeTug App Store</string>
    <key>com.timetug.app.store.widgets</key><string>TimeTug Widgets App Store</string>
  </dict>
  <key>destination</key><string>$([ "$DESTINATION" = upload ] && echo upload || echo export)</string>
</dict></plist>
PLIST

auth=()
if [ "$DESTINATION" = upload ]; then
  auth=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi
xcodebuild -exportArchive -archivePath "$BUILD_DIR/appstore.xcarchive" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions-AppStore.plist" -exportPath "$OUT" "${auth[@]}"
echo "done: $DESTINATION ($OUT)"
```

The profile names above are the names you give them in the developer portal (Scott's checklist); keep the two in step.

- [ ] **Step 4: Run to verify it passes**

Run: `chmod +x scripts/release/build-appstore.sh scripts/release/tests/test-build-appstore.sh && bash scripts/release/tests/test-build-appstore.sh`
Expected: five `ok`/silent lines and exit 0. Add the test to the `architecture` job's script-test step in `ci.yml` (read how the other `scripts/release/tests` are run and add this one the same way) and to `scripts/dev/affected-tests.sh` if it lists script tests explicitly.

- [ ] **Step 5: Add the workflow**

Create `.github/workflows/appstore.yml`:

```yaml
# Builds the App Store target, signs it with the Apple Distribution certificate and uploads it to App Store Connect
# (TestFlight, then review). Manual only: run it from the Actions tab with the stable version to upload. Needs the
# `appstore` environment (required reviewer) and its secrets; see docs/release.md "App Store".
name: App Store

on:
  workflow_dispatch:
    inputs:
      version:
        description: Stable version X.Y.Z (no suffix), e.g. 2.0.0
        required: true

permissions:
  contents: read

jobs:
  upload:
    runs-on: macos-26
    environment: appstore
    steps:
      - uses: actions/checkout@v7
      - name: Select newest Xcode
        run: scripts/ci/select-xcode.sh
      - name: Install XcodeGen
        run: brew install xcodegen
      - name: Install signing material
        env:
          DISTRIBUTION_CERT_P12: ${{ secrets.APPSTORE_DISTRIBUTION_CERT_P12 }}
          INSTALLER_CERT_P12: ${{ secrets.APPSTORE_INSTALLER_CERT_P12 }}
          CERT_PASSWORD: ${{ secrets.APPSTORE_CERT_PASSWORD }}
          APP_PROFILE: ${{ secrets.APPSTORE_APP_PROFILE }}
          WIDGET_PROFILE: ${{ secrets.APPSTORE_WIDGET_PROFILE }}
        run: |
          # Same temporary-keychain steps as the Developer ID import in release.yml; read them there and keep the
          # two in step (this job imports two certificates instead of one).
          security create-keychain -p "$RUNNER_TEMP" build.keychain
          security default-keychain -s build.keychain
          security unlock-keychain -p "$RUNNER_TEMP" build.keychain
          for cert in DISTRIBUTION_CERT_P12 INSTALLER_CERT_P12; do
            echo "${!cert}" | base64 --decode > "$RUNNER_TEMP/$cert.p12"
            security import "$RUNNER_TEMP/$cert.p12" -k build.keychain -P "$CERT_PASSWORD" -T /usr/bin/codesign -T /usr/bin/productbuild
          done
          security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$RUNNER_TEMP" build.keychain
          mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
          echo "$APP_PROFILE" | base64 --decode > "$HOME/Library/MobileDevice/Provisioning Profiles/app.provisionprofile"
          echo "$WIDGET_PROFILE" | base64 --decode > "$HOME/Library/MobileDevice/Provisioning Profiles/widget.provisionprofile"
      - name: Archive and upload
        env:
          APP_VERSION: ${{ inputs.version }}
          DESTINATION: upload
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          ASC_KEY_B64: ${{ secrets.ASC_KEY_P8 }}
        run: |
          export BUILD_NUMBER="$(date -u +%Y%m%d%H%M%S)"
          export ASC_KEY_PATH="$RUNNER_TEMP/AuthKey.p8"
          echo "$ASC_KEY_B64" | base64 --decode > "$ASC_KEY_PATH"
          scripts/release/build-appstore.sh
      - name: Remove signing material
        if: always()
        run: |
          security delete-keychain build.keychain || true
          rm -f "$RUNNER_TEMP"/*.p12 "$RUNNER_TEMP/AuthKey.p8"
          rm -rf "$HOME/Library/MobileDevice/Provisioning Profiles"
```

Before merging, check the `BUILD_NUMBER` choice against App Store Connect's rule (build must increase and be a dot-separated integer string): the first TestFlight upload tells you; if 14 digits is refused, switch to a counter stored in a repository variable and record it in `docs/release.md`.

- [ ] **Step 6: Document it**

Add an "App Store" section to `docs/release.md`: what the workflow does and why it is manual; the required secrets by name (`APPSTORE_DISTRIBUTION_CERT_P12`, `APPSTORE_INSTALLER_CERT_P12`, `APPSTORE_CERT_PASSWORD`, `APPSTORE_APP_PROFILE`, `APPSTORE_WIDGET_PROFILE`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`) in the `appstore` environment; that the version must be a stable `X.Y.Z` equal to a published stable tag; that TestFlight replaces the Sparkle beta channel for this build.

- [ ] **Step 7: Commit, PR**

```bash
git add scripts .github docs
git commit -m "Add the App Store archive and upload script and a manual workflow

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Open the phase 3 PR to `master` (Tasks 5 to 7), wait for CI (including the new `app-store-build` job), squash-merge.

---

## Phase 4: One running instance, newest wins

### Task 8: (dropped)

Was a semantic `AppVersion` type. Removed: the build number orders every channel (see Global Constraints), so no version parsing is needed. Task 9 carries the build-number rule and its tests.

### Task 9: The arbitration decision

**Files:**
- Create: `Apps/macOS/Sources/InstanceArbitration.swift`
- Create: `Apps/macOS/Tests/InstanceArbitrationTests.swift`

**Interfaces:**
- Consumes: `AppVersion` (Task 8), `Distribution` (Task 5).
- Produces: `struct InstanceInfo: Codable, Equatable { bundleID: String; version: String; build: String; distribution: Distribution; static var current: InstanceInfo }`; `enum InstanceArbitration { enum Decision { case askHolderToQuit, exit }; static func isNewer(_ a: InstanceInfo, than b: InstanceInfo) -> Bool; static func decide(me: InstanceInfo, holder: InstanceInfo?) -> Decision }`.

- [ ] **Step 1: Write the failing tests**

Create `Apps/macOS/Tests/InstanceArbitrationTests.swift`:

```swift
import XCTest
@testable import TimeTug

final class InstanceArbitrationTests: XCTestCase {
    private func info(_ version: String, build: String = "1", _ distribution: Distribution = .direct) -> InstanceInfo {
        InstanceInfo(bundleID: "com.timetug.app", version: version, build: build, distribution: distribution)
    }

    func testNewerVersionWins() {
        XCTAssertTrue(InstanceArbitration.isNewer(info("2.0.0"), than: info("1.4.1")))
        XCTAssertFalse(InstanceArbitration.isNewer(info("1.4.1"), than: info("2.0.0")))
    }

    func testBuildNumberBreaksAVersionTie() {
        XCTAssertTrue(InstanceArbitration.isNewer(info("2.0.0", build: "20261006010101"), than: info("2.0.0", build: "20261005010101")))
        XCTAssertFalse(InstanceArbitration.isNewer(info("2.0.0", build: "5"), than: info("2.0.0", build: "5")))
    }

    func testBuildNumbersCompareByValueNotText() {
        XCTAssertTrue(InstanceArbitration.isNewer(info("2.0.0", build: "10"), than: info("2.0.0", build: "9")))
    }

    func testStableBeatsABetaOfTheSameBase() {
        XCTAssertTrue(InstanceArbitration.isNewer(info("1.4.1"), than: info("1.4.1-beta.20261001000000", build: "99999999999999")))
    }

    func testAnUnparseableVersionLosesToAParseableOne() {
        XCTAssertTrue(InstanceArbitration.isNewer(info("1.0.0"), than: info("?")))
        XCTAssertFalse(InstanceArbitration.isNewer(info("?"), than: info("1.0.0")))
    }

    func testTwoUnparseableVersionsAreEqual() {
        XCTAssertFalse(InstanceArbitration.isNewer(info("?", build: "1"), than: info("?", build: "1")))
    }

    func testANewerNewcomerAsksTheHolderToQuit() {
        XCTAssertEqual(InstanceArbitration.decide(me: info("2.0.0"), holder: info("1.4.1")), .askHolderToQuit)
    }

    func testAnOlderOrEqualNewcomerExits() {
        XCTAssertEqual(InstanceArbitration.decide(me: info("1.4.1"), holder: info("2.0.0")), .exit)
        XCTAssertEqual(InstanceArbitration.decide(me: info("2.0.0"), holder: info("2.0.0")), .exit)
    }

    func testAnUnknownHolderMeansTheNewcomerExits() {
        XCTAssertEqual(InstanceArbitration.decide(me: info("2.0.0"), holder: nil), .exit)
    }

    func testDistributionDoesNotChangeTheOrder() {
        XCTAssertEqual(InstanceArbitration.decide(me: info("2.0.0", .appStore), holder: info("1.9.0", .direct)), .askHolderToQuit)
        XCTAssertEqual(InstanceArbitration.decide(me: info("1.9.0", .direct), holder: info("2.0.0", .appStore)), .exit)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodegen generate --spec Apps/macOS/project.yml && xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test -only-testing:TimeTugTests/InstanceArbitrationTests`
Expected: build FAILS (`InstanceInfo` not found).

- [ ] **Step 3: Implement**

Create `Apps/macOS/Sources/InstanceArbitration.swift`:

```swift
import Foundation

/// Who a running (or starting) TimeTug is. Written next to the instance lock so a newcomer can compare itself with the
/// holder.
struct InstanceInfo: Codable, Equatable {
    let bundleID: String
    let version: String
    let build: String
    let distribution: Distribution

    static var current: InstanceInfo {
        let bundle = Bundle.main
        return InstanceInfo(
            bundleID: bundle.bundleIdentifier ?? "com.timetug.app",
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            distribution: .current)
    }
}

/// Which of two TimeTug copies keeps running: the newer version; the build number breaks a tie.
enum InstanceArbitration {
    enum Decision: Equatable {
        /// The newcomer is newer: ask the running copy to quit, then take over.
        case askHolderToQuit
        /// The newcomer is older, equal, or the holder is unknown: the newcomer leaves.
        case exit
    }

    static func isNewer(_ a: InstanceInfo, than b: InstanceInfo) -> Bool {
        switch (AppVersion(a.version), AppVersion(b.version)) {
        case let (x?, y?) where x != y: return x > y
        case (.some, .none): return true
        case (.none, .some): return false
        default: return (Int(a.build) ?? 0) > (Int(b.build) ?? 0)
        }
    }

    static func decide(me: InstanceInfo, holder: InstanceInfo?) -> Decision {
        guard let holder else { return .exit }
        return isNewer(me, than: holder) ? .askHolderToQuit : .exit
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: the Step 2 command. Expected: PASS (10 tests).

- [ ] **Step 5: Commit**

```bash
git checkout Apps/macOS/Sources/Info.plist Apps/macOS/Widgets/Info.plist
git add Apps/macOS
git commit -m "Decide which TimeTug copy keeps running

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 10: The instance lock and its files

**Files:**
- Create: `Apps/macOS/Sources/InstanceFiles.swift`
- Create: `Apps/macOS/Tests/InstanceFilesTests.swift`

**Interfaces:**
- Consumes: `InstanceInfo` (Task 9), `AppSupportFiles.directory()`.
- Produces: `final class InstanceLock { static func acquire(at: URL) -> InstanceLock? }` (held until deallocated or process exit); `struct InstanceFiles { init(directory: URL); static var `default`: InstanceFiles; var lockURL, recordURL, handoffURL, collisionURL: URL; func read(_ url: URL) -> InstanceInfo?; func write(_ info: InstanceInfo, to url: URL) }`.

- [ ] **Step 1: Write the failing tests**

Create `Apps/macOS/Tests/InstanceFilesTests.swift`:

```swift
import XCTest
@testable import TimeTug

final class InstanceFilesTests: XCTestCase {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("InstanceFilesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testOnlyOneHolderAtATime() throws {
        let files = InstanceFiles(directory: try tempDirectory())
        var first = InstanceLock.acquire(at: files.lockURL)
        XCTAssertNotNil(first)
        XCTAssertNil(InstanceLock.acquire(at: files.lockURL))
        first = nil
        XCTAssertNotNil(InstanceLock.acquire(at: files.lockURL))
    }

    func testAcquireCreatesTheDirectory() throws {
        let nested = try tempDirectory().appendingPathComponent("a/b", isDirectory: true)
        XCTAssertNotNil(InstanceLock.acquire(at: InstanceFiles(directory: nested).lockURL))
    }

    func testRecordsRoundTrip() throws {
        let files = InstanceFiles(directory: try tempDirectory())
        let info = InstanceInfo(bundleID: "com.timetug.app", version: "2.0.0", build: "7", distribution: .appStore)
        files.write(info, to: files.recordURL)
        XCTAssertEqual(files.read(files.recordURL), info)
    }

    func testMissingOrCorruptRecordsReadAsNil() throws {
        let files = InstanceFiles(directory: try tempDirectory())
        XCTAssertNil(files.read(files.recordURL))
        try "not json".write(to: files.recordURL, atomically: true, encoding: .utf8)
        XCTAssertNil(files.read(files.recordURL))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodegen generate --spec Apps/macOS/project.yml && xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test -only-testing:TimeTugTests/InstanceFilesTests`
Expected: build FAILS (`InstanceFiles` not found).

- [ ] **Step 3: Implement**

Create `Apps/macOS/Sources/InstanceFiles.swift`:

```swift
import Darwin
import Foundation

/// An exclusive advisory lock on a file. Held until the object is released or the process ends, so a crash never
/// leaves a stale lock.
final class InstanceLock {
    private let descriptor: Int32

    private init(descriptor: Int32) { self.descriptor = descriptor }

    /// nil when another process (or another holder in this one) has the lock, or the file cannot be opened.
    static func acquire(at url: URL) -> InstanceLock? {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        return InstanceLock(descriptor: descriptor)
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}

/// The small files the instances use to find each other, all in one folder.
struct InstanceFiles {
    let directory: URL

    init(directory: URL) { self.directory = directory }

    /// The same folder the app's other state lives in, so an ad-hoc dev build never collides with an installed one.
    static var `default`: InstanceFiles { InstanceFiles(directory: AppSupportFiles.directory()) }

    var lockURL: URL { directory.appendingPathComponent("instance.lock") }
    /// Who holds the lock.
    var recordURL: URL { directory.appendingPathComponent("instance.json") }
    /// A newcomer's request that the holder quit (the newcomer's own info).
    var handoffURL: URL { directory.appendingPathComponent("instance-handoff.json") }
    /// A copy that was opened and left; the survivor shows the notice about it.
    var collisionURL: URL { directory.appendingPathComponent("instance-collision.json") }

    func read(_ url: URL) -> InstanceInfo? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(InstanceInfo.self, from: $0) }
    }

    func write(_ info: InstanceInfo, to url: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(info).write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: the Step 2 command. Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git checkout Apps/macOS/Sources/Info.plist Apps/macOS/Widgets/Info.plist
git add Apps/macOS
git commit -m "Add the instance lock and the files copies use to find each other

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 11: The launch-time arbiter and its signals

**Files:**
- Create: `Apps/macOS/Sources/InstanceArbiter.swift`
- Create: `Apps/macOS/Sources/InstanceSignals.swift`
- Create: `Apps/macOS/Tests/InstanceArbiterTests.swift`
- Modify: `Apps/macOS/Sources/AppDelegate.swift`

**Interfaces:**
- Consumes: `InstanceInfo`, `InstanceArbitration`, `InstanceLock`, `InstanceFiles` (Tasks 9, 10).
- Produces: `protocol InstanceSignaling { func postYield(); func postCollision() }`; `final class InstanceArbiter { enum Outcome: Equatable { case run(collidedWith: InstanceInfo?), exit }; init(me:files:signals:attempts:pause:); func arbitrate() -> Outcome; func shouldYield() -> Bool; func release() }`; `struct InstanceSignals: InstanceSignaling` with `static let yieldName`, `collisionName`, `final class Observer`.

- [ ] **Step 1: Write the failing tests**

Create `Apps/macOS/Tests/InstanceArbiterTests.swift`:

```swift
import XCTest
@testable import TimeTug

final class InstanceArbiterTests: XCTestCase {
    private final class FakeSignals: InstanceSignaling {
        var yields = 0, collisions = 0
        func postYield() { yields += 1 }
        func postCollision() { collisions += 1 }
    }

    private func tempFiles() throws -> InstanceFiles {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("InstanceArbiterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return InstanceFiles(directory: url)
    }

    private func info(_ version: String, _ distribution: Distribution = .direct) -> InstanceInfo {
        InstanceInfo(bundleID: distribution == .direct ? "com.timetug.app" : "com.timetug.app.store",
                     version: version, build: "1", distribution: distribution)
    }

    private func arbiter(_ me: InstanceInfo, _ files: InstanceFiles, _ signals: FakeSignals = FakeSignals(),
                         attempts: Int = 5, pause: @escaping () -> Void = {}) -> InstanceArbiter {
        InstanceArbiter(me: me, files: files, signals: signals, attempts: attempts, pause: pause)
    }

    func testFirstInstanceRunsAndRecordsItself() throws {
        let files = try tempFiles()
        let first = arbiter(info("1.4.1"), files)
        XCTAssertEqual(first.arbitrate(), .run(collidedWith: nil))
        XCTAssertEqual(files.read(files.recordURL), info("1.4.1"))
    }

    func testOlderNewcomerExitsAndLeavesANoticeForTheHolder() throws {
        let files = try tempFiles(), signals = FakeSignals()
        let holder = arbiter(info("2.0.0"), files)
        _ = holder.arbitrate()
        let newcomer = arbiter(info("1.4.1"), files, signals)
        XCTAssertEqual(newcomer.arbitrate(), .exit)
        XCTAssertEqual(files.read(files.collisionURL), info("1.4.1"))
        XCTAssertEqual(signals.collisions, 1)
        XCTAssertEqual(signals.yields, 0)
    }

    func testNewerNewcomerAsksTheHolderToQuitThenTakesOver() throws {
        let files = try tempFiles(), signals = FakeSignals()
        let holder = arbiter(info("1.4.1"), files)
        _ = holder.arbitrate()
        var pauses = 0
        let newcomer = arbiter(info("2.0.0", .appStore), files, signals, pause: {
            pauses += 1
            if pauses == 2 { holder.release() }
        })
        XCTAssertEqual(newcomer.arbitrate(), .run(collidedWith: info("1.4.1")))
        XCTAssertEqual(signals.yields, 1)
        XCTAssertEqual(files.read(files.handoffURL), info("2.0.0", .appStore))
        XCTAssertEqual(files.read(files.recordURL), info("2.0.0", .appStore))
    }

    func testNewcomerGivesUpWhenTheHolderNeverQuits() throws {
        let files = try tempFiles(), signals = FakeSignals()
        let holder = arbiter(info("1.4.1"), files)
        _ = holder.arbitrate()
        let newcomer = arbiter(info("2.0.0"), files, signals, attempts: 3)
        XCTAssertEqual(newcomer.arbitrate(), .exit)
        XCTAssertEqual(signals.collisions, 1)
    }

    func testMissingHolderRecordMakesTheNewcomerExit() throws {
        let files = try tempFiles()
        let holder = arbiter(info("1.4.1"), files)
        _ = holder.arbitrate()
        try FileManager.default.removeItem(at: files.recordURL)
        XCTAssertEqual(arbiter(info("2.0.0"), files).arbitrate(), .exit)
    }

    func testTheHolderYieldsToANewerRequesterOnly() throws {
        let files = try tempFiles()
        let holder = arbiter(info("2.0.0"), files)
        _ = holder.arbitrate()
        XCTAssertFalse(holder.shouldYield(), "no request on file")
        files.write(info("1.4.1"), to: files.handoffURL)
        XCTAssertFalse(holder.shouldYield(), "an older requester must not make the running copy quit")
        files.write(info("2.0.0"), to: files.handoffURL)
        XCTAssertFalse(holder.shouldYield(), "an equal requester must not either")
        files.write(info("2.1.0"), to: files.handoffURL)
        XCTAssertTrue(holder.shouldYield())
    }

    func testReleasingTheLockLetsAnotherInstanceIn() throws {
        let files = try tempFiles()
        let first = arbiter(info("1.0.0"), files)
        _ = first.arbitrate()
        first.release()
        XCTAssertEqual(arbiter(info("1.0.0"), files).arbitrate(), .run(collidedWith: nil))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodegen generate --spec Apps/macOS/project.yml && xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test -only-testing:TimeTugTests/InstanceArbiterTests`
Expected: build FAILS (`InstanceArbiter`, `InstanceSignaling` not found).

- [ ] **Step 3: Implement the signals**

Create `Apps/macOS/Sources/InstanceSignals.swift`:

```swift
import Foundation

protocol InstanceSignaling {
    func postYield()
    func postCollision()
}

/// Cross-process nudges between TimeTug copies, as Darwin notifications (no payload; the data is in `InstanceFiles`).
struct InstanceSignals: InstanceSignaling {
    static let yieldName = "com.timetug.instance.yield"
    static let collisionName = "com.timetug.instance.collision"

    func postYield() { Self.post(Self.yieldName) }
    func postCollision() { Self.post(Self.collisionName) }

    private static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }

    /// The handler may run on any thread. Keep the observer alive for the process lifetime.
    final class Observer {
        private let name: String
        private let handler: () -> Void

        init(name: String, handler: @escaping () -> Void) {
            self.name = name
            self.handler = handler
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
                { _, observer, _, _, _ in
                    guard let observer else { return }
                    Unmanaged<Observer>.fromOpaque(observer).takeUnretainedValue().handler()
                },
                name as CFString, nil, .deliverImmediately)
        }

        deinit {
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(), nil, nil)
        }
    }
}
```

- [ ] **Step 4: Implement the arbiter**

Create `Apps/macOS/Sources/InstanceArbiter.swift`:

```swift
import Foundation

/// Makes sure only one TimeTug runs. Call `arbitrate()` first thing at launch, before any window, status item or
/// calendar read; on `.exit` the process must end without doing anything else.
final class InstanceArbiter {
    enum Outcome: Equatable {
        /// This copy runs. `collidedWith` is the copy it replaced, if any (for the notice).
        case run(collidedWith: InstanceInfo?)
        case exit
    }

    private let me: InstanceInfo
    private let files: InstanceFiles
    private let signals: InstanceSignaling
    private let attempts: Int
    private let pause: () -> Void
    private var lock: InstanceLock?

    /// Waits up to `attempts` x `pause` (50 x 0.1 s = 5 s by default) for the holder to quit.
    init(me: InstanceInfo = .current, files: InstanceFiles = .default, signals: InstanceSignaling = InstanceSignals(),
         attempts: Int = 50, pause: @escaping () -> Void = { usleep(100_000) }) {
        self.me = me
        self.files = files
        self.signals = signals
        self.attempts = attempts
        self.pause = pause
    }

    func arbitrate() -> Outcome {
        if take() { return .run(collidedWith: nil) }
        let holder = files.read(files.recordURL)
        switch InstanceArbitration.decide(me: me, holder: holder) {
        case .exit:
            leaveNotice()
            return .exit
        case .askHolderToQuit:
            files.write(me, to: files.handoffURL)
            signals.postYield()
            for _ in 0..<attempts {
                pause()
                if take() { return .run(collidedWith: holder) }
            }
            leaveNotice()
            return .exit
        }
    }

    /// True when the running copy should quit because a newer one asked it to. A stale or equal request is ignored.
    func shouldYield() -> Bool {
        guard let requester = files.read(files.handoffURL) else { return false }
        return InstanceArbitration.isNewer(requester, than: me)
    }

    func release() { lock = nil }

    private func take() -> Bool {
        guard let acquired = InstanceLock.acquire(at: files.lockURL) else { return false }
        lock = acquired
        files.write(me, to: files.recordURL)
        return true
    }

    private func leaveNotice() {
        files.write(me, to: files.collisionURL)
        signals.postCollision()
    }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: the Step 2 command. Expected: PASS (7 tests).

- [ ] **Step 6: Wire it into the app delegate**

Replace `AppDelegate.swift` with (this replaces Task 1's and Task 2's version; the migrations now run only after this copy wins):

```swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private let arbiter = InstanceArbiter()
    private var yieldObserver: InstanceSignals.Observer?
    private var collisionObserver: InstanceSignals.Observer?
    /// The other copy to tell the user about, kept until the coordinator exists.
    private var pendingCollision: InstanceInfo?
    private var isTestHost: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !isTestHost else { return }
        switch arbiter.arbitrate() {
        case .exit:
            exit(0)
        case .run(let replaced):
            pendingCollision = replaced
        }
        AppSupportFiles.migrateIfNeeded()
        GroupDefaults.migrate(from: .standard, to: GroupDefaults.suite)
        yieldObserver = InstanceSignals.Observer(name: InstanceSignals.yieldName) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.arbiter.shouldYield() else { return }
                NSApp.terminate(nil)
            }
        }
        collisionObserver = InstanceSignals.Observer(name: InstanceSignals.collisionName) { [weak self] in
            DispatchQueue.main.async { self?.showCollisionFromFile() }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        if let other = pendingCollision { coordinator.noteCollision(with: other) }
        pendingCollision = nil
        Task { await coordinator.start() }
    }

    private func showCollisionFromFile() {
        let files = InstanceFiles.default
        guard let other = files.read(files.collisionURL) else { return }
        if let coordinator { coordinator.noteCollision(with: other) } else { pendingCollision = other }
    }
}
```

`AppCoordinator.noteCollision(with:)` does not exist yet (Task 12 adds it). To keep this task compiling, add this stub to `AppCoordinator` now and let Task 12 replace its body:

```swift
    /// Another copy of TimeTug was opened and left (or was replaced by this one). Task 12 shows the notice.
    func noteCollision(with other: InstanceInfo) {}
```

- [ ] **Step 7: Run the whole app suite, then verify by hand (team-signed)**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test` (Expected: PASS). Then build both targets team-signed under different file names (as in Task 6 Step 3) and check:
1. Open the direct build, then the store build while it runs. If the store build has the higher version, the direct one quits within a second and the store one stays. Otherwise the store one exits and nothing appears for it (no menu bar flash).
2. `open -n` the same app twice: the second exits at once; one menu bar icon.
3. Kill the running one with `kill -9`, open another: it starts (no stale lock).

- [ ] **Step 8: Commit**

```bash
git checkout Apps/macOS/Sources/Info.plist Apps/macOS/Widgets/Info.plist
git add Apps/macOS
git commit -m "Run only one TimeTug at a time, newest version wins

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 12: The collision notice

**Files:**
- Create: `Apps/macOS/Sources/CollisionNotice.swift`
- Create: `Apps/macOS/Tests/CollisionNoticeTests.swift`
- Create: `Apps/macOS/Sources/CollisionNoticeRow.swift`
- Modify: `Apps/macOS/Sources/AppModel.swift`, `Apps/macOS/Sources/AppCoordinator.swift` (`noteCollision`, dismissal, the `DropdownView` call), `Apps/macOS/Sources/DropdownView.swift`, `Apps/macOS/Sources/GeneralPane.swift`, `Apps/macOS/Sources/SettingsView.swift`

**Interfaces:**
- Consumes: `InstanceInfo`, `Distribution.label`, `GroupDefaults.suite`.
- Produces: `struct CollisionNotice: Equatable { let message: String; let pairKey: String; static func make(survivor:other:) -> CollisionNotice; static func shouldShow(_:dismissedPair:) -> Bool; static let dismissedKey: String }`; `AppModel.collisionNotice: CollisionNotice?`; `AppCoordinator.noteCollision(with:)` and `dismissCollisionNotice()`.

- [ ] **Step 1: Write the failing tests**

Create `Apps/macOS/Tests/CollisionNoticeTests.swift`:

```swift
import XCTest
@testable import TimeTug

final class CollisionNoticeTests: XCTestCase {
    private let store = InstanceInfo(bundleID: "com.timetug.app.store", version: "2.0.0", build: "9", distribution: .appStore)
    private let direct = InstanceInfo(bundleID: "com.timetug.app", version: "1.4.1", build: "5", distribution: .direct)

    func testMessageNamesBothCopiesAndSuggestsKeepingOne() {
        let notice = CollisionNotice.make(survivor: store, other: direct)
        XCTAssertTrue(notice.message.contains("App Store 2.0.0"))
        XCTAssertTrue(notice.message.contains("downloaded 1.4.1"))
        XCTAssertTrue(notice.message.contains("Only one copy runs at a time"))
        XCTAssertTrue(notice.message.contains("Keeping just one installed"))
    }

    func testPairKeyIsTheSameFromEitherSide() {
        XCTAssertEqual(CollisionNotice.make(survivor: store, other: direct).pairKey,
                       CollisionNotice.make(survivor: direct, other: store).pairKey)
    }

    func testPairKeyChangesWhenAVersionChanges() {
        let newer = InstanceInfo(bundleID: "com.timetug.app", version: "1.5.0", build: "6", distribution: .direct)
        XCTAssertNotEqual(CollisionNotice.make(survivor: store, other: direct).pairKey,
                          CollisionNotice.make(survivor: store, other: newer).pairKey)
    }

    func testShownUnlessThisPairWasDismissed() {
        let notice = CollisionNotice.make(survivor: store, other: direct)
        XCTAssertTrue(CollisionNotice.shouldShow(notice, dismissedPair: nil))
        XCTAssertFalse(CollisionNotice.shouldShow(notice, dismissedPair: notice.pairKey))
        XCTAssertTrue(CollisionNotice.shouldShow(notice, dismissedPair: "direct-1.0.0+direct-1.1.0"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodegen generate --spec Apps/macOS/project.yml && xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test -only-testing:TimeTugTests/CollisionNoticeTests`
Expected: build FAILS (`CollisionNotice` not found).

- [ ] **Step 3: Implement the content**

Create `Apps/macOS/Sources/CollisionNotice.swift`:

```swift
import Foundation

/// The quiet "you have two copies" hint shown by the copy that keeps running.
struct CollisionNotice: Equatable {
    /// Group-suite key holding the pair the user dismissed.
    static let dismissedKey = "collision.dismissedPair.v1"

    let message: String
    /// Stable for the same two builds from either side; a new version of either one makes a new pair.
    let pairKey: String

    static func make(survivor: InstanceInfo, other: InstanceInfo) -> CollisionNotice {
        func name(_ info: InstanceInfo) -> String { "\(info.distribution.label) \(info.version)" }
        let message = "Another copy of TimeTug (\(name(other))) was opened. Only one copy runs at a time, and this one "
            + "(\(name(survivor))) is the one running. Keeping just one installed avoids this."
        let key = [survivor, other].map { "\($0.distribution.rawValue)-\($0.version)" }.sorted().joined(separator: "+")
        return CollisionNotice(message: message, pairKey: key)
    }

    static func shouldShow(_ notice: CollisionNotice, dismissedPair: String?) -> Bool {
        notice.pairKey != dismissedPair
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: the Step 2 command. Expected: PASS (4 tests).

- [ ] **Step 5: Show it in the app**

Create `Apps/macOS/Sources/CollisionNoticeRow.swift`:

```swift
import SwiftUI

/// A quiet banner: the message and a Dismiss button. Never modal.
struct CollisionNoticeRow: View {
    let notice: CollisionNotice
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text(notice.message).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Dismiss", action: onDismiss).buttonStyle(.link).font(.footnote)
        }
    }
}
```

In `AppModel.swift` add `@Published var collisionNotice: CollisionNotice?`. In `AppCoordinator.swift` replace the stub with:

```swift
    /// Another copy of TimeTug was opened and left (or was replaced by this one): show the hint unless this pair of
    /// builds was dismissed before.
    func noteCollision(with other: InstanceInfo) {
        let notice = CollisionNotice.make(survivor: .current, other: other)
        let dismissed = GroupDefaults.suite.string(forKey: CollisionNotice.dismissedKey)
        model.collisionNotice = CollisionNotice.shouldShow(notice, dismissedPair: dismissed) ? notice : nil
    }

    func dismissCollisionNotice() {
        guard let notice = model.collisionNotice else { return }
        GroupDefaults.suite.set(notice.pairKey, forKey: CollisionNotice.dismissedKey)
        model.collisionNotice = nil
    }
```

In `DropdownView.swift` add a property `let onDismissCollision: () -> Void` after `onMerge`, and at the top of the inner `VStack` in `content(now:)` (before `if !problems.isEmpty`) add:

```swift
                if let notice = model.collisionNotice {
                    CollisionNoticeRow(notice: notice, onDismiss: onDismissCollision)
                        .padding(.horizontal, 12).padding(.top, 12)
                }
```

In `AppCoordinator.start()` pass `onDismissCollision: { [weak self] in self?.dismissCollisionNotice() }` to `DropdownView(...)`; update any other `DropdownView(` call (previews, tests: `grep -rn "DropdownView(" Apps`). In `SettingsView.swift` pass `collision: model.collisionNotice` to `GeneralPane`, and in `GeneralPane.swift` add `let collision: CollisionNotice?` and, as the first `Section` of its form when non-nil, a `Section("Other copy installed") { Text(collision.message).font(.footnote).foregroundStyle(.secondary) }` (no dismiss here: this line is the permanent record that the dropdown banner points at).

- [ ] **Step 6: Run the whole app suite and verify by hand**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test` (Expected: PASS). By hand with the two team-signed copies from Task 11: open both in either order and confirm (a) the surviving copy shows the banner in its dropdown and the line in Settings > General, (b) Dismiss hides the banner and it does not return after relaunch with the same two builds, (c) a different version of either build shows it again.

- [ ] **Step 7: Commit, open the phase 4 PR**

```bash
git checkout Apps/macOS/Sources/Info.plist Apps/macOS/Widgets/Info.plist
git add Apps/macOS
git commit -m "Tell the user, once and quietly, when a second copy of TimeTug is opened

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Open the phase 4 PR (Tasks 8 to 12) to `master`, wait for CI, squash-merge.

---

## Phase 5: Documentation

### Task 13: Docs

**Files:**
- Modify: `docs/decisions/0019-shared-state-and-sandbox.md (created in PR #58, extended in PR #59)`
- Create: `docs/decisions/0020-single-instance.md`
- Modify: `AGENTS.md`, `docs/architecture.md`, `docs/release.md`, `README.md` (download and App Store notes), the privacy policy page under `site/` if it states where data is stored

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Finish the ADRs**

Extend ADR 0019 with the outcomes of Tasks 3, 4 and 6 (keychain group findings, final entitlement list, update-from-1.x result, bundle IDs) and create ADR 0020 in the same format: Context (two builds can be installed together; a duplicate would double every takeover), Decision (the lock file, `instance.json`, the handoff and collision files and Darwin notifications, newest version wins with the build tiebreak, cooperative quit, the quiet notice and its once-per-pair dismissal), Consequences (the exit is silent for the loser, an unknown holder record makes the newcomer leave, ad-hoc dev builds use their own folder so they never collide with an installed copy).

- [ ] **Step 2: Update the guides**

`AGENTS.md`: Layout lists `Distribution`, `GroupDefaults`, `AppSupportFiles` (group container), `AppCredentials`, `InstanceArbiter` and friends; Gotchas gain: state lives in the App Group (files and suite now; keychain group once Task 3 is unblocked), the per-build exceptions, ad-hoc fallbacks, "do not read the real home directory" (sandbox), and the single-instance rule. `docs/architecture.md`: a short "Builds and shared state" section with the same facts. `docs/release.md`: the App Store workflow is documented in Task 7; add that a direct and an App Store release of the same version must be cut together. Check the privacy policy source under `site/` (`grep -rn "Application Support\|stored" site`) and update any sentence about where data is stored.

- [ ] **Step 3: Run the full verification**

Run: `scripts/dev/affected-tests.sh --run && scripts/ci/check-architecture.sh && bash scripts/release/tests/test-build-appstore.sh`
Expected: all PASS. Then re-run the manual checklist (`docs/manual-tests/macos-checklist.md`, including the Sandbox section) on a team-signed build.

- [ ] **Step 4: Commit, open the phase 5 PR**

```bash
git add docs AGENTS.md README.md site
git commit -m "Document the builds, shared state and single-instance rule

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Open the PR, wait for CI, squash-merge.

The release itself (version, tag, notes, dispatching the `App Store` workflow, submitting for review) is Scott's, done when he makes the release; this plan stops at the merged documentation.

---

## Scott's checklist (cannot be done from the repository)

- [ ] **Settle the Apple team first.** App group ids, keychain access groups and signing identities are team-prefixed (`YYA6ZKMD36`). Moving to the LLC changes the Team ID, so do it before the group-state build ships (PR #58), then update `AppGroup` and the entitlements to the new prefix.
- [ ] Create a Developer ID provisioning profile with Keychain Sharing for `com.timetug.app` (needed to unblock Task 3).
- [ ] Apple Developer portal: register App IDs `com.timetug.app.store` and `com.timetug.app.store.widgets` with the App Groups capability (`YYA6ZKMD36.com.timetug.shared`) and Keychain Sharing; add Keychain Sharing and the group to `com.timetug.app` and `com.timetug.app.widgets`.
- [ ] Create the profiles: Developer ID profiles for the two direct IDs (refresh the existing ones), and Mac App Store profiles named `TimeTug App Store` and `TimeTug Widgets App Store`.
- [ ] Create the Apple Distribution and Mac Installer certificates; export both as `.p12`.
- [ ] App Store Connect: create the app record (bundle `com.timetug.app.store`, name TimeTug), privacy nutrition labels (calendar and contacts read on device; the connector accounts send requests only to the providers), screenshots, category Productivity, review notes ("Opt-in full-screen reminder before meetings; dismiss with Esc or a click; calendar access is required and explained in-app"), and a link to the privacy policy.
- [ ] Create an App Store Connect API key (App Manager); put the eight `appstore` environment secrets from `docs/release.md` in GitHub, with a required reviewer on the environment.
- [ ] Decide the App Store price and availability, and whether to run an external TestFlight group before submitting.

## Self-review (spec coverage)

- Decision 1 (two targets, one template): Tasks 5, 6. Decision 2 (both sandboxed, Sparkle in the sandbox): Task 4. Decision 3 (bundle IDs, group sharing): Tasks 6 (and 3 once unblocked) (Step 3 proves the sharing). Decision 4 (state in the group before the sandbox, ad-hoc fallbacks): Tasks 1 and 2 and the phase order (Task 3 is blocked on a profile). Decision 5 (per-build state): Global Constraints and ADR 0019 (Task 13). Decisions 6 and 7 (single instance, notice): Tasks 8 to 12. Decision 8 (versioning): deliberately left to Scott's release; no task.
- Placeholder scan: no TBD/TODO; every code step shows code. Steps that depend on facts I could not verify here (Sparkle 2.10.0 sandbox key names, the Developer ID keychain-group profile, 14-digit App Store build numbers, ad-hoc launch with the keychain entitlement) say so and name the check and the fallback.
- Type consistency: `InstanceInfo` (Task 9) is used unchanged in Tasks 10 to 12; `InstanceArbiter.init(me:files:signals:attempts:pause:)` matches its tests and the delegate's `InstanceArbiter()` defaults; `Distribution.label` (Task 5) feeds `CollisionNotice` (Task 12); `AppCoordinator.noteCollision(with:)` is stubbed in Task 11 and filled in Task 12; `UpdateController.isAvailable` (Task 5) is read by `GeneralPane` in the same task.
