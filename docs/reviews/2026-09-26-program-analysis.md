# TimeTug program analysis — 2026-09-26

Reviewed commit: `7f96bb8a9847aaca148d3817f3b66663479113ac` on `master`, fast-forwarded from `92fe288`. The checkout was clean before the pull. This report is the only intended repository change; no implementation fixes, commits, releases, or live calendar writes were performed.

## Assessment

TimeTug has a sound foundation: a portable Core, explicit connector boundaries, injected time, provider-specific adapters, extensive tests, and a small native shell. The most important problems are asynchronous lifecycle races, several gaps between documented and implemented behavior, and missing validation at trust boundaries. There is no evidence from this review of a critical remotely exploitable vulnerability; that is not a security certification.

Two bugs were reproduced with deterministic offline probes: an obsolete refresh overwrites newer calendar data, and an in-flight token refresh can recreate deleted credentials or overwrite a newer sign-in. A third probe confirmed that structured conference links bypass scheme validation. Whether a live provider will deliver the dangerous link used in that probe remains unverified.

For agent productivity, fixing the repository's conflicting instructions and making verification discoverable should come before broad refactoring. The code is already reasonably divided into small files; excessive fragmentation would make agents read more, not less.

## Scope and validation

Review covered scheduling and store orchestration, duplicate detection and inference, OAuth and credential storage, Google/Microsoft/EventKit adapter boundaries and write paths, widgets, app coordination, release scripts, GitHub workflows, and the small static website. This is a broad, risk-focused review, not a line-by-line proof of every function.

| Validation | Result |
|---|---|
| TimeTugCore | 278 tests reported passing |
| CalendarConnectors | 523 total across four reported runs: 116, 198, 26, 183 |
| CalendarBridge | 12 tests reported passing |
| CalendarApple | 22 tests reported passing |
| EventKitSource | 66 tests reported passing |
| AppleIntelligenceInference | 11 tests reported passing |
| macOS app | 222 XCTest tests, zero failures; `TEST SUCCEEDED` |
| Release Python tests | 25 tests passed |
| CI/release shell suites | All six scripts passed, including workflow checks |
| Offline probes | Refresh regression and both credential races reproduced; unsafe structured URI retained |

The Swift runners reported 1,134 tests in aggregate, including explicitly skipped opt-in live tests. Seven live calendar tests were reported skipped. No live OAuth, calendar writes, notarization, deployment, Linux execution, manual multi-display testing, model-quality evaluation, dependency advisory audit, or inspection of hosted branch/environment/service-account permissions was performed. The initial sandboxed Swift invocations failed on compiler-cache access; reruns with appropriate filesystem access passed. XcodeGen and Python test side effects were restored.

## Findings requiring fixes

### 1. High priority: token refresh can undo removal or overwrite reauthorization

**Category:** credential lifecycle/security and correctness. **Confidence:** reproduced. **Priority:** P1; security impact is medium, because the probe establishes stale credential persistence, not unauthorized remote account access.

**Evidence:** [Packages/CalendarConnectors/Sources/CalendarOAuth/AccessTokenProvider.swift:57](/Users/scottobryan/Source/timetug/Packages/CalendarConnectors/Sources/CalendarOAuth/AccessTokenProvider.swift:57) reads a refresh token, awaits the network, then unconditionally writes the rotated token into the latest credential dictionary. A missing dictionary becomes `[:]`. The unstructured refresh task deliberately survives caller cancellation. [Apps/macOS/Sources/AccountsController.swift:139](/Users/scottobryan/Source/timetug/Apps/macOS/Sources/AccountsController.swift:139) removes account secrets without invalidating outstanding providers.

**Trigger:** remove an account, or complete a new sign-in, while an old token refresh is suspended. When the old response arrives, it can recreate the removed secret or replace the newly issued refresh token. Offline probe results: `Deleted credential recreated: true`; `New sign-in overwritten: true`. Only fake tokens and an in-memory store were used.

**Fix:** give each credential lifecycle a revision/tombstone and use an atomic compare-and-set when persisting refresh results. Account removal and reauthorization must invalidate old providers and their cached access tokens. A separate read-then-compare is insufficient because another await can race. Add deterministic removal-during-refresh and reauthorization-during-refresh tests across the provider/store boundary.

### 2. High priority: overlapping refreshes publish stale data

