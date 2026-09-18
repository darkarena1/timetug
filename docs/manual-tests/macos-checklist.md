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
- [ ] Settings sidebar order is General, Calendars, Tug Rules; General has "Menu bar" and "App" sections; "About TimeTug…" opens a sheet with logo, version and Done.
