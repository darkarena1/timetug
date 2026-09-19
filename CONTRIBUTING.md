# Contributing to TimeTug

Thanks for helping. TimeTug is a macOS menu bar app that takes over the screen shortly before a meeting.

## Build and test
Requires Xcode 26 or newer and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
swift test --package-path Packages/TimeTugCore                # Core logic tests
swift build --package-path Packages/EventKitSource            # Apple Calendar adapter
xcodegen generate --spec Apps/macOS/project.yml               # generate the (git-ignored) Xcode project
xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' build
xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test
```

Window, overlay and status item behavior is verified by hand: `docs/manual-tests/macos-checklist.md`.

## Repository layout
- `Packages/TimeTugCore`: pure Swift, platform-neutral logic.
- `Packages/EventKitSource`: Apple Calendar adapter (macOS only).
- `Apps/macOS`: AppKit/SwiftUI shell; the Xcode project is generated from `Apps/macOS/project.yml`.
- `artwork/`: brand images (not open source, see Licensing).
- `docs/`: architecture, decision records (`docs/decisions/`), manual tests, release process.
- `scripts/`, `.github/`: CI and release automation.

## Boundaries
Core answers "what and when": events, policies, scheduling, link detection. It has no UI, no Apple-only imports,
no third-party dependencies and no display strings, and time is always passed in (`now: Date`). Every Core
behavior gets a test, written first.

Source packages (like `EventKitSource`) adapt one calendar provider to Core's model and contain no UI. The app
is the composition root: it owns windows, the menu bar, settings and credential storage, and formats
everything the user sees. Dependencies point toward Core. Details: `docs/architecture.md`.

## Adding a calendar source
Implement `CalendarSource` in a new package under `Packages/`, return only Core's model, and register it in the
app. See "Adding a calendar source" in `docs/architecture.md`.

## Commits and pull requests
- Small, focused changes with a clear reason. Conventional-style subjects (`feat:`, `fix:`, `docs:`, `ci:`, `chore:`) are appreciated.
- Record significant decisions as an ADR in `docs/decisions/`.
- Fill in the pull request template. CI must pass.

## Working with AI agents
Agent-assisted contributions are welcome. Agents and humans alike should read `AGENTS.md` first; it has the rules and commands.

## Licensing
Source code is MIT (`LICENSE`); contributions are accepted under the same license. The brand artwork
(`artwork/` and the artwork-derived images in the app's asset catalog) is all rights reserved and not open
source; see `artwork/LICENSE.md`. Do not submit third-party artwork you do not have the right to license.
