# Releasing TimeTug

## Cut a release
1. Make sure `master` is green and `docs/manual-tests/macos-checklist.md` has been run.
2. Tag and push:
   ```bash
   git tag v0.1.0 && git push origin v0.1.0
   ```
   (Or run the "Release" workflow manually from the Actions tab and enter the tag.)
3. The `Release` workflow builds the app and publishes a GitHub Release with generated notes. The version is the tag without the `v`.

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
Use `TAG=v0.1.0` to set the version for `build-release.sh`; without it the version comes from `Apps/macOS/project.yml`.

## Changing the runner label
Workflows use `runs-on: macos-26` (the hosted image with Xcode 26 or newer). If that label is unavailable for your account, edit `runs-on` in the `core`, `app` and `dmg` jobs of `.github/workflows/ci.yml` and in `.github/workflows/release.yml` (for example to `macos-latest` once it ships Xcode 26, or a self-hosted label). `scripts/ci/select-xcode.sh` selects the newest Xcode installed on whatever runner is used.

## Who can release
- Releases run in the `release` GitHub environment: the repository owner must approve each run, and only `master` and `v*` tags may deploy.
- `v*` tags are protected by a ruleset; only the repository admin can create, move or delete them.
- The workflow fails unless the tagged commit is an ancestor of `master`.
