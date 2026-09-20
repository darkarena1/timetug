# Releasing TimeTug

## Cut a release
1. Make sure `master` is green and `docs/manual-tests/macos-checklist.md` has been run.
2. In GitHub, draft a new release (Releases > Draft a new release). Create a tag that starts with `v`, for example `v0.1.0`, on `master`, and write the title and notes. Saving the draft does nothing. Review it, then click **Publish release**.
3. Publishing triggers the `Release` workflow (`release: published`; tags that do not start with `v` are ignored, and beta releases, created by the `Beta` workflow's own token, never trigger it). Pushing a tag alone no longer triggers anything. The workflow checks out `refs/tags/<tag>` (qualified, so a branch with the same name cannot shadow it) and fails if HEAD is not the tag's commit. A `Validate the tag` step runs `compute-versions.sh stable` first, so a bad tag such as an uppercase `V1.2.3` fails before any build or secrets. It builds that commit, waits for your approval in the `release` environment, then signs and notarizes the app and DMG and uploads `TimeTug-<version>.dmg`, its `.sha256` and the Sparkle zip to the release you published. It does not touch your title or notes. Only after the upload does it add the item to the appcast (see "Publishing the stable update"). The version is the tag without the `v`.
4. The release is visible without assets for the roughly 30 minutes the build takes, and the appcast item appears only after the assets are uploaded. Do not announce it until the workflow is green.

Fallback: run the "Release" workflow from the Actions tab (`workflow_dispatch`, input `tag`). For an existing tag it builds that tag's commit and uploads to that release. For a new tag it builds the selected ref, creates the tag and the release (with generated notes). The commit must be on `master` either way.

A tag with a `-` suffix (for example `v1.2.3-rc1`), or a release you marked as a pre-release in the GitHub UI, goes to the `beta` channel of the appcast, not the stable feed (a `-` tag is also marked prerelease on GitHub). If the Apple secrets are missing, the workflow uploads an unsigned DMG, marks the release a prerelease and never adds it to the feed.

## Channels and versioning
Installed apps update through Sparkle from one feed, `https://darkarena1.github.io/timetug/appcast.xml` (`SUFeedURL` in `Apps/macOS/project.yml`). Items in it are either stable or on the `beta` channel; a user sees beta items only after turning on Settings > General > Software Update > Beta updates.

| | Display version (`CFBundleShortVersionString`) | Build number (`CFBundleVersion`) |
| --- | --- | --- |
| Stable | the tag without `v`, e.g. `1.2.3` | UTC timestamp `YYYYMMDDHHMMSS` (14 digits) |
| Beta | `<base>-beta.<timestamp>`, e.g. `1.1.0-beta.20260920050214` | UTC timestamp `YYYYMMDDHHMMSS` (14 digits) |

- `<base>` is the newest stable release tag (`v*` with no suffix, highest by version order), without the `v`. Tags such as `v1.2.0-rc1`, `v1.2.0-beta.<timestamp>` and the legacy `beta-*` are ignored. With no stable tag yet, it falls back to `CFBundleShortVersionString` in `Apps/macOS/project.yml` (`0.0.0-dev`, so betas are labelled `0.0.0-dev-beta.<timestamp>`). No manual bump is needed; that `project.yml` value is only the local-dev fallback.
- `<timestamp>` is the same 14-digit UTC build number. It is a label only.
- Sparkle orders updates by the build number, so it must always increase. A timestamp does: a stable release cut after a beta outranks it, and a newer beta outranks an older one. Second resolution makes a beta and a release build-number collision very unlikely, not impossible. A commit hash has no order, and `GITHUB_RUN_NUMBER` is per workflow, so beta and release runs would collide. Both come from `scripts/ci/compute-versions.sh`; never bump the build number in the repo. Older 12-digit items in the feed still order correctly, because a 14-digit value is always larger.
- A pre-release tag (a version containing `-`, e.g. `v1.2.3-rc1`) is published as a GitHub prerelease and goes to the beta channel in the appcast, never the stable feed. It counts toward the newest-5 beta window of the feed: its GitHub release is never auto-deleted (only beta-build releases, tagged `v<version>-beta.<timestamp>` or the legacy `beta-<timestamp>`, are), but its feed entry ages out once five newer betas exist. `appcast.py add` refuses to replace an item with the same `sparkle:version` but a different download URL, so a build-number collision fails loudly; re-run the job. It does replace an item with the same download URL.

## How betas work
Pull requests only build and run tests (`ci.yml`). They get no signing, no secrets and produce no artifact for the feed. A beta is built after a change is merged.

1. `.github/workflows/beta.yml` (name `Beta`) runs on `workflow_run` of `CI` completed, on `master`. It proceeds only when CI succeeded, the CI run was a `push`, and its head repository is this repository. `workflow_run` always runs the copy of the workflow on the default branch.
2. It builds only the tip of `master`. It checks out the CI-verified commit and requires it to be an ancestor of `origin/master`. If it is no longer the tip, the run skips with a notice: the newer commit gets its own run. This also makes re-running an old run harmless (it cannot stamp old code with a fresh build number).
3. If any of the signing secrets (Developer ID certificate, its password, team id, `SPARKLE_PRIVATE_KEY`) is missing, it skips with a notice and the run stays green. `beta.yml` declares no environment, so these must be repository secrets (see Troubleshooting).
4. Otherwise it builds (`scripts/ci/build-release.sh`, with `APP_VERSION` and `BUILD_NUMBER` from `scripts/ci/compute-versions.sh beta`), signs with `scripts/release/sign-app.sh` (Developer ID Application certificate, hardened runtime, inside-out: Sparkle helpers, framework, widget, app; not notarized), zips with `make-update-zip.sh` (`ditto`) and EdDSA-signs the zip with `SPARKLE_PRIVATE_KEY`.
5. It creates the GitHub release `v<version>-beta.<timestamp>` (for example `v1.2.0-beta.20260920052623`, the same as the app version) as a draft prerelease, publishes it, and only then adds the appcast item (`scripts/release/publish-appcast.sh`, channel `beta`, with a release-notes link), keeping the newest 5 betas. Pruned betas have their releases and tags deleted (`scripts/release/beta-tags-from-urls.sh` picks only beta tags, so a stable or rc tag can never be deleted). The two betas published before this naming change use the legacy `beta-<timestamp>` tags and are pruned by the same logic. The order means the feed never points at an asset that cannot be downloaded. If the appcast step fails, the release stays public but unlisted.
6. Publishing to `gh-pages` is serialised with the `appcast` concurrency group (`cancel-in-progress: false`).

Betas are Developer-ID-signed but not notarized. Sparkle downloads them without the quarantine flag, so Gatekeeper does not check them; users never run an unnotarized DMG. Betas publish automatically; there is no approval step. Users on beta can go back to stable by turning Beta updates off and installing a stable release.

## Security model
Signing keys are only ever used by workflows that run merged code: `beta.yml` on a `master` commit that passed CI, and `release.yml` on a `master` commit with the owner's approval. A pull request can never reach the signing keys, because `ci.yml` is the only workflow that runs on `pull_request` and it has no secrets. What matters now:
- Keep `master` protected (the rulesets "Protect master" and "Protect release tags" are active). Beta builds sign and ship whatever is merged to `master`, so anything that reaches `master` reaches beta users; merges need the review you already require.
- Keep the `release` environment with required reviewers and a deployment policy limited to `master` and `v*` tags (it is configured that way).
- Anyone with write access can publish a release on a `v*` tag. For the stable path the environment approval and the tag ruleset are the real guards. The on-`master` check inside `release.yml` is a safety net, not a security boundary.


## One-time setup (owner)
No SSH or deploy keys are needed: the workflows use `GITHUB_TOKEN` with `contents: write`. The six Apple secrets already exist.

1. **`SPARKLE_PRIVATE_KEY` secret.** The public key (`SUPublicEDKey`) is already in `project.yml`; the matching private key is in the owner's login keychain. Export it and store it as a secret:
   ```bash
   scripts/release/fetch-sparkle-tools.sh /tmp/sparkle-tools
   /tmp/sparkle-tools/bin/generate_keys -x /tmp/sparkle-private.key
   gh secret set SPARKLE_PRIVATE_KEY < /tmp/sparkle-private.key
   rm /tmp/sparkle-private.key
   ```
   Back the key up somewhere safe. If it is lost, installed apps can never verify another update and users must reinstall by hand.
2. **`gh-pages` and Pages.** Enable Settings > Pages > Deploy from a branch > `gh-pages` / root. The first `publish-appcast.sh` run creates the branch if it is missing, but Pages must be enabled for the feed URL to work.
3. **Protect `master` and the release path** (require pull requests and the CI checks; keep the rulesets "Protect master" and "Protect release tags"; keep the `release` environment reviewers and its `master` / `v*` deployment policy).


## Publishing the stable update
With all six Apple secrets and `SPARKLE_PRIVATE_KEY` set, the `Release` workflow also zips the notarized app (`make-update-zip.sh`), EdDSA-signs it and uploads the zip to the release with the DMG. After the upload it adds the item to the appcast (the stable feed; the beta channel for a pre-release tag). Upload first, then appcast, for the same reason as betas. If `SPARKLE_PRIVATE_KEY` is missing while the Apple secrets exist, the workflow fails before building. An unsigned release (no Apple secrets) has no zip and never enters the update feed.

The release workflow is not idempotent after the appcast step fails. Re-running a manual run for an existing tag builds the tag's commit again with a new build number, uploads with `--clobber` (replacing the assets) and replaces the tag's appcast item (`appcast.py add` replaces an item with the same download URL), so no stale item is left behind. A same `sparkle:version` with a different URL is still an error. Recovery:
- If only the appcast step failed, add the item by hand from a checkout of `master`, using the release's zip URL, its length in bytes and the `edSignature` (from the failed job's log, or re-sign the downloaded zip with `sign_update`):
  ```bash
  scripts/release/publish-appcast.sh "https://github.com/<owner>/<repo>.git" -- \
    --title "TimeTug 1.2.3" --version <BUILD_NUMBER> --short 1.2.3 \
    --url "https://github.com/<owner>/<repo>/releases/download/v1.2.3/TimeTug-1.2.3.zip" \
    --length <bytes> --signature <edSignature> --min-system 14.0 \
    --notes-url "https://github.com/<owner>/<repo>/releases/tag/v1.2.3"
  ```
  Add `--channel beta` for a pre-release. `<BUILD_NUMBER>` must be the value stamped into the shipped app (read `CFBundleVersion` from the app inside the uploaded zip), not a new one.
