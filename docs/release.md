# Releasing TimeTug

## Cut a release
You write the title and notes in the GitHub UI; the workflow builds, signs, notarizes and attaches the assets. There are two ways to start it. Use a NEW tag that starts with `v`, on `master`.

1. Make sure `master` is green and `docs/manual-tests/macos-checklist.md` has been run.
2. Either:
   - **Draft flow (recommended).** Draft a release (Releases > Draft a new release) with a new tag such as `v1.2.1`, your title and notes, and click **Save draft** (do not publish). A saved draft fires no event, so start the `Release` workflow manually: Actions > Release > Run workflow, input `tag`. It builds the tag's commit (or the selected commit if the tag does not exist yet), uploads the assets to your draft and publishes it, creating the tag at the built commit if needed. The release stays invisible until it is complete.
   - **Publish flow.** Publish the release in the UI. Publishing creates the tag and fires `release: published` (tags that do not start with `v`, such as `beta-*`, are ignored), which starts the workflow; it builds the tag's commit and attaches the assets to the published release. The release is visible without assets for the roughly 30 minutes the build takes. Do not also start a manual run.
3. Either way the workflow first validates the tag (`compute-versions.sh stable`, so `V1.2.3` fails before any build) and runs `scripts/release/release-state.sh`; it then checks out `refs/tags/<tag>` (qualified, so a same-named branch cannot shadow it) for a release event, requires the commit to be on `master`, waits for your approval in the `release` environment, builds, signs and notarizes the app and DMG, and `scripts/release/upload-release-assets.sh` attaches `TimeTug-<version>.dmg`, its `.sha256` and the Sparkle zip. Your title and notes are never overwritten. Only after that does it add the item to the appcast (see "Publishing the stable update"). The version is the tag without the `v`.
4. Do not announce the release until the workflow is green.

Starting both flows for one tag (for example publishing in the UI and also running the workflow) is safe: a per-tag concurrency group (`release-<tag>`) serialises the runs, and the second then either fails fast at the release-state check or re-attaches the assets harmlessly. Recovering a stuck draft is simply re-running the workflow: an asset of the same name left by the earlier attempt is deleted and replaced.

If there is no release at all, a manual run creates it with generated notes and the DMG SHA-256. There is no tag-push trigger: publishing in the UI creates the tag and would fire both.

A tag with a `-` suffix (for example `v1.2.3-rc1`), or a release you marked as a pre-release in the GitHub UI, goes to the `beta` channel of the appcast, not the stable feed (a `-` tag is also marked prerelease on GitHub). If the Apple secrets are missing, the workflow attaches an unsigned DMG, marks the release a prerelease and never adds it to the feed.

**Immutable releases.** GitHub's "immutable releases" repository setting locks a published release's assets and tag. It is currently OFF. If it is ever turned on again, only the draft flow can work: the publish flow would try to upload to a locked release (`HTTP 422: Cannot upload assets to an immutable release`), so the run fails early, before building, with "published and immutable; cannot add assets to an immutable release; use a new version".

**Burned tag `v1.2.0`.** It was published, and locked, while immutable releases were on, with no assets; it cannot be reused. The next version is `v1.2.1` or higher.

## Release rules
These apply whenever a release is prepared, by hand or by Claude. They follow the format of the existing releases.

- **Tag:** `v<version>`, e.g. `v1.3.0`. It must be new, on `master`, and higher than the newest stable tag.
- **Title:** `TimeTug <version>`, e.g. `TimeTug 1.3.0` (the tag without the `v`).
- **Notes:** a list of the changes since the previous stable release, in the format GitHub generates: a `## What's Changed` heading, one `* <PR title> by @<author> in <PR URL>` line per merged PR, then `**Full Changelog**: <compare URL>` from the previous stable tag to the new one. Do not add the DMG SHA-256 line; the workflow adds it.
- **Flow:** the draft flow above. Save the draft with the tag, title and notes, then run the `Release` workflow with the `tag` input.
- **Manual gate:** the only manual step is approving the deployment to the `release` environment. Claude may draft the release and start the run; it never approves.

