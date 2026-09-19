<p align="center">
  <img src="artwork/GitHub/timetug-readme-banner.png" alt="TimeTug: a tug when time needs your attention">
</p>

# TimeTug

[![CI](https://github.com/darkarena1/timetug/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/darkarena1/timetug/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A tug when time needs your attention. TimeTug lives in your macOS menu bar, lists today's meetings,
and takes over every screen shortly before a meeting starts, so you don't hyperfocus through it.

Created by [Scott O'Bryan](https://github.com/darkarena1).

## Features
- Reads Apple Calendar (iCloud, Google and Exchange accounts added to macOS) via EventKit
- Merges the same meeting across calendars and accounts, so it shows (and tugs) once; see [Event merging](#event-merging)
- Full-screen takeover on every display at a configurable lead time (0 = "starting now"), with Join, Snooze and Dismiss
- Detects Zoom, Meet, Teams, Webex and similar links for a one-click Join
- Per-calendar Tug opt-in; never takes over for all-day events; skips declined and solo events by default
- Menu bar icon turns color when a meeting is about to tug you
- Menu bar: icon only (default), next meeting, or countdown
- Light, Dark or Auto appearance
- Optional global shortcut to show today's meetings

## Event merging
The same meeting often shows up on several calendars or accounts, sometimes with different titles. TimeTug
finds those duplicates across every calendar and account and merges them into one entry, so you see the meeting
once and it takes over only once.

- **Rules first.** Identical events merge. Events on different calendars that start and end close together
  merge when they share a conference link, invite, attendee or place. A clear conflict (a different room or a
  different meeting link), or two separate events on the same calendar, keeps them apart.
- **Apple Intelligence for the hard cases (Beta, off by default).** When nothing in the details settles it (for
  example a bare "Scott: Doctor" reminder and a detailed "Intermountain Health" appointment), TimeTug can ask
  your Mac's on-device Apple Intelligence model whether they are the same appointment. Turn it on in
  **Settings > Calendars**. It needs macOS 26 on a Mac that supports Apple Intelligence, runs entirely on your
  Mac (nothing is sent anywhere) and falls back to rules only when the model isn't available.
- **You stay in control.** Merged entries show how they were merged ("Merged with Apple Intelligence" or
  "Merged manually") and expand to list each event with its calendar and time. Use **Split off** to pull one
  event out, **Unmerge all** to undo a merge, or **Merge with...** to join two events yourself. TimeTug
  remembers your corrections; **Forget learned corrections** in Settings clears them.
- **Timing.** A merged meeting shows the longer entry's time range. It tugs you at the start of the entry that
  has the video link, or at the longer entry's start if none does.

Details: `docs/decisions/0009-duplicate-detection-and-on-device-inference.md`.

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

Apple Intelligence adapter tests: `swift test --package-path Packages/AppleIntelligenceInference`

## Architecture
`Packages/TimeTugCore` (portable logic, including the merge rules), `Packages/EventKitSource` (Apple Calendar),
`Packages/AppleIntelligenceInference` (on-device Apple Intelligence adapter for merging), `Apps/macOS` (the app).
See `docs/architecture.md`. Agents and contributors: read `AGENTS.md`.

## Third-party
Uses KeyboardShortcuts by Sindre Sorhus (MIT).

## Status
Early development.

## Author
Created and maintained by Scott O'Bryan.

## Licensing
The source code is released under the [MIT License](LICENSE).

The brand artwork is ALL RIGHTS RESERVED and is not covered by the MIT license: the `artwork/` directory and the
artwork-derived images in `Apps/macOS/Resources/Assets.xcassets` (app icon, menu bar icons, logo lockups, hero
images). Please ask before reuse; see [artwork/LICENSE.md](artwork/LICENSE.md).
