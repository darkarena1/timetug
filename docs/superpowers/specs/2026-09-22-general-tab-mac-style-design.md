# General settings tab: macOS System Settings styling

Date: 2026-09-22. Status: approved.

## Problem

The General settings tab is a single flat `Form` with five sections stacked in a scroll view
(Software Update, App, Shortcut, Appearance). It doesn't match the drill-down, card-styled pattern of
macOS System Settings' own General page, and there's no in-app way to see the app's branding/version
without opening the separate About window. The Appearance section (menu bar text, popup card style,
light/dark/auto) is buried at the bottom of General rather than being its own destination, and its
controls are plain `Picker`s with no visual preview of what each option actually looks like.

## Decision

Restructure General into a **hub page** with two drill-down rows (About, Software Update) styled like
System Settings' icon-in-colored-square rows, each pushing a sub-page with a standard SwiftUI back
button. Promote **Appearance** to its own top-level sidebar entry, and replace its three Pickers with
tappable preview tiles (mockups) so each option is visible before it's chosen, matching System
Settings' Appearance page (Light/Dark/Auto swatches).

No accent-color picker is introduced — popup card style stays a fixed set of three named looks. No
custom back/forward browser-style history — `NavigationStack`'s default back button is enough (per
user: "I'm okay with a general sort of back arrow for Software Update and about").

## Navigation structure

### `SettingsPane` (`SettingsNavigation.swift`)
Add `case appearance` between `.general` and `.accounts`:
- `title`: "Appearance"
- `systemImage`: `"circle.righthalf.filled"` (a plain "before/after" glyph, echoing System Settings'
  actual Appearance icon)
- `iconColor`: `Color(white: 0.35)` (dark neutral square, distinct from the existing green/blue/orange
  panes)

`SettingsView.detail` gets a matching `case .appearance: AppearancePane(settings: settings, navigation: navigation)`.

### `GeneralDestination` (new, in `SettingsNavigation.swift`)
```swift
enum GeneralDestination: Hashable {
    case about
    case softwareUpdate
}
```

### `SettingsNavigation`
- New `@Published var generalPath: [GeneralDestination] = []`.
- `reveal(_:)` extended: if the item's id is one of `software-update` / `automatic-updates` /
  `beta-updates`, also set `generalPath = [.softwareUpdate]`. For every other id, set `generalPath = []`
  (pop to the hub) so the highlighted control on the hub page is actually visible. This runs regardless
  of which pane the item targets, so it stays correct if the user was mid-navigation in General.

### `GeneralPane` (rewritten)
```swift
NavigationStack(path: $navigation.generalPath) {
    hub
        .navigationDestination(for: GeneralDestination.self) { destination in
            switch destination {
            case .about: AboutPaneContent()
                .navigationTitle("About")
            case .softwareUpdate:
                Form { UpdatesSection(updates: updates, navigation: navigation) }
                    .formStyle(.grouped)
                    .navigationTitle("Software Update")
            }
        }
}
```
`hub` is today's `Form` minus the `UpdatesSection` and the Appearance section, plus a new first
`Section` containing two rows:
```swift
NavigationLink(value: GeneralDestination.about) {
    Label { Text("About") } icon: {
        Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
            .resizable().frame(width: 22, height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))
    }
}
NavigationLink(value: GeneralDestination.softwareUpdate) {
    Label { VStack(alignment: .leading) {
        Text("Software Update")
        Text("TimeTug \(updates.currentVersion)").font(.caption).foregroundStyle(.secondary)
    } } icon: { PaneIcon-style square with "arrow.triangle.2.circlepath", blue }
}
```
(Exact icon asset for About: reuse the app's own icon image rather than an SF Symbol, since TimeTug
already has strong icon branding; Software Update reuses the `PaneIcon` square pattern with a refresh
glyph.)

The `App` and `Shortcut` sections below are unchanged — same toggle, same `KeyboardShortcuts.Recorder`,
same `settingsHighlight` ids.

### Search catalog (`SettingsSearch.swift`)
Change `pane: .general` → `pane: .appearance` for the `appearance`, `popup-card-style`, and
`menu-bar-text` entries only. The `software-update` / `automatic-updates` / `beta-updates` /
`launch-at-login` / `popup-shortcut` entries keep `pane: .general` (handled by the `reveal()` change
above). No new search entry for "About" — it's not a tunable setting, so it isn't cataloged, consistent
with there being no search entry for it today.

## About sub-page

`AboutView.swift` is split into a shared content view and two thin wrappers, so the standalone window
and the embedded sub-page render identical branding from one source:

```swift
struct AboutContent: View {
    // everything currently in AboutView.body except the outer .frame(width: 460)/.background/Button("Done")
    // i.e. hero image, logo lockup, tagline, version text, credit text, license text
}

struct AboutView: View {           // standalone window, unchanged behavior
    let onDone: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            AboutContent()
            Button("Done") { onDone() }...
        }
        .padding(24).frame(width: 460).background(palette.background)...
    }
}

struct AboutPaneContent: View {    // embedded in General's NavigationStack
    var body: some View {
        AboutContent()
            .padding(24)
            .frame(maxWidth: .infinity)
    }
}
```
The color `Palette` (light/dark background/primary/secondary/pill) and `brandBlue` move to wherever
`AboutContent` lives so both wrappers can use them. `AboutWindowController` is untouched — the
right-click menu's "About TimeTug" still opens the same standalone window.

