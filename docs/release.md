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
`scripts/ci/build-release.sh` archives the app in Release into `dist/TimeTug.app` (ad-hoc signed, hardened runtime).

- **Without signing secrets:** `scripts/release/make-zip.sh` creates `TimeTug-<version>-unsigned.zip` plus a `.sha256`, and the release is marked as a PRERELEASE with the note "Unsigned build: macOS will warn on first open; right-click Open". 
- **With all signing secrets:** `scripts/release/sign-and-notarize.sh` signs with the Developer ID Application certificate, notarizes with `notarytool`, staples and checks with `spctl`; `scripts/release/make-dmg.sh` builds `TimeTug-<version>.dmg` (with an /Applications symlink); a normal release is published with the DMG and its SHA-256.

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
scripts/release/sign-and-notarize.sh
VERSION=0.1.0 scripts/release/make-dmg.sh
```
Use `TAG=v0.1.0` to set the version for `build-release.sh`; without it the version comes from `Apps/macOS/project.yml`.

## Changing the runner label
Workflows use `runs-on: macos-26` (the hosted image with Xcode 26 or newer). If that label is unavailable for your account, edit `runs-on` in the `core` and `app` jobs of `.github/workflows/ci.yml` and in `.github/workflows/release.yml` (for example to `macos-latest` once it ships Xcode 26, or a self-hosted label). `scripts/ci/select-xcode.sh` selects the newest Xcode installed on whatever runner is used.
