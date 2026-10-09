# TimeTug for Windows: program design

Status: design approved in brainstorming (2026-10-09). This is a program-level design: it fixes the architecture, the repository split, the Windows capability gaps, distribution and the phase order. Each phase gets its own spec and implementation plan before any code is written. This file lives in the Mac repo until `timetug-shared` exists, then moves there because it spans repositories.

## Purpose

Ship a native Windows version of TimeTug with the same behaviour as the direct-download Mac app (accounts, day list, takeover, settings, widgets, duplicate detection), built the way a Windows user expects an app to be, from install to uninstall. Reuse TimeTug's portable Swift code (Core and the connector library) instead of re-implementing it, because iOS, Android and Linux front ends will follow and should share the same logic.

## Requirements (from the user)

1. Use Microsoft's on-device intelligence for duplicate merging where possible.
2. Split the project so the Windows and Mac apps release separately.
3. Flag every capability difference between Windows and macOS and propose a Windows-native alternative.
4. Distribute through the Microsoft Store and from the website, and explain what differs between the two.
5. Reuse as much of TimeTugCore as possible; the Windows front end is a real Windows application.
6. Only the owner can merge into any repository's default branch or start an official release build, and nobody can use the owner's signing identities, store accounts or OAuth registrations to build their own software.

## Assumptions

- Windows 11 22H2 (build 22621) or later, x64 and ARM64. Windows 10 support ended in October 2025, and third-party Windows Widgets need 22H2.
- Development and manual testing happen in a Windows 11 ARM virtual machine (Parallels) on the user's Mac; CI uses GitHub's Windows runners. The owner has no Copilot+ PC; on-device AI testing is layered so only one final check needs supported hardware (section 5).
- All repositories are public. The `binary-companion` organization is on GitHub Free, where organization secrets, required-reviewer environments and rulesets work for public repositories.

## Decisions

| Topic | Decision |
|---|---|
| Windows stack | C# on .NET 10 (LTS), WinUI 3 on the Windows App SDK (stable 2.x), MSIX packaging |
| Shared logic | Swift engine compiled for Windows as a DLL behind a small C interface carrying versioned JSON (approach A) |
| Repositories | Four public repositories in the `binary-companion` GitHub organization |
| Microsoft sign-in | Web Account Manager (WAM) through MSAL in Windows 1.0, with automatic first-run consent; browser sign-in stays as a fallback |
| Takeover focus | Overlay always; "Click anywhere to respond" when Windows refuses focus; a reminder toast only when the overlay cannot be shown |
| Control Center controls | Enable Tug toggle on the Windows widget plus a grouped tray menu |
| On-device AI | Windows AI `LanguageModel`, targeting Aion Instruct; opt-in Beta, default off, on-device only |
| Distribution | Microsoft Store first (free); signed website download deferred |
| Website and feed domain | `timetug.binarycompanions.com`; `timetug.obryan.cloud` redirects permanently |
| Code index | Every new repository gets the semantic code index workflow |
| Release control | Owner-only merges and releases through organization rulesets and reviewer-gated environments; every secret lives in an environment (section 8) |

Rejected approaches for the Windows front end:

- **Swift all the way (WinUI through swift-winrt).** The WinUI bindings are experimental (The Browser Company archived `swift-winui` in October 2025), Swift 6.1 and later hit Windows symbol export limits with generated bindings, and MSIX packaging and the Windows AI APIs are unproven from Swift. It works against the "real Windows app" goal and does nothing for Android.
- **C# app plus the engine as a separate process (named-pipe IPC).** Two processes to package, start, update and keep in sync, harder Store review, and not viable on Android or iOS. Its only gain over approach A is crash isolation.
- **Re-implementing Core in C#.** Duplicates about 12,700 lines of portable logic and 15,000 lines of tests, and every later platform would need its own copy.

## 1. Repositories, ownership and release flow

### Repositories

All in the `binary-companion` organization:

