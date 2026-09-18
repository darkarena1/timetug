# TimeTug: Core App Design

Date: 2026-09-18
Status: Draft for review
Scope: Sub-project 1 of 3 (core app + Apple Calendar source + takeover).
Out of scope here: public plugin loading (sub-project 2), Google/iCloud/Exchange sources (sub-project 3), Windows/Linux front ends.

## Purpose

TimeTug is a macOS menu bar app that reads calendars, lists the day's events, and takes over every screen shortly before a meeting so a hyper-focused user gets to it on time.

## Decisions

| Topic | Decision |
|---|---|
| Language / UI | Swift; SwiftUI + AppKit; Swift Package Manager modules |
| Takeover style | Full-screen overlay on all displays at a configurable lead time; user can Join, Snooze or Dismiss. Lead time 0 = "meeting is starting now" |
| Which events take over | Per-calendar opt-in, plus toggleable filters, default on: skip declined, skip events with no other attendees; optional "video link only". All-day events never take over. A separate "Skip all-day events" toggle (default on) only hides them from the day list |
| Dropdown | All events on opted-in calendars for today; finished events greyed out |
| Sources | Open-source repo; sources isolated behind a small `CalendarSource` protocol so runtime plugins and other front ends are possible later. No runtime plugin loading now |
| Time window | Current local calendar day for display; fetch extends to next midnight + lead time + buffer for takeover scheduling |
| Portability | Core is pure Swift and platform-neutral. Each OS front end owns presentation and how the app lives in the system |

## Repo layout

```
TimeTug/
├── AGENTS.md              # conventions, commands, gotchas (CLAUDE.md points here)
├── docs/
│   ├── architecture.md
│   ├── decisions/         # ADRs (why Swift, module boundaries, day window, link allowlist)
│   ├── manual-tests/      # checklists for window/status-item behavior
│   └── superpowers/specs/
├── Packages/
│   ├── TimeTugCore/       # pure Swift, no UI, no Apple-only imports
│   ├── EventKitSource/    # Apple Calendar adapter (macOS only)
│   └── (future) GoogleSource, CalDAVSource, ExchangeSource
└── Apps/
    └── macOS/             # menu bar, dropdown, overlay, settings
```

Dependencies point toward Core: `Apps/macOS -> EventKitSource -> TimeTugCore`, and `Apps/macOS -> TimeTugCore` directly. Core defines the `CalendarSource` protocol and imports nothing else; each source package implements it. The app is the composition root: it is the only place that knows which concrete sources exist, and it owns any source configuration UI (sign-in, server settings) and credential storage. Source packages contain no UI.

## TimeTugCore

Core answers "what and when". The native app answers "how it looks and where it lives". If a function needs to know a window, tray or pixel exists, it belongs in the app.

Contents:

