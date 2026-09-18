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
