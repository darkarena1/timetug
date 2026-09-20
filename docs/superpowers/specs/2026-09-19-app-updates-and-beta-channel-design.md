# App updates and beta channel: design

Date: 2026-09-19. Status: approved; the beta and release pipeline was redesigned after first implementation (this document describes the redesign).

## Goals
1. TimeTug updates itself when a new version is available, using Sparkle 2.
2. Settings gets controls that mimic macOS Software Update: Check for Updates, Automatic Updates, Beta Updates.
3. CI publishes a beta build for every merge to `master` that passes CI. Betas are full signed apps delivered through Sparkle (Sparkle replaces the whole bundle; partial updates are not possible). Pull requests never sign or publish anything.
4. When the owner publishes a GitHub Release on a `v*` tag, CI builds the full DMG as before, uploads it and the stable Sparkle update to that release, and adds it to the feed.

## Decisions
- Library: Sparkle 2 via Swift Package, pinned exactly in `Apps/macOS/project.yml` (precedent: ADR 0005). New ADR records it.
- Hosting: builds are GitHub Releases assets; the appcast is `appcast.xml` on the `gh-pages` branch (GitHub Pages).
- One appcast. Stable items carry no channel; beta items carry `<sparkle:channel>beta</sparkle:channel>`. The app opts in to the `beta` channel through Sparkle's `allowedChannels(for:)` delegate method.
- Ordering key: `CFBundleVersion` (`sparkle:version`) is a UTC timestamp `YYYYMMDDHHMMSS` (14 digits, second resolution, so a beta and a release build-number collision is very unlikely, not impossible). It is stamped by `scripts/ci/build-release.sh` from the `BUILD_NUMBER` environment variable (for both the app and widget plists); `scripts/ci/compute-versions.sh` produces it. The script's fallback to `GITHUB_RUN_NUMBER` is removed, because run numbers are per workflow and would not order betas against releases. The value is never a hash and is shared by beta and release workflows, so a release always outranks earlier betas. `appcast.py` rejects, loudly, an add with the same `sparkle:version` but a different download URL, and replaces an item with the same enclosure URL. The literal `CFBundleVersion: "2"` values in `project.yml` remain only as the local-dev default.
- Display version (`CFBundleShortVersionString`): beta is `<base>-beta.<timestamp>`; stable is the tag without `v`. `<base>` is the newest stable release tag (`v*` without suffix, by version order, `v` stripped), falling back to `CFBundleShortVersionString` in `Apps/macOS/project.yml` when there is no stable tag; no manual bump is needed. `<timestamp>` is the 14-digit `BUILD_NUMBER`.
- Signing: betas are signed with the Developer ID Application certificate in CI and NOT notarized. Sparkle-installed updates are not quarantined, so Gatekeeper does not check them; the first install still comes from the notarized DMG. Developer ID signing keeps widgets/controls working (they need team signing) and keeps the signing identity stable across updates. Every zip also carries a Sparkle EdDSA signature.
- Retention: keep the 5 newest beta prereleases and their appcast entries; prune the rest (their releases and tags are deleted).

## App changes
- `UpdateController` in `Apps/macOS/Sources`, wrapping `SPUStandardUpdaterController`, behind a small protocol so tests never launch Sparkle. Exposes `checkForUpdates()`, `automaticallyChecks` (bound to Sparkle's own preference), `includeBetas` (stored in the app's `UserDefaults`, key `updates.includeBetas.v1`; the widgets do not need it; drives `allowedChannels(for:)`, returning `["beta"]` when on, empty set when off), `lastCheckDate`, current version string.
- Add `SUFeedURL` (gh-pages appcast URL) and `SUPublicEDKey` (public key only) under `info.properties` of the app target in `Apps/macOS/project.yml`. XcodeGen regenerates `Sources/Info.plist` from those properties, so editing the plist directly would lose them.
- Settings > General gets an "Updates" section laid out like macOS Software Update: status line ("TimeTug <version>" and "Last checked <date>"; Sparkle only reports "up to date" as the result of a check, so there is no standing claim) with a Check for Updates button; Automatic Updates row; Beta Updates row, each with help text. Turning Beta Updates off leaves a beta user on their beta until a stable release outranks it; the help text says so.
- Menu bar dropdown gets a "Check for Updates…" item.
- Core is untouched (no update logic; AGENTS.md layering holds).
- Testing: unit tests for `UpdateController` logic (channel selection, defaults, persistence) using a fake updater. Real Sparkle UI verified by hand; steps added to `docs/manual-tests/macos-checklist.md`.

