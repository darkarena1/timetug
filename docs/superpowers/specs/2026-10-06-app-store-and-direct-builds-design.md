# Direct and App Store builds, shared state, one running instance

Status: draft for review, 2026-10-06.

## Goal
Ship TimeTug two ways from one codebase: the downloaded build (Developer ID, DMG, Sparkle) and a Mac App Store build. They behave the same except for updates. Both keep their data in the team's App Group, so a future second TimeTug app can share it. Only one TimeTug runs at a time, preferring the newest version.

## Decisions
1. **One codebase, two app targets.** `TimeTug` (direct) and `TimeTug-AppStore` come from one XcodeGen template and share `Sources`, `Resources`, `Shared` and the widget sources. Only these differ: Sparkle (direct only), bundle IDs, entitlements/Info.plist update keys, and the `APPSTORE` compilation condition.
2. **Both builds are sandboxed.** One set of behaviour to test. The direct build keeps Sparkle working in the sandbox (installer launcher service, mach-lookup entitlements, `network.client`).
3. **Separate bundle IDs, shared App Group.** Direct: `com.timetug.app` (widget `com.timetug.app.widgets`). App Store: `com.timetug.app.store` (widget `com.timetug.app.store.widgets`). The group `YYA6ZKMD36.com.timetug.shared` is already team-prefixed and is the sharing channel. Sharing does not depend on the bundle ID, so both builds can be installed side by side and a second product can join the group.
4. **State lives in the group, before sandboxing.** Order matters: an unsandboxed build can still read `~/Library/Application Support/TimeTug/`, a sandboxed one cannot. So the migration into the group ships first (in the direct build), and the sandbox comes second.
   - Preferences: `UserDefaults(suiteName: AppGroup.identifier)`. Known keys are copied once from `UserDefaults.standard`.
   - Files (`accounts.json`, `sync-state.json`, `takeover-ledger.json`, `dedup-state.json`): `<group container>/TimeTug/`. Moved once from the legacy folder; the old copy is left in place.
   - Credentials: data-protection Keychain with access group `YYA6ZKMD36.com.timetug.shared`. Items are moved lazily on first read: read primary, else read the legacy item, copy it to primary, delete the legacy one.
   - Ad-hoc builds (CI, local without a team) have no group container or keychain group. They fall back to the old locations and the legacy keychain, as the widget code already does.
5. **Known per-build state.** The global shortcut (stored by KeyboardShortcuts in `UserDefaults.standard`), launch at login (`SMAppService`) and Sparkle's own keys stay per build. The Settings text says so where it matters.
6. **One instance, newest wins.**
   - A lock file `instance.lock` in the group container, taken with `flock(LOCK_EX | LOCK_NB)`; the OS drops it when the process dies.
   - `instance.json` next to it holds the holder's `{bundleID, version, build, distribution}`.
   - A newcomer that gets the lock proceeds. A newcomer that cannot compares itself with the holder: newer (marketing version, then build) asks the holder to quit and waits up to 5 seconds for the lock, otherwise exits; older or equal exits at once. Version order treats `1.2.0-beta.N` as lower than `1.2.0`, and compares beta timestamps numerically.
   - The ask is cooperative: the newcomer writes `handoff.json` and posts the Darwin notification `com.timetug.instance.yield`. The holder re-checks that the requester really is newer, then quits itself. No process is killed.
   - This runs in `applicationWillFinishLaunching`, before any status item, window, calendar read or Sparkle start.
7. **Collision notice.** When a second copy is opened (whichever side wins), the surviving instance shows one quiet, non-modal notice: a banner in the menu dropdown and a line in Settings > General. It names the other copy (distribution and version) and suggests keeping only one installed. It can be dismissed; dismissal is remembered per pair of versions in the group defaults (`collision.dismissedPair.v1`). No alert, no modal, no uninstall action.
8. **Versioning.** The release version and when to cut it are decided by Scott when the release is made; nothing in this work picks or bumps a version.

## Out of scope
- Sharing the global shortcut or login-item state between builds.
- Migrating data from a sandboxed build back out, or from the direct build's legacy folder after sandboxing (the move into the group happens in the last unsandboxed build).
- The second app itself.
- App Store pricing, in-app purchase, TestFlight external testing groups.
- Stable-beats-beta tiebreaks beyond version order (a `-beta` build of the same base version loses to the stable one).

## Risks and unknowns
- The keychain access group may need an explicit `keychain-access-groups` entitlement and a provisioning profile that grants it for Developer ID. Task 3 verifies this on a signed build before anything depends on it.
- The OAuth loopback listener (`NWListener` in `CalendarApple/LoopbackAuthorizationInteraction.swift`) needs `com.apple.security.network.server` under the sandbox. Task 6 verifies a real sign-in.
- Both builds installed means two widget sets in the widget gallery. Accepted; the notice tells people to keep one.
- App Review may question the full-screen takeover. The review notes explain that it is opt-in and dismissible.
- Both builds are named `TimeTug.app`, so both cannot sit at `/Applications/TimeTug.app`; the App Store would replace the downloaded copy. Two copies at once come from renamed copies, other folders or volumes, and version skew, which is what the single-instance rule covers. The widget gallery lists both widget sets when both are installed.
