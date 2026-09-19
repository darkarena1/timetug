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

## Consequences
- `CalendarEvent` gained attendees, organizer, external UID and merge data; EventKit supplies them (emails are often missing).
- A wrong AI merge is visible (badge) and reversible in one click.
- Other platforms add an adjudicator package; Core stays portable.
