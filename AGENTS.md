# TimeTug: agent guide

TimeTug is a macOS menu bar app that takes over the screen before meetings. Read
`docs/superpowers/specs/2026-09-18-timetug-core-design.md` first, then `docs/architecture.md`.

## Finding code
- If your agent has a semantic code-index skill (in Claude Code, the `index` skill), use it in this repo without asking first; this is standing permission. At the start of a task check its status. If this checkout is not indexed, or files changed a lot since the last index, run the (incremental) index. A new checkout or worktree is seeded from the index that the `Code index` workflow publishes from `master` (artifact `qindex`, fetched with `gh`), so the first run only embeds what differs from `master` and takes seconds. Without a compatible published index a full build takes about 25 minutes: start it in the background and keep working with grep until it finishes. Then search the index before broad grepping or reading many files, and read the hit ranges rather than trusting snippets. Use grep for exact identifiers and strings. `.qindexignore` lists paths the index leaves out (past-work plans, which repeat the code they produced).
- Without such a skill, start from Layout below and grep.
- Exact references ("who uses or calls this?", definitions, implementations, a type's real signature) come from a Swift language server when your agent has one: in Claude Code the `swift-lsp` plugin's LSP tool, in Codex the Serena MCP server; both run `sourcekit-lsp`. Prefer it to grep for these questions: grep cannot tell `EventMapper` from `GoogleEventMapper`, or Core's `CalendarSource` from the library's. It reads the compiler's index, so build the package with its tests first (`swift build --build-tests --package-path Packages/<Package>`); an empty result before that means "not indexed", not "unused". The first query in a package can also come back empty or fail while the server loads it; retry after a few seconds. It covers `Packages/*` only: for `Apps/macOS` (the XcodeGen project) use grep. (`xcode-build-server` was tried for the app and broke package lookups.) Local tool state it creates (`.serena/`, `buildServer.json`) is git-ignored.

## Task skills
Guides for specific tasks are skills in `.agents/skills/<name>/SKILL.md`: Codex reads them there, and Claude Code reads them through the `.claude/skills` link. If your agent does not load skills, open the file when a task matches.
- `releasing-timetug`: releases, betas, versions, Sparkle, the DMG, signing and the release workflows.
- `configuring-local-app-builds`: local code signing, widgets, Google and Microsoft OAuth client setup, the sign-in sheet (iCloud and Other CalDAV need no configuration).
- `diagnosing-takeovers`: why a running app did or did not take over, merged duplicates or shows stale widgets (logs, ledger, saved state).
- `running-live-calendar-tests`: write tests against real Apple Calendar, Google, Microsoft and iCloud accounts.
When you move guidance between this file and a skill, keep one copy: skills hold task procedures, this file holds what every change needs.

## Layout
- `Packages/TimeTugCore`: pure Swift, platform-neutral logic. NO UI or Apple-only imports.
- `Packages/EventKitSource`: Apple Calendar adapter (macOS only); speaks the library's `CalendarSource`.
- `Packages/CalendarConnectors`: portable connector library (ADR 0012), no external dependencies, pure Swift that builds on Linux. Products: `CalendarCore` (model, `CalendarSource`, `ConnectorKind`, `ChangeMonitor`, `AllDay`, `ConferenceDetector`, `FileConnectionStore`, `FileSyncStateStore`, and the optional write API: `WritableCalendarSource`, `EventDraft`, `EventPatch`, `RecurrenceRule`, `RecurrenceSet`, `CalendarSeries`, `SeriesSource`, `PatchMerge`), `CalendarOAuth` (OAuth PKCE, refresh provider, `SHA256Hashing` seam with the pure-Swift `PureSwiftSHA256` default), `GoogleCalendar` (Google connector with optional writes), `MicrosoftCalendar` (Microsoft connector), `ICalendar` (iCalendar parser, writer and event mapping), `CalDAVCalendar` (CalDAV connector with an iCloud preset) and `CalendarTestSupport`. Imports nothing from TimeTug. The host app supplies `CredentialStore`, the OAuth browser/loopback redirect and persistence.
- `Packages/CalendarBridge`: minimal glue. `EventMapper` wraps library events in `TimeTugCalendarEvent` (drops cancelled ones, adds calendar info); `ConnectedSource` adapts a library source to Core's source protocol and translates errors and changes.
- `Packages/CalendarApple`: Apple-side adapters for the library (Keychain `CredentialStore`, loopback OAuth interaction, `WebAuthenticationSessionPresenter` (the `ASWebAuthenticationSession` sign-in sheet), `CryptoKitSHA256`, injected in `AppConnectors.swift`).
- `Packages/AppleIntelligenceInference`: Apple on-device model adapter for duplicate detection (macOS 26+, compile-guarded). Only place with Foundation Models imports.
- `Apps/macOS`: AppKit/SwiftUI shell. Generated Xcode project (XcodeGen).
- `Apps/macOS/Sources/UpdateController.swift`, `UpdatesSection.swift`: Sparkle in the app layer only (never Core). Beta opt-in is `updates.includeBetas.v1` in UserDefaults.
- `Apps/macOS/Widgets`: WidgetKit extension `TimeTugWidgets` (Next Up, Today, and macOS 26 Control Center controls). Reads the snapshot; no EventKit.
- `Apps/macOS/Shared`: AppGroup, SharedSettings, SettingsChangeSignal, WidgetSnapshotStore. Compiled into both the app and the extension.
- `artwork/`: brand images (see `docs/ARTWORK_USAGE.md`); the app's asset catalog is `Apps/macOS/Resources/Assets.xcassets`. Do not use the app icon for the menu bar; the menu bar icon is the puppy set (`MenuBarPuppyLight`/`MenuBarPuppyDark` idle, chosen by the menu bar's appearance, and `MenuBarPuppyColor` while a meeting is near), picked by `MenuBarIconState.assetName(darkMenuBar:)`.

