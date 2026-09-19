# App updates and beta channel: design

Date: 2026-09-19. Status: approved in conversation, pending written-spec review.

## Goals
1. TimeTug updates itself when a new version is available, using Sparkle 2.
2. Settings gets controls that mimic macOS Software Update: Check for Updates, Automatic Updates, Beta Updates.
3. CI publishes a beta build for the latest green PR. Betas are full signed apps delivered through Sparkle (Sparkle replaces the whole bundle; partial updates are not possible).
4. A tagged release builds the full DMG as it does today and also publishes the stable Sparkle update.

## Decisions
- Library: Sparkle 2 via Swift Package, pinned exactly in `Apps/macOS/project.yml` (precedent: ADR 0005). New ADR records it.
- Hosting: builds are GitHub Releases assets; the appcast is `appcast.xml` on the `gh-pages` branch (GitHub Pages).
- One appcast. Stable items carry no channel; beta items carry `<sparkle:channel>beta</sparkle:channel>`. The app opts in to the `beta` channel through Sparkle's `allowedChannels(for:)` delegate method.
- Ordering key: `CFBundleVersion` (`sparkle:version`) is a UTC timestamp `YYYYMMDDHHMM`. It is stamped by `scripts/ci/build-release.sh` from the `BUILD_NUMBER` environment variable (the script already does this for both the app and widget plists); the workflows set `BUILD_NUMBER=$(date -u +%Y%m%d%H%M)`. The script's fallback to `GITHUB_RUN_NUMBER` is removed, because run numbers are per workflow and would not order betas against releases. The value is never a hash and is shared by beta and release workflows, so a release always outranks earlier betas. The literal `CFBundleVersion: "2"` values in `project.yml` remain only as the local-dev default.
- Display version (`CFBundleShortVersionString`): beta is `<base>-beta.<PR number>.<run number>`; stable is the tag without `v`. `<base>` is the existing `CFBundleShortVersionString` in `Apps/macOS/project.yml` (the value `build-release.sh` already reads when no tag is given), bumped by hand when a release cycle starts. `<run number>` is `github.run_number` of the beta build workflow.
- Signing: betas are signed with the Developer ID Application certificate in CI and NOT notarized. Sparkle-installed updates are not quarantined, so Gatekeeper does not check them; the first install still comes from the notarized DMG. Developer ID signing keeps widgets/controls working (they need team signing) and keeps the signing identity stable across updates. Every zip also carries a Sparkle EdDSA signature.
- Retention: keep the 5 newest beta prereleases and their appcast entries; prune the rest.

## App changes
- `UpdateController` in `Apps/macOS/Sources`, wrapping `SPUStandardUpdaterController`, behind a small protocol so tests never launch Sparkle. Exposes `checkForUpdates()`, `automaticallyChecks` (bound to Sparkle's own preference), `includeBetas` (stored in the app's `UserDefaults`, key `updates.includeBetas.v1`; the widgets do not need it; drives `allowedChannels(for:)`, returning `["beta"]` when on, empty set when off), `lastCheckDate`, current version string.
- Add `SUFeedURL` (gh-pages appcast URL) and `SUPublicEDKey` (public key only) under `info.properties` of the app target in `Apps/macOS/project.yml`. XcodeGen regenerates `Sources/Info.plist` from those properties, so editing the plist directly would lose them.
- Settings > General gets an "Updates" section laid out like macOS Software Update: status line ("TimeTug <version>" and "Last checked <date>"; Sparkle only reports "up to date" as the result of a check, so there is no standing claim) with a Check for Updates button; Automatic Updates row; Beta Updates row, each with help text. Turning Beta Updates off leaves a beta user on their beta until a stable release outranks it; the help text says so.
- Menu bar dropdown gets a "Check for Updates…" item.
- Core is untouched (no update logic; AGENTS.md layering holds).
- Testing: unit tests for `UpdateController` logic (channel selection, defaults, persistence) using a fake updater. Real Sparkle UI verified by hand; steps added to `docs/manual-tests/macos-checklist.md`.

## CI changes
### Beta pipeline (two workflows, so PR code never runs with the keys)
PR-authored scripts (`build-release.sh`, `project.yml`, XcodeGen run-script phases) can be changed by anyone who can push a branch, so they must never execute in a job that holds the Developer ID certificate or `SPARKLE_PRIVATE_KEY`.

