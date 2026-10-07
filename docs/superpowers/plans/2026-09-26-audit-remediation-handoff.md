# TimeTug Audit Remediation Implementation Plan

> **For agentic workers:** Use `superpowers:executing-plans` to implement this plan task-by-task. Use `superpowers:subagent-driven-development` only if the user selects delegated execution. Steps use checkboxes for tracking. This document supplies the context for a lower-reasoning implementation agent; do not infer extra scope from the original review.

**Goal:** Address every finding and improvement in the September 26 review except the recommendation to reduce Microsoft calendar write access.

**Architecture:** Preserve the portable connector library, Core/app separation, injected time, and native UI. Fix lifecycle correctness first; then harden boundaries, make verification predictable, and optimize measured hot paths. Deliver separate reviewable batches rather than one repository-wide rewrite.

**Tech stack:** Swift 6 portable packages; Swift 5 app/EventKit language mode; Swift Testing and XCTest; SwiftUI/AppKit; XcodeGen; Python/Bash release tools; GitHub Actions; static Firebase website.

**Spec:** [September 26 analysis](../../reviews/2026-09-26-program-analysis.md). Baseline commit: `7f96bb8a9847aaca148d3817f3b66663479113ac`. The report explains the evidence; this plan controls implementation scope. If code has changed, verify whether each issue still exists before editing.

## Explicit exclusion: preserve Microsoft write access