## Rules
- Core answers "what and when". The app answers "how it looks and where it lives". If code needs a window, tray or pixel, it belongs in the app.
- Dependencies point toward Core and the connector library: the app depends on `TimeTugCore`, `CalendarBridge`, `EventKitSource`, `CalendarApple` and the connector library (`CalendarCore`, `CalendarOAuth`, `GoogleCalendar`, `MicrosoftCalendar`, `CalDAVCalendar`); `TimeTugCore -> CalendarCore`; `CalendarBridge -> TimeTugCore + CalendarCore`; `EventKitSource` and `CalendarApple -> CalendarCore` (plus `CalendarOAuth` for `CalendarApple`); `GoogleCalendar` and `MicrosoftCalendar -> CalendarCore + CalendarOAuth`; `ICalendar -> CalendarCore`; `CalDAVCalendar -> CalendarCore + ICalendar`. `TimeTugCore` depends only on `CalendarCore` (which has no dependencies), and the library imports nothing from TimeTug. The app is the composition root: it owns source configuration UI and credential storage. Source packages contain no UI.
- Time is always passed in (`now: Date`); never call `Date()` inside Core logic.
- Core has no display strings. Formatting belongs to the front end.
- Every Core behavior has a Swift Testing test. Write the failing test first.
- Record significant decisions in `docs/decisions/` (ADR, one file each).
- `scripts/ci/check-architecture.sh` enforces the import, dependency and clock rules above (CI job `architecture`). When a rule changes or a package is added, update this list, the script and `scripts/ci/tests/test-check-architecture.sh` together. A justified clock read in Core carries a `// architecture-check: allow (reason)` comment.

