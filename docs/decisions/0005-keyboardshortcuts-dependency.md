# ADR 0005: KeyboardShortcuts Dependency for the Global Popup Shortcut

**Status:** Accepted

## Context

Users want a global keyboard shortcut, chosen by them, that shows or hides the menu bar popup from any app. That needs three things: a shortcut recorder control, persistence of the chosen combination, and a system-wide hotkey registration that does not demand Accessibility permission. It should also warn about combinations macOS reserves.

## Decision

Use the MIT-licensed SwiftPM package [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus. It provides the SwiftUI recorder, stores the shortcut in UserDefaults, registers the hotkey through Carbon (no Accessibility permission) and warns about reserved system shortcuts. There is no default shortcut: it stays empty until the user records one, so it cannot conflict with anything.

- **Pin:** `exactVersion: 2.4.0` in `Apps/macOS/project.yml`. `Package.resolved` lives in the git-ignored generated project, so the exact pin is the only reproducible record. 3.x exists; upgrade deliberately.
- **Scope:** app layer only (`Apps/macOS`). `Packages/TimeTugCore` stays dependency-free and portable.
- **Rejected:** hand-rolled Carbon `RegisterEventHotKey` plus a custom recorder view. It is a lot of subtle code (key-code mapping, modifier handling, layout changes, reserved-shortcut detection, accessibility) for no benefit over a small, widely used library.
- **Rejected:** `NSEvent` global monitors. They need Accessibility permission and cannot consume the key.

## Consequences

- One remote dependency, fetched on first build (network needed once). Regenerate the project after editing `project.yml`.
- We track upstream releases for macOS compatibility and security fixes.
- Global registration and the recorder UI cannot be unit-tested; they are covered by the manual checklist.
- Third-party attribution (MIT) is noted in the README.
