---
name: diagnosing-takeovers
description: Use when a running TimeTug app took over the screen when it should not have, did not take over for a meeting, took over twice, merged or failed to merge duplicate events, or shows stale or placeholder widgets, and you need to find out why.
---

# Diagnosing takeovers

Look at what the running app recorded before changing code. Then reproduce the decision in a Core test, which gets `now` passed in.

## What the app records

| Question | Where to look |
| --- | --- |
| Why did a meeting tug, or not? | `log show --predicate 'subsystem == "com.timetug.app" AND category == "takeover"' --last 1h` (titles are redacted) |
| Duplicate detection | the same predicate with `category == "dedup"`. Lessons and verdicts persist in `~/Library/Application Support/TimeTug/dedup-state.json` |
| Widgets | the same predicate with `category == "widgets"`. The app writes `agenda-snapshot.json` to `~/Library/Group Containers/YYA6ZKMD36.com.timetug.shared/` |
| Already shown? | the ledger, `~/Library/Application Support/TimeTug/takeover-ledger.json` (ADR 0006) |

- Deleting the ledger resets the "already shown" memory, and deleting `dedup-state.json` resets duplicate lessons. Ask before deleting either on the user's machine: this is their real state.
- Some shells cannot read the group container (privacy protection). If a read fails there, say so rather than concluding the file is missing.
- Ad-hoc-signed builds skip the snapshot write (it logs and skips), so widgets show the placeholder. Check the signing first; the `configuring-local-app-builds` skill covers it.

## Rules that explain most surprises

The takeover and calendar rules are in `AGENTS.md` under "Gotchas": Enable Tug is enforced in Core, a hidden calendar never tugs, declined events never take over, and all-day events belong to their own time zone's date. Check the logged decision against them before assuming a bug. The decision itself is `TakeoverPolicy.qualifies` in Core; the app only shows the result.