## CI changes
Pull requests run only `ci.yml` (build and tests). There is no signing and no secret for a PR, and nothing it produces can enter the update feed (the `dmg` job still uploads an unsigned `TimeTug-dmg`, and `app` uploads `TestResults` on failure), so PR code never runs with the keys. Secrets are used only by workflows that run merged code.

### `beta.yml` (name `Beta`, automatic, no approval)
Trigger: `workflow_run` of `CI` completed, `branches: [master]`, and the job runs only when the conclusion is `success`, the event is `push` and the head repository is this repository. It has no environment, so it reads repository-scoped secrets.
1. Check out the CI-verified `head_sha` and require it to be an ancestor of `origin/master`. Build only the tip of `master`: if the commit is no longer the tip, skip with a notice (the newer commit gets its own run; this also makes re-running an old run harmless).
2. Skip (green run, notice) if the Developer ID certificate, its password, the team id or `SPARKLE_PRIVATE_KEY` is missing.
3. Build with `scripts/ci/build-release.sh`, with `APP_VERSION` and `BUILD_NUMBER` from `scripts/ci/compute-versions.sh beta`.
4. Sign with Developer ID, without notarizing: `scripts/release/sign-app.sh` (split out of `sign-and-notarize.sh`, whose `app` mode calls it). Order: Sparkle's nested XPC services and `Autoupdate` helper, then `Sparkle.framework`, then the widget extension, then the app, hardened runtime, in a temporary keychain that is deleted at the end.
5. `scripts/release/make-update-zip.sh` (`ditto -c -k --keepParent`), then `sign_update --ed-key-file` for the EdDSA signature and length.
6. Create the GitHub prerelease as a DRAFT tagged `v<APP_VERSION>` (`v<base>-beta.<BUILD_NUMBER>`; the two betas published earlier use the legacy `beta-<BUILD_NUMBER>` tag and are pruned by the same logic) with the zip attached, then PUBLISH it. An existing release or tag of that name fails the run.
7. Only then `scripts/release/publish-appcast.sh` adds a beta item (with a release-notes link) to `appcast.xml` on `gh-pages` and prunes to the newest 5 betas. The release is published before the feed lists it so the feed never points at an asset that cannot be downloaded. If the appcast step fails the run fails visibly and the release stays public but unlisted.
8. Pruned beta releases and tags are deleted; a failed delete warns but does not fail the run.

**Appcast writes.** Beta runs are serialised by the concurrency group `appcast` (`cancel-in-progress: false`). `release.yml` has no such group (it would block betas behind a whole release); instead every write goes through `publish-appcast.sh`, which never force-pushes and re-applies its edit onto the latest `gh-pages` after a rejected push (bounded retries), so concurrent writers both land.

**Appcast generation.** `scripts/release/appcast.py` (Python stdlib) edits the XML: it inserts an `<item>` with `sparkle:version`, `sparkle:shortVersionString`, `sparkle:minimumSystemVersion`, the enclosure URL (the release asset), `length`, `sparkle:edSignature`, a release-notes link and, for betas, `<sparkle:channel>beta</sparkle:channel>`. It rejects an add with the same `sparkle:version` but a different URL, and replaces an item with the same enclosure URL (so re-running a release replaces its item). It does not depend on `generate_appcast`.

