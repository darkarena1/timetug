# ADR 0008: DMG packaging with dmgbuild

**Status:** Accepted

## Context

Releases shipped an unsigned zip, or a plain `hdiutil` DMG with no layout. Users should see the app icon and an Applications shortcut side by side with a clear "drag to install" cue. The Finder window layout lives in a `.DS_Store` file. Scripting Finder with AppleScript needs a GUI session and is flaky on CI runners.

## Decision

- **dmgbuild** (Python, MIT) writes the `.DS_Store`, the volume icon and the background directly, so it runs headless on GitHub runners and locally without Finder. It is pinned exactly (`scripts/release/dmg/requirements.txt`) and installed into a throwaway virtualenv (`build/dmg-venv`) by `make-dmg.sh`. Alternatives rejected: AppleScript Finder scripting (needs a GUI session, timing-sensitive) and `create-dmg` (a shell wrapper around that same scripting).
- **Layout in code:** `scripts/release/dmg/settings.py` sets a 660x400 window, 128 px icons at (170, 200) and (490, 200), no toolbar, status bar or sidebar, and the app icon as the volume icon.
- **Hi-dpi background:** `generate-background.swift` renders a 1x and a 2x PNG, which are committed (CI renders nothing); `make-dmg.sh` merges them into one TIFF with `tiffutil -cathidpicheck` so Retina displays stay sharp. The art is brand artwork under `artwork/LICENSE.md`.
- **Verification script:** `scripts/release/verify-dmg.sh` mounts the DMG read-only and checks the app, the `/Applications` symlink, background, volume icon and `.DS_Store`, and reads the stored icon positions and window size back with `ds_store`. It runs in the `dmg` CI job and in the release workflow before publishing.
- **Signed versus unsigned:** both paths ship a DMG. Unsigned: `TimeTug-<version>-unsigned.dmg` as a prerelease. Signed: the app is signed, notarized and stapled, then the DMG is built and itself codesigned, notarized and stapled (`sign-and-notarize.sh app|dmg`). The zip is removed.

## Consequences

- Every CI run produces a downloadable installer (`TimeTug-dmg` artifact, 14 days).
- One extra dependency (dmgbuild and its `ds_store` and `mac_alias` dependencies), installed only in the venv and bumped deliberately.
- The verification script proves structure, not looks; the visual check stays in `docs/manual-tests/macos-checklist.md`.
- Signing and notarizing the DMG could not be tested without Apple credentials; its first real run may need fixes.
- Changing the icon positions means editing `settings.py` and the arrow in the generator together.