**Category:** correctness. **Confidence:** reproduced. **Priority:** P1.

**Evidence:** [Packages/TimeTugCore/Sources/TimeTugCore/Store/CalendarStore.swift:96](/Users/scottobryan/Source/timetug/Packages/TimeTugCore/Sources/TimeTugCore/Store/CalendarStore.swift:96) captures `generation`, but that generation changes only when sources change. Ordinary overlapping refreshes share it. Both may therefore commit their results. `lastWindow` is also assigned even when the source-generation check fails.

**Reproduction:** suspend refresh A; start B; return B with title `NEW`; then return A with title `OLD`. The final stored snapshot contains `OLD`. Actors prevent simultaneous access, but permit interleaving across awaits.

**Impact:** an edited or cancelled meeting can reappear and arm the wrong takeover until another successful refresh. Wake, periodic refresh, and different source listeners can overlap.

**Fix:** coalesce refresh requests and/or track monotonic refresh revisions, including the returned snapshot and window. Preserve a pending-refresh signal so coalescing does not lose changes arriving during a request. Test reversed completion order, source replacement, and midnight rollover.

### 3. The fetch window retains the launch-time calendar/time zone

**Category:** correctness. **Confidence:** code-confirmed; OS-setting transition not exercised. **Priority:** P2.

**Evidence:** [Packages/TimeTugCore/Sources/TimeTugCore/Store/CalendarStore.swift:71](/Users/scottobryan/Source/timetug/Packages/TimeTugCore/Sources/TimeTugCore/Store/CalendarStore.swift:71) captures `Calendar.current` into an immutable property. The timezone-change notification in [Apps/macOS/Sources/AppCoordinator.swift:318](/Users/scottobryan/Source/timetug/Apps/macOS/Sources/AppCoordinator.swift:318) refreshes the same store. UI calculations separately request a fresh `.current` calendar.

**Impact:** after changing time zones, the store and UI can disagree about the day's bounds. The 26-hour query margin does not fully solve this: `makeSnapshot` filters the results back to the old window.