### Choosing the version
Take the newest stable tag (`v*` with no suffix) as `X.Y.Z`, then:

| Release kind | Rule | Example |
| --- | --- | --- |
| Default | increment Y, set Z to 0 | 1.0.0 -> 1.1.0, 1.3.1 -> 1.4.0 |
| Major (a major shift, or you say "major release") | increment X, set Y and Z to 0 | 1.2.0 -> 2.0.0, 2.0.3 -> 3.0.0 |
| Trivial (you say it is trivial) | increment Z only | 1.2.0 -> 1.2.1 |
| Explicit version | use exactly what you specify; it overrides the rules above | |

Never reuse a burned tag (see below).

## Channels and versioning
Installed apps update through Sparkle from one feed, `https://darkarena1.github.io/timetug/appcast.xml` (`SUFeedURL` in `Apps/macOS/project.yml`). Items in it are either stable or on the `beta` channel; a user sees beta items only after turning on Settings > General > Software Update > Beta updates.

| | Display version (`CFBundleShortVersionString`) | Build number (`CFBundleVersion`) |
| --- | --- | --- |
| Stable | the tag without `v`, e.g. `1.2.3` | UTC timestamp `YYYYMMDDHHMMSS` (14 digits) |
| Beta | `<base>-beta.<timestamp>`, e.g. `1.1.0-beta.20260920050214` | UTC timestamp `YYYYMMDDHHMMSS` (14 digits) |

- `<base>` is the newest stable release tag (`v*` with no suffix, highest by version order), without the `v`. Tags such as `v1.2.0-rc1` and `beta-*` are ignored. With no stable tag yet, it falls back to `CFBundleShortVersionString` in `Apps/macOS/project.yml` (`0.0.0-dev`, so betas are labelled `0.0.0-dev-beta.<timestamp>`). No manual bump is needed; that `project.yml` value is only the local-dev fallback.
- `<timestamp>` is the same 14-digit UTC build number. It is a label only.
- Sparkle orders updates by the build number, so it must always increase. A timestamp does: a stable release cut after a beta outranks it, and a newer beta outranks an older one. Second resolution makes a beta and a release build-number collision very unlikely, not impossible. A commit hash has no order, and `GITHUB_RUN_NUMBER` is per workflow, so beta and release runs would collide. Both come from `scripts/ci/compute-versions.sh`; never bump the build number in the repo. Older 12-digit items in the feed still order correctly, because a 14-digit value is always larger.
- A pre-release tag (a version containing `-`, e.g. `v1.2.3-rc1`) is published as a GitHub prerelease and goes to the beta channel in the appcast, never the stable feed. It counts toward the newest-5 beta window of the feed: its GitHub release is never auto-deleted (only `beta-<build>` releases are), but its feed entry ages out once five newer betas exist. `appcast.py add` refuses to replace an item with the same `sparkle:version` but a different download URL, so a build-number collision fails loudly; re-run the job. It does replace an item with the same download URL.

## How betas work
Pull requests only build and run tests (`ci.yml`). They get no signing, no secrets and produce no artifact for the feed. A beta is built after a change is merged.

