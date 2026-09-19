# 0009: Duplicate detection with rules first and optional on-device inference

Status: accepted, 2026-09-19

## Context
The exact title+time merge misses real duplicates ("Scott: Doctor" vs "Intermountain Health") and cannot use shared people, places or conference links. Inference is platform specific and unproven, and a wrong merge hides a real appointment.

## Decision
- Core owns a deterministic pipeline (exact match, time gate of 30 min start / 60 min end, strong matches, vetoes) and only sends the leftover ambiguous pairs to a `DuplicateAdjudicator` protocol.
- Inference lives in per-platform packages behind that protocol (`Packages/AppleIntelligenceInference` first). It must be on-device. It is opt-in, default off, marked Beta; unavailable or off means rules only.
- Verdicts are asynchronous and cached; refresh and takeover never wait on a model, and a pending pair is simply not merged.
- Merges are non-destructive (`mergedMembers` keeps every copy) and badged by provenance; user merge/unmerge decisions become small bounded lessons that decide the exact pair next time and inform the model prompt.
- The takeover ledger and guard match on any member's content key so a late merge cannot re-fire a meeting.
- Bounds: rule and user merges are uncapped (every exact duplicate joins one card), while model verdicts join at most 4 clusters of certain duplicates into one group, the lesson book keeps at most 300 lessons, the verdict cache at most 1000 verdicts, a verdict lives 7 days, and notes sent to a model are cut to 500 characters.
- Verdicts are kept by age (the 7-day TTL) and the cap, not by event end: the fetch window includes events that already ended today, and dropping their verdicts would put the pair back in the pending queue and re-judge it forever.
- Current rule order in `DuplicateRules.decide`: exact match, same calendar, all-day, time gate, external UID (merge), conference link (merge), the vetoes (conflicting location, conflicting conference), shared attendee or organizer email (merge), same location (merge), attendee-disjoint veto, then ambiguous. Vetoes run before shared-attendee and same-location merges (user decision 2026-09-19).
- A merged event takes the largest attendee count and the most-attending response of its copies, so merging never makes a meeting stop qualifying for takeover.

- Grouping is three literal phases: (1) identical items, (2) those groups by the other rules and learned `same` lessons, (3) model verdicts between groups, one request per pair of groups. Phases 1 and 2 are uncapped; hard blocks (rule `.separate`, learned `different`) hold at every phase across all members.
- The model is asked once per pair of groups, from the richest copy of each (ties: earliest index), so identical copies cannot get different answers. The request fingerprint excludes calendar keys. The prompt carries rule-computed facts (offsets, overlap, detail fields, no conflicts) and calendar titles but never account names; its instructions say a missing detail is not a mismatch and give worked examples.
- A merged event displays the longer copy's time range (`CalendarEvent.displayStart`, read through `shownStart`). Its tug time (`start`, which everything schedules on) is the start of the copy carrying a conference link, else the start of the longer copy.

- Merged cards expand to show each merged event (title, calendar, own time; `MergedMember` carries `start`/`end`). Copies with the same `contentKey` are listed once ("×N"), and a group whose members are all identical copies is presented as one plain event (no summary, list or "Unmerge all"; Core still keeps every member for the ledger). A per-row **Split off** (`CalendarStore.separate(_:from:now:)`) records `different` lessons between each of the row's copies and every participant outside the row, so a wrong event can be split off without undoing the rest; the card-level action is **Unmerge all**. Lessons key on normalized title plus calendar, so two copies with the same title on the same calendar cannot be told apart and are separated together.

## Consequences
- `CalendarEvent` gained attendees, organizer, external UID and merge data; EventKit supplies them (emails are often missing).
- A wrong AI merge is visible (badge) and reversible in one click.
- Other platforms add an adjudicator package; Core stays portable.
