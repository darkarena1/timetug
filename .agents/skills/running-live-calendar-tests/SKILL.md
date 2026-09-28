---
name: running-live-calendar-tests
description: Use when calendar write code (creating, updating or deleting events through EventKit, Google, Microsoft or iCloud) must be checked against a real account, or when asked for live, smoke or end-to-end calendar tests.
---

# Running live calendar tests

Live write tests are opt-in, touch the user's real calendars and never run in CI. Run one only when the user asks, or after asking them. Google and Microsoft open an interactive sign-in, so the user has to be present.

| Target | Command |
| --- | --- |
| Apple Calendar (EventKit) | `TIMETUG_LIVE_EVENTKIT=1 swift test --package-path Packages/EventKitSource --filter eventKit` |
| Google | `TIMETUG_LIVE_GOOGLE=1 GOOGLE_OAUTH_CLIENT_ID=... GOOGLE_OAUTH_CLIENT_SECRET=... swift test --package-path Packages/CalendarApple --filter googleWriteSmoke` |
| Microsoft | `TIMETUG_LIVE_MICROSOFT=1 MICROSOFT_OAUTH_CLIENT_ID=... swift test --package-path Packages/CalendarApple --filter microsoftWriteSmoke` |
| iCloud | `TIMETUG_LIVE_ICLOUD=1 swift test --package-path Packages/CalendarConnectors --filter iCloudLiveSmoke` |

- EventKit: every live test id starts with `eventKit`, so `--filter Live` matches nothing. xctest may lack calendar permission. If so, run the tests from a bundled context.
- Google and Microsoft write attendee-free events named "TimeTug write smoke" to the primary calendar and then delete them. Google's events scope cannot create calendars, so the primary calendar is used.
- The client ids come from the user's OAuth xcconfigs (see the `configuring-local-app-builds` skill). Have the user export them in their own shell, or read the values from those files into the environment. Never echo them or paste them into chat, logs or commit messages.
- If a run fails midway, tell the user that "TimeTug write smoke" events may be left on the primary calendar.
- iCloud needs no interactive sign-in: the test reads `~/.config/timetug/icloud-live` (line 1 the Apple ID, line 2 an
  app-specific password from account.apple.com > Sign-In and Security). Never read, print or paste that file. The user
  creates a calendar named "TimeTug Live Test"; the test writes only there and deletes only the events it made (titles
  starting with "TimeTug write smoke"). Optional: `TIMETUG_LIVE_ICLOUD_ATTENDEE=<an address the user reads>` checks
  whether iCloud honors `SCHEDULE-AGENT=CLIENT`; if it does not, iCloud may send a real invitation and cancellation to
  that address, so use one the user owns and ask first.
- Paste the `LIVE` lines into the Phase 5 spec's "Live findings".

The write rules these tests exercise are in `AGENTS.md` under "Gotchas" ("Calendar writes are opt-in").