| Repository | Contents | Released as |
|---|---|---|
| `calendar-connectors` | The general-purpose connector library (CalendarCore, CalendarOAuth, Google, Microsoft, ICalendar, CalDAV, ICalSubscription, test support) and optional platform adapters (today's `CalendarApple`: Keychain credential store, loopback sign-in, CryptoKit hashing) | SwiftPM tags |
| `timetug-shared` | TimeTugCore, CalendarBridge, TimeTugEngine (new), TimeTugEngineProtocol (new), TimeTugEngineC (new) | SwiftPM tags, plus the `TimeTug.Engine` NuGet package on nuget.org |
| `timetug` | The Mac app, Apple-only adapters (EventKitSource, AppleIntelligenceInference), and the product website (`site/`), which serves both platforms: the Windows download page is added there in phase 9 | Unchanged: `v*` releases, DMG, Sparkle, Mac App Store |
| `timetug-windows` | The WinUI app, its platform services, widgets, MSIX packaging, Store submission | `v*` releases in its own repository |

`timetug` is the existing `darkarena1/timetug`, transferred with its history, releases and stars. `homebrew-tap` moves from `digital-companion-llc` to `binary-companion` (nobody uses it yet), after which `digital-companion-llc` can be deleted.

Dependency direction: `calendar-connectors` <- `timetug-shared` <- {`timetug`, `timetug-windows`}; `timetug` also depends on `calendar-connectors` directly (it registers connector kinds and supplies Apple adapters).

### Pinning

- The apps pin exact versions: the Mac app in `Apps/macOS/project.yml` with its `Package.resolved` committed; the Windows app in `Directory.Packages.props` (central package management).
- `timetug-shared` depends on `calendar-connectors` with a semver range, because it is a library, and commits its `Package.resolved`. Its CI and its NuGet build use that resolved version, and each release records it in the release notes. When the Mac app takes a `timetug-shared` bump, the same PR moves its `calendar-connectors` pin to at least the recorded version, so both apps run the connector version the engine was tested with.
- Each app's CI fails when a shared dependency points at anything other than a released tag, so an app never ships an unreleased shared commit.

### Library releases

- Every merge to `main` in `calendar-connectors` or `timetug-shared` publishes a new version automatically. The bump comes from a PR label (`semver:major`, `semver:minor`, `semver:patch`; default patch).
- A `timetug-shared` release also builds the engine on Windows runners (x64 and native ARM64) and publishes `TimeTug.Engine` to nuget.org under a Binary Companion account. nuget.org is chosen over GitHub Packages because GitHub Packages needs a token even to read a public package, which would burden Dependabot and outside users.

### Bump pull requests

- A library release notifies its dependents (`repository_dispatch`). Each dependent's `bump-dependencies.yml` updates the pin and opens "Bump <library> to X.Y.Z" with that release's notes. CI on that PR proves the app still builds and passes its tests.
- Cross-repository PRs are opened by the organization-owned GitHub App `timetug-bot`, because a workflow's built-in token cannot open PRs in another repository.
- Dependabot runs daily for Swift, NuGet and GitHub Actions as a safety net and for third-party dependencies (KeyboardShortcuts and Sparkle on Mac, NuGet packages on Windows). Dependabot alone is not enough: it runs on a schedule, and it cannot read the XcodeGen `project.yml`.

### App releases

App releases stay manual and work as they do today: the owner drafts and publishes a `v*` release in that app's repository, and that repository's workflows build, sign and distribute it. Separate repositories mean no tag prefixes and no conflict over GitHub's "Latest release" badge (the Homebrew tap and the website read "latest").

### Agent instructions

- Every repository's `AGENTS.md` gets a **Repositories** section: what each repository is, the dependency direction, and the release-and-bump flow.
- A cross-repository skill, `working-across-timetug-repos`, explains how to make a change that spans repositories (library PR, merge, automatic release, bump PRs) and how to test unreleased shared code locally (a SwiftPM and XcodeGen local path override; a local NuGet feed for Windows).

### Phase 0: organization move

The Sparkle feed is served by GitHub Pages at `https://darkarena1.github.io/timetug/appcast.xml` (the `gh-pages` branch). GitHub redirects git and web URLs after a transfer but not Pages URLs, so transferring first would silently stop updates for every installed copy. Order:

1. Ship a Mac release whose `SUFeedURL` is `https://timetug.binarycompanions.com/appcast.xml`. Firebase Hosting answers that path with a 301 to wherever the appcast lives; Sparkle follows redirects, so later moves only change the redirect.
2. Create `darkarena1/darkarena1.github.io` and mirror `/timetug/appcast.xml` there for copies that have not updated. The mirror pulls: a scheduled workflow in that repository (hourly, plus a manual run) fetches `https://timetug.binarycompanions.com/appcast.xml` and commits it when it changes, using only that repository's own token, so no workflow elsewhere needs credentials for a personal-account repository. The mirror is kept indefinitely (it costs nothing, and an old copy that never updated would otherwise stop updating). A user-site repository can serve that path without breaking the transferred repository's redirect. Release asset links in the appcast point at `github.com/darkarena1/timetug/releases/...`, which GitHub redirects after the transfer.
3. Transfer `timetug` and `homebrew-tap` to `binary-companion`. Update every `darkarena1/timetug` reference (README, docs, site, CODEOWNERS, issue templates, the cask URL and homepage, the tap's `bump.yml`), point the Firebase redirect at `binary-companion.github.io/timetug/appcast.xml`, and re-check the repository secrets, the `release` and `appstore` environments, rulesets, the Firebase deploy credential and the code-index artifact. Fix the cask description, which currently describes a different product.
4. The tap becomes `brew tap binary-companion/tap`.
5. Organization setup and hardening: the section 8 controls (2FA, organization rulesets for default branches and release tags, the Actions policy, every secret moved into a protected environment, admin bypass off), and the `timetug-bot` GitHub App. Phase 0 ends when the audit script passes.

## 1.5 Domain and sign-in branding migration

Goal: every public TimeTug URL lives under `timetug.binarycompanions.com`; the old `timetug.obryan.cloud` addresses keep working permanently as 301 redirects; Google and Microsoft show the new branding with no interruption for signed-in users. The domain must be live before phase 0 step 1.

1. **Domain and hosting.** Add `timetug.binarycompanions.com` as a custom domain of the existing Firebase Hosting site. Update `site/`: canonical and social-card URLs, support and security contact addresses at `binarycompanions.com`, privacy and terms naming Binary Companion as the operator, and the `appcast.xml` redirect. Move `timetug.obryan.cloud` to a second, minimal Firebase Hosting site whose only rule is a catch-all 301 to the same path on the new domain (Firebase redirects match paths, not hostnames, so one site cannot treat the two domains differently). A site test checks that every old path (`/`, `/privacy`, `/terms`, `/download`, ...) answers 301 with the matching new URL.
2. **Microsoft (Entra app registration).** Update the homepage, terms and privacy URLs and the logo under Branding & properties; these change in place with no review. The app is publisher verified under a personal partner account, and Microsoft requires the publisher domain to match that account's email domain, so switching the publisher domain first would cause a mismatch and could drop the verified badge. Order: create the Binary Companion partner account (it is also the Microsoft Store account, free since May 2026; a D-U-N-S number speeds verification), verify `binarycompanions.com` on the registration (by hosting `/.well-known/microsoft-identity-association.json`), then re-run publisher verification with the new partner ID. Client ID, redirect URIs and scopes do not change.
3. **Google (OAuth consent screen).** The app is in production and verified. Changing the homepage or privacy-policy link, name, logo or redirect URI requires brand verification again; scopes are unchanged, so no scope re-justification. Before submitting, verify `binarycompanions.com` in Google Search Console as a project owner and add it to Authorized domains, keeping `obryan.cloud` there until approval. Make every brand change in one edit (homepage, privacy and terms links, support and developer contact email, and name or logo if they change), then Prepare for verification and submit. The homepage must link to the privacy policy, and both must be HTML pages on that domain. Remove `obryan.cloud` from Authorized domains only after approval.
4. **Apple and the Mac repository.** Update the privacy-policy, support and marketing URLs in App Store Connect (editable at any time), and the README, SECURITY, CODEOWNERS contacts, `site/README.md` and the release-notes link base. The Mac app's sources contain no website URLs.

Done when: every old URL answers 301 with its new URL; Google shows the new branding as verified; the Microsoft consent prompt shows the new publisher domain with the verified badge; a fresh Google and Microsoft sign-in on the current Mac release succeeds; an existing signed-in account still refreshes.

## 2. The shared engine and its C interface

### TimeTugEngine

A new module in `timetug-shared`. It imports only Foundation, TimeTugCore, CalendarBridge and the connector library, and builds on macOS, iOS, Windows, Linux and Android. It takes over the platform-neutral orchestration the Mac app does today in `AppCoordinator` and its Foundation-only helpers (`AccountsController`, `SourceReconciler`, `SourceRefreshCoordinator`, `LedgerStore`, `DedupStateStore`, `SettingsStore`, `UITickPolicy`, `LaunchAcknowledgement`):

- account lifecycle, the connector registry, source reconcile and refresh (the periodic five-minute refresh and refresh on change signals);
- the store, dedup resolve passes, and merge, unmerge, split-off and forget actions with their persistence;
- the scheduler, the takeover ledger, the fire guard, launch acknowledgement, snooze and Test tug;
- the settings model and its persistence;
- the inference switch and pending-pair orchestration, including prompt building and answer parsing (today `PromptBuilder` in `AppleIntelligenceInference`), with a prompt profile per model;
- widget snapshot production and the UI-tick policy (when a front end next needs to redraw).

Timers use Swift concurrency and an injected clock, so tests drive time. The Core rule stands: Core never reads the clock; the engine is where the clock is injected. The host reports system events (wake, clock change, time-zone change, network change, display change); the engine recomputes. Power state is not a system event: the host's text-generation service reports itself temporarily unavailable while the device saves energy, and the engine keeps those pairs pending. The engine produces no display strings.

**Outputs:** an `EngineState` snapshot (day agenda, account and source statuses, settings, inference status, next takeover) and events (`takeoverDue(TakeoverRequest)`, `takeoverWithdrawn`, `widgetSnapshot`, `diagnostic`).

**Inputs (commands):** start and refresh; add, remove and reconnect account; apply settings changes (from the settings UI, the tray menu or a widget); takeover presentation reports (shown on screen, shown only as the fallback toast, closed), which drive the fire guard (a second takeover waits while one is visible) and the ledger; takeover actions (join, snooze N minutes, dismiss, test); dedup actions; system events.

### Host services

Supplied by each front end, through the existing seams where they exist:

| Service | Seam | Mac | Windows |
|---|---|---|---|
| Credential storage | `CredentialStore` | Keychain (shared group) | Windows Credential Locker (`PasswordVault`) |
| Sign-in interaction | `AuthorizationInteraction`, `OAuthRedirectSession` | Existing web-authentication sheet | Default browser plus a loopback listener (`HttpListener` on 127.0.0.1) |
| External tokens | new (section 4.5) | not used | MSAL with the WAM broker |
| HTTP | `HTTPTransport` | `URLSession` | .NET `HttpClient`, so the system proxy, corporate TLS inspection and the Windows certificate store apply. Swift Foundation on Windows uses libcurl and ignores system proxy settings |
| Text generation | new: availability and generate | Apple Intelligence | Windows AI `LanguageModel` |
| Data directory | config | App Group container | The package's `LocalState` folder |
| Diagnostics sink | config | OSLog | Rolling log file plus ETW `EventSource` |

### Two ways in

- **Swift front ends** (Mac, later iOS) call the engine's Swift API directly, with no JSON. They may register extra connector kinds (EventKit).
- **Every other front end** goes through `TimeTugEngineC`:

```c
tt_engine *tt_engine_create(const char *config_json, tt_message_fn on_message, void *context);
void tt_engine_send(tt_engine *, const char *command_json);
void tt_engine_reply(tt_engine *, uint64_t request_id, const char *reply_json);
void tt_engine_destroy(tt_engine *);
```

Every message is a UTF-8 JSON envelope `{"v":1,"type":...,"id":...,"payload":...}`. State, events and host-service requests arrive through `on_message`; the host answers a request with `tt_engine_reply` and the request's `id`. Strings passed to a callback belong to the engine for the duration of the call; the host copies what it keeps. Callbacks arrive on an engine thread; the host moves them to its UI thread.

### Contract

The message types live in `TimeTugEngineProtocol` (Codable). Golden JSON fixtures in `timetug-shared` are round-tripped by the Swift tests and shipped in the NuGet package, where the C# tests deserialize and round-trip them. A breaking change bumps `v` and the major version.

### Mac migration first

The Mac app moves onto the engine before any Windows code exists, in small PRs. Its unit tests, the manual checklist and a beta cycle prove that nothing changed for users. What stays in the Mac app: AppKit and SwiftUI UI, the status item, popover, overlay, widgets and Control Center controls, Sparkle, KeyboardShortcuts, instance arbitration, and the EventKit and Apple Intelligence adapters. The Keychain credential store and the loopback sign-in adapter live in `calendar-connectors` (today's `CalendarApple`) and are injected by the Mac app.

## 3. Windows app architecture

### Stack and libraries

.NET 10, C#, WinUI 3 on the Windows App SDK, MSIX. Common libraries, mostly first-party:

| Need | Library |
|---|---|
| MVVM, observable models, commands | `CommunityToolkit.Mvvm` |
| Settings-style UI (cards and expanders, like Windows Settings) | `CommunityToolkit.WinUI` (`SettingsCard`, `SettingsExpander`) |
| Dependency injection, logging, configuration | `Microsoft.Extensions.Hosting`, `Microsoft.Extensions.Logging` |
| Win32 calls (hotkey, foreground, monitors, power, notification state) | `Microsoft.Windows.CsWin32` (generated P/Invoke) |
| Tray icon and context menu | `H.NotifyIcon.WinUI` (WinUI has no tray API) |
| Microsoft sign-in through WAM | `Microsoft.Identity.Client`, `Microsoft.Identity.Client.Broker` |
| JSON for the engine contract | `System.Text.Json` with source generation |
| Tests | xUnit, FluentAssertions; UI smoke tests later with Appium/WinAppDriver |

### Repository layout

```
src/TimeTug.App/          WinUI app: tray, flyout, overlay, settings, about
src/TimeTug.Platform/     host services: credentials, HTTP, sign-in, WAM tokens, AI, data folder
src/TimeTug.Widgets/      Windows Widgets provider, hosted in the app's own process (the app executable is the registered COM server),
                          so widgets read engine state and send commands (Enable Tug) directly; the widget host starts the app if it is not running
packaging/                Store and website manifests, the .appinstaller template (deferred)
tests/                    view models, platform services, contract and conformance tests
scripts/                  verify.ps1 and friends; logic lives in scripts, not workflow YAML
```

The `TimeTug.Engine` NuGet package, built in `timetug-shared`, contains the native DLLs for win-x64 and win-arm64 with the Swift runtime, and a managed wrapper: P/Invoke to the four C functions, C# records for every message, and an `IEngineHost` interface for the host services. The C# types are tested against the golden fixtures in `timetug-shared`'s CI, so a contract break fails before release.

### Runtime flow

1. The app starts and claims single instance through the Windows App SDK `AppInstance`; a second launch redirects to the running copy and opens the flyout.
2. It creates the engine with the `LocalState` folder and the host services.
3. Engine state feeds view models on the UI thread.
4. `takeoverDue` shows the overlay; overlay buttons send takeover commands.
5. Wake, time-zone, clock, display and network changes are forwarded as system events.

### Rules

Kept in the repository's `AGENTS.md` and enforced by an architecture test: the app answers "how it looks and where it lives", the engine answers "what and when"; no scheduling or dedup logic in C#; view models talk only to `IEngine`, never to P/Invoke; platform services are small classes behind interfaces, each with tests.

### Tray menu

Grouped, at most six rows:

```
Next: Design review · 2:30 PM     (information only; "Join Design review" once a link is near)
---------------------
✓ Enable Tug
  Test tug
---------------------
  Settings…
  About TimeTug
---------------------
  Quit TimeTug
```

## 4. Mac vs Windows capabilities

Legend: **=** same behaviour; **≈** same goal, different mechanism; **⚠** real gap with a proposed alternative; **+** Windows-only addition.

### Living in the system

| Capability | Mac | Windows | | Notes and alternative |
|---|---|---|---|---|
| Always-present icon | Menu bar puppy (light, dark, colour when a meeting is near) | Notification-area puppy with the same three states | ≈ | Follows the taskbar theme (`SystemUsesLightTheme`), which is separate from the app theme |
| Text in the icon | Optional title and countdown modes | Tray icons cannot show text | ⚠ | Live tooltip ("Design review in 4 min") and an icon that draws the remaining minutes (9 to 1) in the final ten minutes. Later option: a small pinned countdown chip near the tray |
| Left-click popup | NSPopover | Flyout window anchored above the tray (Mica or Acrylic, closes on deactivate), same cards | ≈ | As OneDrive and Teams do |
| Right-click menu | Settings, About, Quit | Grouped tray menu (section 3) | = | |
| Launch at login | `SMAppService` | MSIX `StartupTask`, also visible in Settings > Apps > Startup | ≈ | Windows does not allow enabling it silently: asked on first run, then a Settings toggle |
| Global popup shortcut | KeyboardShortcuts | `RegisterHotKey` and our own shortcut recorder | ≈ | |
| Single instance | File-based arbitration between builds | `AppInstance`; the other distribution's copy is detected and the collision notice shown | ≈ | |

### The takeover

| Capability | Mac | Windows | | Notes and alternative |
|---|---|---|---|---|
| Cover every display | Window per screen above full-screen apps | Borderless topmost window per monitor, tracking monitor changes | ≈ | Covers normal and borderless full-screen apps. Exclusive full-screen games and some presentation modes cannot be covered (⚠, see below) |
| Take keyboard focus | Overlay becomes key | Windows' foreground lock stops a background app from taking focus from an app the user is actively using | ⚠ | When the user is idle, focus is granted as on Mac. Otherwise the overlay shows "Click anywhere to respond", and the first click gives it the keyboard. No focus-stealing workarounds (simulated key presses, thread-input attachment) |
| Cannot be shown | n/a | Exclusive full-screen (D3D) or presentation mode, detected with `SHQueryUserNotificationState` | ⚠ | A reminder-scenario toast with Join, Snooze and Dismiss, shown only in that case; Windows Do Not Disturb may hold it |
| Backdrop | Blurred navy | Desktop Acrylic with navy tint; solid navy when transparency effects are off | = | |
| Actions and keys | Join, Snooze, Dismiss; Return, Esc, 1, 5, 0 | Same, once focused | = | |
| Screen reader | VoiceOver announcement | Narrator through UI Automation notification events | ≈ | |
| Reduce motion and transparency | Respected | `UISettings.AnimationsEnabled`, transparency-effects setting | = | |
| Contrast themes | n/a | Windows contrast themes honoured | + | Checked with Accessibility Insights |

### Calendars and sign-in

| Capability | Mac | Windows | | Notes and alternative |
|---|---|---|---|---|
| System calendar store (EventKit: local calendars, macOS internet accounts, Birthdays) | Yes | No equivalent: Mail & Calendar is retired, new Outlook does not populate the system appointment store, and that API needs a restricted capability | ⚠ | Connect accounts directly. Microsoft accounts on the PC appear through WAM (section 4.5), the closest match to EventKit's "already there" accounts. Birthdays come from Google's birthday calendar. Outlook classic local PST calendars are not supported (only reachable through COM automation) |
| Google, Microsoft, iCloud/CalDAV, iCal links | Yes | Same connectors through the engine | = | |
| Sign-in window | In-app web-authentication sheet | Default browser and loopback redirect; WAM for Microsoft | ≈ | Google blocks embedded web views |
| Credentials | Keychain | Credential Locker; WAM accounts store no refresh token at all | ≈ | |
| Attendee email lookup | Contacts permission | Not needed (connectors return emails) | = | |

### Glanceable surfaces

| Capability | Mac | Windows | | Notes and alternative |
|---|---|---|---|---|
| Widgets: Next Up, Today | WidgetKit | Windows Widgets board (Adaptive Card provider in the same package) | ≈ | Same snapshot data, refreshed when the engine publishes |
| Control Center controls | macOS 26 controls | Quick Settings is closed to third-party apps | ⚠ | Enable Tug toggle on the widget, plus the tray menu |

### Intelligence, updates, diagnostics

| Capability | Mac | Windows | | Notes and alternative |
|---|---|---|---|---|
| On-device duplicate judging | Apple Intelligence | Windows AI `LanguageModel` | ⚠ | Narrower hardware (section 5); rules only elsewhere |
| Updates and betas | Sparkle with a Beta updates toggle | Store updates; betas through Store package flights to a tester group | ≈ | Section 6 |
| Package manager | Homebrew cask | winget | ≈ | |
| Diagnostics | OSLog, diagnostics pane | Rolling log file plus ETW `EventSource`; Copy diagnostics button | ≈ | |
| Sandbox | App Sandbox | MSIX full-trust desktop app with clean install and uninstall | ≈ | AppContainer is not required by the Store and would block the loopback sign-in |

## 4.5 Windows account sign-in (WAM)

Ships in Windows 1.0. Web Account Manager is Windows' account broker: it already holds the Microsoft account the user signed into Windows with (personal, work or school), so TimeTug can use it without a password or a browser.

- **Consent is still required, once per account.** Microsoft requires every third-party app to get permission to read calendars; a native Windows dialog asks once. Until then silent token requests fail with "interaction required". In tenants that block user consent an admin approves once, as with today's browser sign-in. This matches the Mac, where EventKit asks once for calendar access.
- **First run:** if Windows is signed in with a Microsoft account, TimeTug shows the consent dialog for that account automatically, as the Mac app asks for calendar access at launch. Approve and the calendars appear; decline and TimeTug runs without accounts and shows an Accounts prompt in the flyout.
- **Accounts pane:** the Windows account appears as "On this PC". Add Microsoft account opens the WAM account picker (every account on the PC, plus adding a new one). Google, iCloud and CalDAV keep the browser flow; WAM supports only Microsoft accounts.
- **Browser fallback for Microsoft:** used when WAM is unavailable (the broker fails or is disabled by policy) or when the user picks "Sign in with a browser instead" in the Add Microsoft account menu. It is today's loopback flow with the connector library's own OAuth and a refresh token in the Credential Locker. A connection records which mode it uses.
- **No stored refresh token.** Windows keeps and renews the tokens; sign-out, password changes and company policies (MFA, device compliance) are handled by Windows.
- **Library seam:** `calendar-connectors` gains an externally managed token mode for the Microsoft connector: the host supplies access tokens and the connector runs no OAuth itself. It is generic, for later iOS (Microsoft Authenticator) and Android (account broker) use.
- **Engine:** such a connection asks the host for a token through a host-service request; "interaction required" becomes the existing needs-reconnect status; Reconnect shows the consent again.
- **Registration:** add the broker redirect URI to the existing Entra app registration. Same client ID, same scopes.
- **Manual tests:** a VM signed into Windows with a test Microsoft account; a work account with MFA; a personal account; consent declined; the account removed from Windows.

## 5. On-device AI for duplicate judging

Same model as Mac (ADR 0009): rules always run, the model judges only leftover ambiguous pairs, opt-in, marked Beta, default off, strictly on-device with no cloud fallback.

- **Host role:** two calls, availability and generate, implemented with `LanguageModel` (`Microsoft.Windows.AI.Text`) behind an `ITextGenerator` interface. Prompt building, answer parsing and the per-model prompt profile are in the engine.
- **Behaviour:** asynchronous, never blocks refresh or takeover; one request at a time with a per-pair timeout; paused while Windows energy saver is on (the host service answers "temporarily unavailable" and the engine keeps the pairs pending); an unparseable or content-filtered answer is "no verdict", never a merge.
- **Model:** Phi Silica needs a Limited Access Feature token and is being replaced by Aion Instruct (no token; Insider builds November 2026, retail January 2027, removal of Phi Silica at retail). Target Aion. If Windows 1.0 ships before January 2027, request the Phi Silica token (a free form).
- **Hardware:** Copilot+ PCs (NPU, model preinstalled); NVIDIA RTX 30 series and newer or AMD RX 9060 series and newer with 6 GB or more of video memory (GPU support is Insider-only and downloads a several-GB model through Windows Update). Not available in China.
- **Settings > Calendars > Smart duplicate detection (Beta)**, in plain language, never by model name:

| Windows reports | TimeTug shows |
|---|---|
| Ready | The toggle |
| Needs download | "Uses an optional Windows AI model (several GB, downloaded by Windows Update)"; download starts only after the user confirms |
| Not supported on this PC | "Needs a Copilot+ PC or a supported graphics card. Duplicate rules still work." |
| Turned off in Windows privacy settings | "Turned off in Settings > Privacy & security > Text and image generation", with a button that opens that page |

- **Acceptance:** the dedup benchmark (today `scripts/benchmarks/run-dedup.sh` in `timetug`; its fixtures move to `timetug-shared` in phase 3 with the prompt building, and each host supplies a model runner) runs against Aion on a Copilot+ PC; the bar is zero wrong merges on the fixture set.
- **Open in the phase spec:** the `systemAIModels` manifest capability and how Store review treats it.
- **Rejected for 1.0:** bundling a model through Windows ML or Foundry Local for PCs without an NPU (a multi-GB download for a Beta feature).
- **Testing, in three layers** (the owner has no Copilot+ PC):
  1. *Everyday, no special hardware:* prompt building and answer parsing are shared Swift code tested on the Mac; the Windows host code is tested with a fake `ITextGenerator`; the Windows VM covers the "Not supported on this PC" state, the settings UI and the rules-only fallback.
  2. *Prompt tuning against Aion, probably no special hardware:* run the dedup benchmark prompts against the Aion model through a small test page in Microsoft Edge preview builds (Edge ships Aion behind a flag and states CPU inference on PCs without a capable GPU), on the Windows VM; or, if Microsoft has published the Aion Instruct open weights as promised, run them on the Mac. Edge's copy may not be the exact build Windows uses, so this tunes the prompt profile but does not prove the integration.
  3. *One real-integration check on supported hardware*, chosen at the start of phase 8: re-check whether Aion's retail rollout (January 2027) widens hardware support so the VM works; or a tester with a Copilot+ PC in the Store flight group runs an in-app **Run AI self-test** (Settings > Diagnostics: judges a fixed set of synthetic event pairs, no calendar data, and adds the results to Copy diagnostics); or a PC with an NVIDIA RTX 30-series or newer GPU on a Windows Insider build; or an inexpensive Copilot+ laptop. No rentable cloud machine with a supported NPU or consumer GPU was found.

## 6. Distribution

One codebase builds two package flavours, as the Mac app's direct and App Store targets do. A build constant (`STORE`) changes only the package identity, the Updates pane and the update plumbing.

| | Microsoft Store | Website download (deferred) |
|---|---|---|
| Account and cost | Partner Center company account for Binary Companion, free | Azure Artifact Signing, about 10 US dollars a month, with identity validation of Binary Companion |
| Signing | Microsoft re-signs the package | Signed in CI |
| SmartScreen | Never warns | Warns on early downloads until reputation builds |
| Identity | Name and publisher reserved by the Store | `BinaryCompanion.TimeTug`, publisher Binary Companion |
| Install | Store page, the Store web installer button on the website, winget (Store source) | Download and open a `.appinstaller` file (one-click `ms-appinstaller:` links are disabled by default since December 2023); winget community repository |
| Updates | Automatic, about daily | App Installer on launch and in the background; optional Check for updates |
| Betas | Package flights to a tester group (each flight passes Store certification) | A second `beta.appinstaller` channel |
| Review | Store certification per submission, hours to about three days | None |
| Store-blocked work PCs | Cannot install | Works where sideloading is allowed |

**Chosen plan:** Store first, at no cost.

- **Stable:** publishing a release whose tag is exactly `vX.Y.Z` (no suffix, not marked pre-release) uploads the package to Partner Center; the owner submits it there, as with App Store Connect. The same rule `appstore.yml` uses today.
- **Betas:** a flight workflow (run by hand, or on a pre-release whose tag has a suffix such as `v1.2.0-beta.1`) submits to the tester flight group; the stable workflow ignores suffixed tags and pre-releases. Flights are slower than Mac betas because each passes certification, so they are cut per batch of changes.
- **Development builds:** CI builds an MSIX on every PR and merge, signed with a throwaway self-signed certificate created in the job (never the owner's); the owner installs it on the VM in Developer Mode after trusting that certificate.
- **Website:** leads with the Store button (web installer) and `winget install`.
- **Deferred:** the signed website download (Artifact Signing, `.appinstaller` feed, public beta channel). Trigger: public betas are wanted, or a user on a Store-blocked work PC asks.

Why not an unsigned website installer: Windows does allow downloading and running unsigned programs, but MSIX refuses unsigned packages, and an unsigned classic installer shows "Unknown publisher" in SmartScreen, is blocked outright by Smart App Control (on by default on fresh Windows 11 installs), draws more antivirus scrutiny, and has no package identity, so no on-device AI and no widgets.

Differences from Mac to note: the Store and website builds, when both exist, have different identities and therefore separate data (no App Group equivalent across differently signed packages); switching builds means signing in again. The Windows site leads with the Store, the reverse of the Mac site.

## 7. Testing and CI

Every repository keeps the current rules: logic in scripts, not YAML; PR jobs get none of the owner's signing material (the development MSIX is signed with a throwaway self-signed certificate created inside the job); live account tests are opt-in and never run in CI; failing test first; a `verify` or `affected-tests` script says what to run.

- **`calendar-connectors`:** macOS and Linux (swift:6.x, now required) plus a Windows job. Tests that depend on platform quirks are skipped with a reason.
- **`timetug-shared`:** unit tests for Core, Bridge and Engine on macOS, Linux, Windows x64 and Windows ARM64 (`windows-11-arm` runners). An engine conformance suite drives a real engine with fake host services (in-memory credentials, recorded HTTP responses, a fake clock) and checks state and events; it runs in Swift and in C# against the real DLL, and later in other front ends. Contract fixtures round-trip in Swift and C#. A C program smoke-tests the four exported functions. The architecture check moves here. The release workflow tags, builds and publishes the NuGet package, and notifies dependents.
- **`timetug`:** existing jobs plus the pin check. After the engine migration, a full `docs/manual-tests/macos-checklist.md` pass and a beta cycle.
- **`timetug-windows`:** build and unit tests on x64 and ARM64; contract and conformance tests; a dev-signed MSIX artifact; the Windows App Certification Kit on every release candidate; Accessibility Insights automated checks (`axe-windows`) on the settings, flyout and overlay windows; `docs/manual-tests/windows-checklist.md` (tray states, tooltip and countdown digits, flyout, overlay on two monitors, the focus case while typing, the toast fallback during full-screen, WAM first-run consent and decline, Google browser sign-in, startup task, hotkey, widgets and their toggle, contrast themes, Narrator, installing a Store flight). Agents reach the VM over OpenSSH and run `scripts/verify.ps1`.
- **Code index:** every new repository gets the semantic code index workflow and its `AGENTS.md` section (the `add-code-indexing` skill) when it is created.

## 8. Security and release control

Requirements (from the user): only the owner can merge into the default branch of any repository; only the owner can start a build that produces an official release; nobody can use the owner's signing identities, store accounts or OAuth registrations to build or ship their own software.

### Findings on 2026-10-09 (read-only audit of `darkarena1/timetug` and `binary-companion`)

| Finding | Risk | Fix |
|---|---|---|
| Signing and notarization material (Developer ID certificate and password, provisioning profile, notary key, Sparkle private key) and the OAuth client values are repository secrets; the `release` environment holds none | Any workflow run in the repository can read them, from any branch a user with write access pushes. The release approval gates the job, not the keys. Today only the owner has access, so this is latent | Move every secret into an environment: `beta` (deployment branch `master` or `main` only, no reviewer, so betas stay automatic), `release` and `appstore` (reviewer: owner). No repository-level or organization-wide signing secrets |
| `Protect master` requires a PR with zero approvals; any user with write access could merge | Latent (no other collaborators) | Add the "Restrict updates" rule with the organization admin role as the only bypass actor, so only the owner can merge |
| Organization: two-factor authentication not required; members can create repositories | Weak baseline | Require 2FA; members cannot create repositories; base permission stays read |
| Actions allow any action; SHA pinning not required | A compromised third-party action could read the secrets of the job it runs in | Organization policy: GitHub-owned and an explicit allow-list only, SHA pinning required (`docs/development/action-pins.md` already pins) |
| Fork PR workflows need approval only for first-time contributors | Low (fork PRs get no secrets) | Require approval for all outside contributors |
| Release environments allow admin bypass | None while the owner is the only admin | Turn bypass off so even an owner token cannot skip the approval |
| Organization Actions policy could not be read (`gh` token lacks `admin:org`) | Unknown | The owner refreshes the token scope and runs the audit script |

### Controls, applied to every repository through organization rulesets

- **Merging:** default branch rules: pull request required, required status checks, no force pushes, no deletion, and Restrict updates with the organization admin role (the owner, the only admin) as the sole bypass actor. Nobody else is given write access; contributions come through fork pull requests.
- **Release tags:** `v*` tag creation, update and deletion restricted to the organization admin role (as `Protect release tags` does today).
- **Update feed branch:** `gh-pages` (the appcast) gets a ruleset that blocks force pushes and deletion and restricts updates to the owner and the publishing workflows' identity, so nobody else can change what installed apps download. The phase 0 spec confirms how the workflows' identity is admitted as a bypass actor.
- **Official builds:** every job that signs, notarizes, uploads to a store, publishes a package or changes the update feed runs in a protected environment with admin bypass off. Two kinds:
  - **Release environments** (`release`, `appstore`, `store-windows`): the owner is a required reviewer, and the deployment policy allows the default branch and `v*` tags only. Starting a release (publishing a GitHub release, or a manual run) needs write access, and the job still waits for the owner's approval.
  - **Automatic environments** (`beta` in `timetug`, `publish` in `calendar-connectors` and `timetug-shared`): no reviewer, deployment policy of the default branch only. They run only on merges to the default branch, which only the owner can make, so betas and library releases stay automatic and owner-initiated. `publish` uses nuget.org trusted publishing (OIDC) and the repository's own token for the tag, so it holds no stored key.
- **Secrets:** only in environments, never at repository or organization level with access for all repositories. Prefer short-lived OIDC credentials over stored keys: nuget.org trusted publishing for `TimeTug.Engine`, and federated credentials for Azure Artifact Signing when the website download arrives. Where a stored key is unavoidable (Apple certificates, Sparkle, App Store Connect, Partner Center), it lives in its environment and is scoped as narrowly as the provider allows.
- **Untrusted code never meets secrets:** pull requests run only `ci.yml` without secrets; `pull_request_target` is banned; `workflow_run` workflows never check out pull request code. `scripts/ci/check-repository-contracts.py` (and its copy in each repository) fails when a workflow uses `pull_request_target`, or references a secret outside an approved environment.
- **The bot:** `timetug-bot` has contents and pull-request permissions on the dependent repositories only, is not a bypass actor (it can open PRs, never merge), and its private key lives in a `bump` environment restricted to the default branch.
- **Forks:** a fork receives no secrets, so it can build TimeTug only with its own certificates and OAuth registrations (the existing git-ignored local configuration). Builds from pull requests embed no OAuth client values.

### Limits to state honestly

- **OAuth client IDs in shipped apps are public by design.** Google and Microsoft treat desktop apps as public clients; the client ID (and Google's desktop "client secret") is inside every released binary and can be copied into another app. That app would still show TimeTug's name on the consent screen and could reach only the accounts of users who consent to it. Mitigations: minimal scopes, monitoring usage in the Google Cloud and Entra consoles, and rotating the registration if abuse appears (which makes existing users sign in again). It cannot be prevented outright.
- **Branding:** the Commons Clause license restricts selling the software but does not protect the name. A short trademark notice for "TimeTug" and the puppy artwork (`artwork/LICENSE.md` already covers the artwork) belongs in the README.
- **Agents act with the owner's identity.** Rulesets cannot tell the owner from an agent using the owner's `gh` token. Agents never merge, publish releases or approve deployments (the release docs' manual gate). Optional hardening: agent sessions use a fine-grained token without administration, merge or environment-approval rights.

### Audit script

`scripts/security/audit-github.sh` (in the organization's `.github` repository) checks, through `gh api`, that: 2FA is required; the owner is the only member and admin and there are no outside collaborators; base permission and repository-creation settings; the Actions policy (allow-list, SHA pinning, read-only default token, fork approval for all outside contributors); every repository has the default-branch and tag rulesets with the expected bypass actors; every signing environment has the owner as reviewer, admin bypass off and the expected branch policy; no repository-level secrets other than an allow-list of non-signing values; no deploy keys or unexpected webhooks or installed apps. It needs the `admin:org` scope, so the owner runs it locally at the end of every phase and monthly. It is not scheduled in CI, because that would require storing an organization-admin token.

## 9. Roadmap

Each phase gets its own spec and plan. The Mac app stays releasable after every phase.

**Spike S (first, one to two days, throwaway):** build TimeTugCore and the connector library with Swift 6.3 on the Windows ARM VM and run their tests; export one C function and call it from a C# console app; record the Swift runtime size and any Foundation gaps. A bad result sends approach A back for review before any repository moves.

| Phase | Delivers | Depends on |
|---|---|---|
| 1.5 Domain and branding | New domain live with redirects; Microsoft URLs; Binary Companion partner account, then publisher re-verification; one Google brand re-verification | none |
| 0 Organization move and hardening | Mac release with the stable feed URL; transfer of `timetug` and `homebrew-tap`; old-URL mirror; section 8 controls (2FA, rulesets, Actions policy, secrets moved into environments, admin bypass off), `timetug-bot`, the audit script passing | 1.5 domain live |
| 1 `calendar-connectors` | Extracted with history, 1.0.0 released; Mac consumes it; automatic releases, bump PRs, Dependabot, the cross-repository skill and instructions, code index | 0 |
| 2 `timetug-shared` | Core and Bridge extracted; Mac consumes it; Windows and Linux CI; code index | 1 |
| 3 Engine | `TimeTugEngine`; orchestration moved out of the Mac app in small PRs; shared prompt building; a Mac release with no behaviour change | 2 |
| 4 C interface and NuGet | `TimeTugEngineC`, the contract and fixtures, the conformance suite, `TimeTug.Engine` with the C# wrapper on nuget.org | 3 |
| 5 Windows app core | `timetug-windows` with code index; tray and menu, flyout, overlay with focus hint and toast fallback, settings, browser sign-in, Credential Locker, `HttpClient` transport, startup task, single instance, hotkey, diagnostics; dev builds on the VM | 4 |
| 6 WAM sign-in | External-token mode in the connector library, MSAL broker, automatic first-run consent, "On this PC" accounts | 5 and a library release |
| 7 Widgets | Next Up and Today, with the Enable Tug toggle | 5 |
| 8 On-device AI | `LanguageModel` host service, availability states, prompt profile tuned via Edge or open weights, energy-saver pause, Run AI self-test; one real-hardware check (section 5) | 5; Aion retail |
| 9 Store 1.0 | Listing, certification kit, tester flights, first stable submission, website Store button, winget | 5, 6, 7 (8 may follow in 1.1) |
| Deferred | Signed website download | Trigger in section 6 |

Phase 1.5 runs alongside everything. After phase 5, phases 6, 7 and 8 are independent. iOS, Android and Linux front ends are outside this program; they reuse the engine and the conformance suite.

## Risks

- **Swift on Windows.** Foundation behaviour differences and toolchain regressions (export limits since Swift 6.1). Mitigated by Spike S, Windows CI from phase 2 and the conformance suite.
- **Swift runtime size.** Roughly 30 to 50 MB added to the package; measured in Spike S.
- **AI timing and coverage.** Aion's dates come partly from a developer email; most Windows PCs lack the hardware. The feature is Beta and optional, and 1.0 does not wait for it.
- **Store certification latency** slows tester flights compared with Mac betas.
- **Focus rules.** Windows may change foreground behaviour; the overlay never depends on focus to be seen.
- **Google brand re-verification** can take days; old URLs stay live as redirects throughout.
- **Public OAuth client IDs** can be copied from shipped binaries (section 8 limits); mitigated by monitoring and rotation, not preventable.

## Sources

- [Phi Silica in the Windows App SDK (updated 2026-10-02)](https://learn.microsoft.com/en-us/windows/ai/apis/phi-silica)
- [Aion Instruct transition report](https://windowsforum.com/windows-news.4/microsoft-will-replace-phi-silica-with-aion-instruct-in-windows-11-this-fall.440821/)
- [The state of WinUI and Swift](https://forums.swift.org/t/the-state-of-winui-and-swift/79963)
- [MSIX overview and packaging models](https://learn.microsoft.com/en-us/windows/msix/overview)
- [Free company Store accounts (May 2026)](https://blogs.windows.com/windowsdeveloper/2026/05/07/publish-to-microsoft-store-as-a-company-now-with-free-registration-and-faster-onboarding/)
- [Code signing options](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options)
- [SmartScreen reputation](https://learn.microsoft.com/et-ee/windows/apps/package-and-deploy/smartscreen-reputation)
- [Distribution feature status (App Installer protocol)](https://learn.microsoft.com/en-us/WINDOWS/APPS/package-and-deploy/distribution-feature-status)
- [Store web installer](https://learn.microsoft.com/en-us/windows/apps/distribute-through-store/how-to-use-store-web-installer-for-distribution)
- [Google OAuth verification requirements](https://support.google.com/cloud/answer/13464321)
- [Google app privacy policy requirements](https://support.google.com/cloud/answer/13806988?hl=en)
- [Microsoft Entra publisher domain](https://learn.microsoft.com/uk-ua/entra/identity-platform/howto-configure-publisher-domain)
- [Microsoft publisher verification troubleshooting](https://learn.microsoft.com/sl-si/entra/identity-platform/troubleshoot-publisher-verification)
- [Expanding on-device AI in Microsoft Edge (Aion, CPU inference)](https://blogs.windows.com/msedgedev/2026/06/02/expanding-on-device-ai-in-microsoft-edge-new-models-and-apis-for-the-web/)
