# ADR 0006: Persisted Takeover Ledger and Fire-Time Guard

**Status:** Accepted

## Context

The full-screen takeover sometimes appeared for a meeting that already had one, or that no longer qualified. Five causes: (1) the ledger of fired/snoozed events was in memory only, so every relaunch made in-progress meetings fire again; (2) `AppCoordinator.fire` trusted the event captured when its timer was armed, so a deleted, moved, declined or opted-out meeting still took over; (3) identity was `TimeTugCalendarEvent.id`, and EventKit's `eventIdentifier` can change after an edit or sync; (4) a second timer firing while an overlay was visible replaced it, losing the first meeting; (5) a cold launch fired "Started N min ago" for meetings the user was already in.

## Decision

- **Persisted ledger:** `TakeoverLedger` is `Codable`; the app stores it as JSON at `~/Library/Application Support/TimeTug/takeover-ledger.json` (`LedgerStore`, atomic writes) and saves after every mutation. A missing or corrupt file loads as empty and is logged.
- **Dual-key identity:** every mutation is recorded under `event.id` and `event.contentKey` (`title|start|end`, lowercased title). Lookup tries the id, then the content key. A changed source id is still the same meeting; a moved meeting (new start) is new.
- **Fire-time guard:** `TakeoverGuard.evaluate` runs before anything is marked or shown. Order: `overlayVisible`, `notInSnapshot`, `ended`, `noLongerQualifies`, `alreadyFired`, else `present`. It judges the current copy of the event from the latest snapshot, so edits apply.
- **Queue, not drop:** `overlayVisible` never marks the event fired; it stays pending and `closeOverlay()` re-arms, so the second meeting appears after the first is dismissed. Any other suppression just re-arms.
- **Cold-launch suppression:** after the first successful refresh following launch (not wake, clock or day-change refreshes), `acknowledgeInProgress` marks un-ledgered meetings that started more than 120 s ago and have not ended as fired, before the first arm. Late fire after wake is unchanged.
- **Bounded file:** each record stores `recordedAt`. `prune(now:)` drops records whose event ended or that are older than 7 days (protects against bogus far-future ends), then caps the ledger at 2000 events, oldest first. Prune runs at launch right after load, at the start of every refresh (saving only when something was removed), and inside `LedgerStore.save`, which never writes expired entries. Files lacking `recordedAt` drop those records instead of crashing.
- **Logging:** every decision is logged via `os.Logger` (subsystem `com.timetug.app`, category `takeover`) with why: lead time, late after wake, snooze expired, or the suppress reason. Event titles are `.private`; ids and reasons are public.

## Consequences

- Relaunching, crashing or re-running from Xcode never repeats a takeover; launching mid-meeting never interrupts it.
- A retitled meeting with the same source id does not repeat; deleting and recreating identical content within its window does not repeat either (accepted).
- The ledger file is tiny and self-cleaning. Real relaunch behavior and log output are verified by hand (`docs/manual-tests/macos-checklist.md`).
