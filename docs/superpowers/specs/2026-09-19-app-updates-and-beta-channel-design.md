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
- Ordering key: `CFBundleVersion` (`sparkle:version`) is a UTC timestamp `YYYYMMDDHHMM`, computed at build time and passed to xcodebuild as `CURRENT_PROJECT_VERSION`. It is never a hash and is shared by beta and release workflows, so a release always outranks earlier betas. The hand-bumped build number in `project.yml` is removed.
- Display version (`CFBundleShortVersionString`): beta is `<base>-beta.<PR number>.<run number>`; stable is the tag without `v`. `<base>` is `MARKETING_VERSION` in `project.yml`, bumped by hand when a release cycle starts.
- Signing: betas are signed with the Developer ID Application certificate in CI and NOT notarized. Sparkle-installed updates are not quarantined, so Gatekeeper does not check them; the first install still comes from the notarized DMG. Developer ID signing keeps widgets/controls working (they need team signing) and keeps the signing identity stable across updates. Every zip also carries a Sparkle EdDSA signature.
- Retention: keep the 5 newest beta prereleases and their appcast entries; prune the rest.

## App changes
- `UpdateController` in `Apps/macOS/Sources`, wrapping `SPUStandardUpdaterController`, behind a small protocol so tests never launch Sparkle. Exposes `checkForUpdates()`, `automaticallyChecks` (bound to Sparkle's own preference), `includeBetas` (stored in `SharedSettings`; drives `allowedChannels(for:)`, returning `["beta"]` when on, empty set when off), `lastCheckDate`, current version string.
- Info.plist: `SUFeedURL` (gh-pages appcast URL), `SUPublicEDKey` (public key only).
- Settings > General gets an "Updates" section laid out like macOS Software Update: status line ("TimeTug is up to date" + version) with a Check for Updates button; Automatic Updates row; Beta Updates row, each with help text. Turning Beta Updates off leaves a beta user on their beta until a stable release outranks it; the help text says so.
- Menu bar dropdown gets a "Check for Updates…" item.
- Core is untouched (no update logic; AGENTS.md layering holds).
- Testing: unit tests for `UpdateController` logic (channel selection, defaults, persistence) using a fake updater. Real Sparkle UI verified by hand; steps added to `docs/manual-tests/macos-checklist.md`.

## CI changes
### `beta.yml`
- Trigger: `workflow_run` on `CI` completed, only for `pull_request` events with conclusion `success`, and only when the PR head repo is this repo (fork PRs never receive secrets).
- Steps: check out the PR head commit; compute timestamp and versions; `scripts/ci/build-release.sh` with those values; import the Developer ID certificate into a temporary keychain and sign (no notarization); `scripts/release/make-update-zip.sh` (`ditto`); `sign_update` for the EdDSA signature; publish a GitHub prerelease tagged `beta-<timestamp>` with the zip; `scripts/release/update-appcast.sh` adds a beta item to `appcast.xml` on `gh-pages`; `scripts/release/prune-betas.sh` keeps the newest 5.
- Concurrency group `beta`, `cancel-in-progress: false`; each run fetches the latest `gh-pages` before editing so appcast writes do not race.
- If the appcast publish fails after the prerelease exists, the workflow fails visibly and the prerelease is left as a draft, so no update is offered that is missing from the feed.

### `release.yml` (existing, tag-triggered)
- Existing build, sign, notarize and DMG steps are unchanged.
- Added: build the Sparkle zip, EdDSA-sign it, attach it to the release, add a stable item to `appcast.xml`.
- Uses the same timestamp `CFBundleVersion` scheme.

### Scripts
Logic lives in `scripts/release/` and `scripts/ci/` (`make-update-zip.sh`, `update-appcast.sh`, `prune-betas.sh`); YAML only wires them together (AGENTS.md rule). The appcast and prune scripts get fixture-based tests runnable locally without GitHub.

## One-time setup (documented in the rewritten `docs/release.md`)
- `generate_keys` creates the Sparkle keypair; public key into Info.plist, private key into the `SPARKLE_PRIVATE_KEY` secret. Never commit the private key.
- Create the `gh-pages` branch and enable Pages.
- Beta needs the existing `MACOS_CERTIFICATE_P12_BASE64` and `MACOS_CERTIFICATE_PASSWORD` secrets (and `APPLE_TEAM_ID`); notarization secrets stay release-only.

## Documentation
- Rewrite `docs/release.md` (channels, versioning, secrets, setup, how to cut a release, how betas work).
- Update the "CI and releases" section of `AGENTS.md`.
- New ADR: Sparkle, channel model, timestamp build numbers, unnotarized Developer-ID-signed betas.

## Out of scope
Delta updates, notarizing betas, per-PR opt-in, self-hosted feed, updating from within a sandbox.
