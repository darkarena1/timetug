# ADR 0011: Sparkle Updates and a Beta Channel

**Status:** Accepted

## Context

Direct-download users need in-app updates, and pull requests should be testable as betas by people who opt in. Stable releases are Developer-ID-signed and notarized (ADR 0007, 0008). The repository is on GitHub with no server of our own.

## Decision

Use [Sparkle 2](https://sparkle-project.org) for updates, one appcast with a `beta` channel, and an automatic two-workflow pipeline for betas.

- **Pin:** Sparkle `exactVersion: 2.10.0` in `Apps/macOS/project.yml`, the same version as `scripts/release/sparkle-version.txt`, which also holds the SHA-256 of the release tarball used for the command-line tools (`sign_update`, `generate_keys`). Bump both together.
- **Feed:** one `appcast.xml` on the `gh-pages` branch, served by GitHub Pages at `https://darkarena1.github.io/timetug/appcast.xml`. Beta items carry `<sparkle:channel>beta</sparkle:channel>`; the app allows that channel only when the user turns on Beta updates. The choice lives in the app's UserDefaults (`updates.includeBetas.v1`). `SUFeedURL` and `SUPublicEDKey` are in `project.yml` `info.properties`. The EdDSA private key is the `SPARKLE_PRIVATE_KEY` Actions secret; a copy is in the owner's keychain.
- **Build number:** `CFBundleVersion` is a UTC timestamp `YYYYMMDDHHMM` from `scripts/ci/compute-versions.sh`. Sparkle orders by it, so it must only increase across betas and stable releases. Run numbers fail because they are per workflow (`Beta build` and `Release` would collide), and commit hashes have no order. Display versions are labels: `<base>-beta.<PR>.<run>` for betas.
- **Betas are Developer-ID-signed, not notarized.** Sparkle downloads and installs the update without the quarantine attribute, so Gatekeeper does not assess it. This avoids a notarization round trip per pull request. Stable releases stay notarized.
- **Two workflows, because PR code must not run with keys.** `beta-build.yml` builds a same-repo PR with no secrets and uploads the app as an artifact. `beta-publish.yml` runs from the default branch on `workflow_run`, treats the artifact as untrusted (tar validated with `scripts/ci/validate-tar.py`, extracted outside the workspace and re-checked), computes and stamps the version and build number itself, waits for `CI` to be green on the PR head, then signs, EdDSA-signs and publishes. The GitHub release is published before the appcast is updated, so the feed never lists an asset that cannot be downloaded. Fork PRs never build a beta. Publishing is serialised with a concurrency group and the newest 5 betas are kept.
- **Accepted risk:** betas publish with no approval step. Anyone who can push a same-repo branch can cause a Developer-ID-signed beta of their own build to ship to opted-in users. Protect `master` and restrict who can push branches. The stable job keeps its `release` environment approval.
- **Rejected:** partial (delta or non-bundle) updates, because whole-bundle zips are small enough and much simpler. Per-PR opt-in labels, because they add ceremony and the risk model is the same. Sparkle's `generate_appcast`, because it wants a local folder of archives and rewrites the whole feed; `scripts/release/appcast.py` edits one item at a time under a concurrency group, and is easy to test.

## Consequences

- The private key is a single point of failure. If it is lost, installed apps cannot verify further updates and users must reinstall manually. Back it up.
- Sparkle adds a framework and XPC helpers to the app bundle; `scripts/release/sign-app.sh` and `sign-and-notarize.sh` sign them inside-out.
- The update path needs a first real pull request run to confirm two workflow facts (the `CI` run's `head_sha` and `workflow_run.pull_requests`); the pipeline fails closed if they do not hold.
- A stable release that fails at the appcast step leaves a public release that is not in the feed; recovery is manual (`docs/release.md`).
- The update UI and Sparkle itself are covered by the manual checklist, not unit tests.