> **Superseded 2026-09-30:** the owner chose read-only Microsoft permissions (ADR 0017, PR #49: `Calendars.Read` and `Calendars.Read.Shared`). Finding 7 is therefore resolved, and the exclusion below no longer applies. The library's write code and capabilities are unchanged.

**Do not implement review finding 7.** Keep `Calendars.ReadWrite`, `Calendars.ReadWrite.Shared`, the existing Microsoft authorization behavior, writable source conformance, and supported write capabilities. Do not create a read-only Microsoft replacement or an authorization upgrade flow. Security/documentation checks must recognize this as intentional.

Microsoft token lifecycle fixes and recurring-series correctness fixes ARE included. The exclusion concerns reducing write permissions, not leaving Microsoft bugs unfixed.

## Global constraints

- This is an implementation proposal, not evidence that any fixes have been made. The user's request in this task is to produce the handoff document.
- Before executing, read current `AGENTS.md`, this plan, and only the relevant report section/files. Historical design prose does not override current code contracts or the Microsoft exclusion above.
- Use an isolated checkout for implementation. Preserve unrelated local changes. Do not commit, push, merge, release, deploy, modify IAM, revoke credentials, or perform live calendar writes without the user's authorization for that action. Run offline tests by default.
- Core answers what/when; the app owns windows, pixels, strings and platform lifecycle. Keep Apple-only imports out of portable packages. Inject `now: Date`; do not introduce `Date()` in Core logic.
- Keep default settings and saved-data compatibility. Read old credential dictionaries and old cache/settings files; never make users sign in again just because storage gained metadata.
- Preserve PKCE/state validation, Keychain storage, generic web Join fallback, all-day date semantics, source failure recovery, ledger/snooze behavior, and Microsoft write access.
- Every behavior fix needs a deterministic failing test before implementation. Avoid real sleeps in race tests: use continuations or controlled fake clocks/sleepers. Do not add tests for trivial prose or ignore-file edits.
- Record material API/storage decisions in the next available ADR number. Do not guess that a historical provider limitation is still current; verify official documentation where a provider-specific decision requires it.
- Existing baseline tests passing does not disprove the audit: the two highest-priority races were reproduced despite green suites.
- Proposed names below are new interfaces unless stated otherwise. Update all callers/test doubles in the same batch. Use `rg` to discover conformers before changing a protocol.

## Review focus

1. Account removal/re-sign-in while a refresh is suspended must not restore or overwrite credentials — Task 1.
2. Old refresh completion after a newer one, midnight, or source replacement must not regress data/windows — Tasks 2–3.
3. Partial startup recovery must distinguish meetings already underway at launch from meetings starting afterward — Task 4.
4. Provider/local callback input must not launch arbitrary handlers or prematurely complete authorization — Tasks 5 and 12.
5. Optimization must preserve cross-calendar merges, user corrections, all-day dates, snoozes, and recurrence exceptions — Tasks 6–11 and 14.

## How to execute one task

1. Read its files and dependencies. Record whether the problem still exists at the current commit.
2. Add the listed behavioral tests; run the focused suite and record the expected failure. Tests listed by name below are proposed tests, not claims that those names already exist.
3. Implement only that task. If an API proposal conflicts with real provider semantics, document the specific conflict and obtain a focused design decision instead of improvising a large redesign.
4. Run the task's checks. A command must exit zero; inspect failures and skipped counts, not just the last line.
5. Review the diff for Microsoft permission changes, private data, unrelated churn and migration regressions. Leave a concise checkpoint before proceeding.

At completion of a batch, present changes and checks for review. Do not turn this checklist into automatic commit authorization.

## Verification commands

Run from repository root; these are current commands until Task 17 introduces the wrapper.

| Label | Command |
|---|---|
| CORE | `swift test --package-path Packages/TimeTugCore` |
| CONNECTORS | `swift test --package-path Packages/CalendarConnectors` |
| BRIDGE | `swift test --package-path Packages/CalendarBridge` |
| APPLE | `swift test --package-path Packages/CalendarApple` |
| EVENTKIT | `swift test --package-path Packages/EventKitSource` |
| INFERENCE | `swift test --package-path Packages/AppleIntelligenceInference` |
| APP | Generate with `xcodegen generate --spec Apps/macOS/project.yml`, then `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test` |
| PYTHON | `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/release/tests -p 'test_*.py'` |
| SHELL | Run each `scripts/ci/tests/test-*.sh` and `scripts/release/tests/test-*.sh` with Bash; stop on any nonzero exit |
| DIFF | `git diff --check` and inspect `git status --short` |

Before Task 18 fixes generation churn, inspect and restore only test-generated Info.plist changes when they do not belong to the task. Never restore unrelated user changes. Provision PyYAML for workflow tests; a skipped workflow check is not a pass.

## Batch A — correctness and trust boundaries

### Task 1 — Make credential updates conditional on the same account lifecycle

**Covers:** finding 1. **Dependencies:** none.

**Files:** modify `Packages/CalendarConnectors/Sources/CalendarCore/Connection.swift`, `Sources/CalendarOAuth/AccessTokenProvider.swift` within that package; `Packages/CalendarApple/Sources/CalendarApple/KeychainCredentialStore.swift`; `Apps/macOS/Sources/AccountsController.swift`; provider factories/conformers found by `rg`. Tests: connector `CalendarOAuthTests/AccessTokenProviderTests.swift`, `CalendarCoreTests/ConnectionTests.swift`, Apple `KeychainCredentialStoreTests.swift`, app `AccountsControllerTests.swift`.

**Interface contract:** add a credential snapshot containing secrets plus an opaque lifecycle revision, and an atomic conditional refresh-token update. Suggested operations are `credentialSnapshot(for:)` and `updateRefreshToken(_:for:expectedRevision:) -> Bool`. Keep lifecycle revision distinct from a token rotation: removal/reauthorization invalidates it; ordinary rotation need not invalidate the source. A removal must leave no secret and must invalidate already-issued snapshots. Do not implement the conditional update as an async read followed by an unconditional write. Serialize Keychain check/write in one shared store authority; document the single-process ownership assumption. Multiple wrappers must not silently pretend to provide cross-process CAS.

- [ ] Add `removalDuringRefreshDoesNotRecreateSecrets`: suspend network refresh, remove credentials, resume with a rotated token; assert store remains empty and old provider cannot supply a usable cached token.
- [ ] Add `reauthorizationDuringRefreshPreservesNewSecrets`: replace credentials while suspended; assert the replacement survives and old response is rejected.
- [ ] Add `cachedTokenRejectedAfterLifecycleChange`, `rotationPreservesUnrelatedSecrets`, and legacy dictionary decoding coverage. Keep the existing single-flight/cancelled-first-caller behavior.
- [ ] Make providers capture/check lifecycle revisions before serving cached tokens or committing refresh responses. Cache successful tokens only after required persistence succeeds. Reject a stale response without overwriting the new lifecycle.
- [ ] Ensure removal/rebuild paths stop using old providers; enumerate all `CredentialStore` conformers and fake stores. Preserve Microsoft scopes/capabilities exactly.
- [ ] Run CONNECTORS, APPLE, APP. Verify no real account or Keychain identity was used in test fixtures. Record the storage/API decision in an ADR.

**Proposed Swift contract to settle in this batch:**

```swift
public struct CredentialSnapshot: Sendable {
    public let secrets: [String: String]
    public let revision: UUID
}
// Add to CredentialStore; implementations own serialization.
func credentialSnapshot(for connectionID: ConnectionID) async throws -> CredentialSnapshot?
func updateRefreshToken(_ token: String, for connectionID: ConnectionID,
                        expectedRevision: UUID) async throws -> Bool
```

A missing/deleted lifecycle returns nil/false. `setSecrets` starts a fresh revision; conditional rotation preserves that revision and unrelated fields. Legacy `secrets(for:)` can remain for compatibility, but AccessTokenProvider uses the snapshot API. Use lifecycle revisions to reject old cached tokens too. If existing external implementers prevent changing the protocol directly, expose this as a required refinement for OAuth providers and migrate every in-repo provider; do not supply an unsafe default CAS implementation.

**Done:** both audit race sequences are covered by tests and fail closed; normal refresh/sign-in and legacy secrets still work.

### Task 2 — Prevent stale refresh publication

**Covers:** finding 2. **Dependencies:** none; finish before Tasks 3, 4, 6, 9.

**Files:** `Packages/TimeTugCore/Sources/TimeTugCore/Store/CalendarStore.swift`; store test files; `Apps/macOS/Sources/AppCoordinator.swift`; create app `RefreshPublicationTests.swift` if needed.

**Interface contract:** retain `refresh(now:leadTime:) -> CalendarSnapshot` compatibility if practical. Add a monotonically increasing publication revision to snapshots and a request/source-generation guard in the store. A stale request may return the latest accepted snapshot but must not commit its results, overwrite `lastWindow`, or publish older timestamps. App application must ignore an older/equal already-applied revision. Revisions also cover locally generated snapshots after settings/lesson changes.

- [ ] Add `olderRefreshCannotOverwriteNewerRefresh`: A suspended; B returns NEW; A returns OLD; final snapshot remains NEW.
- [ ] Add reversed midnight-window completion and `replacedSourceCannotRestoreOldEvents`, including replacement with the same source ID. Assert events, status, window and publication ordering.
- [ ] Add a publication test delivering revisions 2 then 1; assert app-visible state stays at 2. Retain last-good events when the latest request fails.
- [ ] Implement guards before every refresh-owned mutation. Do not rely on actor isolation alone. Do not silently drop a refresh requested during active work.
- [ ] Run CORE and APP. Review all snapshot constructors and apply paths so settings/inference changes are not accidentally suppressed.

### Task 3 — Update calendar context explicitly

**Covers:** finding 3. **Dependencies:** Task 2.

**Files:** `CalendarStore.swift`, `AppCoordinator.swift`, Core `CalendarStoreTests.swift`.

**Interface:** add `setCalendar(_ calendar: Calendar)` on the store, invalidating the active refresh generation; keep the constructor's fixed-calendar injection for tests. The app passes a fresh `Calendar.current` on timezone/calendar-context changes before refreshing. Carry one captured calendar through window construction and filtering.

- [ ] Add a test switching a single existing store from America/Denver to Asia/Tokyo at the same instant; assert its window and included day update.
- [ ] Add timezone-change-during-refresh: old-zone completion cannot restore old bounds. Cover a DST transition and an all-day event in a different source zone.
- [ ] Wire system notifications through the updated calendar path; do not read global time/zone inside Core logic.
- [ ] Run CORE and APP; retain the 26-hour all-day query margin.

### Task 4 — Track startup acknowledgement per source

**Covers:** finding 4 and lifecycle-test recommendations. **Dependencies:** Tasks 2–3.

**Files:** `AppCoordinator.swift`; create `Apps/macOS/Sources/LaunchAcknowledgement.swift` and `Apps/macOS/Tests/LaunchAcknowledgementTests.swift`; `TakeoverLedger.swift` only if a narrowly scoped API is needed.

**Interface:** a pure app-layer state object initialized with `launchedAt: Date` and the initial source IDs, with a method returning events to acknowledge from each source's first successful snapshot. Retain the existing 120-second grace. Use raw source/member identity for merged events; do not treat one successful source as successful initialization of every source.

- [ ] At launch 10:00, a meeting starting 09:50 and ending 11:00 is acknowledged after recovery at 10:15.
- [ ] A meeting starting 10:05 is not acknowledged as a pre-launch meeting after that same recovery; it remains eligible to tug.
- [ ] Failed/empty-error snapshot does not initialize a source; successful empty snapshot does. A succeeds/B fails: B remains pending. Removed sources do not remain pending forever.
- [ ] Specify/test accounts added after startup separately: initialize against their addition timestamp so old meetings do not flood the user. Preserve current wake behavior after a source is initialized.
- [ ] Replace the single boolean with this state object. Persist ledger entries using actual acknowledgement time while judging “already underway” against the captured initialization timestamp.
- [ ] Run CORE and APP. No UI redesign is needed.

### Task 5 — Centralize safe Join URL validation

**Covers:** finding 5. **Dependencies:** none.

**Files:** create `Packages/CalendarConnectors/Sources/CalendarCore/JoinURLPolicy.swift`; modify `ConferenceDetector.swift`; app `StatusItemController.swift`, overlay Join path in `AppCoordinator.swift`; widget link paths in `Apps/macOS/Widgets`; connector and app tests.

**Interface:** `JoinURLPolicy.isAllowed(_ url: URL) -> Bool`. Allow HTTP/HTTPS with a nonempty host and no embedded username/password; allow `zoommtg` only for existing Zoom host rules. Reject file, data, javascript, missing-scheme and arbitrary application schemes. Do not expand supported schemes without a documented use case. Keep valid generic web event links.

- [ ] Add a table-driven test for file/javascript/data/custom schemes, credential-bearing URLs, Zoom subdomains and deceptive suffixes, upper-case scheme handling, valid Teams/Meet and generic HTTPS.
- [ ] Assert invalid structured links are dropped just like invalid scanned links. Safe provider fallback survives when the first structured link is rejected.
- [ ] Guard immediately before app URL opening and widget Link construction as defense in depth. Test with an injected opener; never open the malicious test URI.
- [ ] Run CONNECTORS, CORE, BRIDGE and APP; manually check a normal Join only when the user supplies a safe test meeting.

### Task 6 — Supply the actual three-day widget horizon

**Covers:** finding 8. **Dependencies:** Tasks 2–3; do before dedup optimization.

**Files:** `CalendarStore.swift`, `WidgetSnapshot.swift`, `AppCoordinator.swift`, `DayAgenda.swift`, `Scheduler.swift` consumers; Core store/widget integration tests.

**Interface:** keep `CalendarSnapshot.events` limited to scheduling/display semantics. Add `widgetEvents: [TimeTugCalendarEvent]`, populated from a retained horizon of at least three local calendar days. Query enough for both horizons plus the source margin; share raw fetch data. The app passes `widgetEvents` to `WidgetSnapshot.make`.

- [ ] Add source→store→widget test: tomorrow 15:00 and day-after-tomorrow 09:00 appear in widget data; a fourth-day event does not. Today popup behavior remains unchanged.
- [ ] Assert a future event does not become an early takeover just because widgets loaded it. Verify after-midnight lead-time behavior.
- [ ] Cover hidden calendars, all-day dates across zones, deduplicated copies, stale snapshot handling and DST.
- [ ] Avoid two network fetches for the same source. Reuse normalized/dedup features where practical without conflating the two output horizons.
- [ ] Run CORE and APP. Document the three distinct windows and their consumers.

### Task 7 — Version the complete inference input and invalidate obsolete work

**Covers:** finding 9. **Dependencies:** Tasks 2 and 6.

**Files:** Core `Dedup/Adjudication.swift`, `DuplicateResolver.swift`, `CalendarStore.swift`; inference `PromptBuilder.swift`, `AppleIntelligence.swift`; tests in `AdjudicationTests.swift`, `CalendarStoreInferenceTests.swift`, `PromptBuilderTests.swift`.

**Interface:** define a canonical `JudgmentInput` and explicit policy version. Cache identity must include all semantic input actually presented to the model plus engine/policy identity: bounded text, times, attendee names, relevant calendar labels, relevant lesson content, computed facts. Exclude volatile lesson usage timestamps. Preserve order-independent equivalent-pair behavior. Do not make Core import the platform prompt builder.

- [ ] Change one input at a time: attendee name, calendar label naming a person, relevant correction, policy version and engine identity must invalidate a prior verdict. Merely touching lesson `lastUsed` must not.
- [ ] Swap equivalent A/B events: preserve equivalent judgment/cache behavior. Keep legacy persisted state readable; discard incompatible verdicts rather than corrupting user lessons.
- [ ] Suspend judgment, forget corrections or disable/re-enable inference, then return old result: it must not repopulate a newer generation's verdict cache.
- [ ] Derive both prompt data and cache identity from the canonical structure; increment inference generation on invalidation/source changes as needed.
- [ ] Run CORE, INFERENCE and APP.

### Task 8 — Bound inference input, retries and work

**Covers:** inference robustness/prompt-injection recommendation. **Dependencies:** Task 7.

**Files:** `Adjudication.swift`, `CalendarStore.swift`, `PromptBuilder.swift`, `AppleIntelligence.swift`; corresponding tests; create inference evaluation fixtures under package tests.

**Interface/policy defaults:** cap title at 256 characters, location at 512, calendar label at 128, attendee names at 10 × 80, notes at the existing 500; use at most five relevant lessons, with bounded lesson strings. Limit event/context portion of each prompt to 6,000 characters. These are new initial engineering budgets, not a provider token-limit claim. Canonicalization precedes both hashing and rendering.

- [ ] Tests assert bounded total input for oversized Unicode fields and a stable key for identical bounded input. Do not split grapheme clusters. Missing details must retain their current semantics.
- [ ] Put event/lesson content in a structured escaped data section; instructions explicitly treat it as data. Add hostile-title/notes fixtures. Do not claim delimiter-based prompt-injection prevention or automatically reject ordinary text containing instructional words.
- [ ] Track transient failure backoff per key using injected time: 60 s, 120 s, 240 s, capped at 900 s; changed key resets it. Cancellation does not create a failed verdict.
- [ ] Keep batches capped at 20, add a 30-second cooperative pass budget: stop starting further requests after budget exhaustion; cancel outstanding model work if supported. Do not pretend a noncooperative request has a hard timeout. All failures leave events separate.
- [ ] Test budgets/backoff with fake adjudicator and clock. Keep fresh model sessions until measured evidence justifies safe session reuse; never reuse conversational state across unrelated events.
- [ ] Run CORE and INFERENCE. Record real on-device adversarial/quality evaluation as a separate manual check, not a mandatory CI network/model dependency.

## Batch B — performance with behavior preserved

### Task 9 — Preserve change scope and coalesce source refreshes

**Covers:** finding 11. **Dependencies:** Tasks 2–4 and 6.

**Files:** Core `Sources/CalendarSource.swift`, `CalendarStore.swift`; bridge `ConnectedSource.swift`; app `SourceReconciler.swift`, `AppCoordinator.swift`; store/reconciler/bridge tests.

**Interface:** preserve source identity and calendar IDs through a new Core change value rather than `Void`. Add a targeted store refresh entry point for a set of source IDs; full refresh remains supported. Calendar-scoped fetching is optional only when a connector explicitly supports it; otherwise refresh that source, not every account. Maintain a dirty-source set and one active refresh cycle; newly arriving changes schedule exactly one follow-up cycle.

- [ ] Fake sources A/B/C count reads: an A event change refetches A only; unknown/global change refetches all. Calendar-change and source-failure signals still reach status handling.
- [ ] Emit 100 A changes during one suspended fetch: assert at most one follow-up fetch, with the final change observed. Remove A during the wait: it is not restored.
- [ ] Add per-source guarded publication so B's fresh data can be applied while A is stalled; each published snapshot uses the publication revisions from Task 2. An old request must not overwrite any newer source state.
- [ ] Retain the existing 300-second full fallback in this batch. Change its cadence only after request-count and recovery evidence; do not delete recovery maintenance.
- [ ] Run CORE, BRIDGE and APP. Update every fake source stream conformance.

### Task 10 — Bound provider request concurrency

**Covers:** remaining finding 11 fanout. **Dependencies:** Task 9.

**Files:** Google/Microsoft `*CalendarSource.swift` event fanout; shared connector helper if needed; provider source/API tests.

**Interface:** maximum four simultaneous calendar reads per source, implemented with a replenished task group or equivalent nonblocking queue. Keep concurrency within the provider; do not add a global lock serializing unrelated accounts.

- [ ] Fake transport tracks active reads: peak <= 4 for 20 calendars, every calendar is fetched, output ordering remains deterministic.
- [ ] Cancellation stops queued work; permission-denied/removed calendars retain existing handling; throttled requests do not exceed the limit.
- [ ] Run CONNECTORS and BRIDGE. Preserve retry limits and Microsoft writes.

### Task 11 — Reduce dedup work using measured candidate generation

**Covers:** finding 10 and repeated normalization/regex work. **Dependencies:** Tasks 6–8.

**Files:** Core `DuplicateResolver.swift`, `DuplicateRules.swift`; create `Dedup/PreparedEvent.swift` if useful; `ConferenceDetector.swift`; resolver tests; create `scripts/benchmarks/` harness with synthetic input only.

**Interface:** `DuplicateResolver.resolve` keeps its public semantics. Build normalized features once per event. Index exact-content and trusted-UID relationships and temporal candidates using the existing rules' actual boundaries, not an invented time threshold. Compute blocking relationships lazily or only for reachable groups; do not remove checks across merged members. Compile the static conference regex once.

- [ ] Capture the existing resolver as a test-only comparison oracle or golden fixtures before changes. Compare outputs, provenance, member sets, candidate lists and pending judgments, not just event counts.
- [ ] Cover sparse/dense events, same-calendar exact duplicates, all-day duplicates, UID conflicts, conflicting locations/conferences, manual merge/separate lessons, and max model cluster size.
- [ ] Add deterministic randomized comparisons with a fixed seed. Do not introduce hash-order-dependent output.
- [ ] Benchmark release mode: 100/500/1,000/5,000 sparse, dense and duplicate-heavy events; warm up, run at least five measured repetitions, record median and memory/feature-comparison counts where available.
- [ ] Accept optimization only when behavior matches and sparse workloads improve. Do not add fragile absolute timing assertions to normal CI or promise a fixed percentage speedup.
- [ ] Run CORE, CONNECTORS and INFERENCE. Save before/after benchmark results without private event data.

### Task 12 — Keep bogus loopback requests from completing OAuth

**Covers:** OAuth listener resilience. **Dependencies:** Task 1 recommended.

**Files:** CalendarApple `LoopbackAuthorizationInteraction.swift`, `LoopbackRequest.swift`, `LoopbackTests.swift`.

**Interface:** derive the expected state and redirect path from the authorization session before opening the presenter/browser. Validate incoming callbacks against them before `deliver`. Retain OAuthClient's downstream validation. Reject duplicate code/state/error query parameters and unexpected paths. Continue listening after invalid callbacks.

- [ ] Wrong state, missing state, duplicate state and favicon/probe requests do not complete the session. A subsequent correct callback succeeds.
- [ ] Correct-state access-denied callback reaches normal cancellation handling. Browser fallback, early response and sheet dismissal tests still pass.
- [ ] Bound simultaneous accepted connections to 8, each request to 16 KiB and incomplete-request lifetime to 5 seconds using an injectable timeout seam. These are new local defensive defaults. Close all accepted connections on session close.
- [ ] Exercise size/timeout/connection-cap behavior offline; keep listener bound to loopback and preserve PKCE.
- [ ] Run APPLE and CONNECTORS.

### Task 13 — Separate structural UI work from countdown ticks

**Covers:** per-second app work. **Dependencies:** Tasks 2, 4 and 9.

**Files:** app `AppCoordinator.swift`, `TimeFormatting.swift`, `MenuBarIconState.swift`; create `UITickPolicy.swift` and `UITickPolicyTests.swift` if needed.

**Interface:** a pure policy computes next required wake from visible UI, display mode, event boundaries and countdown precision. Rebuild agenda structure only on data/settings/day changes and start/end boundaries. For status countdowns, update at minute-value transitions when >=60 seconds away and each second during the final minute. Icon-only idle must not create a one-second structural loop.

- [ ] Fake time tests cover 61→60→59 seconds, event start/end, no meetings, icon-only, popover opening/closing and timezone change.
- [ ] A scheduled event still changes icon/agenda at the exact relevant boundary; removing a periodic tick must not miss it. Overlay countdown and keyboard behavior remain unchanged.
- [ ] Capture before/after structural rebuild counts over an idle simulated hour. Profile energy separately if making battery claims.
- [ ] Run APP and CORE. Use the manual macOS checklist for visible countdown/focus behavior.

### Task 14 — Correct numbered Microsoft series splits

**Covers:** Microsoft series-write limitation, not the excluded permission change. **Dependencies:** none; retain existing split rollback behavior.

**Files:** Microsoft `MicrosoftCalendarSource+Split.swift`, `GraphRecurrenceMapper.swift`, `GraphTime.swift`; `MicrosoftCalendarTests/SplitSeriesTests.swift`, `RecurrenceMapperTests.swift`.

**Contract:** remaining count equals original scheduled recurrence slots from the split slot onward, including deleted slots before the split in the consumed count. Do not infer recurrence position solely from the number of returned instances. Preserve existing supported write scopes and OAuth access.

- [ ] Numbered five-slot series: delete slot 2, split at original slot 4; continuation count must be 2, not 3. Moving slot 3 beyond the split must not change that result.
- [ ] Cover weekly multiple weekdays, interval >1, monthly relative rules and DST. Count based on original recurrence slots in the recurrence zone, not moved exception timestamps.
- [ ] Implement a bounded recurrence-position calculation for supported Graph recurrence patterns. For a pattern not yet representable, return the existing typed unsupported/invalid error before any mutation; do not silently extend a series. Document the specific limitation for review rather than reducing write authorization.
- [ ] Preserve transaction IDs, retry and rollback tests. Run CONNECTORS. Live tests remain opt-in. Do not claim Graph read-before-write is atomic or change that documented contract in this batch.

## Batch C — CI, documentation and agent efficiency

### Task 15 — Remove credentials from pre-merge Firebase execution

**Covers:** finding 6. **Dependencies:** none.

**Files:** `.github/workflows/firebase-hosting-pull-request.yml`, `scripts/ci/tests/test-workflows.sh`, documentation of website previews.

**Selected local approach:** replace the credential-bearing PR deploy job with credential-free static-site validation. Keep merge deployment unchanged. This intentionally removes automatic hosted PR previews; document the change clearly. If hosted previews are a user requirement, stop this task for a separate preview-only identity/project design instead of reusing the production service account.

- [ ] Add workflow checks asserting PR-triggered jobs never reference Firebase/deployment secrets and never use `pull_request_target` to execute PR code.
- [ ] Validate website files/link-policy tests on relevant PRs. Preserve fork-safe read permissions and do not grant unnecessary write tokens.
- [ ] Inspect the merge workflow for accidental edits; no deploy, credential rotation or IAM mutation is part of this code task.
- [ ] Run SHELL and website tests from Task 19 when available. Record actual hosted IAM/environment checks as pending external verification, not as completed remediation.

### Task 16 — Pin Actions and require release-tooling checks

**Covers:** supply-chain hardening and review recommendation B. **Dependencies:** Task 15.

**Files:** all `.github/workflows/*.yml`, `.github/dependabot.yml`, `scripts/ci/tests/test-workflows.sh`; create a pinned tooling requirements file under `scripts/ci/` if absent.

- [ ] Resolve each currently selected action version from its official repository to a full commit SHA; verify provenance and retain the version in a comment. Do not invent SHAs or silently upgrade major versions.
- [ ] Keep Dependabot configured and verify it can update pinned workflow references. Keep Sparkle package/tool versions and SHA-256 validation unchanged.
- [ ] Add a release-tooling CI job that installs pinned test prerequisites and runs PYTHON and all six shell suites. Missing PyYAML must fail this job rather than return success with SKIP.
- [ ] Add tests for action pinning, secret-free PR jobs and release-tooling job coverage. Scope permissions to jobs where possible without breaking artifact/preview checks.
- [ ] Run SHELL and PYTHON; inspect the rendered workflow structure. For Linux, inspect a successful same-code run before removing `continue-on-error`. If Linux cannot be verified, explicitly leave enforcement pending; never relabel it proven.

### Task 17 — Add one verification entry point

**Covers:** recommendation B and repeatable agent checks. **Dependencies:** Task 16.

**Create:** `scripts/dev/verify.sh`, `scripts/dev/tests/test-verify.sh`, `docs/development.md`. **Modify:** CI to reuse applicable portions after parity is demonstrated.

**CLI:** `scripts/dev/verify.sh core|connectors|app|release-tools|all|affected [--base <git-ref>]`. No auto-installing global tools. `affected` defaults to changed tracked/untracked source files in the working tree; explicit base includes changes against that ref. Unknown source/config paths select `all`; documentation-only changes select documentation checks once Task 18 exists.

- [ ] Implement prerequisite checks, stable per-run log directory, checked commit plus dirty status, elapsed time, exit code and executed/skipped test summary. Distinguish missing prerequisite from test failure.
- [ ] Test routing with stub executables: Core changes run Core/dependents; CalendarCore/connector model changes run all package/app dependents; app-only changes run APP; release/workflow changes run release-tools and workflow checks. Mixed changes union/deduplicate checks.
- [ ] APP performs XcodeGen first; package checks run once each. No automatic live-test environment flags. `all` includes every package, APP and release tools; report Linux/manual tests separately.
- [ ] Test failed subprocess propagation, spaces in paths, missing base ref, untracked source and no changes. A skipped required check cannot produce success.
- [ ] Run wrapper tests, then `verify.sh all` once. Compare coverage with the pre-wrapper command table before replacing CI commands.

### Task 18 — Make the repository instructions current and reduce artifact churn

**Covers:** recommendations A, C, D and E. **Dependencies:** completed behavior/API tasks above; may stage the navigation skeleton earlier.

**Modify:** `AGENTS.md`, `docs/architecture.md`, old spec status header, `.gitignore`, `Apps/macOS/project.yml`, tracked Info.plist ownership as required. **Create:** `docs/decisions/README.md`, focused signing/OAuth/release runbook links, optional scoped `AGENTS.md` only where rules differ, `scripts/ci/check-repository-contracts.py`, a checkpoint template under `docs/development/`.

- [ ] Make current architecture the entry point. Document MicrosoftCalendar, actual dependencies, correct source-addition flow and current defaults. Mark old specs superseded for changed topics without rewriting historical rationale.
- [ ] Move long operational recipes from root into linked runbooks; retain invariants, security boundaries, commands and the explicit Microsoft write-access decision in root. Avoid repeated copied instructions across scoped guides.
- [ ] Create ADR index with current/superseded status, affected module and relevant test references. Link the verification wrapper and one checkpoint format: task ID, head, files, checks, limitations, next step.
- [ ] Add focused automated contracts: portable package imports/dependencies, documented path existence, registered provider coverage, source capability invariants, and intended Microsoft write scopes. Use manifest/compiler-aware checks where practical; avoid fragile general Swift parsing by regex.
- [ ] Remove only confirmed generated tracked Python bytecode and obsolete `.bak` artifact; ignore `__pycache__/` and `*.pyc`. Inspect the backup first to ensure it contains no unique needed test.
- [ ] Make XcodeGen's Info.plist source of truth explicit: reconcile generated keys with `project.yml` and checked-in files so two consecutive generations leave tracked files unchanged. Do not delete entitlements, privacy descriptions, OAuth substitutions or Sparkle metadata.
- [ ] Pin a compatible formatter/linter version and introduce a focused check without whole-repo autoformatting. Baseline existing violations explicitly; do not suppress new violations globally.
- [ ] Run repository-contract checks, wrapper tests, generate twice and inspect diff. Run APP if project/Info.plist inputs changed. Keep UI behavior checks manual where automation cannot prove them.

### Task 19 — Harden and test website links/headers

**Covers:** static website recommendations. **Dependencies:** Task 15; no deployment.

**Files:** `site/public/download.js`, `site/firebase.json`; create a small offline JS test using the existing runtime if available, otherwise a documented Node built-in test setup.

**Interface:** validate a release download URL before setting `href`: HTTPS, no credentials, exact `github.com` host, and path under `/darkarena1/timetug/releases/download/`. Keep the existing GitHub latest-release fallback if validation/fetch fails.

- [ ] Tests cover valid signed-DMG path, unsigned asset exclusion, deceptive host, other repository, javascript/file scheme, embedded credentials, malformed JSON and failed request.
- [ ] Inspect current page resources before adding CSP. Allow the existing local script, GitHub API connection, required Google font style/font hosts and local images/styles; avoid `unsafe-eval` or broad `*` sources. Choose frame/object restrictions consistent with a static public site.
- [ ] Add the policy in Firebase headers, verify local page behavior with the intended policy, and document that hosted headers require verification after a separately authorized deployment. Do not claim the original production site lacked headers solely from repository inspection.
- [ ] Run offline JS checks and SHELL. Wire these checks into `verify.sh release-tools` or a documented website mode and update affected routing.

### Task 20 — Close the handoff with evidence and measurements

**Covers:** all review recommendations and efficiency measurement. **Dependencies:** all implemented tasks; pending external checks remain explicit.

**Files:** update this checklist and add `docs/reviews/2026-09-26-remediation-results.md` (or a current-date results file); keep original audit as historical evidence.

- [ ] Map every included report item to its task/result using the table below. Mark finding 7 excluded by the user, not fixed.
- [ ] Run the complete verification wrapper after the final implementation changes. Record actual counts, skips, commit, dirty state and platform. Do not reuse the audit's baseline counts as new evidence.
- [ ] Review the whole change set for lost migrations, Microsoft scope/capability changes, secret leakage and incorrect “all verified” claims. Perform required manual checks or list them pending.
- [ ] Record before/after measurements: startup documentation words/estimated tokens, verification wall time, duplicate benchmark, provider request counts, idle structural UI rebuilds. Agent token/tool-call/review-pass metrics require actual session data; do not invent them or promise a fixed savings percentage.
- [ ] Provide the reviewed batches and outstanding external work to the user. Integration/release authorization remains separate from local test success.

## Coverage map

| Original report item | Task(s) |
|---|---|
| 1 Credential lifecycle | 1 |
| 2 Refresh ordering | 2 |
| 3 Timezone context | 3 |
| 4 Startup acknowledgement | 4 |
| 5 Structured Join URLs | 5 |
| 6 Firebase PR secrets | 15–16 |
| 7 Reduce Microsoft write access | **EXCLUDED — preserve current access** |
| 8 Widget horizon | 6 |
| 9 Inference cache inputs | 7 |
| 10 Dedup performance | 11 |
| 11 Scoped refresh/fanout | 9–10 |
| Per-second UI work | 13 |
| Inference bounds/backoff/injection evaluation | 8 |
| Microsoft series correctness | 14 |
| OAuth callback resilience | 12 |
| Actions pinning | 16 |
| Website URL/CSP hardening | 19 |
| Agent guidance and architecture consistency | 18 |
| Unified verification and release-tool CI | 16–17 |
| Lifecycle seams and meaningful tests | 1–4, 7, 9, 13 |
| Executable contracts, ADR map, checkpoints | 18 |
| Generated artifacts, XcodeGen, formatter stability | 18 |
| Measured LLM/workflow efficiency | 20 |

## Copyable execution instruction

Implement `docs/superpowers/plans/2026-09-26-audit-remediation-handoff.md` one reviewable task at a time, starting with Task 1. Preserve Microsoft calendar write scopes and capabilities. Reproduce each bug with a deterministic offline test before fixing it. Keep tests and production changes scoped to the current task, record evidence, and preserve outstanding approval/manual/live-verification boundaries. Use the report for background; this plan's explicit exclusion controls scope. Do not start by redesigning the whole application or editing every file at once.
