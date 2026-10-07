# Development and verification

The current [architecture](architecture.md) and root [agent guide](../AGENTS.md) define module boundaries. Detailed signing, OAuth, widget, CI, live-test and release recipes are in the [operations runbook](development/runbooks/operations.md). Keep a [checkpoint](development/checkpoint-template.md) when handing work to another agent.

## Local checks

Run `scripts/dev/verify.sh affected` for working-tree changes. `affected --base <git-ref>` also checks committed changes against that base. Explicit modes are `core`, `connectors`, `app`, `release-tools`, and `all`. The wrapper records the commit, dirty state, platform, commands, pass/fail counts and elapsed time under `build/verify/<UTC timestamp>-<pid>/`. Exit 2 means a missing prerequisite or invalid selection; other nonzero exits are failing checks. It never installs global tools or enables live provider tests.

The `core` mode tests Core, CalendarConnectors, Bridge and inference. `connectors` tests CalendarConnectors, CalendarApple and EventKitSource. `app` regenerates the Xcode project before app tests. `release-tools` runs the six shell suites, Python release tests, website Node tests, workflow checks and repository contracts. `all` runs every package, app and release-tool check. Changed connector code routes to all dependents; app-only code routes to app; workflow/release/site code routes to release tools; documentation routes to repository contracts; unknown paths route to all. Linux portability and the [macOS UI checklist](manual-tests/macos-checklist.md) are separate checks. The wrapper's output says so.

Prerequisites: Swift 6/Xcode for packages, XcodeGen and xcodebuild for app, Python 3 with pinned `scripts/ci/requirements-test.txt`, Node for website tests, and Bash. CI installs the Python prerequisites in a virtual environment. No live calendar test flags are set by the wrapper. Run live tests only from the [operations runbook](development/runbooks/operations.md) with the required account and explicit task authorization.

`Apps/macOS/project.yml` owns generated app and widget Info.plist properties, including privacy descriptions, Sparkle metadata and OAuth substitutions. After editing it, run XcodeGen twice and verify no second-generation tracked diff appears. Keep checked-in Info.plists in sync. `*.xcodeproj` is intentionally ignored.

## Focused lint

ShellCheck 0.11.0 is the pinned shell linter for new verification scripts. Run `scripts/dev/lint.sh` when editing them; it requires exactly ShellCheck 0.11.0. A 2026-09-26 baseline scan of every `scripts/**/*.sh` found seven SC2016 notes in `scripts/ci/build-release.sh` and the Google/Microsoft OAuth-config shell tests (intentional literal shell expressions in fixtures). The focused lint command passes without suppressing warnings globally. Expand lint coverage after resolving those seven notes in a scoped change. The CI release-tooling job runs executable tests and syntax checks.
