# Releasing TimeTug

## Cut a release
1. Make sure `master` is green and `docs/manual-tests/macos-checklist.md` has been run.
2. Tag and push:
   ```bash
   git tag v0.1.0 && git push origin v0.1.0
   ```
   (Or run the "Release" workflow manually from the Actions tab and enter the tag.)
3. The `Release` workflow builds the app and publishes a GitHub Release with generated notes. The version is the tag without the `v`. A signed release also updates the appcast (see "Publishing the stable update").

## Channels and versioning
Installed apps update through Sparkle from one feed, `https://darkarena1.github.io/timetug/appcast.xml` (`SUFeedURL` in `Apps/macOS/project.yml`). Items in it are either stable or on the `beta` channel; a user sees beta items only after turning on Settings > General > Software Update > Beta updates.

| | Display version (`CFBundleShortVersionString`) | Build number (`CFBundleVersion`) |
| --- | --- | --- |
| Stable | the tag without `v`, e.g. `1.2.3` | UTC timestamp `YYYYMMDDHHMM` |
| Beta | `<base>-beta.<PR>.<run>`, e.g. `1.3.0-beta.42.7` | UTC timestamp `YYYYMMDDHHMM` |

- `<base>` is `CFBundleShortVersionString` in `Apps/macOS/project.yml`. Bump it by hand at the start of each release cycle. It is `0.0.0-dev` today, so bump it before the first real beta, or betas are labelled `0.0.0-dev-beta.N.M`.
- `<PR>` is the pull request number and `<run>` the `Beta build` workflow run number. They are labels only.
- Sparkle orders updates by the build number, so it must always increase. A timestamp does: a stable release cut after a beta outranks it, and a newer beta outranks an older one. A commit hash has no order, and `GITHUB_RUN_NUMBER` is per workflow, so beta and release runs would collide. Both come from `scripts/ci/compute-versions.sh`; never bump the build number in the repo.
- A pre-release tag (a version containing `-`, e.g. `v1.2.3-rc1`) is published as a GitHub prerelease and goes to the beta channel in the appcast, never the stable feed.

## How betas work
1. A pull request from a branch in this repository triggers `.github/workflows/beta-build.yml`. It has no secrets and only `contents: read`, because the code it builds is the pull request's own. It builds the app and uploads `TimeTug.tar` (retained 3 days). Fork pull requests never build a beta.
2. When that run completes successfully, `.github/workflows/beta-publish.yml` starts. It runs from the default branch, so it only ever uses trusted scripts. A `gate` job waits (up to 45 minutes) until the newest `CI` run for the PR head commit succeeds (`scripts/ci/wait-for-ci.sh`); a failed or missing CI blocks the beta.
3. The `publish` job downloads the tar as untrusted input. `scripts/ci/unpack-untrusted-app.sh` validates the tar with `scripts/ci/validate-tar.py` (only files, directories and in-bundle symlinks under `TimeTug.app/`), extracts it outside the workspace and re-checks the extracted tree. The version and build number are computed by `compute-versions.sh` from the workflow run's PR and run numbers and stamped into the app and widget `Info.plist` files by the publish job; nothing but the app bytes is taken from the artifact.
4. `scripts/release/sign-app.sh` signs the app with the Developer ID Application certificate and hardened runtime, inside-out (Sparkle helpers, framework, widget, app). It does not notarize. `make-update-zip.sh` zips it with `ditto` and the zip is EdDSA-signed with `SPARKLE_PRIVATE_KEY`.
5. The GitHub release `beta-<build number>` is created as a draft prerelease, then published, and only then is the appcast updated (`scripts/release/publish-appcast.sh`, channel `beta`, keeping the newest 5 betas). Pruned betas have their releases and tags deleted. The order means the feed never points at an asset that cannot be downloaded. If the appcast step fails, the release stays public but unlisted.
6. Publishing to `gh-pages` is serialised with the `appcast` concurrency group.

Betas are Developer-ID-signed but not notarized. Sparkle downloads them without the quarantine flag, so Gatekeeper does not check them; users never run an unnotarized DMG.

Betas publish automatically: there is no approval step (the stable `release` job keeps its `release` environment). The accepted risk is that anyone who can push a branch to this repository and open a pull request can cause a Developer-ID-signed beta of their own build to ship to every user who enabled beta updates. So protect `master` and limit who can push branches. Users on beta can go back to stable by turning Beta updates off and installing a stable release.

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
3. **Protect `master`** (require pull requests and the CI checks) and restrict who can push branches.

