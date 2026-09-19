# Calendar de-duplication with rules and optional on-device inference

Status: design approved 2026-09-19. Supersedes the exact-match merge in `CalendarStore.merged(within:)`.

## Goal

Recognize that events on different calendars are the same meeting even when titles differ
("Scott: Doctor" on one account, "Intermountain Health" on another), without merging events
that are genuinely separate ("Kristin: Logan Dance"). Deterministic rules decide most cases.
An optional on-device model decides only the ambiguous remainder. The user can always correct it.

## Non-goals

- Cloud inference. Only on-device engines are allowed.
- Training or fine-tuning a model, or inferring broad rules from corrections.
- Merging events on the same calendar (except the existing exact-match behavior).
- Windows/Linux inference adapters (the interface must allow them; they are built later).

## 1. Decision pipeline (TimeTugCore, deterministic)

Evaluated per pair of events, in this order:

0. **Learned pair memory** (section 4b) wins over everything below when it has an entry.
1. **Exact match:** same lowercased title, start and end. Merge (existing behavior).
2. **Same calendar:** separate. Never sent to inference.
3. **Time gate (candidates only):** intervals overlap, |start difference| <= 30 min and
   |end difference| <= 60 min. Pairs outside the gate are separate. The end tolerance is
   deliberately looser because end times are uncertain and may include travel.
4. **Strong match, merge** on any of: same conference URL or meeting ID; same iCal UID; a shared
   attendee email; same normalized location.
5. **Veto, separate:** a hard field present on BOTH events with different values (location,
   conference link, attendee sets with no overlap). The veto never fires when a field is
   absent on either side. Inference is not consulted.
6. **Ambiguous:** none of the above decided the pair. This bucket may go to inference.

A **sparse** event has no location, conference link, attendees or notes. Inference may run when
ONE event is sparse and the other rich (an official appointment plus a placeholder). The rich
event's details are evidence in the prompt. Inference may also run when both are sparse.

All-day events merge only on an exact match and are never sent to inference. A learned `same` lesson still requires the time gate; a learned `different` lesson is consulted inside the gate too (outside it the rules already keep the pair separate).

Grouping is conservative: a merge group is only extended when the candidate is consistent with
every member (no member vetoes it). Group size is capped (default 4).

## 2. Inference boundary

Core defines (no Apple or UI imports):

```swift
public protocol DuplicateAdjudicator: Sendable {
    var availability: AdjudicatorAvailability { get }   // .available(EngineInfo) | .unavailable(reason)
    func judge(_ requests: [AdjudicationRequest]) async -> [AdjudicationVerdict]
}
```

- `EngineInfo`: stable `id`, `displayName` (product name such as "Apple Intelligence"), `isOnDevice`.
- `AdjudicationRequest`: both events (only the fields the judgment needs), calendar and account
  names, the rich/sparse roles, and up to about 5 relevant lessons.
- `AdjudicationVerdict`: `same` | `different` | `unsure`. Only `same` merges.

**Rules-only is the default and a normal mode.** If no adjudicator is injected, availability is
not `.available`, or `isOnDevice` is false, the ambiguous bucket stays unmerged and the adjudicator
is never called. Core refuses non-on-device engines regardless of what the app injects.

`Packages/AppleIntelligenceInference` (new, macOS 26+, Swift 5 mode like the other Apple packages):
Foundation Models adapter with structured (guided) output. Reports `.available` only when
`SystemLanguageModel.default` reports the model ready; otherwise `.unavailable` with a reason.
Sends only: titles, times, location, attendee names (no emails), calendar and account names,
notes truncated to about 500 characters, and lessons.
`AdjudicationEvent` (Core) truncates notes to 500 characters and carries attendee names only; the prompt builder cannot see emails. The prompt builder is a pure function.
The app is the composition root: it constructs the adapter and injects it. Other platforms add
sibling packages later.

Settings: a toggle "Find duplicates with on-device intelligence", **off by default** (opt-in),
marked with a **Beta** badge. The app always injects the adjudicator and Core gates on the enabled
flag, so when off the adjudicator is never called and behavior is rules-only, identical to the
no-engine case (pair memory from lessons still applies). When on, a
status line shows the engine, or why none is available (the toggle stays visible but inert, and
behavior remains rules-only). The setting is persisted in `SettingsStore`; toggling it takes
effect on the next refresh, and already-cached AI verdicts are ignored while it is off.

## 3. Async flow and caching

- `CalendarStore.refresh` returns the rules-merged snapshot immediately and never awaits inference.
- Ambiguous pairs go to a background resolver. Verdicts are cached on disk (same pattern as
  `LedgerStore`), keyed by a fingerprint of both events' relevant content, so an edited event is
  re-judged. Stale entries are pruned (ended events, TTL, size cap).