## Commands
- Tests a change needs: `scripts/dev/affected-tests.sh` prints the commands for the packages you touched, every package and the app that depend on them, and the tests of changed scripts, dependencies first. `--run` runs them and stops at the first failure; pass paths or `--base <ref>` to scope it (default: everything changed since the merge base with `origin/master`, including uncommitted and untracked files). Use it before committing instead of guessing or running every suite.
- Architecture rules: `scripts/ci/check-architecture.sh`
- Core tests: `swift test --package-path Packages/TimeTugCore`
- EventKitSource tests: `swift test --package-path Packages/EventKitSource`
- Bridge tests: `swift test --package-path Packages/CalendarBridge`
- Apple adapter tests: `swift test --package-path Packages/CalendarApple`
- Connector library tests: `swift test --package-path Packages/CalendarConnectors`.
- Inference package tests: `swift test --package-path Packages/AppleIntelligenceInference`
- Generate app project: `xcodegen generate --spec Apps/macOS/project.yml`
- Build app: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' build`
- App tests: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test`
- Window/status-item behavior is verified by hand: `docs/manual-tests/macos-checklist.md`.

## Gotchas
- App and EventKitSource use Swift 5 language mode; Core uses Swift 6.
- Generated `*.xcodeproj` is git-ignored; regenerate after editing `project.yml`.
- The app depends on the remote package KeyboardShortcuts, pinned exactly in `Apps/macOS/project.yml`; regenerate the project after changing it (the first build needs the network). Keep it at 3.1.0 or newer: 2.x silently drops modifier key combos in the Settings recorder on macOS 27.
- Calendar access needs the calendars entitlement and `NSCalendarsFullAccessUsageDescription`. EventKit attendee lookup (participants with no `mailto:` address) also needs the `com.apple.security.personal-information.addressbook` entitlement and `NSContactsUsageDescription`; the prompt appears once, never blocks a read, and denying it just leaves those emails nil.
- Duplicate detection: rules run always; on-device inference is opt-in (Settings > Calendars, Beta), default off.
- Widgets and Control Center controls read a snapshot the app writes to the app group container, and only work in team-signed builds (ADR 0010). Control Center intents live in the extension, write the shared suite and signal the app with a Darwin notification; the app re-reads.
- `xcodegen generate` rewrites the two checked-in Info.plists (`Apps/macOS/Sources/Info.plist`, `Apps/macOS/Widgets/Info.plist`); restore them with `git checkout` before committing.
- Calendar writes are opt-in: `capabilities.canWrite == (source is WritableCalendarSource)`, unsupported fields throw `WriteError.unsupported`, updates send only changed fields and a stale version is judged per field against `EventPatch.base`. Live write tests against real accounts are opt-in and never run in CI.
- `TimeTugCore` and `CalendarCore` both define `CalendarSource` and `SourceError`: inside Core the local declaration shadows the import; elsewhere qualify (`CalendarCore.SourceError`). All-day events belong to a day by calendar date in the event's own zone (`TimeTugCalendarEvent.allDayDates/covers`), never the viewer's zone; `CalendarStore` queries sources with a 26 hour margin each side (`sourceQueryMargin`).
- A calendar that is not shown never tugs: `TakeoverPolicy` requires an opted-in copy on a calendar that is not hidden, and saved settings that both hide and opt in a calendar decode as hidden. The Calendars pane sets system-style calendars (`CalendarKind`: birthdays, subscribed feeds, from EventKit and Google ids) apart unless Tug is on for them.
- Enable Tug is enforced in Core (`TakeoverPolicy.qualifies` via `TakeoverSettings.enabled`, default on), not in the app. Declined events never take over (no setting); "Require a video link" and "Require other attendees" are off by default. `TakeoverSettings` still decodes the retired `disabled` and `skipSoloEvents` keys so saved choices carry over; the shared-suite key is `shared.enableTug` (the old `shared.disableTug` is unused).

## CI
- `.github/workflows/ci.yml`: on push to `master` and every PR (build and tests only; PRs get no signing, no secrets, and nothing that can enter the update feed). Jobs: `core` (tests for Core, the connector library, CalendarBridge, CalendarApple, EventKitSource and the inference package), `app` (XcodeGen + app tests, uploads the `.xcresult` on failure), `dmg` (unsigned DMG, uploaded as the `TimeTug-dmg` artifact), `architecture` (`scripts/ci/check-architecture.sh`, its tests and those of `affected-tests.sh`), `core-linux` (allowed to fail; swift:6.0; runs the Core and connector library tests to prove both stay portable).
- Releases and betas (`release.yml`, `beta.yml`, Sparkle, the DMG, versions and signing) follow `docs/release.md`; see the `releasing-timetug` skill.
- When CI fails: reproduce with the Commands above; for the app job download the `TestResults` artifact. Runner label or Xcode problems: `scripts/ci/select-xcode.sh` and the `runs-on` lines. Keep logic in the scripts, not in YAML.
- `.github/workflows/index.yml` (`Code index`): on pushes to `master` builds the semantic code index incrementally from the previous `qindex` artifact against a throwaway Qdrant and publishes it as the `qindex` artifact (90 days) for agents' index skill. `scripts/dev/qindex.py` is a copy of the index skill's script (`~/.claude/skills/index/scripts/qindex.py`): keep the two identical (`diff` them) and keep the library versions in the workflow equal to the skill's. The export records the model and chunker version, and the skill refuses an index that does not match and builds locally instead.
- Never commit certificates or keys (`*.p12`, `*.p8`, ...); they are git-ignored.