## Publishing the stable update
With all six Apple secrets and `SPARKLE_PRIVATE_KEY` set, the `Release` workflow also zips the notarized app (`make-update-zip.sh`), EdDSA-signs it and attaches the zip to the release. After the release is created it adds the item to the appcast (the stable feed; the beta channel for a pre-release tag). Release first, then appcast, for the same reason as betas. An unsigned release (no Apple secrets) has no zip and never enters the update feed.

Re-running a failed release after the GitHub release exists fails at `gh release create`. That is deliberate: a re-run would rebuild different bytes than the ones published. Recovery:
- If only the appcast step failed, add the item by hand from a checkout of `master`, using the release's zip URL, its length in bytes and the `edSignature` (from the failed job's log, or re-sign the downloaded zip with `sign_update`):
  ```bash
  scripts/release/publish-appcast.sh "https://github.com/<owner>/<repo>.git" -- \
    --title "TimeTug 1.2.3" --version <BUILD_NUMBER> --short 1.2.3 \
    --url "https://github.com/<owner>/<repo>/releases/download/v1.2.3/TimeTug-1.2.3.zip" \
    --length <bytes> --signature <edSignature> --min-system 14.0
  ```
  Add `--channel beta` for a pre-release. `<BUILD_NUMBER>` must be the value stamped into the shipped app (the release job logs it), not a new one.
- Otherwise delete the GitHub release and the tag, and re-run.

## What the workflow does
`scripts/ci/build-release.sh` archives the app in Release into `dist/TimeTug.app` (ad-hoc signed, hardened runtime). Both paths ship a drag-to-install DMG and run `scripts/release/verify-dmg.sh` on it before publishing.

- **Without signing secrets:** `scripts/release/make-dmg.sh` with `DMG_SUFFIX=-unsigned` creates `TimeTug-<version>-unsigned.dmg` plus a `.sha256`, and the release is marked as a PRERELEASE with the note "Unsigned build: macOS will warn on first open; right-click Open", plus a hint to run `xattr -dr com.apple.quarantine /Applications/TimeTug.app` if macOS says the app is damaged.
- **With all signing secrets:** `scripts/release/sign-and-notarize.sh app` signs the app with the Developer ID Application certificate, notarizes it with `notarytool`, staples and checks with `spctl`; `scripts/release/make-dmg.sh` builds `TimeTug-<version>.dmg`; `scripts/release/sign-and-notarize.sh dmg` then codesigns the DMG, notarizes it, staples the ticket, checks with `spctl` and refreshes the `.sha256`; a normal release is published with the DMG and its SHA-256. (This signed path has not been exercised without Apple credentials; see ADR 0007 and 0008.)

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
Add these under Settings > Secrets and variables > Actions. Signing happens only when ALL six are set.

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
Workflows use `runs-on: macos-26` (the hosted image with Xcode 26 or newer). If that label is unavailable for your account, edit `runs-on` in the `core`, `app` and `dmg` jobs of `.github/workflows/ci.yml` and in `.github/workflows/release.yml` (for example to `macos-latest` once it ships Xcode 26, or a self-hosted label). `scripts/ci/select-xcode.sh` selects the newest Xcode installed on whatever runner is used.

## Who can release
- Releases run in the `release` GitHub environment: the repository owner must approve each run, and only `master` and `v*` tags may deploy.
- `v*` tags are protected by a ruleset; only the repository admin can create, move or delete them.
- The workflow fails unless the tagged commit is an ancestor of `master`.
- Betas are the exception: they need no approval (see "How betas work" for the accepted risk).

## Troubleshooting
- **"Check for Updates" finds nothing or errors.** Open `https://darkarena1.github.io/timetug/appcast.xml` in a browser. A 404 means Pages is not enabled or `gh-pages` has no `appcast.xml` yet. To test a different feed locally, `defaults write com.timetug.app SUFeedURL <url>`, and remove it afterwards with `defaults delete com.timetug.app SUFeedURL`.
- **`sign_update` fails or the workflow says it could not read edSignature.** `SPARKLE_PRIVATE_KEY` is missing, empty or not the key from `generate_keys -x`. The secret holds the file contents.
- **The app rejects an update (signature error).** The private key that signed the zip does not match `SUPublicEDKey` in the installed app.
- **A user is not offered a beta.** Beta updates is off (Settings > General); their installed build number is not lower than the beta's; the beta was pruned (only the newest 5 are kept); or the appcast step failed after the release was published (check the `Beta publish` run).
- **Beta publish fails with a clear error before signing.** Either the workflow run has no numeric PR number, the tar failed validation, or `beta-<build number>` already exists. These fail closed on purpose.
- **To verify on the first real pull request run:** that the `CI` workflow run's `head_sha` matches the PR head commit (`wait-for-ci.sh` looks runs up by it), and that `workflow_run.pull_requests[0]` is populated for same-repo PRs. If it is not, publish stops with "no numeric PR number".
