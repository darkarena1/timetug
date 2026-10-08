# 0019: App state lives in the App Group; the app is sandboxed

Status: accepted, 2026-10-07

## Context
TimeTug will ship a downloaded (Developer ID) build and a Mac App Store build, and later a second app, and they should share data. The App Store requires the App Sandbox. A sandboxed app cannot read `~/Library/Application Support/TimeTug/`, so existing users' data has to move out of it while the app can still read it.

## Decision
- **Files** (`accounts.json`, `sync-state.json`, `takeover-ledger.json`, `dedup-state.json`) live in `<App Group container>/TimeTug/` (`AppSupportFiles`). The old files are copied there once, at launch, and only when the group does not already have the file; they are never overwritten or deleted. An ad-hoc build has no group container and keeps using the old folder.
- **Preferences** live in the group suite (`GroupDefaults.suite`). The known keys are copied once per build from `UserDefaults.standard` and never overwrite a value already in the group. Sparkle's keys, the beta opt-in and the global shortcut (KeyboardShortcuts uses `UserDefaults.standard`) stay per build.
- **Order matters**: the move into the group ships in a build that is still unsandboxed, so the copy can read the old folder; the sandbox ships after it.
- **Credentials share the keychain group when the build is profile-signed** (added after this was first written; the original finding follows). `sign-app.sh` embeds the Developer ID provisioning profile (`MACOS_PROVISIONING_PROFILE_BASE64`) and adds `keychain-access-groups: YYA6ZKMD36.com.timetug.shared`, which the profile's `YYA6ZKMD36.*` allowance covers. `AppCredentials` uses the group only when the running build holds that entitlement, and migrates the old private item on first read. Ad-hoc, CI and Xcode builds cannot hold a restricted entitlement and keep a private item. The private item is pinned to the login keychain: an unpinned query also reaches the group's data-protection item (same service and account), and removing the old item deleted the migrated one. A profile signed build verified the move: old item copied into the group, then removed, and readable from the group.
- **Originally credentials stayed in each build's own Keychain item.** A shared keychain access group was tried: `kSecAttrAccessGroup` with the app group id fails with `errSecMissingEntitlement` (-34018) with or without the sandbox, because the explicit `keychain-access-groups` entitlement is needed, and that restricted entitlement needs a provisioning profile. The Developer ID release pipeline signs without a profile (the team-prefixed `application-groups` entitlement does not need one). Sharing credentials across builds therefore needs a Developer ID profile in the release pipeline; until then each build signs in once. The migration code is parked on the branch `app-store/keychain-group-wip`.
- The `KeychainCredentialStore` documents that one process is the credential authority (refresh-token rotation is atomic only inside it). Two builds sharing a keychain group would need the single-instance rule first.

## Consequences
- Settings, accounts and the takeover ledger carry over between builds that share the group.
- A build that is not team-signed keeps a separate copy in `~/Library/Application Support/TimeTug/`, so a dev build never touches a user's data.

## Sandbox outcome
The main app is sandboxed (`Apps/macOS/project.yml`, generated into `Sources/TimeTug.entitlements`).

- **Entitlements**: `app-sandbox`, `network.client`, `network.server` (the OAuth loopback `NWListener`), calendars, address book, and the team `application-groups`.
- **Sparkle** (2.10.0) follows its sandbox guide: Info.plist `SUEnableInstallerLauncherService`, plus `temporary-exception.mach-lookup.global-name` for `com.timetug.app-spks` and `com.timetug.app-spki`.
- **The mach-lookup ids must be literal.** The release pipeline re-signs with the raw checked-in entitlements file, which does not expand `$(PRODUCT_BUNDLE_IDENTIFIER)`. With the variable, a sandboxed to sandboxed Sparkle update failed with "installation data was never received".
- **Verified** with a Developer ID signed build, no provisioning profile, over real data: it launches, Google and Microsoft accounts stay connected, the migrated state is present, and there are no unexpected sandbox denials (`system-info vfs.disk-space` is harmless). Sparkle updates worked for both hops, unsandboxed to sandboxed and sandboxed to sandboxed.
- The unit tests run inside the real app, so `AppDelegate` skips the coordinator when `XCTestConfigurationFilePath` is set. Without that guard the tests wrote empty settings into the real group.
- The interactive items are in the Sandbox section of `docs/manual-tests/macos-checklist.md`.
