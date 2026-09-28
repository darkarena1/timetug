---
name: configuring-local-app-builds
description: Use when a local TimeTug app build needs code signing, working widgets or Control Center controls, or Google or Microsoft sign-in; when an account provider is missing or unavailable in Settings > Accounts; when changing how CI passes OAuth client ids to builds; or on "Embedded binary is not signed with the same certificate".
---

# Configuring local app builds

Per-machine settings live in `~/.config/timetug/`, outside the repo. `scripts/dev/link-signing.sh` links them into each checkout as git-ignored files under `Apps/macOS/Config/`. XcodeGen's `preGenCommand` runs the script, so `xcodegen generate --spec Apps/macOS/project.yml` picks up changes. Xcode cannot include a file by `$(HOME)`, hence the links.

## Signing (widgets and controls)

Widgets and Control Center controls only work in team-signed builds. Ad-hoc builds (CI, or no signing file) run normally: the snapshot write logs and skips, and widgets show the placeholder. See ADR 0010.

- Put `DEVELOPMENT_TEAM`, `CODE_SIGN_STYLE` and `CODE_SIGN_IDENTITY` in `~/.config/timetug/signing.xcconfig`. The team id is public; certificates stay in the keychain. It is linked in as `Apps/macOS/Config/Local.xcconfig`, which `Config/Signing.xcconfig` includes.
- `DEVELOPMENT_TEAM` is deliberately not in `project.yml`.
- Automatic `Apple Development` signing needs Xcode signed in to the Apple ID (Xcode > Settings > Accounts). Manual Developer ID signing also works, but without the debugger.
- After changing signing, do a `clean` build. A stale ad-hoc extension fails with "Embedded binary is not signed with the same certificate".
- Reproduce CI's unsigned build: `TIMETUG_SIGNING_XCCONFIG=/nonexistent xcodegen generate --spec Apps/macOS/project.yml`.
- Hand checks: `docs/manual-tests/macos-checklist.md`.

## Google and Microsoft accounts

| | Google | Microsoft |
| --- | --- | --- |
| Local file (either location) | `Apps/macOS/Config/GoogleOAuth.xcconfig` or `~/.config/timetug/google-oauth.xcconfig` | `Apps/macOS/Config/MicrosoftOAuth.xcconfig` or `~/.config/timetug/microsoft-oauth.xcconfig` |
| Defines | `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET` | `MICROSOFT_OAUTH_CLIENT_ID` (an Entra public client, no secret) |
| Without it | Google is not offered in Settings > Accounts | Microsoft shows as unavailable |
| Beta and release builds | optional repository secrets of the same names | optional repository secret of the same name |

- In CI only the `Build Release app` steps of `beta.yml` and `release.yml` receive these secrets, never `ci.yml`. `scripts/ci/google-oauth-config.sh` and `scripts/ci/microsoft-oauth-config.sh` write a mode-600 temporary xcconfig and export `TIMETUG_GOOGLE_XCCONFIG` or `TIMETUG_MICROSOFT_XCCONFIG` before `xcodegen generate`. `build-release.sh` checks the built Info.plist and prints only "configured" or "absent".
- iCloud and Other CalDAV are always registered (no client id). If they are missing from Settings > Accounts, check
  `AppConnectors.makeRegistry`.
- Google's Desktop-app client secret is not confidential (it ships inside the app), but it must stay out of git. Never print it or pass it on the command line of a logged step.

## The sign-in sheet

Sign-in opens a system web-authentication sheet (`ASWebAuthenticationSession`), which shares Safari sessions, passkeys and autofill. The sheet closes itself because the loopback listener answers the redirect with a 302 to `timetug-oauth://done`, which the sheet catches. If the sheet cannot start, the flow falls back to the default browser and a plain "You're signed in" page. Cancelling the sheet ends the flow at once. An embedded web view is not an option, because Google blocks embedded user agents.

A hidden switch sends sign-in to the default browser instead: `defaults write com.timetug.app oauth.useBrowser.v1 -bool true` (read on every sign-in by `BrowserPreferringPresenter`). Undo it with `defaults delete com.timetug.app oauth.useBrowser.v1`. It exists for Google's verification demo video, which must show the OAuth client id in the browser's address bar; the sheet does not show it.