- **Model:** `CalendarEvent` (id, title, start, end, all-day, attendees, response status, location, notes, url, optional `conferenceURL`, calendar id), `CalendarInfo`.
- **`CalendarSource` protocol:** list calendars, fetch events for a `DateInterval`, and a change stream. Returns normalized model only; EventKit types never leak. Reports a status: `ok`, `needsPermission`, `authExpired`, `failing(reason)`.
- **`CalendarStore`:** merges and de-duplicates events from all sources (by lowercased title + start + end, so one meeting on several calendars appears once), keeps last-good events per source, publishes a snapshot.
- **`TakeoverPolicy`:** pure functions deciding whether an event qualifies (opt-in, filters).
- **`Scheduler`:** given a snapshot, policy, lead time and injected clock, computes the next fire moment and emits `TakeoverRequest`.
- **`ConferenceLinkDetector`:** see below.
- **Shared settings model** (Codable, no storage): lead time, opted-in calendars, filter toggles.
- **Plain view-state data:** `DayAgenda` (today's events, each past/upcoming, plus next event), `TakeoverRequest` (title, times, join link, snooze options, already-started flag). No display strings, no menu bar mode enums.

## Data flow

1. Launch: request calendar access, load sources.
2. `CalendarStore` fetches each source for the **fetch window**: local midnight today through next local midnight + lead time + buffer (5 min, named constant).
3. Sources signal changes (EventKit `EKEventStoreChanged`); the store re-fetches that source. A periodic refresh every few minutes is a safety net.
4. The store publishes a snapshot. `Scheduler` computes the next fire moment; the app arms one timer for it.
5. On fire, Core emits a `TakeoverRequest`; the native app renders it.

**Display window vs. fetch window.** The dropdown shows today only. An event after midnight appears there only once inside its lead-time period, but it is in the takeover queue the whole time (a 12:05 AM meeting with a 10 min lead fires at 11:55 PM).

## Robustness

- Recompute the schedule on wake, system clock change and timezone change. Timers alone are not trusted.
- **Late fire:** if the lead time has passed but the meeting has not ended, show the takeover immediately, marked already started.
- **No repeats:** remember fired events by id + start. Edited/rescheduled events count as new. At midnight, prune the fired memory by event end time (not wholesale) so a 11:55 PM takeover does not repeat after rollover.
- **Snooze:** re-arms the same event; capped at the meeting's end.
- **Source failure isolation:** one failing source does not affect others. Takeovers fire from last-known events even if a refresh just failed. Source problems are visible in the dropdown and settings, never silent.

## Conference link detection

Two layers:

1. **Structured:** sources fill `conferenceURL` from structured fields (EventKit `url`; later Google `conferenceData`/`hangoutLink`, Exchange `onlineMeetingUrl`). Core trusts it.
2. **Fallback text scan** in `ConferenceLinkDetector` over location, then url, then notes, matching a **known-provider allowlist**: Zoom (`zoom.us`, `zoom.com`, `zoommtg://`), Google Meet, Microsoft Teams (`teams.microsoft.com`, `teams.live.com`), Webex, GoTo, Whereby, Jitsi, Slack huddles. Normalizes wrapped links (Outlook SafeLinks, Google redirects), strips HTML, trims trailing punctuation.

Choices: allowlist rather than "any URL" (avoid a Join button that opens a Google Doc); if the event's own `url` field is set but not on the allowlist, still offer it as Join; dial-in numbers ignored in v1. The provider list is data and a documented extension point.

## macOS app (`Apps/macOS/`)

- **Shell:** menu bar-only (`LSUIElement`), launch at login via `SMAppService` (setting). `AppCoordinator` wires sources, store, scheduler and overlay.
- **Status item:** icon only by default. Optional modes (off by default): next-meeting title, or countdown-only. The mac layer formats and truncates text; updates each minute, each second in the final minute.
- **Left click:** dropdown (NSPopover or NSMenu, decided in planning) of today's events; finished greyed out, current emphasized, source problems at top. **Right click:** Settings, Quit.
- **Overlay:** one borderless window per display at a high window level (covers full-screen apps), tracks display connect/disconnect. Primary display: title, time, live countdown, large **Join** (if link), **Snooze** (1/5/10 min, capped), **Dismiss**. Other displays: dimmed cover with title. Return joins, Esc dismisses; overlay takes key focus so stray keystrokes do not reach background apps. Shows "Started N min ago" for late fires. Respects reduce-motion and accessibility labels.
- **Settings** (SwiftUI, stored in `UserDefaults` as the Core Codable model): lead time (a picker; 0 labelled "At start"); per-calendar tug opt-in (the "Tug" checkbox; calendars are listed grouped by account) and separate dropdown visibility (default on); takeover filters (video-link only default off; skip solo and skip declined default on; all-day events never take over); "Skip all-day events" (default on, in the Calendars section) only hides all-day events from the day list; menu bar display mode; launch at login; a "Test tug" button. Settings panes: General (launch at login, About, menu bar mode, Appearance last), Calendars, Tug Rules. Tug and "Show in list" are coupled: turning Tug on shows the calendar in the list, and hiding a calendar turns its Tug off.

## Testing

- Core (scheduler, policy, store, detector) is pure Swift with an injected clock and fake sources: covers sleep/wake, late fire, duplicates, midnight rollover, snooze cap, day-boundary fetch.
- Detector has a fixture set of real-world invite bodies (Zoom, Teams, Meet, wrapped links, HTML, multiple links).
- macOS window/status-item behavior: manual checklist in `docs/manual-tests/`; snapshot tests for overlay layouts if cheap.

## AI-first repo practices

- `AGENTS.md` at root (with `CLAUDE.md` pointing to it): build/test commands, module boundaries, the Core-vs-app rule above, gotchas.
- ADRs in `docs/decisions/` for each decision in the table.
- Small, single-purpose modules and files; strict typing; protocol boundaries; tests for all Core logic; conventions documented, not implied.

## Known simplifications

- Display window is the current day only; may widen later (single parameter in the store).
- No dial-in number detection.
- No runtime plugin loading.
