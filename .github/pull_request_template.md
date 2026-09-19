## What
<!-- What does this change? -->

## Why
<!-- The problem or motivation. Link issues with "Fixes #123". -->

## How I tested it
<!-- Commands run, manual steps, screenshots for UI changes. -->

## Checklist
- [ ] `swift test --package-path Packages/TimeTugCore` passes
- [ ] App tests pass: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test`
- [ ] For UI, overlay or status item changes: ran through `docs/manual-tests/macos-checklist.md`
- [ ] New Core behavior has a test written first
- [ ] Core stays dependency-free and UI-free (no UIKit/AppKit/SwiftUI/EventKit imports, no display strings)
- [ ] Docs updated (README, `docs/`, or a new ADR in `docs/decisions/`) if behavior or structure changed