**Fix:** explicitly inject an updated calendar into refresh/window calculations, or update the stored calendar on the notification. Keep fixed calendars in tests. Apple documents that `autoupdatingCurrent` tracks setting changes whereas `current` does not: [Apple documentation](https://developer.apple.com/documentation/foundation/nscalendar/autoupdatingcurrent).

### 4. An empty/failed startup snapshot consumes launch acknowledgement

**Category:** correctness. **Confidence:** code-confirmed. **Priority:** P2.

**Evidence:** [Apps/macOS/Sources/AppCoordinator.swift:173](/Users/scottobryan/Source/timetug/Apps/macOS/Sources/AppCoordinator.swift:173) clears `needsLaunchAcknowledge` on the first applied snapshot without checking source success. The intended behavior is to acknowledge meetings already underway at launch.

**Trigger:** launch offline, or while a provider fails; first refresh contains no events. When connectivity returns, a still-running old meeting appears and can trigger a takeover. Partial success also leaves other sources unacknowledged.

**Fix:** track launch initialization per source and compare recovered events to a captured launch timestamp. Do not merely delay acknowledgement of every meeting until recovery, because meetings starting after launch should still tug. Add app orchestration tests covering failure then recovery and partial source success.

### 5. Structured conference links bypass URL safety checks

**Category:** security hardening. **Confidence:** validation gap reproduced; live exploitability unverified. **Priority:** P2.

**Evidence:** [Packages/CalendarConnectors/Sources/CalendarCore/ConferenceDetector.swift:57](/Users/scottobryan/Source/timetug/Packages/CalendarConnectors/Sources/CalendarCore/ConferenceDetector.swift:57) adds structured links without validating their schemes. Google mapping accepts parsed structured URLs at [Packages/CalendarConnectors/Sources/GoogleCalendar/GoogleEventMapper.swift:135](/Users/scottobryan/Source/timetug/Packages/CalendarConnectors/Sources/GoogleCalendar/GoogleEventMapper.swift:135). [Apps/macOS/Sources/StatusItemController.swift:51](/Users/scottobryan/Source/timetug/Apps/macOS/Sources/StatusItemController.swift:51) and the overlay pass the selected URL to `NSWorkspace.open`.

**Reproduction:** a structured `file:///tmp/unsafe.command` entry survives `conferences(...)`. The probe only inspected the result; it did not open or execute the URL.

**Impact:** if unsafe structured data enters through a provider or future connector, clicking Join could invoke a local file or unexpected application handler. Provider-side validation may block this input today, so this is not a demonstrated remote-code-execution chain.

**Fix:** validate schemes centrally for all conference origins and again at the launch boundary. Permit web URLs and narrowly specified meeting deep links; reject file and arbitrary application schemes. Preserve the intentional generic HTTPS event-link fallback rather than treating all unfamiliar hosts as bugs.

### 6. Firebase PR previews cross the documented pre-merge secret boundary

**Category:** CI security boundary. **Confidence:** workflow-confirmed; hosted permissions unverified. **Priority:** P2.

**Evidence:** [.github/workflows/firebase-hosting-pull-request.yml:15](/Users/scottobryan/Source/timetug/.github/workflows/firebase-hosting-pull-request.yml:15) permits same-repository PRs and supplies `FIREBASE_SERVICE_ACCOUNT_TIMETUG` to an action operating on the checked-out PR. The guard excludes forks, but does not require merge or review. The action is also referenced by a mutable `@v0` tag.

**Impact:** branch authors/agents can cause privileged preview execution before merge. This conflicts with the broad “PRs get no secrets” guidance. The service account's actual IAM privileges and hosted environment protections were not inspected, so production compromise is not established.

**Fix:** either remove secrets from PR execution, or explicitly design a preview-only deployment boundary with a narrowly scoped separate identity/project and approval where appropriate. Inspect actual IAM permissions before deciding the risk. Update the root guidance so agents cannot mistake the app CI policy for a repository-wide guarantee.

### 7. Microsoft sign-in requests write access for a read-only app flow

**Category:** least privilege. **Confidence:** code-confirmed. **Priority:** P2 improvement, not an authorization bypass.

**Evidence:** [Packages/CalendarConnectors/Sources/MicrosoftCalendar/MicrosoftConnectorKind.swift:24](/Users/scottobryan/Source/timetug/Packages/CalendarConnectors/Sources/MicrosoftCalendar/MicrosoftConnectorKind.swift:24) always asks for `Calendars.ReadWrite` and `Calendars.ReadWrite.Shared`. The app consumes the source through the read-oriented bridge; Microsoft does not expose a separate read-only connector kind here. By contrast, Google has read and write variants.

**Impact:** a stolen Microsoft token has more calendar privileges than the current TimeTug UI needs. The user grants those permissions during consent; this finding concerns blast radius.

**Fix:** separate read-only and writable Microsoft source authorization/capabilities, keeping write support for library consumers that explicitly need it. Do not just reduce scopes while leaving `canWrite: true`. Add capability/scope consistency checks and an explicit upgrade flow when writes are introduced in the app.

### 8. Widget horizon exceeds the data supplied to widgets

**Category:** correctness/contract mismatch. **Confidence:** code-confirmed. **Priority:** P2.

**Evidence:** [Packages/TimeTugCore/Sources/TimeTugCore/Widget/WidgetSnapshot.swift:29](/Users/scottobryan/Source/timetug/Packages/TimeTugCore/Sources/TimeTugCore/Widget/WidgetSnapshot.swift:29) declares a three-day horizon. [Packages/TimeTugCore/Sources/TimeTugCore/Store/CalendarStore.swift:90](/Users/scottobryan/Source/timetug/Packages/TimeTugCore/Sources/TimeTugCore/Store/CalendarStore.swift:90) exposes only today plus lead time and five minutes beyond midnight; `makeSnapshot` removes later timed events before the widget snapshot is built.

**Impact:** a three-day filter cannot recover events removed upstream. Widgets cannot deliver the stated future horizon; for example, tomorrow afternoon's event is absent late today even if the source query's margin fetched it. Practical visibility depends on the widget view and refresh schedule.

**Fix:** distinguish source fetch horizon, scheduling horizon, and widget horizon. Keep the bounded display behavior but supply widgets with the broader data they promise. Add an integration test from source through store to widget snapshot, not just a widget-unit test fed an ideal event array.

### 9. Inference cache keys omit inputs that influence the judgment

**Category:** correctness and inference efficiency. **Confidence:** code-confirmed. **Priority:** P2.

**Evidence:** [Packages/TimeTugCore/Sources/TimeTugCore/Dedup/DuplicateResolver.swift:300](/Users/scottobryan/Source/timetug/Packages/TimeTugCore/Sources/TimeTugCore/Dedup/DuplicateResolver.swift:300) fingerprints title, times, location, notes, emails and attendee count. The actual prompt also includes attendee names, calendar title and relevant lessons. [Packages/TimeTugCore/Sources/TimeTugCore/Dedup/Adjudication.swift:112](/Users/scottobryan/Source/timetug/Packages/TimeTugCore/Sources/TimeTugCore/Dedup/Adjudication.swift:112) retrieves by request ID alone; engine metadata is stored but not part of lookup validity.

**Impact:** changes to an attendee name, a person-named calendar, relevant correction context, or prompt policy can reuse a judgment made from different evidence. Old decisions remain for up to the cache retention period.

**Fix:** define a versioned canonical judgment input and derive both prompt and cache key from it. Include relevant semantic context and a prompt-policy version, while retaining deliberate equivalence between identical copies. Add tests that change one prompt-visible input at a time. Handle in-flight judgments when corrections are forgotten so an old result cannot silently repopulate the cleared cache.

### 10. Duplicate resolution has avoidable quadratic work and memory

**Category:** performance. **Confidence:** measured. **Priority:** P2 for large calendars.

**Evidence:** [Packages/TimeTugCore/Sources/TimeTugCore/Dedup/DuplicateResolver.swift:73](/Users/scottobryan/Source/timetug/Packages/TimeTugCore/Sources/TimeTugCore/Dedup/DuplicateResolver.swift:73) compares all pairs and stores separate pairs in `blocked`; [Packages/TimeTugCore/Sources/TimeTugCore/Dedup/DuplicateResolver.swift:144](/Users/scottobryan/Source/timetug/Packages/TimeTugCore/Sources/TimeTugCore/Dedup/DuplicateResolver.swift:144) scans all pairs again to build manual candidates. Normalization and detail calculations recur inside these loops.

Release-build local probe, synthetic sequential meetings, inference disabled:

| Events | Resolution time |
|---:|---:|
| 100 | about 0.048 s |
| 500 | about 0.423 s |
| 1,000 | about 1.224 s |

These are single-run directional measurements, not a statistically controlled device benchmark. The probe intentionally exercises the public resolver over the supplied event count; typical daily workloads can be much smaller.

**Fix:** precompute normalized features, use exact-content/UID buckets and a temporal candidate index, and represent only relevant blocking relationships. Preserve same-calendar exact-duplicate handling and user correction semantics. Add a repeatable release-mode benchmark with sparse, dense, all-day and duplicate-heavy workloads before changing the algorithm.

### 11. Change notifications lose their scope and trigger excessive refresh work

**Category:** performance and responsiveness. **Confidence:** code-confirmed. **Priority:** P2.

**Evidence:** [Packages/CalendarBridge/Sources/CalendarBridge/ConnectedSource.swift:29](/Users/scottobryan/Source/timetug/Packages/CalendarBridge/Sources/CalendarBridge/ConnectedSource.swift:29) turns every detailed `CalendarChange` into `Void`. [Apps/macOS/Sources/SourceReconciler.swift:93](/Users/scottobryan/Source/timetug/Apps/macOS/Sources/SourceReconciler.swift:93) calls a global refresh for each change. The store refetches every source and waits for all source results before publishing.

**Impact:** one calendar edit can refresh every account, and several source notifications can overlap. A slow/throttled account delays publication of fresh data from healthy accounts. The five-minute full-refresh fallback compounds this work; per-calendar source requests also have no concurrency limit.

**Fix:** preserve source/calendar identity across the bridge, coalesce bursts, refresh affected sources, cap provider concurrency, and retain a slower authoritative full reconciliation. Publish healthy-source updates without waiting indefinitely for a stalled provider, using a clear snapshot-generation policy. Measure request counts before removing any recovery mechanism.

## Further improvements and known limitations

- **Per-second app work:** [Apps/macOS/Sources/AppCoordinator.swift:133](/Users/scottobryan/Source/timetug/Apps/macOS/Sources/AppCoordinator.swift:133) runs `updateUI()` every second. It rebuilds/filter-sorts the agenda and scans takeover eligibility even with an idle icon-only menu bar. Recompute structural agenda state on data/settings/day/event-boundary changes; update only visible countdown text at the needed cadence. Profile energy impact before claiming a battery improvement.
- **Inference robustness:** [Packages/AppleIntelligenceInference/Sources/AppleIntelligenceInference/AppleIntelligence.swift:41](/Users/scottobryan/Source/timetug/Packages/AppleIntelligenceInference/Sources/AppleIntelligenceInference/AppleIntelligence.swift:41) creates a fresh session for each request and retries failures on subsequent refreshes. Notes are capped, but titles, locations, names and total prompt size are not. Cap the total input, add failure backoff and a time/work budget, and evaluate prompt-injection cases. Calendar prose is untrusted and currently interpolated directly into the prompt. The model has no tools and runs locally, so the concern is false merges and missed/separated reminders, not demonstrated data exfiltration. Delimiters alone are not a complete defense.
- **Microsoft series writes:** [Packages/CalendarConnectors/Sources/MicrosoftCalendar/MicrosoftCalendarSource+Split.swift:5](/Users/scottobryan/Source/timetug/Packages/CalendarConnectors/Sources/MicrosoftCalendar/MicrosoftCalendarSource+Split.swift:5) explicitly notes that deleted occurrences can make numbered-series counts wrong. Calculating remaining occurrences from returned instances can extend the continuation incorrectly. Reconstruct recurrence positions or reject unsupported cases before mutation. Test cancelled and moved exceptions. The read-before-write concurrency gap in Microsoft updates is already documented; do not advertise atomic conflict protection for it without provider-backed evidence.
- **OAuth listener resilience:** [Packages/CalendarApple/Sources/CalendarApple/LoopbackRequest.swift:6](/Users/scottobryan/Source/timetug/Packages/CalendarApple/Sources/CalendarApple/LoopbackRequest.swift:6) accepts any GET with a code/error query; state validation happens later. A bogus callback can end an attempt, though it cannot pass the subsequent state check and acquire credentials. Consider validating the expected callback/state before completing the session and bounding connection lifetimes. Binding to loopback, PKCE and downstream state validation are existing strengths.
- **Supply-chain hardening:** pin Actions to reviewed full commit SHAs, especially privileged deploy/signing jobs, and automate updates. Current tags are mutable. [GitHub recommends full-length SHA pinning](https://docs.github.com/en/actions/reference/security/secure-use). Sparkle's downloaded tool archive already has a SHA-256 check; retain it.
- **Static website:** the download script has a fixed GitHub API endpoint and no HTML/eval sink. Consider validating the returned download URL's host/scheme. The checked-in Firebase config contains cache headers but no CSP; live response headers were not inspected, so absence in production is not established. These are lower priority than credential and workflow fixes.

## Increasing coding-agent / LLM efficiency

This section concerns agents maintaining the repository. The on-device inference recommendations above are a separate runtime concern.

### A. Replace conflicting entry documents with one current map

The mandatory startup reading totals approximately 4,006 whitespace-delimited words: `AGENTS.md` 2,100, original design 1,546, architecture 360. More costly than the length is disagreement:

- The original design says Core imports nothing and sources depend on Core; current code uses `CalendarCore` and `CalendarBridge`.
- [docs/architecture.md:24](/Users/scottobryan/Source/timetug/docs/architecture.md:24) still instructs new sources to return Core models and register in `AppCoordinator`, bypassing the actual connector-library pattern.
- The old design's default skip-solo behavior differs from current settings.
- The module map omits the newly shipped Microsoft connector.
- Root CI guidance omits the Firebase preview secret exception.

Make the current architecture map the canonical first read. Mark original specs as historical/superseded and link to them for rationale. Keep root instructions to invariants, a navigation table, verification entry points and release boundaries. Move detailed signing/OAuth operations into focused runbooks linked only for relevant tasks. Keep safety-critical rules in the root; move detail, not protections.

**Acceptance measure:** a new agent can locate the right connector seam and required tests without reading historical plans, and an automated documentation check flags nonexistent symbols/paths or missing package entries.

### B. Provide one deterministic verification interface

Introduce a small wrapper with explicit modes such as `core`, `connectors`, `app`, `release-tools`, `all`, and `affected`. This is a proposed interface, not an existing command.

It should own Xcode generation, log locations, prerequisites, test-result summaries and the mapping from changed paths to checks. Shared models must trigger all dependents; unknown paths should fall back to broader checks. Keep full CI as the authoritative backstop.

Today [.github/workflows/ci.yml:30](/Users/scottobryan/Source/timetug/.github/workflows/ci.yml:30) runs Swift/app/DMG checks but none of the six shell suites or 25 Python release tests. Agents can change security-sensitive scripts while all declared CI checks remain green. Add a mandatory release-tooling job, provision PyYAML explicitly, and ensure a missing dependency cannot produce a successful skip. Revisit optional Linux failure once the Linux baseline is confirmed.

**Acceptance measure:** one invocation yields exit status, executed/skipped test counts, checked commit, and a stable log/result path. Track verification time and avoid rebuilding unaffected products repeatedly.

### C. Add lifecycle seams and deterministic adversarial tests

The missing tests are largely about ordering, not ordinary input/output cases. Add controllable source completions, credential revisions, launch/recovery state, and time-zone updates. Extract a small refresh coordinator and launch-acknowledgement state machine from `AppCoordinator` so tests can exercise behavior without driving windows.

Use the existing pure Core and protocol seams. Prefer a few multi-component tests proving real contracts over more tests that mirror helper implementations. Keep manual checks for actual window/focus/display behavior.

**Acceptance measure:** each reproduced race fails deterministically before its fix and passes after it, without sleeps or live accounts.

### D. Make contracts executable and discoverable

Add automated checks for dependency direction, provider capability/scope consistency, safe Join URLs, and coverage of release tooling. Provide an ADR index with status (current, superseded), affected modules, and associated tests. Add scoped agent guides only where rules differ—connector conformance, app UI, release tooling—rather than copying the root guide everywhere.

Keep proposed changes in small reviewable batches. Useful per-task evidence is commit, changed behavior, exact checks, known limitations and next step. Store checkpoints in one designated location; avoid accumulating overlapping narrative plans as competing instructions.

### E. Remove artifact churn and stabilize tooling

Python bytecode is already tracked (`scripts/release/tests/__pycache__/test_appcast.cpython-314.pyc`); this review's tests modified it. There is also a tracked `.bak` release-test file. Remove generated/backup artifacts in an approved cleanup and add ignore patterns. Make XcodeGen output deterministic or remove the need to routinely restore checked-in Info.plists. Pin formatter/linter versions and add lightweight checks; do not introduce a repository-wide style rewrite as part of a bug fix.

The 154 Swift non-test files and 109 Swift test files are already relatively modular. Split the 384-line coordinator along lifecycle boundaries when justified; do not mechanically split every file to hit an arbitrary line count.

**Measure improvements:** tokens/context loaded per task, tool calls, time to first relevant test, verification wall time, first-pass review success, and regressions per change. Establish a baseline before promising a percentage improvement in LLM efficiency.

## Suggested order

1. Credential revision/invalidation and refresh ordering, with the deterministic regression probes converted into repository tests.
2. Source-aware launch recovery, timezone updates, safe Join URL validation, and widget horizon integration.
3. Firebase preview trust boundary, Microsoft least privilege, and mandatory release-tooling checks.
4. Current architecture/agent map plus the unified verification interface.
5. Profile-driven refresh/dedup/timer optimizations and inference cache/input hardening.

No fixes are included in this report. The next implementation batch should be deliberately small: findings 1 and 2 first, with separate reviewable changes.

## Reproduction evidence

The isolated probe used the repository packages as local SwiftPM dependencies and ran in release mode. It used only synthetic calendar events and in-memory fake credentials:

```text
Deleted credential recreated: true
New sign-in overwritten: true
New refresh: ["NEW"]
Late older refresh: ["OLD"]
Stored final: ["OLD"]
Structured links: ["file:///tmp/unsafe.command"]
Dedupe count 100: 0.047557041 seconds
Dedupe count 500: 0.422610792 seconds
Dedupe count 1000: 1.223829083 seconds
```

Session-local probe source: `/tmp/timetug-audit-probes/Sources/Probe/main.swift`. Logs: `/tmp/timetug-probes.log`, `/tmp/timetug-core-review.log`, `/tmp/timetug-connectors-review.log`, `/tmp/timetug-app-review.log`, `/tmp/timetug-<package>-review.log`, `/tmp/timetug-release-python-review.log`, `/tmp/timetug-test-*.log`. Temporary files may be removed by the OS; the key evidence is preserved above.
