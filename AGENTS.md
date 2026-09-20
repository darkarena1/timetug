# TimeTug: agent guide

TimeTug is a macOS menu bar app that takes over the screen before meetings. Read
`docs/superpowers/specs/2026-09-18-timetug-core-design.md` first, then `docs/architecture.md`.

## Layout
- `Packages/TimeTugCore`: pure Swift, platform-neutral logic. NO UI or Apple-only imports.
- `Packages/EventKitSource`: Apple Calendar adapter (macOS only).
- `Packages/AppleIntelligenceInference`: Apple on-device model adapter for duplicate detection (macOS 26+, compile-guarded). Only place with Foundation Models imports.
- `Apps/macOS`: AppKit/SwiftUI shell. Generated Xcode project (XcodeGen).
- `Apps/macOS/Sources/UpdateController.swift`, `UpdatesSection.swift`: Sparkle in the app layer only (never Core). Beta opt-in is `updates.includeBetas.v1` in UserDefaults.
- `Apps/macOS/Widgets`: WidgetKit extension `TimeTugWidgets` (Next Up, Today, and macOS 26 Control Center controls). Reads the snapshot; no EventKit.
- `Apps/macOS/Shared`: AppGroup, SharedSettings, SettingsChangeSignal, WidgetSnapshotStore. Compiled into both the app and the extension.
- `artwork/`: brand images (see `docs/ARTWORK_USAGE.md`); the app's asset catalog is `Apps/macOS/Resources/Assets.xcassets`. Do not use the app icon for the menu bar; use the `MenuBarTemplate` template image.

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
- Inference package tests: `swift test --package-path Packages/AppleIntelligenceInference`
- Generate app project: `xcodegen generate --spec Apps/macOS/project.yml`
- Build app: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' build`
- App tests: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test`
- Window/status-item behavior is verified by hand: `docs/manual-tests/macos-checklist.md`.

## Gotchas
- App and EventKitSource use Swift 5 language mode; Core uses Swift 6.
- Generated `*.xcodeproj` is git-ignored; regenerate after editing `project.yml`.
- The app depends on the remote package KeyboardShortcuts, pinned exactly in `Apps/macOS/project.yml`; regenerate the project after changing it (first build needs network).
- Calendar access needs the calendars entitlement and `NSCalendarsFullAccessUsageDescription`.
- Takeover decisions are logged (titles redacted). Read them with ``log show --predicate 'subsystem == "com.timetug.app" AND category == "takeover"' --last 1h``. The persisted ledger is `~/Library/Application Support/TimeTug/takeover-ledger.json`; delete it to reset "already shown" memory.
- Duplicate detection: rules run always; on-device inference is opt-in (Settings > Calendars, Beta), default off. Lessons and verdicts persist at `~/Library/Application Support/TimeTug/dedup-state.json` (delete to reset).
- Widgets and controls only work in team-signed builds. Local signing: put `DEVELOPMENT_TEAM`, `CODE_SIGN_STYLE` and `CODE_SIGN_IDENTITY` in `~/.config/timetug/signing.xcconfig` (outside the repo; the team id is public, certificates stay in the keychain). `scripts/dev/link-signing.sh` (run by xcodegen's `preGenCommand`) links it into each checkout as the git-ignored `Apps/macOS/Config/Local.xcconfig`, which `Config/Signing.xcconfig` includes; with no such file builds are ad-hoc signed (CI). Xcode cannot include a file by `$(HOME)`, hence the link. Automatic `Apple Development` signing needs Xcode signed in to the Apple ID (Xcode > Settings > Accounts); manual Developer ID also works (no debugger). After changing signing, do a `clean` build (a stale ad-hoc extension fails with "Embedded binary is not signed with the same certificate"). To reproduce CI locally: `TIMETUG_SIGNING_XCCONFIG=/nonexistent xcodegen generate --spec Apps/macOS/project.yml`. `DEVELOPMENT_TEAM` is deliberately not in `project.yml`. Checks in `docs/manual-tests/macos-checklist.md`. Ad-hoc builds run normally: the snapshot write logs and skips, and widgets show the placeholder. See ADR 0010.
- The app writes `agenda-snapshot.json` to `~/Library/Group Containers/YYA6ZKMD36.com.timetug.shared/`; some shells cannot read that path (privacy protection). Control Center intents live in the extension, write the shared suite and signal the app with a Darwin notification; the app re-reads.
- Disable Tug is enforced in Core (`TakeoverPolicy.qualifies` via `TakeoverSettings.disabled`), not in the app.

## CI and releases
- `.github/workflows/ci.yml`: on push to `master` and every PR (build and tests only; PRs get no signing, no secrets, and nothing that can enter the update feed). Jobs: `core` (Core tests + EventKitSource build + inference package tests), `app` (XcodeGen + app tests, uploads the `.xcresult` on failure), `dmg` (unsigned DMG), `core-linux` (allowed to fail; proves Core portability).
- `.github/workflows/release.yml`: runs when the owner publishes a GitHub Release whose tag starts with `v` (draft it in the GitHub UI, then Publish; pushing a tag alone does nothing; `workflow_dispatch` with `tag` is the fallback). Builds the tag's commit (must be on `master`; needs approval via the `release` environment) with `scripts/ci/build-release.sh`; signed and notarized DMG when the Apple secrets exist, otherwise an unsigned prerelease DMG (`scripts/release/`). Uploads the DMG, `.sha256` and Sparkle zip to the owner's release, then adds the appcast item (a `-` tag goes to the beta channel; unsigned never does). The release commit is `refs/tags/<tag>` (a same-named branch cannot shadow it) and a `Validate the tag` step rejects a bad tag (e.g. `V1.2.3`) before any build; a release marked prerelease in the UI, like a `-` tag, goes to the beta channel. Fails early if the Apple secrets exist without `SPARKLE_PRIVATE_KEY`. Process and secrets: `docs/release.md`; rationale: ADR 0007, 0008, 0011.
- `.github/workflows/beta.yml` (`Beta`): `workflow_run` of `CI` on `master` pushes that passed, same repo. Builds only the tip of `master` (skips with a notice if a newer commit exists) and skips if the signing secrets are missing. Versions from `scripts/ci/compute-versions.sh beta`, signs with Developer ID (no notarization), publishes a `v<version>-beta.<timestamp>` prerelease (tag = app version; two older betas use the legacy `beta-<timestamp>` tag and are pruned the same way), then updates the appcast on `gh-pages` (keeps 5). No approval; secrets are only used on merged code, so keep `master` protected. Rationale and risk: ADR 0011.
- Sparkle scripts in `scripts/release/`: `sign-app.sh`, `make-update-zip.sh`, `fetch-sparkle-tools.sh` (pinned in `sparkle-version.txt`), `publish-appcast.sh`, `appcast.py`. Gotcha: `CFBundleVersion` is a UTC timestamp `YYYYMMDDHHMMSS` (14 digits) from `compute-versions.sh`; never a hash or `GITHUB_RUN_NUMBER`. Beta display versions are `<newest stable v* tag>-beta.<BUILD_NUMBER>`; no manual bump (the `project.yml` value is only the fallback when no stable tag exists).
- Gotcha: `SUFeedURL` and `SUPublicEDKey` live in `project.yml` `info.properties`; Sparkle is `exactVersion`-pinned there and in `sparkle-version.txt` (keep both equal). The private key is only the `SPARKLE_PRIVATE_KEY` secret.
- The `dmg` CI job builds and verifies an unsigned DMG on every run and uploads it as the `TimeTug-dmg` artifact.
- DMG scripts: `scripts/release/make-dmg.sh` (dmgbuild, pinned in `scripts/release/dmg/requirements.txt`, installed in `build/dmg-venv`), `scripts/release/verify-dmg.sh <dmg>`, `scripts/release/sign-and-notarize.sh [app|dmg]`. Gotcha: the DMG background PNGs are committed; after editing `scripts/release/dmg/generate-background.swift` re-run it and commit the PNGs, and keep the icon positions in `scripts/release/dmg/settings.py` in sync with the arrow.
- When CI fails: reproduce with the Commands above; for the app job download the `TestResults` artifact. Runner label or Xcode problems: `scripts/ci/select-xcode.sh` and the `runs-on` lines. Keep logic in the scripts, not in YAML.
- Never commit certificates or keys (`*.p12`, `*.p8`, ...); they are git-ignored.