- Otherwise fix the cause and re-run (`workflow_dispatch` with the existing tag). The new run builds new bytes with a new build number, replaces the assets and replaces the tag's appcast item.

## What the workflow does
`scripts/ci/build-release.sh` archives the app in Release into `dist/TimeTug.app` (ad-hoc signed, hardened runtime). Both paths ship a drag-to-install DMG and run `scripts/release/verify-dmg.sh` on it before publishing.

- **Without signing secrets:** `scripts/release/make-dmg.sh` with `DMG_SUFFIX=-unsigned` creates `TimeTug-<version>-unsigned.dmg` plus a `.sha256`, and the release is marked as a PRERELEASE with the note "Unsigned build: macOS will warn on first open; right-click Open", plus a hint to run `xattr -dr com.apple.quarantine /Applications/TimeTug.app` if macOS says the app is damaged.
- **With all signing secrets:** `scripts/release/sign-and-notarize.sh app` signs the app with the Developer ID Application certificate, notarizes it with `notarytool`, staples and checks with `spctl`; `scripts/release/make-dmg.sh` builds `TimeTug-<version>.dmg`; `scripts/release/sign-and-notarize.sh dmg` then codesigns the DMG, notarizes it, staples the ticket, checks with `spctl` and refreshes the `.sha256`; the DMG, its SHA-256 and the Sparkle zip are uploaded to the release. (This signed path has not been exercised without Apple credentials; see ADR 0007 and 0008.)

