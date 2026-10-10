# TimeTug for Windows: program tracker

This is the saved progress for the Windows program. It is updated at the end of every working session and committed with that session's work, so any later session (or agent) can resume from it.

**Spec:** [`docs/superpowers/specs/2026-10-09-windows-program-design.md`](../specs/2026-10-09-windows-program-design.md) (approved 2026-10-09).

## How to resume

1. Read the spec once, then this file.
2. Go to **Now**. The first unchecked item is the next thing to do. Items marked **(owner)** are for the owner; agents never do them (publishing releases, approving deployments, merging, console changes in Google, Microsoft, Apple or GitHub settings, entering credentials).
3. Before starting a phase, check that its spec and plan exist (links in the phase table). A phase without a plan gets one first: a short phase spec (brainstorming), then a plan (writing-plans), both linked here.
4. When you finish an item: check it, add a line to the **Session log**, and commit this file with the work.
5. When a phase's last item is done, set its status to `done` and add its PR links.

Status values: `not started`, `planning`, `in progress`, `blocked` (say on what), `done`.

## Phases

| Phase | Status | Spec | Plan | PRs |
|---|---|---|---|---|
| S Spike: Swift on Windows | done; approach A confirmed 2026-10-09 | spec section 9 | [plan](2026-10-09-windows-spike-s.md) | [findings](../../spikes/2026-10-09-swift-on-windows.md) |
| A Secrets into environments (standalone, Mac repo) | planning (plan written, awaiting owner review) | spec section 8 | [plan](2026-10-09-phase-a-secrets-into-environments.md) | |
| 1.5 Domain and branding | not started | spec section 1.5 | to write (site changes only) | |
| 0 Organization move and hardening | not started | spec sections 1 and 8 | to write | |
| 1 `calendar-connectors` repository | not started | spec section 1 | to write | |
| 2 `timetug-shared` repository | not started | spec section 1 | to write | |
| 3 Engine | not started | spec section 2 | to write | |
| 4 C interface and NuGet | not started | spec section 2 | to write | |
| 5 Windows app core | not started | spec sections 3 and 4 | to write | |
| 6 WAM sign-in | not started | spec section 4.5 | to write | |
| 7 Widgets | not started | spec section 4 | to write | |
| 8 On-device AI | not started | spec section 5 | to write | |
| 9 Store 1.0 | not started | spec section 6 | to write | |
| Deferred: signed website download | not started | spec section 6 | trigger not met | |

Order: S first. A and 1.5 can run alongside S. Phase 0 needs the 1.5 domain live. Phases 1 to 5 are sequential; 6, 7 and 8 follow 5 in any order; 9 needs 5, 6 and 7.

## Now

- [x] **(owner)** Confirm the Sparkle key in the login keychain is the one the app trusts. Confirmed 2026-10-09: `generate_keys -p` prints the key in `SUPublicEDKey`.
- [x] **(owner)** Export a backup of the Sparkle private key into the password manager. Done 2026-10-09 (1Password); the exported file must be deleted from the Mac.
- [x] **(owner)** Prepare the Windows VM for Spike S (plan Task 1). Done 2026-10-09: the agent installed the tools itself through `prlctl exec`.
- [x] Spike S, plan Tasks 2 to 5. Done 2026-10-09; findings in `docs/spikes/2026-10-09-swift-on-windows.md`.
- [x] **(owner)** Review the Spike S findings and decide on approach A. Decided: approach A, 2026-10-09.
- [x] Apply the spike's six recommendations to the spec. Done in the approach A decision PR.
- [x] Write the plan for phase A. Written 2026-10-09.
- [ ] **(owner)** Review the phase A plan; then choose Native or Subagent-driven for the code tasks (1 to 3). Tasks 4 and 5 are yours.

## Owner checklist by phase

Agents keep this list current; the owner checks items off (or tells an agent to).

### A Secrets into environments
- [ ] Locate or recreate each value (see **Where each secret comes from** at the end of this file).
- [ ] Create the `beta` environment (deployment branch `master` only, no reviewer) and enter the beta signing values there.
- [ ] Enter the release values into `release`; turn off admin bypass on `release` (not needed on `appstore`, which has no reviewer). Details: phase A plan, Task 4.
- [ ] After one beta and one release run green from environments, delete the repository-level copies.

### 1.5 Domain and branding
- [ ] Confirm ownership of `binarycompanions.com` and DNS access.
- [ ] Verify `binarycompanions.com` in Google Search Console as an owner of the OAuth project.
- [ ] Create the Binary Companion Microsoft partner (Partner Center) company account; get a D-U-N-S number if Binary Companion has none.
- [ ] Microsoft Entra: update homepage, terms and privacy URLs (after the new site is live).
- [ ] Microsoft Entra: verify the publisher domain, then re-run publisher verification with the Binary Companion partner ID.
- [ ] Google: one bundled brand edit and submit for verification; remove `obryan.cloud` from Authorized domains after approval.
- [ ] App Store Connect: update the privacy, support and marketing URLs.