1. `.github/workflows/beta.yml` (name `Beta`) runs on `workflow_run` of `CI` completed, on `master`. It proceeds only when CI succeeded, the CI run was a `push`, and its head repository is this repository. `workflow_run` always runs the copy of the workflow on the default branch.
2. It builds only the tip of `master`. It checks out the CI-verified commit and requires it to be an ancestor of `origin/master`. If it is no longer the tip, the run skips with a notice: the newer commit gets its own run. This also makes re-running an old run harmless (it cannot stamp old code with a fresh build number).
3. If any of the signing secrets (Developer ID certificate, its password, team id, `SPARKLE_PRIVATE_KEY`) is missing, it skips with a notice and the run stays green. `beta.yml` declares no environment, so these must be repository secrets (see Troubleshooting).
4. Otherwise it builds (`scripts/ci/build-release.sh`, with `APP_VERSION` and `BUILD_NUMBER` from `scripts/ci/compute-versions.sh beta`), signs with `scripts/release/sign-app.sh` (Developer ID Application certificate, hardened runtime, inside-out: Sparkle helpers, framework, widget, app; not notarized), zips with `make-update-zip.sh` (`ditto`) and EdDSA-signs the zip with `SPARKLE_PRIVATE_KEY`.
5. It creates the GitHub release `beta-<build number>` as a draft prerelease, publishes it, and only then adds the appcast item (`scripts/release/publish-appcast.sh`, channel `beta`, with a release-notes link), keeping the newest 5 betas. Pruned betas have their releases and tags deleted. The order means the feed never points at an asset that cannot be downloaded. If the appcast step fails, the release stays public but unlisted.
6. Beta runs share the `appcast` concurrency group (`cancel-in-progress: false`). The release workflow does not use it (a shared group could cancel a queued release run when betas queue behind it); `publish-appcast.sh` never force-pushes and fetches, rebases and retries a rejected push, which covers the overlap.

Betas are Developer-ID-signed but not notarized. Sparkle downloads them without the quarantine flag, so Gatekeeper does not check them; users never run an unnotarized DMG. Betas publish automatically; there is no approval step. Users on beta can go back to stable by turning Beta updates off and installing a stable release.

## Security model
Signing keys are only ever used by workflows that run merged code: `beta.yml` on a `master` commit that passed CI, and `release.yml` on a `master` commit with the owner's approval. A pull request can never reach the signing keys, because `ci.yml` is the only workflow that runs on `pull_request` and it has no secrets. What matters now:
- Keep `master` protected (the rulesets "Protect master" and "Protect release tags" are active). Beta builds sign and ship whatever is merged to `master`, so anything that reaches `master` reaches beta users; merges need the review you already require.
- Keep the `release` environment with required reviewers and a deployment policy limited to `master` and `v*` tags (it is configured that way).
- Anyone with write access can push a `v*` tag or start the workflow. For the stable path the environment approval and the tag ruleset are the real guards. The on-`master` check inside `release.yml` is a safety net, not a security boundary.


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
With all six Apple secrets and `SPARKLE_PRIVATE_KEY` set, the `Release` workflow also zips the notarized app (`make-update-zip.sh`), EdDSA-signs it and uploads the zip to the release with the DMG. After publishing it adds the item to the appcast (the stable feed; the beta channel for a pre-release tag). Publish first, then appcast, for the same reason as betas. If `SPARKLE_PRIVATE_KEY` is missing while the Apple secrets exist, the workflow fails before building. An unsigned release (no Apple secrets) has no zip and never enters the update feed.

If the run fails before the publish step of the draft flow, the draft is intact and the workflow can simply be re-run. A re-run for an already published (non-immutable) release re-attaches the assets with `--clobber` (new bytes, new build number) and replaces the tag's appcast item (`appcast.py add` replaces an item with the same download URL; a same `sparkle:version` with a different URL is still an error). If immutable releases are on and the release is published, the re-run fails early and a failure at the appcast step is recovered by hand:
- If only the appcast step failed, add the item by hand from a checkout of `master`, using the release's zip URL, its length in bytes and the `edSignature` (from the failed job's log, or re-sign the downloaded zip with `sign_update`). Release notes are rendered HTML embedded in the appcast item, not a link to the GitHub page (see `docs/superpowers/specs/2026-09-22-sparkle-release-notes-design.md`), so render them into a file first:
  ```bash
  gh api "repos/<owner>/<repo>/releases/tags/v1.2.3" --jq .body \
    | jq -Rs '{text: ., mode: "gfm", context: "<owner>/<repo>"}' \
    | gh api /markdown --input - \
    | python3 scripts/release/wrap-notes-html.py > /tmp/notes.html
  scripts/release/publish-appcast.sh "https://github.com/<owner>/<repo>.git" -- \
    --title "TimeTug 1.2.3" --version <BUILD_NUMBER> --short 1.2.3 \
    --url "https://github.com/<owner>/<repo>/releases/download/v1.2.3/TimeTug-1.2.3.zip" \
    --length <bytes> --signature <edSignature> --min-system 14.0 \
    --notes-html-file /tmp/notes.html
  ```
  Add `--channel beta` for a pre-release. `<BUILD_NUMBER>` must be the value stamped into the shipped app (read `CFBundleVersion` from the app inside the uploaded zip), not a new one.
