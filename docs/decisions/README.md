# Architecture decision index

ADRs record rationale and may describe the state when written. The [architecture map](../architecture.md) and current code show today's integration. “Current” means the decision still guides this area; “historical” means later code or an ADR changed details.

| ADR | Area | Status | Relevant verification |
|---|---|---|---|
| [0001](0001-swift-and-native-stack.md) | Swift/native app | Current | `verify.sh app` |
| [0002](0002-core-source-app-boundaries.md) | Core/source/app boundaries | Current | `verify.sh all` |
| [0003](0003-current-day-window-with-lead-buffer.md) | Day window | Current | `verify.sh core` |
| [0004](0004-conference-link-allowlist.md) | Join URLs | Historical: see 0013 and current JoinURLPolicy | Core and connector tests |
| [0005](0005-keyboardshortcuts-dependency.md) | App shortcut | Current | App tests, manual checklist |
| [0006](0006-takeover-ledger-persistence-and-fire-guard.md) | Takeover ledger | Current | Core and app tests |
| [0007](0007-ci-and-release-automation.md) | CI/release | Current with credential-free website PR validation | `verify.sh release-tools` |
| [0008](0008-dmg-packaging-with-dmgbuild.md) | DMG | Current | release shell suites, DMG CI |
| [0009](0009-duplicate-detection-and-on-device-inference.md) | Dedup/inference | Current | Core and inference tests |
| [0010](0010-widgets-app-group-and-snapshot.md) | Widgets | Current | App tests, team-signed manual check |
| [0011](0011-sparkle-updates-and-beta-channel.md) | Updates | Current | release shell/Python suites |
| [0012](0012-calendar-connector-library.md) | Portable sources | Current; library now includes MicrosoftCalendar and writes | connector tests |
| [0013](0013-conference-links-in-connector-library.md) | Link detection | Current | connector tests |
| [0014](0014-reminder-model.md) | Reminders | Current | connector tests |
| [0015](0015-recurrence-model.md) | Recurrence | Current | connector tests |
