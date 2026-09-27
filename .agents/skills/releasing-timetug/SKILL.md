---
name: releasing-timetug
description: Use when preparing, cutting or troubleshooting a TimeTug release or beta, choosing its version or writing its notes, or changing release.yml, beta.yml, Sparkle, the appcast, the DMG, or the scripts in scripts/release and scripts/ci that build and sign them.
---

# Releasing TimeTug

`docs/release.md` is the source of truth. Read the section for your task before acting:

| Task | Section of `docs/release.md` |
| --- | --- |
| Cut a stable release | "Cut a release", then "Release rules" and "Choosing the version" |
| Why a beta did or did not ship | "How betas work", "Troubleshooting" |
| Version and build numbers | "Channels and versioning" |
| Signing, notarization, secrets | "Security model", "One-time setup (owner)", "GitHub Actions secrets to add later" |
| DMG layout or background | "DMG packaging", "Build and verify a DMG locally" |
| Runner label or Xcode version | "Changing the runner label" (`scripts/ci/select-xcode.sh`) |

Rationale: ADR 0007, 0008 and 0011 in `docs/decisions/`.

## Rules that are easy to get wrong

- Releases use the draft flow: save a draft with a new `v*` tag on `master`, title and notes, then run the `Release` workflow with the `tag` input. There is no tag-push trigger. Only the owner approves the `release` environment; never approve it yourself.
- Tag `v1.2.0` is burned. Use `v1.2.1` or higher, and never reuse a tag.
- A tag with a `-` (for example `v1.3.0-rc1`), or a release marked prerelease, goes to the beta channel. An unsigned build never enters the feed.
- `CFBundleVersion` is a 14-digit UTC timestamp (`YYYYMMDDHHMMSS`) from `scripts/ci/compute-versions.sh`. Never use a commit hash or `GITHUB_RUN_NUMBER`, and never bump the build number in the repo. Beta display versions are `<newest stable tag>-beta.<build>`, so no version bump is needed; the `project.yml` value is only a fallback.
- Sparkle is pinned with `exactVersion` in `Apps/macOS/project.yml` and in `scripts/release/sparkle-version.txt`; change both together. `SUFeedURL` and `SUPublicEDKey` live in `project.yml` `info.properties`. The private key exists only as the `SPARKLE_PRIVATE_KEY` secret.
- Secrets reach only the build steps of `beta.yml` and `release.yml`, never `ci.yml`. Pull requests get no signing and no secrets, and nothing they build can enter the update feed. Keep it that way, and keep `master` protected, because betas publish merged code without approval.
- The DMG background PNGs are committed. After editing `scripts/release/dmg/generate-background.swift`, re-run it and commit the PNGs with it. Keep `icon_locations` in `scripts/release/dmg/settings.py` in line with the arrow.
- Script tests live in `scripts/<dir>/tests`; `scripts/dev/affected-tests.sh` finds the ones a change needs.