- Otherwise fix the cause and re-run (`workflow_dispatch` with the existing tag) while immutable releases are off; if they are on, the release cannot be fixed in place: cut a new version.

## What the workflow does
`scripts/ci/build-release.sh` archives the app in Release into `dist/TimeTug.app` (ad-hoc signed, hardened runtime). Both paths ship a drag-to-install DMG and run `scripts/release/verify-dmg.sh` on it before publishing.

- **Without signing secrets:** `scripts/release/make-dmg.sh` with `DMG_SUFFIX=-unsigned` creates `TimeTug-<version>-unsigned.dmg` plus a `.sha256`, and the release is marked as a PRERELEASE with the note "Unsigned build: macOS will warn on first open; right-click Open", plus a hint to run `xattr -dr com.apple.quarantine /Applications/TimeTug.app` if macOS says the app is damaged.
- **With all signing secrets:** `scripts/release/sign-and-notarize.sh app` signs the app with the Developer ID Application certificate, notarizes it with `notarytool`, staples and checks with `spctl`; `scripts/release/make-dmg.sh` builds `TimeTug-<version>.dmg`; `scripts/release/sign-and-notarize.sh dmg` then codesigns the DMG, notarizes it, staples the ticket, checks with `spctl` and refreshes the `.sha256`; the DMG, its SHA-256 and the Sparkle zip are uploaded to the draft release, which is then published. (This signed path has not been exercised without Apple credentials; see ADR 0007 and 0008.)

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

Two optional secrets, `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET`, hold the Google "Desktop app" OAuth client that `beta.yml` and `release.yml` bake into the app (only their `Build Release app` step reads them; `ci.yml` never does). Without them the build still succeeds but Google is not offered in Settings > Accounts. Set both or neither: one alone fails the build. Google treats a Desktop-app client secret as non-confidential because it ships inside the app, but keep both values out of git and out of logs.

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

To smoke-test signing the update payload with an ad-hoc identity and no certificate, run `SIGN_IDENTITY=- scripts/release/sign-app.sh dist/TimeTug.app`.

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
- **The `Beta` run fails.** Before building: the commit is not on `master`. After building and signing, at "Create and publish the prerelease": `beta-<build number>` already exists as a release or tag. These fail closed on purpose.
- **To verify on the first real run after merging this pipeline:** that `workflow_run` fires the `Beta` workflow for `CI` runs on `master` pushes, and that the signing secrets are repository-scoped. `beta.yml` declares no environment, so secrets stored only in the `release` environment are not visible to it and it skips with a notice.
- **The Release run fails early with "published and immutable; cannot add assets to an immutable release".** That tag is published and GitHub immutable releases are on, so its assets are locked and the tag cannot be reused. Draft a new release for a higher version and start the workflow manually with that tag. `scripts/release/release-state.sh <tag>` prints `none`, `draft`, `published` or `published-immutable`.
- **Publishing a release did not start the workflow.** Only `v*` tags start it, and a saved draft never does: use the manual run.
- **A stable release fails at the appcast step.** See the recovery steps under "Publishing the stable update".