### `release.yml` (stable)
Trigger: `release: published` for a tag starting with `v` (beta releases are created with the workflow token, which never triggers workflows), and `workflow_dispatch` with a `tag` input as a fallback. Pushing a tag alone does nothing. The owner drafts the release in the GitHub UI, reviews it and clicks Publish.
- For the release event, checks out `refs/tags/<tag>` (so a branch named like the tag cannot shadow it) and fails if HEAD is not the tag's commit. A `Validate the tag` step runs `compute-versions.sh stable` right after checkout, so a bad tag (e.g. uppercase `V1.2.3`) fails before any build or secrets.
- Builds the tag's commit (for dispatch: the tag's commit if the tag exists, otherwise the selected ref, and the workflow then creates the tag). The commit must be on `master`. The job needs the owner's approval through the `release` environment (reviewers, deployments limited to `master` and `v*` tags).
- Fails early if the Apple secrets exist but `SPARKLE_PRIVATE_KEY` does not.
- With all Apple secrets: sign, notarize and staple the app and the DMG, build the Sparkle zip from the stapled app and EdDSA-sign it, then UPLOAD the DMG, its `.sha256` and the zip to the release the owner published (the owner's title and notes are not overwritten), then add the stable appcast item. A `-` suffix tag (for example `v1.2.3-rc1`), or a release the owner marked as a pre-release in the GitHub UI, goes to the beta channel.
- Without them: upload an unsigned DMG, mark the release a prerelease and never add it to the feed.
- The release is visible without assets for the roughly 30 minutes the build takes; the appcast item appears only after the upload.
- Re-running for an existing tag builds new bytes with a new build number, re-uploads with `--clobber` and replaces the tag's appcast item (same enclosure URL). Recovery is in `docs/release.md`.

### Scripts
Logic lives in `scripts/release/` and `scripts/ci/` (`compute-versions.sh`, `sign-app.sh`, `make-update-zip.sh`, `fetch-sparkle-tools.sh`, `publish-appcast.sh`, `appcast.py`); YAML only wires them together (AGENTS.md rule). The version, appcast and publish scripts have fixture-based tests runnable locally without GitHub.

## Security model
Secrets are only used by `beta.yml` (a `master` commit that passed CI) and `release.yml` (a `master` commit with owner approval). A pull request can never reach the signing keys. Keep `master` protected (rulesets "Protect master" and "Protect release tags") and keep the `release` environment with required reviewers and a `master` / `v*` deployment policy. Anyone with write access can publish a release on a `v*` tag, so the environment approval and the tag ruleset are the real guards for stable; the on-`master` check in the workflow is a safety net. Betas ship whatever is merged to `master`, so merges need the review already required.

## One-time setup (documented in `docs/release.md`)
- `generate_keys` creates the Sparkle keypair; public key into Info.plist, private key into the `SPARKLE_PRIVATE_KEY` secret. Never commit the private key.
- Create the `gh-pages` branch and enable Pages.
- `beta.yml` needs `MACOS_CERTIFICATE_P12_BASE64`, `MACOS_CERTIFICATE_PASSWORD`, `APPLE_TEAM_ID` and `SPARKLE_PRIVATE_KEY` as repository secrets (it has no environment); notarization secrets are used only by `release.yml`.
- Keep the `release` environment and both rulesets in place.
- First real run: confirm `workflow_run` fires for `CI` on `master` pushes and the secrets are visible to `beta.yml`.

## Documentation
- Rewrite `docs/release.md` (channels, versioning, secrets, setup, how to cut a release, how betas work).
- Update the "CI and releases" section of `AGENTS.md`.
- New ADR: Sparkle, channel model, timestamp build numbers, unnotarized Developer-ID-signed betas.

## Out of scope
Delta updates, notarizing betas, betas built from pull requests (PRs get no signing or secrets), per-PR opt-in, self-hosted feed, updating from within a sandbox.