### 0 Organization move
- [ ] Publish the Mac release that carries the new feed URL; wait for users to take it (watch the appcast download counts).
- [ ] Enable 2FA requirement and the organization settings in spec section 8.
- [ ] Docker Hub (after the transfer): `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` were set as repository secrets on `darkarena1/timetug` on 2026-10-09; the token is a read-only token from the Binary Companion Docker Hub account (PR 71's `core-linux` job reads them). Once `binary-companion` exists, set the same two values as organization secrets limited to the repositories that run Linux CI (`timetug` first), then delete the repository-level copies.
- [ ] Transfer `timetug` and `homebrew-tap` to `binary-companion` (repository Settings > Transfer).
- [ ] Create the `timetug-bot` GitHub App and install it on the dependent repositories.
- [ ] Run the audit script with an `admin:org` token; it must pass.

### Later phases
- Phase 4: create the Binary Companion nuget.org account and configure trusted publishing for `TimeTug.Engine`.
- Phase 6: add the WAM broker redirect URI to the Entra app registration.
- Phase 8: choose the real-hardware check (spec section 5, layer 3).
- Phase 9: Store listing, IARC rating, screenshots; create the tester flight group.

## Waiting on

| Item | Since | Unblocks |
|---|---|---|
| | | |

## Open questions

- None yet.

## Session log

Append one line per session: date, what was done, what is next.

- 2026-10-09: Program spec written, reviewed (DeepSeek: 14 findings, all real, fixed) and approved. Read-only security audit of `darkarena1/timetug` and `binary-companion` (findings in spec section 8). Sparkle key found in the login keychain (item created 2026-09-20); public-key match not yet confirmed. Next: owner prepares the VM, then Spike S.
- 2026-10-09: Checked master's #69 (App Store manual runs accept only `master` or a `vX.Y.Z` tag). It matches the spec; the Windows stable workflow copies the rule. `appstore` has no required reviewer; the owner accepted that (can be added later), recorded in spec section 8.
- 2026-10-09 (later): Spike S done. All three packages pass on Windows 11 ARM64 (98, 299, 13 tests; 0 failures); the Swift DLL exports the four C functions and a .NET 10 host calls them with an off-thread callback; runtime 57.4 MB minimal (ICU is 36 MB); Foundation probe all PASS. Merged PR 71 (Docker Hub login for `core-linux`); amended the secrets rule for read-only CI tokens. Next: owner decides on approach A, then phase A (secrets into environments) and 1.5 can start.
- 2026-10-09 (later still): Owner chose approach A. Spec updated with the six Spike S recommendations (`.gitattributes`, `--show-bin-path`, parsed-JSON fixtures, proxy note, runtime size and x64 risks). Sparkle public key confirmed by the owner. Next: phase A plan, then phase 1.5.

## Where each secret comes from

GitHub never shows a secret's value again, so each value is re-entered from its source with `gh secret set NAME --env <environment> < file` in the owner's own terminal (or the GitHub UI). Values never go into chat or files in the repository. Keep the repository-level copy until the environment copy has signed a beta and a release.

| Secret | Source | If it cannot be found |
|---|---|---|
| `SPARKLE_PRIVATE_KEY` | Login keychain item (service `https://sparkle-project.org`, account `ed25519`, created 2026-09-20); export with Sparkle's `generate_keys -x <file>` | Must not be recreated: installed apps trust only this key's public half (`SUPublicEDKey` in `Apps/macOS/project.yml`). Recover the GitHub copy with a one-time, `release`-gated workflow that encrypts it to an `age` public key the owner holds and uploads only the ciphertext |
| `MACOS_CERTIFICATE_P12_BASE64`, `MACOS_CERTIFICATE_PASSWORD` | Developer ID Application certificate, exported from Keychain Access as `.p12` | Issue a new Developer ID certificate in the Apple developer portal (same Team ID, so updates and the keychain group keep working) |
| `MACOS_PROVISIONING_PROFILE_BASE64` | Developer ID provisioning profile from the developer portal | Download again (regenerate it if the certificate changed) |
| `NOTARY_API_KEY_P8_BASE64`, `NOTARY_API_KEY_ID`, `NOTARY_API_ISSUER_ID` | App Store Connect API key (the `.p8` downloads once) | Revoke and create a new key |
| `APPLE_TEAM_ID` | Developer portal, Membership | Look it up (not sensitive) |
| `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET` | `~/.config/timetug/google-oauth.xcconfig` and the Google Cloud console | Add a new client secret in the console; signed-in users are unaffected |
| `MICROSOFT_OAUTH_CLIENT_ID` | `~/.config/timetug/microsoft-oauth.xcconfig` and the Entra app registration | Read it from the registration |
| `FIREBASE_SERVICE_ACCOUNT_TIMETUG` | Google Cloud service-account key for Firebase Hosting deploys | Create a new key for the same service account, then delete the old one |
| `appstore` environment values | Already in the `appstore` environment | Nothing to move |
