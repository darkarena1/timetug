<p align="center">
  <img src="artwork/GitHub/timetug-readme-banner.png" alt="TimeTug: a tug when time needs your attention">
</p>

# TimeTug

[![CI](https://github.com/darkarena1/timetug/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/darkarena1/timetug/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A tug when time needs your attention. TimeTug lives in your macOS menu bar, lists today's meetings,
and takes over every screen shortly before a meeting starts, so you don't hyperfocus through it.

## Features
- Reads Apple Calendar (iCloud, Google and Exchange accounts added to macOS) via EventKit
- Full-screen takeover on every display at a configurable lead time (0 = "starting now"), with Join, Snooze and Dismiss
- Detects Zoom, Meet, Teams, Webex and similar links for a one-click Join
- Per-calendar Tug opt-in; never takes over for all-day events; skips declined and solo events by default
- Menu bar icon turns color when a meeting is about to tug you
- Menu bar: icon only (default), next meeting, or countdown
- Light, Dark or Auto appearance
- Optional global shortcut to show today's meetings

## Install
Download the `.dmg` from the [Releases page](https://github.com/darkarena1/timetug/releases), open it and drag
TimeTug onto the Applications shortcut. Until Apple Developer signing is set up, releases are unsigned
prereleases: the first time, right-click TimeTug and choose Open. If macOS says the app is damaged, run
`xattr -dr com.apple.quarantine /Applications/TimeTug.app`.

## Build
Requires macOS 14+ to run and Xcode 26 or newer to build (needs [XcodeGen](https://github.com/yonaskolb/XcodeGen):
`brew install xcodegen`). The Liquid Glass style needs the macOS 26 SDK.

```bash
xcodegen generate --spec Apps/macOS/project.yml
```

```bash
xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' build
```

Core logic tests: `swift test --package-path Packages/TimeTugCore`

## Architecture
`Packages/TimeTugCore` (portable logic), `Packages/EventKitSource` (Apple Calendar), `Apps/macOS` (the app).
See `docs/architecture.md`. Agents and contributors: read `AGENTS.md`.

## Third-party
Uses KeyboardShortcuts by Sindre Sorhus (MIT).

## Status
Early development.

## Licensing
The source code is released under the [MIT License](LICENSE).

The brand artwork is ALL RIGHTS RESERVED and is not covered by the MIT license: the `artwork/` directory and the
artwork-derived images in `Apps/macOS/Resources/Assets.xcassets` (app icon, menu bar icons, logo lockups, hero
images). Please ask before reuse; see [artwork/LICENSE.md](artwork/LICENSE.md).