- When a verdict lands that changes the merge result, the store publishes an updated snapshot.
- A pending or missing verdict means "not merged".
- **Takeover safety:** a merged `CalendarEvent` carries the `contentKey` of every member.
  `TakeoverLedger` and `TakeoverGuard` treat the meeting as already fired or acknowledged if ANY
  member key was. This prevents a late merge from making the surviving copy take over a second
  time (the failure ADR 0006 fixed). Takeover timing never waits on inference.

## 4. Merge result, provenance and user override

- `mergedMembers` lists every original copy including the primary; the ledger, guard, unmerge and manual merge all work from it.
- The richer event is the primary, so the official title and details win. The other calendar key
  goes into `additionalCalendarKeys` as today. Missing details are borrowed as today.
- `MergeProvenance` on the event: `.rule`, `.inference(engineID, engineName)`, `.userConfirmed`.
  Core holds data only; the app produces text ("Merged with Apple Intelligence", "Merged
  manually") and the badge. `.rule` merges have no badge.
- AI merges are automatic (no confirmation), badged, with one-click **Not the same meeting**.
  Separate pairs that were candidates get a **Merge** action. Both create lessons and persist
  across relaunch. A user decision outranks rules and AI.

### 4b. Learning from corrections

Every unmerge and every manual merge saves one small **lesson**:
`{ normalizedTitleA, normalizedTitleB, calendarKeyA, calendarKeyB, decision(same|different),
signals summary, lastUsed }`. No notes, attendee names or emails are stored.

1. **Deterministic pair memory** (works in rules-only mode). A lesson keyed by the normalized
   title pair and calendar pair decides that pair immediately next time (recurring events).
   It is scoped to the exact pair on those calendars, not a global rule. It ranks above rules and
   AI (pipeline step 0). Only a new explicit correction changes it.
2. **Few-shot context for the model.** For an ambiguous pair, include at most about 5 lessons,
   chosen by similarity (shared title tokens, same calendar pair), not recency. Each is one compact
   line: both titles, both calendar names, the decision, and which signals were present.

Bounds: stored in a local file beside the takeover ledger; cap about 300 lessons (oldest first
out); refreshing a recurring pair updates its lesson rather than adding one; lessons expire after
about 6 months unused. Nothing leaves the device. Settings has "Forget learned corrections".
Settings > Calendars has a 'Forget learned corrections' button.

## 5. Data model changes

- `CalendarEvent`: add `attendees` (`[Attendee]`, name and optional email), `organizerEmail`,
  `externalUID`, `memberContentKeys`, `mergeProvenance`. Existing initializer defaults keep current
  call sites compiling.
- `EventKitSource`: populate attendees from `EKParticipant` (mailto URL when present), the
  organizer, and the external identifier. Emails are often missing (notably iCloud); the rules
  must degrade gracefully when they are.
- `CalendarInfo.accountName` is already available and is passed to the model as context.

## 6. Testing

- Core (Swift Testing, test first): exact match unchanged; same-calendar separation; time gate
  boundaries (30 min start, 60 min end, overlap); each strong-match rule; veto including "absent
  on one side is not a veto"; sparse+rich and sparse+sparse reaching the adjudicator; conservative
  grouping and size cap; the setting defaults to off and persists, and off means the adjudicator is
  never called and cached AI verdicts are ignored; rules-only when there is no adjudicator, `.unavailable`, or a non-on-device
  engine; `unsure` and `different` do not merge; verdict cache hit, miss and invalidation on edit;
  lesson storage, bounds, expiry, similarity selection and pair memory priority; user override
  outranks everything; takeover any-member ledger rule. All with a `FakeAdjudicator`.
- Apple adapter: prompt builder tests (fields sent, notes truncation, no emails). Model quality is
  checked with a small fixture set of real cases and a `docs/manual-tests/macos-checklist.md`
  entry, since the model is not deterministic.
- App: badge text logic as pure functions with tests. Visual layout is verified by hand.

## 7. Deliverables

- ADR `docs/decisions/0009-duplicate-detection-and-on-device-inference.md`.
- Update `docs/architecture.md`, `AGENTS.md` layout, and `docs/PROGRESS.md`.

## Open risks

- Foundation Models quality on sparse-vs-rich pairs is unproven; the fixture set should be built
  early and may show the prompt needs work.
- Missing attendee emails weaken the attendee rules for some accounts.
- Verdicts arriving after a takeover has been displayed can change the list mid-day; the
  any-member ledger rule covers takeover, and the list simply updates.
