# macOS manual checklist
Run before a release, and after touching overlay, status item or scheduling code.

- [ ] First launch with no opted-in calendars opens Settings.
- [ ] Denying calendar access shows the orange banner with a working "Open System Settings" link.
- [ ] Popover: ended events greyed, in-progress bold with dot, all-day shows "All day".
- [ ] Takeover fires at lead time on every connected display; lead time 0 fires at start.
- [ ] On a real takeover, Join opens the link and closes the overlay; Return joins; Esc dismisses; Snooze re-fires later. (Settings' "Test tug" Join only closes the overlay; it never opens the sample URL.)
- [ ] Overlay covers a full-screen app and follows display plug/unplug.
- [ ] Takeover backdrop is a blurred navy layer: windows and Calendar content behind it are not readable. With Reduce Transparency on it is a solid navy.
- [ ] Primary display shows the puppy hero, a big countdown (soft blue, turning orange with a gentle pulse under a minute), "Starting now" (orange) and "Started N min ago" (red-orange); details line shows time range, calendar and people count.
- [ ] Join, the Snooze menu (1, 5, 10 minutes) and Dismiss all work; Return joins (dismisses when there is no link), Esc dismisses, 1/5/0 snooze 1/5/10 minutes, and the hint line lists only what applies.
- [ ] Other displays mirror the countdown and title with the app icon and "Dismiss on your main display", and no buttons.
- [ ] VoiceOver announces the meeting when the takeover appears and focus starts on Join (Dismiss without a link).
- [ ] Reduce Motion: no fade-in and no countdown pulse.
- [ ] Sleep the Mac through a meeting start; on wake with the meeting in progress the overlay appears with "Started N ago".
- [ ] Changing the system clock/timezone recomputes the schedule.
- [ ] A meeting at 12:05 AM with a 10 min lead fires at 11:55 PM and does not repeat after midnight.
- [ ] Declined, all-day and non-opted-in events never take over. Solo events (no other attendees) take over unless "Require other attendees" is on.
- [ ] Menu bar modes: icon only, next meeting (long titles truncated), countdown only.
- [ ] Launch at login toggle works.
- [ ] Settings sidebar order is General, Accounts, Calendars, Tug Rules; General has "Software Update" (first), "App", "Shortcut", "Menu bar" and "Appearance" (last) sections.
- [ ] Left-click popup: it is only as tall as its content (one event = short popup; many events scroll the list under a fixed header, max about 520 pt); light and dark both look right.
- [ ] Popup header shows the weekday, the date and "N meetings left" ("No meetings today" when empty, with the puppy empty state); the gear button opens Settings.
- [ ] Event cards use the real calendar colors; the current meeting shows a "Now" pill and a progress bar; the next meeting has the blue border and an orange "in 3h 40m" countdown; finished meetings stay readable.
- [ ] The Join button on the next or current meeting (labelled Zoom / Google Meet / Teams / etc.) opens the link and closes the popup.
- [ ] Popup footer shows the lead time ("Tugs you 1 min before", "Tugs you at start").
- [ ] Right-click the menu bar icon: About TimeTug (own window, follows Light/Dark), Check for Updates…, separator, Settings…, separator, Quit TimeTug. The About window shows logo, version and Done.
- [ ] Appearance Auto/Light/Dark changes Settings, the popover and the About window; Auto follows the OS setting (the takeover overlay stays dark).
- [ ] Settings > General > Appearance > Popup cards: switch Glass / Frosted / Solid and open the popup: cards change live; with Reduce Transparency on the cards are solid.
- [ ] About window is readable in both Light and Dark appearance (logo lockup, tagline pill, version, Done).
- [ ] Calendars pane lists calendars grouped by account (section header per account, "Other" when unknown) under pinned "Calendar / Tug / Show in list" column headers; checkboxes line up under the headers, also after scrolling.
- [ ] With VoiceOver on, each calendar checkbox is announced with the calendar name ("Tug for <name>", "Show <name> in list") and Space toggles it; checkboxes are reachable with Tab/keyboard navigation.
- [ ] Tug Rules "Lead time" is a menu picker ("At start", "1 minute", ... "30 minutes"); a previously saved odd value (e.g. 7 minutes) still appears and is selected.
- [ ] Turning on "Require a video link" shows the orange "Meetings without a link won't tug you." note; turning it off hides it.
- [ ] Menu bar icon turns to the color puppy within 10 minutes of a tug-worthy meeting and returns to the template icon after Join/Dismiss or when the meeting ends (works in light and dark menu bars).
- [ ] With Xcode (or any app) frontmost on the same display, right-click the icon: Settings and About open in front of it.
- [ ] With Xcode full-screen on a display, invoke Settings/About from that display: they appear over it in the current Space.
- [ ] With two displays, Settings/About open on the display whose menu bar icon you clicked.
- [ ] Settings > General > Shortcut: record a shortcut; from another app press it: the popup appears under the menu bar icon and takes keyboard focus. Press it again: the popup closes.
- [ ] Clear the shortcut with the recorder's ✕: pressing the old combination no longer does anything. A system-reserved combination shows the library's warning.
- [ ] Dismiss a takeover, then quit and relaunch the app during the meeting: no second takeover for it.
- [ ] Launch the app 10 minutes into a meeting that qualifies: no takeover for it.
- [ ] Delete or decline a meeting right before its takeover is due: no takeover appears.
- [ ] Edit a meeting's title after its takeover: no second takeover. Move its time: a new takeover appears for the new time.
- [ ] Two meetings starting together: the second takeover appears after you dismiss the first.
- [ ] Ledger file does not grow: after several days of use `~/Library/Application Support/TimeTug/takeover-ledger.json` only contains recent meetings.
- [ ] Installer DMG (from a CI artifact or a release): opening it shows a cream window with the TimeTug icon on the left, the Applications shortcut on the right, a blue arrow between them and "Drag TimeTug to Applications"; no toolbar, sidebar or status bar.
- [ ] Dragging TimeTug onto Applications copies the app (it then launches from /Applications); Eject works afterwards and the mounted volume shows the TimeTug icon.

## General tab and Appearance
- [ ] Settings sidebar shows General, Appearance, Accounts, Calendars, Tug Rules in that order.
- [ ] Settings > General > About pushes the About sub-page with a working back button; content matches the standalone About window (right-click menu bar icon → About TimeTug).
- [ ] Settings > General > Software Update pushes the Software Update sub-page with a working back button; Check for Updates, Automatic updates and Beta updates all work as before.
- [ ] Settings > Appearance: Menu Bar Text tiles change the real menu bar, Popup Cards tiles change the real popup's card style, and Light/Dark/Auto tiles change the app's appearance; verify all three groups in both light and dark system appearance.
- [ ] Sidebar search reveals controls correctly: a Software-Update-related query lands inside the Software Update sub-page (not just the General hub); an Appearance-related query lands on the Appearance pane.
- [ ] With VoiceOver on, the Menu Bar Text and Popup Cards tiles read sensible labels, including selected state.

## Updates
- [ ] Settings > General shows Software Update with the current version, Check for Updates, Automatic updates and Beta updates.
- [ ] Right-click the menu bar icon: the menu has "Check for Updates…".
- [ ] Against a test appcast (`defaults write com.timetug.app SUFeedURL <url>`; the feed needs a validly EdDSA-signed item): a newer stable item is offered; a beta item is offered only with Beta updates on; turning it off and checking again offers only stable. Afterwards `defaults delete com.timetug.app SUFeedURL`.
- [ ] Installing an update relaunches the app and widgets still load (team-signed build).

## Duplicate detection (beta)
- [ ] Settings > Calendars: the on-device intelligence toggle is off by default and shows a Beta badge.
- [ ] With it off, "Scott: Doctor" vs a detailed entry for the same appointment stay separate.
- [ ] With it on and Apple Intelligence available, the pair merges and shows "Merged with Apple Intelligence".
- [ ] "Unmerge all" (card menu or right-click) splits it, and it stays split after relaunch.
- [ ] "Merge with..." on a separate look-alike merges it and shows "Merged manually".
- [ ] On a Mac without Apple Intelligence, the status line says rules only and nothing is merged by the model.
- [ ] A merged meeting takes over exactly once.
- [ ] A merged meeting with a longer placeholder copy: the list shows the longer time range; the takeover fires at the appointment's start when a copy has a conference link, otherwise at the longer copy's start.
- [ ] A merged card shows a chevron with "Merged with Apple Intelligence · N events" (or "N events merged"); clicking expands one row per distinct event, with identical copies collapsed into one row marked "×N" with its calendar, account and own time range, and the shown copy is tagged. The popup grows and shrinks with it.
- [ ] Hovering the merged-events line shows the titles joined with " + ".
- [ ] Identical copies alone (same title and time on several calendars) show as one plain card: no chevron, no badge, no "Unmerge all".
- [ ] With a placeholder merged into identical copies, "Split off" on the placeholder row leaves the copies merged and the placeholder as its own card; it stays that way after relaunch.
- [ ] Three identical copies plus a placeholder show two rows; "Split off" on the copies row (×3) leaves the placeholder as its own card and the copies merged. The Split off button reads correctly with VoiceOver ("Split off: <title>, 3 copies").
- [ ] "Forget learned corrections" resets decisions and clears cached AI verdicts.

## Widgets and controls (needs a team-signed build)
- [ ] Set up local signing once: `~/.config/timetug/signing.xcconfig` (see AGENTS.md "Widgets and controls"), run `xcodegen generate --spec Apps/macOS/project.yml`, then a `clean` build/Run in Xcode. Confirm `codesign -d --entitlements - TimeTug.app` shows the `YYA6ZKMD36.com.timetug.shared` group on the app and on `PlugIns/TimeTugWidgets.appex`.
- [ ] Add each widget and size from the widget gallery: Next Up small and medium, Today medium and large.
- [ ] Widgets show real meetings with the right calendar colours.
- [ ] Next Up advances to the next meeting at a meeting's start and end without reloading the widget.
- [ ] Today dims meetings that have already ended (visible on the large widget, or on the medium widget when the day has at most 2 meetings; medium shows 2 rows).
- [ ] Deleting `agenda-snapshot.json` from `~/Library/Group Containers/YYA6ZKMD36.com.timetug.shared/` makes the widgets show the placeholder; it recovers when the app next publishes.
- [ ] Clicking a widget with a meeting that has a Join link opens the link; without one it just activates the app.
- [ ] Each of the three controls (Skip All Day Events, Use Intelligence, Enable Tug) flips the matching Settings toggle and behaves as expected (Enable Tug: no takeover fires while off; it starts on).
- [ ] Toggling each setting in Settings updates the matching control in Control Center.
- [ ] An ad-hoc build runs normally, with no widgets loading and no crash.
- [ ] Settings > Accounts lists "Apple Calendar (this Mac)" with an enable checkbox and a `+ −` bar. Turning the checkbox off removes the Apple calendars from Calendars and the popup; turning it back on restores them with their Tug/Show choices intact.
- [ ] With Calendar access denied in System Settings, the Apple Calendar row says "Calendar access is off" and "Open System Settings" opens the Calendars privacy pane.
- [ ] (Needs the Google client) `+` > Google opens the browser; after signing in the account appears with its email as status "Connected" and its calendars appear in Calendars under that email. Cancel during "Waiting for your browser…" leaves nothing behind.
- [ ] Adding a second Google account works; adding the same account again says it is already added and leaves no extra Keychain item.
- [ ] Select an account and `−`, confirm: its calendars and their Tug/Show choices disappear, the Keychain item (service com.timetug.app.credentials) is gone, and relaunching does not bring it back.
- [ ] Relaunch: Google accounts reconnect with no browser and no prompt.
- [ ] Revoke TimeTug at myaccount.google.com/permissions: within a minute the account shows "Sign in again"; clicking it and signing in as the same account restores it and edits made in Google appear within about a minute (the change listener restarted). Signing in as a different account is refused.
- [ ] Edit an event's title in Google Calendar: the popup shows the new title within about a minute.
- [ ] An all-day event created in Google in another time zone (for example a Tokyo calendar) appears on the same calendar date in the popup here, and an Apple all-day event created in another zone still appears on its date.
- [ ] A meeting present in both Apple Calendar and a direct Google account merges into one popup entry.
