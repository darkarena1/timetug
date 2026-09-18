# macOS manual checklist
Run before a release, and after touching overlay, status item or scheduling code.

- [ ] First launch with no opted-in calendars opens Settings.
- [ ] Denying calendar access shows the orange banner with a working "Open System Settings" link.
- [ ] Popover: ended events greyed, in-progress bold with dot, all-day shows "All day".
- [ ] Takeover fires at lead time on every connected display; lead time 0 fires at start.
- [ ] On a real takeover, Join opens the link and closes the overlay; Return joins; Esc dismisses; Snooze re-fires later. (Settings' "Test tug" Join only closes the overlay; it never opens the sample URL.)
- [ ] Overlay covers a full-screen app and follows display plug/unplug.
- [ ] Sleep the Mac through a meeting start; on wake with the meeting in progress the overlay appears with "Started N ago".
- [ ] Changing the system clock/timezone recomputes the schedule.
- [ ] A meeting at 12:05 AM with a 10 min lead fires at 11:55 PM and does not repeat after midnight.
- [ ] Declined, solo, all-day and non-opted-in events never take over.
- [ ] Menu bar modes: icon only, next meeting (long titles truncated), countdown only.
- [ ] Launch at login toggle works.
- [ ] Settings sidebar order is General, Calendars, Tug Rules; General has "App", "Menu bar" and "Appearance" (last) sections.
- [ ] Right-click the menu bar icon: About TimeTug (own window, follows Light/Dark), separator, Settings…, separator, Quit. The About window shows logo, version and Done.
- [ ] Appearance Auto/Light/Dark changes Settings, the popover and the About window; Auto follows the OS setting (the takeover overlay stays dark).
- [ ] About window is readable in both Light and Dark appearance (logo lockup, tagline pill, version, Done).
- [ ] Calendars pane lists calendars grouped by account (section header per account, "Other" when unknown) under pinned "Calendar / Tug / Show in list" column headers; checkboxes line up under the headers, also after scrolling.
- [ ] With VoiceOver on, each calendar checkbox is announced with the calendar name ("Tug for <name>", "Show <name> in list") and Space toggles it; checkboxes are reachable with Tab/keyboard navigation.
- [ ] Tug Rules "Lead time" is a menu picker ("At start", "1 minute", ... "30 minutes"); a previously saved odd value (e.g. 7 minutes) still appears and is selected.
- [ ] Turning on "Require a video link" shows the orange "Meetings without a link won't tug you." note; turning it off hides it.
- [ ] Menu bar icon turns to the color puppy within 10 minutes of a tug-worthy meeting and returns to the template icon after Join/Dismiss or when the meeting ends (works in light and dark menu bars).
- [ ] With Xcode (or any app) frontmost on the same display, right-click the icon: Settings and About open in front of it.
- [ ] With Xcode full-screen on a display, invoke Settings/About from that display: they appear over it in the current Space.
- [ ] With two displays, Settings/About open on the display whose menu bar icon you clicked.