## Software Update sub-page

No new code beyond what's in the Navigation section above: `UpdatesSection` moves from the General hub
`Form` into the pushed sub-page's own `Form`. The section's internals (status line, Check for Updates
button, Automatic/Beta toggles, `settingsHighlight` ids) are unchanged.

## Appearance pane (new file `AppearancePane.swift`)

Extracted from `GeneralPane`'s current Appearance `Section`, restructured as three tappable-tile groups
inside a `Form`. `AppearanceTile` and `DiagonalHalf` move here from `GeneralPane.swift` (they're only
used by this pane now).

### Menu Bar Text tiles (new: `MenuBarModeTile`)
Three tiles, one per `MenuBarDisplayMode` case, replacing the current `Picker`:
- A small rounded-rect "menu bar" mockup (dark bar, ~140×28pt) containing the real `MenuBarTemplate`
  image (tinted white, same asset the actual status item uses) plus representative sample text:
  - Icon only: icon alone
  - Next meeting: icon + "Team Sync"
  - Countdown only: icon + "12m"
- Selection affordance matches `AppearanceTile`: accent-colored border when selected, plain border
  otherwise, tap to select, `.accessibilityLabel`/`.accessibilityAddTraits(.isSelected)`.
- Same `settingsHighlight("menu-bar-text", ...)` id as today, applied to the tile row.
- Sample text is illustrative only — not computed from any real event.

### Popup Cards tiles (new: `PopupCardStyleTile`)
Three tiles (or two, per `PopupCardStyle.available`), one per style, replacing the current `Picker`:
- A small card mockup (~90×54pt) using that style's actual fill so the preview isn't just an
  approximation: `.ultraThinMaterial` for Frosted, a plain opaque brand-color fill for Solid, and for
  Glass, `.ultraThinMaterial` as a stand-in (matching what `DropdownView` already falls back to when
  Liquid Glass isn't available) rather than invoking `.glassEffect` at tile scale — avoids coupling this
  preview to `CardChrome`/glass-effect behavior at a size it wasn't designed for.
- Sample content inside the mock card: one line of placeholder event text ("Team Sync · 10:00 AM").
- Same selection affordance and `settingsHighlight("popup-card-style", ...)` id as today.
- Caption below keeps today's conditional text ("Glass uses the system's Liquid Glass..." /
  "Frosted is translucent; Solid is opaque.").

### Light / Dark / Auto tiles
Reuses `AppearanceTile` as-is (already close to System Settings' own mini-window swatches). Tiles grow
slightly (e.g. 72×50 instead of 64×44) to give the now-dedicated page appropriate visual weight; no
behavior change.

### Pane layout
```swift
struct AppearancePane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var navigation: SettingsNavigation
    var body: some View {
        Form {
            Section("Menu Bar Text") { /* three MenuBarModeTile */ ; caption }
            Section("Popup Cards") { /* PopupCardStyleTile row */ ; caption }
            Section("Light, Dark, or Auto") { /* three AppearanceTile, enlarged */ ; caption }
        }
        .formStyle(.grouped)
    }
}
```

## Out of scope

- Accent-color customization (a user-selectable color that re-tints popup cards/menu bar/highlights
  app-wide) — explicitly declined; popup card style stays limited to Glass/Frosted/Solid.
- The menu bar glyph's own legibility at 16–22pt (the dog-face-holding-a-clock template icon collapsing
  into a blob at status-item size) — flagged separately as its own follow-up design, unrelated to this
  settings-layout work.
- Cross-pane browser-style back/forward history (Safari-style forward stack) — not requested; a plain
  `NavigationStack` back button covers the two sub-pages.
- Changing what "About" shows on the right-click menu — that continues to open the existing standalone
  `AboutWindowController` window unchanged.

## Testing

- `SettingsSearchTests.swift`: update/extend assertions for the three search items whose `pane` moves to
  `.appearance`, and add a case confirming a "beta updates" search reveal leaves `generalPath ==
  [.softwareUpdate]`.
- Manual verification (SwiftUI view logic, no unit-testable behavior beyond search/reveal):
  - General hub shows About and Software Update rows; tapping each pushes the right sub-page with a
    working back button.
  - Searching "beta" from the sidebar search reveals the toggle inside the Software Update sub-page
    (not just the General pane).
  - Appearance appears in the sidebar between General and Accounts; all three tile groups render and
    persist selection the same way the old Pickers did (same `SettingsStore` keys, unchanged).
  - Right-click menu bar icon → "About TimeTug" still opens the standalone window, unaffected by the
    embedded About page.
  - Light and dark mode, and VoiceOver labels on the new tiles (menu bar and popup card tiles need the
    same accessibility treatment `AppearanceTile` already has).
