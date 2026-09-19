# ADR 0007: CI and Release Automation

**Status:** Accepted

## Context

TimeTug is going public on GitHub. It needs CI on every change and a repeatable release path. The app uses macOS 26 SDK APIs behind `#available`, so builds need a recent Xcode. There is no Apple Developer account configured yet, so signed and notarized releases cannot be produced today.

## Decision

- **GitHub Actions**, with `contents: read` for CI and `contents: write` only for the release workflow. Third-party actions are limited to `actions/checkout`, `cache` and `upload-artifact`; releases use the preinstalled `gh` CLI.
- **macOS runner with the macOS 26 SDK** (`macos-26`); `scripts/ci/select-xcode.sh` picks the newest installed Xcode. The label is documented as changeable in `docs/release.md`.
- **Core-on-Linux job** (`core-linux`, `continue-on-error`) checks the portability goal. It is allowed to fail until Linux support is confirmed.
- **Signed versus unsigned switch by secrets:** the release workflow computes `has_signing` from six secrets. With all set it signs (Developer ID, hardened runtime), notarizes, staples and ships a DMG. Without them it ships an ad-hoc signed zip as a prerelease.
- **Scripts kept out of YAML:** logic lives in `scripts/ci/` and `scripts/release/`, takes inputs from environment variables and can be run locally.

## Consequences

- Every PR runs the Core and app test suites; failures upload an `.xcresult`.
- Publishing a release is `git tag vX.Y.Z && git push origin vX.Y.Z`; adding the secrets later upgrades releases to signed ones with no workflow change.
- The signing and notarization path cannot be exercised without Apple credentials, so its first real run may need fixes.
- CI depends on the hosted runner image shipping Xcode 26 or newer.
