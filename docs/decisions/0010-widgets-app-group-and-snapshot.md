# 0010: Widgets and controls read an app-written snapshot in an App Group

Status: accepted, 2026-09-19

## Context
TimeTug should show the next meeting and today's agenda in WidgetKit widgets and let Control Center flip three settings (skip all-day events, use Intelligence, disable Tug). Widgets run in a sandboxed extension process, and the popover already applies duplicate merging, the Intelligence toggle and the all-day setting. A second EventKit reader in the extension would disagree with the popover and need its own permission prompt.

## Decision
- Widgets are a sandboxed WidgetKit extension (`TimeTugWidgets`, bundle id `com.timetug.app.widgets`) that reads an app-written `agenda-snapshot.json` in App Group `YYA6ZKMD36.com.timetug.shared`. They do not use EventKit, so dedup, Intelligence and all-day settings match the popover and there is a single calendar permission prompt.
- Three booleans (skip all-day, use Intelligence, disable Tug) live in the shared suite. Control Center intents run in the extension, write the booleans and post a Darwin notification; the app re-reads the suite (`SettingsStore.reloadFromShared()`). No payload travels in the notification, so there is no race over values. `SettingsStore` mirrors only the keys that changed into the suite.
- Core owns `WidgetSnapshot` and `WidgetTimeline` (what and when, no display strings). `TakeoverSettings.disabled` is enforced in `TakeoverPolicy.qualifies`, so Disable Tug holds for every front end.
- The three controls are macOS 26 only, behind `#available`. Widgets work on earlier supported versions.
- Timeline reloads are diffed and debounced: the app calls `WidgetCenter.reloadAllTimelines()` only when the published events changed.
- The app is the only writer of the snapshot; the extension only reads it.

## Consequences
- Widgets and controls need a team-signed build. Ad-hoc builds run normally, but the snapshot write logs and is skipped and widgets show the placeholder.
- Release signing must go inside-out: the appex is signed before the app (`build-release.sh` ad hoc, `sign-and-notarize.sh` with Developer ID). `verify-dmg.sh` checks the appex is embedded.
- The snapshot goes stale when the app is not running: widgets treat it as stale after 12 hours and the timeline has an hourly safety reload.
- Deviations decided while planning: no `DEVELOPMENT_TEAM` in `project.yml` (signed builds pass it on the command line; it would trigger automatic provisioning for ad-hoc CI builds); no URL scheme to open the popover (a widget tap opens the join link, else just activates the app); no extra menu bar indicator for a disabled Tug (the icon simply never turns colour; Settings and the control show the state).
- Accepted spec deviations: the spec's "merged flag" on snapshot events was dropped (YAGNI, nothing displays merge state); KVO on the shared suite was not implemented, instead a missed Darwin notification self-heals because `refresh()` re-reads the shared values every 5 minutes.
- The group container is `~/Library/Group Containers/YYA6ZKMD36.com.timetug.shared/` and is privacy-protected from some shells.