## DMG packaging
`scripts/release/make-dmg.sh` builds the installer with [dmgbuild](https://github.com/dmgbuild/dmgbuild) (MIT), which writes the Finder layout (`.DS_Store`) directly instead of scripting Finder, so it works headless on CI. The exact version is pinned in `scripts/release/dmg/requirements.txt` (currently `dmgbuild==1.6.7`) and installed into a throwaway virtualenv at `build/dmg-venv`; nothing is installed globally. Layout and window size live in `scripts/release/dmg/settings.py`; the window shows the app icon (170, 200) and an Applications shortcut (490, 200) over the branded background, and the volume icon is the app icon. To bump dmgbuild, change the pin, rebuild and run the verification below.

The background is brand artwork (see `artwork/LICENSE.md`). The committed `scripts/release/dmg/background.png` (660x400) and `background@2x.png` (1320x800) come from `scripts/release/dmg/generate-background.swift`; CI does not render them. To change the design, edit the script, run:
```bash
swift scripts/release/dmg/generate-background.swift
```
look at both PNGs, and commit them together with the script. If you move an icon, update `icon_locations` in `settings.py` and the arrow in the script to match. `make-dmg.sh` merges both images into one hi-dpi TIFF with `tiffutil -cathidpicheck`.

Every CI run also builds an unsigned DMG (job `dmg`) and uploads it as the `TimeTug-dmg` artifact for 14 days.

## Build and verify a DMG locally
```bash
scripts/ci/build-release.sh
VERSION=$(cat dist/version.txt) DMG_SUFFIX=-unsigned scripts/release/make-dmg.sh
scripts/release/verify-dmg.sh dist/TimeTug-*-unsigned.dmg
```
`verify-dmg.sh` mounts the image read-only and checks the app executable, the `Applications` symlink, the hidden background, `.DS_Store`, the volume icon, and the stored icon positions and window size; it prints PASS or FAIL. It checks structure, not looks: open the DMG and follow `docs/manual-tests/macos-checklist.md` for the visual check.

## GitHub Actions secrets to add later
Add these under Settings > Secrets and variables > Actions. Signing and notarizing a release happens only when ALL six are set (the `release` job). Betas are never notarized: they need only `MACOS_CERTIFICATE_P12_BASE64`, `MACOS_CERTIFICATE_PASSWORD`, `APPLE_TEAM_ID` and `SPARKLE_PRIVATE_KEY`, and skip when any of those four is missing.

| Secret | Contents |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Developer ID Application certificate with its private key, exported from Keychain Access as `.p12`, then `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERTIFICATE_PASSWORD` | The password you chose when exporting the `.p12` |
| `APPLE_TEAM_ID` | Your 10-character team id (developer.apple.com > Membership) |
| `NOTARY_API_KEY_ID` | Key ID of an App Store Connect API key (Users and Access > Integrations > App Store Connect API) |
| `NOTARY_API_ISSUER_ID` | The Issuer ID shown on that same page |
| `NOTARY_API_KEY_P8_BASE64` | The downloaded `AuthKey_XXXX.p8`, encoded with `base64 -i AuthKey_XXXX.p8 \| pbcopy` |

`SPARKLE_PRIVATE_KEY` (see "One-time setup") is separate: it is needed to publish updates, not to sign the app.

Create the certificate at developer.apple.com > Certificates > "Developer ID Application" (needs a certificate signing request from Keychain Access).

WARNING: never commit certificates, `.p12`, `.p8`, `.cer` or `.pem` files, or their base64 text. They are git-ignored; keep it that way.

## Test signing locally
```bash
scripts/ci/build-release.sh                      # no secrets needed; produces dist/TimeTug.app
export MACOS_CERTIFICATE_P12_BASE64="$(base64 -i cert.p12)" MACOS_CERTIFICATE_PASSWORD=... \
  APPLE_TEAM_ID=... NOTARY_API_KEY_ID=... NOTARY_API_ISSUER_ID=... \
  NOTARY_API_KEY_P8_BASE64="$(base64 -i AuthKey_XXXX.p8)"
scripts/release/sign-and-notarize.sh app
VERSION=0.1.0 scripts/release/make-dmg.sh
scripts/release/sign-and-notarize.sh dmg         # signs, notarizes and staples dist/TimeTug-0.1.0.dmg
```
Use `TAG=v0.1.0` to set the version for `build-release.sh`; without it the version comes from `Apps/macOS/project.yml` (a `0.0.0-dev` placeholder). The build number (`CFBundleVersion`) is stamped from `BUILD_NUMBER`; CI sets it from `scripts/ci/compute-versions.sh` (a UTC timestamp), never from the run number. Never bump the build number in the repo: the tag is the source of truth for releases.

To smoke-test signing the update payload without secrets: `SIGN_IDENTITY=- scripts/release/sign-app.sh dist/TimeTug.app`.

## Changing the runner label
Workflows use `runs-on: macos-26` (the hosted image with Xcode 26 or newer). If that label is unavailable for your account, edit `runs-on` in the `core`, `app` and `dmg` jobs of `.github/workflows/ci.yml`, in the `release` job of `.github/workflows/release.yml` and in the `beta` job of `.github/workflows/beta.yml` (for example to `macos-latest` once it ships Xcode 26, or a self-hosted label). `scripts/ci/select-xcode.sh` selects the newest Xcode installed on whatever runner is used.

## Who can release
- Releases run in the `release` GitHub environment: the repository owner must approve each run, and only `master` and `v*` tags may deploy.
- `v*` tags are protected by a ruleset; only the repository admin can create, move or delete them.
- The workflow fails unless the release commit is an ancestor of `master`. This is a safety net; see "Security model".
- Betas are the exception: they need no approval, and only run for commits merged to `master` that passed CI.

## Troubleshooting
- **"Check for Updates" finds nothing or errors.** Open `https://darkarena1.github.io/timetug/appcast.xml` in a browser. A 404 means Pages is not enabled or `gh-pages` has no `appcast.xml` yet. To test a different feed locally, `defaults write com.timetug.app SUFeedURL <url>`, and remove it afterwards with `defaults delete com.timetug.app SUFeedURL`.
- **`sign_update` fails or the workflow says it could not read edSignature.** `SPARKLE_PRIVATE_KEY` is missing, empty or not the key from `generate_keys -x`. The secret holds the file contents.
- **The app rejects an update (signature error).** The private key that signed the zip does not match `SUPublicEDKey` in the installed app.
- **A user is not offered a beta.** Beta updates is off (Settings > General); their installed build number is not lower than the beta's; the beta was pruned (only the newest 5 are kept); or the appcast step failed after the release was published (check the `Beta` run).
- **A merge to `master` produced no beta.** Open the `Beta` run. A notice "A newer commit is on master" means a later commit got its own run. A notice "Signing secrets are not set" means one of the four secrets is missing or not visible to the workflow. No `Beta` run at all means CI on that push did not succeed. A `Beta` run can also show as cancelled: GitHub's `appcast` concurrency group keeps only one pending run, so a later CI completion (even a failed CI run) can cancel a queued beta run for an older commit. This is expected with the tip-only rule; the newest green tip still gets its beta.
- **The `Beta` run fails.** Before building: the commit is not on `master`. After building and signing, at "Create and publish the prerelease": `v<version>-beta.<timestamp>` already exists as a release or tag. These fail closed on purpose.
- **To verify on the first real run after merging this pipeline:** that `workflow_run` fires the `Beta` workflow for `CI` runs on `master` pushes, and that the signing secrets are repository-scoped. `beta.yml` declares no environment, so secrets stored only in the `release` environment are not visible to it and it skips with a notice.
- **A stable release fails at the appcast step.** See the recovery steps under "Publishing the stable update".