**`beta-build.yml` (unprivileged).** Trigger: `pull_request`, same-repo PRs only (`github.event.pull_request.head.repo.full_name == github.repository`); no secrets, `permissions: contents: read`. It builds the app with `BUILD_NUMBER` set to the timestamp and the beta display version, ad-hoc signed as CI does today, and uploads `dist/TimeTug.app` (as a tar/zip preserving the bundle) plus a small `meta.json` (PR number, head SHA, timestamp, version) as an artifact. It runs after, or as part of, the same checks as CI; the publish workflow only proceeds when the build workflow succeeded.

**`beta-publish.yml` (privileged, trusted code only).** Trigger: `workflow_run` on `beta-build` completed with `conclusion == success`. Payload fields used: `github.event.workflow_run.head_repository.full_name` (must equal `github.repository`), `.event == 'pull_request'`, `.head_sha`, `.id` (to download the artifact), and the PR number and timestamp come from `meta.json`. It checks out the DEFAULT branch (never the PR head) and runs only default-branch scripts on the downloaded artifact, which is treated as untrusted input:
1. Re-sign the app inside-out with Developer ID, without notarizing: `scripts/release/sign-app.sh` (new, split out of `sign-and-notarize.sh`, which keeps signing then notarizing by calling it). Order: Sparkle's nested XPC services and `Autoupdate` helper, then `Sparkle.framework`, then the widget extension, then the app, hardened runtime, in a temporary keychain that is deleted at the end.
2. `scripts/release/make-update-zip.sh` (`ditto -c -k --keepParent`).
3. `sign_update` adds the EdDSA signature and length.
4. Create the GitHub prerelease as a DRAFT tagged `beta-<timestamp>` with the zip attached.
5. `scripts/release/update-appcast.sh` adds a beta item to `appcast.xml` on `gh-pages` (see below), then the release is flipped from draft to published. If any step fails the workflow fails visibly and the draft is left unpublished, so no update is offered that is missing from the feed, and a beta is never public without a feed entry.
6. `scripts/release/prune-betas.sh` keeps the newest 5 beta releases and appcast entries.

**Appcast writes.** Beta publishes are serialised by the concurrency group `appcast` (`cancel-in-progress: false`). `release.yml` has no such group (it would block betas behind a whole release and can drop queued runs); instead every write, beta or release, goes through `publish-appcast.sh`, which never force-pushes and re-applies its edit onto the latest `gh-pages` after a rejected push (bounded retries), so concurrent writers both land. Note GitHub keeps at most one pending run per group, so a beta for an intermediate green PR can be skipped when several finish at once; that is acceptable because only the newest beta matters.

**Appcast generation.** `scripts/release/update-appcast.sh` edits the XML with a small script (Python stdlib): it inserts an `<item>` with `sparkle:version`, `sparkle:shortVersionString`, `sparkle:minimumSystemVersion`, the enclosure URL (the release asset), `length`, `sparkle:edSignature` and, for betas, `<sparkle:channel>beta</sparkle:channel>`. It does not depend on `generate_appcast`.

### `release.yml` (existing, tag-triggered)
- Existing build, sign, notarize and DMG steps are unchanged.
- Added, only when `steps.signing.outputs.has_signing == 'true'` (an unsigned/ad-hoc release never enters the update feed): after the app is signed, notarized and stapled, build the Sparkle zip from that stapled app, EdDSA-sign it, attach it to the release, and add a stable item to `appcast.xml` through `publish-appcast.sh`, after the GitHub release exists.
- Uses the same timestamp `CFBundleVersion` scheme.

### Scripts
Logic lives in `scripts/release/` and `scripts/ci/` (`make-update-zip.sh`, `update-appcast.sh`, `prune-betas.sh`); YAML only wires them together (AGENTS.md rule). The appcast and prune scripts get fixture-based tests runnable locally without GitHub.

## One-time setup (documented in the rewritten `docs/release.md`)
- `generate_keys` creates the Sparkle keypair; public key into Info.plist, private key into the `SPARKLE_PRIVATE_KEY` secret. Never commit the private key.
- Create the `gh-pages` branch and enable Pages.
- The beta publish workflow needs the existing `MACOS_CERTIFICATE_P12_BASE64` and `MACOS_CERTIFICATE_PASSWORD` secrets (and `APPLE_TEAM_ID`); notarization secrets stay release-only.

## Documentation
- Rewrite `docs/release.md` (channels, versioning, secrets, setup, how to cut a release, how betas work).
- Update the "CI and releases" section of `AGENTS.md`.
- New ADR: Sparkle, channel model, timestamp build numbers, unnotarized Developer-ID-signed betas.

## Out of scope
Delta updates, notarizing betas, per-PR opt-in, self-hosted feed, updating from within a sandbox.
