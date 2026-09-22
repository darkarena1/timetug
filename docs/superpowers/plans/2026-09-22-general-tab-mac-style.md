# General Settings Tab: macOS System Settings Styling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the General settings tab into a macOS-System-Settings-style hub (About and Software
Update as drill-down sub-pages with a standard back button), promote Appearance to its own top-level
sidebar pane, and replace its three Pickers with tappable preview tiles.

**Architecture:** `GeneralPane` becomes a `NavigationStack` wrapping a hub `Form` plus two
`.navigationDestination` cases (`GeneralDestination.about`, `.softwareUpdate`). A new `AppearancePane`
becomes a sibling of `GeneralPane` selected via a new `SettingsPane.appearance` sidebar case. `AboutView`
is split so its branding content is shared between the standalone About window and the new embedded
About sub-page.

**Tech Stack:** Swift 5, SwiftUI, XCTest, XcodeGen-generated Xcode project.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-09-22-general-tab-mac-style-design.md` — follow it exactly; this
  plan implements it task-by-task.
- No accent-color picker; popup card style stays limited to Glass/Frosted/Solid (per spec "Out of
  scope").
- No custom back/forward history stack — `NavigationStack`'s default back button only.
- Right-click menu bar "About TimeTug" must keep opening the existing standalone `AboutWindowController`
  window, unchanged.
- Every `SettingsStore`-backed value keeps its existing `UserDefaults` key — this is a UI restructuring,
  not a data migration. Do not rename `menuBarMode.v1`, `appearanceMode.v1`, or `popupCardStyle.v1`.
- Build command: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination
  'platform=macOS' build`
- App test command: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination
  'platform=macOS' test`
- If `Apps/macOS/project.yml` is ever edited, re-run `xcodegen generate --spec Apps/macOS/project.yml`
  and then `git checkout Apps/macOS/Sources/Info.plist Apps/macOS/Widgets/Info.plist` (xcodegen rewrites
  those two files). No task in this plan edits `project.yml`, so this shouldn't come up, but don't run
  `xcodegen generate` speculatively.
- Manual verification checklist: `docs/manual-tests/macos-checklist.md` (add an entry for this feature
  per Task 6).

---

### Task 1: Extract `SettingsRowIcon` from `PaneIcon`

Small prep refactor: the new "Software Update" row inside `GeneralPane` (Task 5) needs an
icon-in-colored-square exactly like the sidebar's `PaneIcon`, but for an ad hoc SF Symbol/color pair
that isn't a `SettingsPane`. Extract the square-icon rendering into a reusable `SettingsRowIcon`, with
`PaneIcon` becoming a thin wrapper over it. No behavior change.

**Files:**
- Modify: `Apps/macOS/Sources/PaneIcon.swift`

**Interfaces:**
- Produces: `SettingsRowIcon(systemImage: String, color: Color)` — a `View`, usable by any settings row
  that needs a colored-square icon without going through `SettingsPane`.

- [ ] **Step 1: Replace the file contents**

Replace all of `Apps/macOS/Sources/PaneIcon.swift` with:

```swift
import SwiftUI

/// System Settings-style icon: a white glyph on a colored rounded square.
struct SettingsRowIcon: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(color, in: RoundedRectangle(cornerRadius: 5.5, style: .continuous))
    }
}

/// A sidebar pane's icon, drawn with `SettingsRowIcon`.
struct PaneIcon: View {
    let pane: SettingsPane

    var body: some View {
        SettingsRowIcon(systemImage: pane.systemImage, color: pane.iconColor)
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`. `PaneIcon` is used unchanged elsewhere (`SettingsView.swift`), so this
is a pure refactor with no visible change — no manual verification needed beyond the build passing.

- [ ] **Step 3: Commit**

```bash
git add Apps/macOS/Sources/PaneIcon.swift
git commit -m "refactor: extract SettingsRowIcon from PaneIcon"
```

---

### Task 2: Add the Appearance pane

Adds `SettingsPane.appearance`, a new `AppearancePane.swift` with tappable preview tiles for Menu Bar
Text, Popup Cards, and Light/Dark/Auto (replacing the Pickers currently in `GeneralPane`'s Appearance
section), wires the new pane into `SettingsView`, and repoints the three affected search-catalog entries.
`GeneralPane`'s old Appearance `Section` is deleted here (its replacement lives in `AppearancePane` now);
`GeneralPane`'s hub/sub-page restructuring happens later, in Task 5 — this task only removes the
Appearance section, it does not touch the rest of `GeneralPane`.

**Files:**
- Modify: `Apps/macOS/Sources/SettingsNavigation.swift` (add `.appearance` case)
- Modify: `Apps/macOS/Sources/SettingsStore.swift` (add `MenuBarDisplayMode.title`)
- Create: `Apps/macOS/Sources/AppearancePane.swift`
- Modify: `Apps/macOS/Sources/GeneralPane.swift` (delete the Appearance section and now-unused helpers)
- Modify: `Apps/macOS/Sources/SettingsView.swift` (wire the new pane into `detail`)
- Modify: `Apps/macOS/Sources/SettingsSearch.swift` (repoint 3 catalog entries)
- Test: `Apps/macOS/Tests/SettingsSearchTests.swift`

**Interfaces:**
- Consumes: `SettingsStore.menuBarMode: MenuBarDisplayMode`, `.popupCardStyle: PopupCardStyle`,
  `.appearanceMode: AppearanceMode` (all existing, unchanged); `SettingsNavigation.settingsHighlight(_:navigation:)`
  (existing `View` extension in `SettingsNavigation.swift`); `PopupPalette(_ scheme: ColorScheme)` with
  members `cardFill, cardBorder, primary, secondary, blue, ...` (existing, `PopupPalette.swift`).
- Produces: `SettingsPane.appearance` case; `AppearancePane: View` with
  `init(settings: SettingsStore, navigation: SettingsNavigation)`; `MenuBarDisplayMode.title: String`.

- [ ] **Step 1: Write the failing test for the new pane's position and title**

In `Apps/macOS/Tests/SettingsSearchTests.swift`, replace `testPaneOrderAndTitles`:

```swift
    func testPaneOrderAndTitles() {
        XCTAssertEqual(SettingsPane.allCases, [.general, .appearance, .accounts, .calendars, .tugRules])
        XCTAssertEqual(SettingsPane.allCases.map(\.title),
                       ["General", "Appearance", "Accounts", "Calendars", "Tug Rules"])
    }
```

- [ ] **Step 2: Write the failing tests for the relocated search entries**

Replace `testAppearanceFoundByDarkAndTheme` and `testPopupCardStyleFoundByGlassAndFrosted`:

```swift
    func testAppearanceFoundByDarkAndTheme() {
        for query in ["dark", "theme"] {
            let hit = SettingsSearch.results(for: query, calendars: []).first { $0.id == "appearance" }
            XCTAssertEqual(hit?.pane, .appearance, query)
        }
    }
```

```swift
    func testPopupCardStyleFoundByGlassAndFrosted() {
        for query in ["glass", "frosted", "popup cards"] {
            let hit = SettingsSearch.results(for: query, calendars: []).first { $0.id == "popup-card-style" }
            XCTAssertEqual(hit?.pane, .appearance, query)
            XCTAssertEqual(hit?.title, "Popup cards")
        }
    }
```

Replace `testGeneralItemsLiveInGeneral` (drop `menu-bar-text`, which is moving) and add a new test for the
moved items:

```swift
    func testGeneralItemsLiveInGeneral() {
        XCTAssertEqual(SettingsSearch.catalog.first { $0.id == "launch-at-login" }?.pane, .general)
    }

    func testAppearanceItemsLiveInAppearance() {
        for id in ["appearance", "popup-card-style", "menu-bar-text"] {
            XCTAssertEqual(SettingsSearch.catalog.first { $0.id == id }?.pane, .appearance, id)
        }
    }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test -only-testing:TimeTugTests/SettingsSearchTests`
Expected: FAIL — `SettingsPane` has no `.appearance` case yet (compile error), and the pane/order
assertions don't match today's values.

- [ ] **Step 4: Add the `.appearance` case to `SettingsPane`**

In `Apps/macOS/Sources/SettingsNavigation.swift`, replace the `SettingsPane` enum:

```swift
enum SettingsPane: String, CaseIterable, Hashable, Identifiable {
    case general, appearance, accounts, calendars, tugRules

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .accounts: "Accounts"
        case .calendars: "Calendars"
        case .tugRules: "Tug Rules"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "circle.righthalf.filled"
        case .accounts: "person.crop.circle"
        case .calendars: "calendar"
        case .tugRules: "bolt.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .general: Color.gray
        case .appearance: Color(white: 0.3)
        case .accounts: Color(red: 0.20, green: 0.70, blue: 0.40)
        case .calendars: Color(red: 0.18, green: 0.48, blue: 0.96)
        case .tugRules: Color(red: 1.0, green: 0.62, blue: 0.10)
        }
    }
}
```

(Only the enum changes in this step — the rest of the file, `SettingsNavigation`, `SettingsHighlight`,
and the `settingsHighlight` extension, is untouched here; `SettingsNavigation` itself is extended in
Task 4.)

- [ ] **Step 5: Add `MenuBarDisplayMode.title`**

In `Apps/macOS/Sources/SettingsStore.swift`, replace:

```swift
enum MenuBarDisplayMode: String, CaseIterable, Codable {
    case iconOnly, nextMeeting, countdown
}
```

with:

```swift
enum MenuBarDisplayMode: String, CaseIterable, Codable {
    case iconOnly, nextMeeting, countdown

    var title: String {
        switch self {
        case .iconOnly: "Icon only"
        case .nextMeeting: "Next meeting"
        case .countdown: "Countdown only"
        }
    }
}
```

- [ ] **Step 6: Create `AppearancePane.swift`**

Create `Apps/macOS/Sources/AppearancePane.swift`:

```swift
import SwiftUI

struct AppearancePane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        Form {
            Section("Menu Bar Text") {
                VStack(spacing: 8) {
                    HStack(spacing: 20) {
                        ForEach(MenuBarDisplayMode.allCases, id: \.self) { mode in
                            MenuBarModeTile(mode: mode, isSelected: settings.menuBarMode == mode) {
                                settings.menuBarMode = mode
                            }
                        }
                    }
                    .settingsHighlight("menu-bar-text", navigation: navigation)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            Section("Popup Cards") {
                VStack(spacing: 8) {
                    HStack(spacing: 20) {
                        ForEach(PopupCardStyle.available, id: \.self) { style in
                            PopupCardStyleTile(style: style, isSelected: settings.popupCardStyle == style) {
                                settings.popupCardStyle = style
                            }
                        }
                    }
                    .settingsHighlight("popup-card-style", navigation: navigation)
                    Text(PopupCardStyle.available.contains(.glass)
                         ? "Glass uses the system's Liquid Glass. Frosted and Solid work everywhere."
                         : "Frosted is translucent; Solid is opaque.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            Section("Light, Dark, or Auto") {
                VStack(spacing: 8) {
                    HStack(spacing: 20) {
                        ForEach([AppearanceMode.light, .dark, .auto], id: \.self) { mode in
                            AppearanceTile(mode: mode, isSelected: settings.appearanceMode == mode) {
                                settings.appearanceMode = mode
                            }
                        }
                    }
                    .settingsHighlight("appearance", navigation: navigation)
                    Text("Auto matches your Mac's appearance.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }
}

/// A selectable miniature menu bar preview: the real `MenuBarTemplate` glyph plus sample text for
/// `mode`, so people can see what each Menu Bar Text option actually looks like before picking it.
private struct MenuBarModeTile: View {
    let mode: MenuBarDisplayMode
    let isSelected: Bool
    let action: () -> Void

    private static let barColor = Color(white: 0.14)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                preview
                    .frame(width: 140, height: 28)
                    .background(Self.barColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.15),
                                          lineWidth: isSelected ? 3 : 1)
                    )
                Text(mode.title).font(.callout)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var preview: some View {
        HStack(spacing: 5) {
            Image("MenuBarTemplate")
                .renderingMode(.template)
                .resizable()
                .frame(width: 16, height: 16)
                .foregroundStyle(.white)
            if let text = sampleText {
                Text(text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
    }

    /// Illustrative only — not a real event.
    private var sampleText: String? {
        switch mode {
        case .iconOnly: nil
        case .nextMeeting: "Team Sync"
        case .countdown: "12m"
        }
    }
}

/// A selectable miniature popup-card preview using `style`'s actual fill/material, so people can see
/// what each Popup Cards option actually looks like before picking it.
private struct PopupCardStyleTile: View {
    let style: PopupCardStyle
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    private var palette: PopupPalette { PopupPalette(scheme) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                preview
                    .frame(width: 96, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.15),
                                          lineWidth: isSelected ? 3 : 1)
                    )
                Text(style.title).font(.callout)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var preview: some View {
        ZStack(alignment: .leading) {
            switch style {
            case .glass, .frosted:
                Rectangle().fill(.ultraThinMaterial)
            case .solid:
                Rectangle().fill(palette.cardFill)
            }
            Capsule().fill(palette.blue).frame(width: 3).padding(.vertical, 10).padding(.leading, 8)
            Text("Team Sync · 10:00 AM")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(style == .solid ? palette.primary : .primary)
                .lineLimit(1)
                .padding(.leading, 16)
                .padding(.trailing, 6)
        }
    }
}

/// A selectable miniature window preview, like System Settings > Appearance.
private struct AppearanceTile: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                preview
                    .frame(width: 72, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.2),
                                          lineWidth: isSelected ? 3 : 1)
                    )
                Text(mode.title).font(.callout)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityText: String {
        switch mode {
        case .light: "Light appearance"
        case .dark: "Dark appearance"
        case .auto: "Automatic appearance, matches the system"
        }
    }

    @ViewBuilder private var preview: some View {
        switch mode {
        case .light: window(background: Color(white: 0.95), bar: Color(white: 0.75))
        case .dark: window(background: Color(white: 0.16), bar: Color(white: 0.4))
        case .auto:
            ZStack {
                window(background: Color(white: 0.95), bar: Color(white: 0.75))
                window(background: Color(white: 0.16), bar: Color(white: 0.4))
                    .mask(DiagonalHalf())
            }
        }
    }

    private func window(background: Color, bar: Color) -> some View {
        ZStack(alignment: .topLeading) {
            background
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(bar).frame(width: 34, height: 5)
                Capsule().fill(bar).frame(width: 46, height: 5)
                Capsule().fill(bar).frame(width: 24, height: 5)
            }
            .padding(8)
        }
    }
}

/// The lower-right triangle of its bounds, splitting a tile diagonally.
private struct DiagonalHalf: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
```

- [ ] **Step 7: Delete the Appearance section and its helpers from `GeneralPane.swift`**

In `Apps/macOS/Sources/GeneralPane.swift`, delete the entire
`Section(SettingsText.appearance) { ... }` block (lines 54–87 in the current file — the block starting
`Section(SettingsText.appearance) {` and ending with the matching `}` right before the closing `}` of
the `Form`), and delete the two private types that block used, `AppearanceTile` (lines 100–158) and
`DiagonalHalf` (lines 160–170), which now live in `AppearancePane.swift`. Leave everything else in the
file (the `UpdatesSection`, `App`, and `Shortcut` sections, the `@State` properties, `.onAppear`) exactly
as-is — this file is restructured further in Task 5.

After this step, `GeneralPane.swift` should read:

```swift
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var updates: UpdateController
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    /// Set while we programmatically revert `launchAtLogin`, so the resulting
    /// `.onChange` doesn't try to register/unregister again.
    @State private var isReverting = false

    var body: some View {
        Form {
            UpdatesSection(updates: updates, navigation: navigation)
            Section("App") {
                Toggle(SettingsText.launchAtLogin, isOn: $launchAtLogin)
                    .settingsHighlight("launch-at-login", navigation: navigation)
                    .onChange(of: launchAtLogin) { _, enabled in
                        if isReverting {
                            isReverting = false
                            return
                        }
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            launchError = nil
                        } catch {
                            launchError = "Couldn't change launch at login: \(error.localizedDescription)"
                            let actual = SMAppService.mainApp.status == .enabled
                            if actual != launchAtLogin {
                                isReverting = true
                                launchAtLogin = actual
                            }
                        }
                    }
                if let launchError {
                    Text(launchError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            Section("Shortcut") {
                VStack(alignment: .leading, spacing: 4) {
                    KeyboardShortcuts.Recorder(SettingsText.popupShortcut, name: .togglePopup)
                        .settingsHighlight("popup-shortcut", navigation: navigation)
                    Text("Press a shortcut to show or hide the popup from anywhere. Click ✕ to clear it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            let actual = SMAppService.mainApp.status == .enabled
            if actual != launchAtLogin {
                isReverting = true
                launchAtLogin = actual
            }
        }
    }
}
```

- [ ] **Step 8: Wire `AppearancePane` into `SettingsView`**

In `Apps/macOS/Sources/SettingsView.swift`, in the `detail` switch, add a case right after `.general`:

```swift
        case .general:
            GeneralPane(settings: settings, navigation: navigation, updates: updates)
        case .appearance:
            AppearancePane(settings: settings, navigation: navigation)
        case .accounts:
```

- [ ] **Step 9: Repoint the three search-catalog entries**

In `Apps/macOS/Sources/SettingsSearch.swift`, change `pane: .general` to `pane: .appearance` on exactly
the `appearance`, `popup-card-style`, and `menu-bar-text` entries:

```swift
        .init(id: "appearance", title: SettingsText.appearance,
              keywords: ["theme", "light", "dark", "auto", "automatic", "mode", "dark mode", "color scheme"], pane: .appearance),
        .init(id: "popup-card-style", title: SettingsText.popupCards,
              keywords: ["glass", "frosted", "translucent", "solid", "bubbles", "cards", "style", "popup"], pane: .appearance),
        .init(id: "menu-bar-text", title: SettingsText.menuBarText,
              keywords: ["menu bar", "text", "next meeting", "countdown", "title", "next to the icon"], pane: .appearance),
```

Leave `software-update`, `automatic-updates`, `beta-updates`, `launch-at-login`, and `popup-shortcut` at
`pane: .general` — unchanged.

- [ ] **Step 10: Run the tests to verify they pass**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test -only-testing:TimeTugTests/SettingsSearchTests`
Expected: all `SettingsSearchTests` pass, including the ones edited in Steps 1–2.

- [ ] **Step 11: Build the whole app target**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 12: Manual verification**

Run the app (or use the `run` skill if available) and open Settings:
- "Appearance" appears in the sidebar between "General" and "Accounts", with a dark half-filled-circle
  icon.
- Clicking it shows three sections: Menu Bar Text (3 tiles), Popup Cards (2 or 3 tiles depending on OS),
  Light/Dark/Auto (3 tiles).
- Tapping a Menu Bar Text tile changes the real menu bar text immediately (check the actual menu bar).
- Tapping a Popup Cards tile changes the real popup's card style (open the popup to confirm).
- Tapping a Light/Dark/Auto tile changes the app's appearance immediately.
- Searching "dark" or "popup cards" from the sidebar search reveals the control on the new Appearance
  pane (not General).
- General's Appearance section is gone; App and Shortcut sections are still there, unchanged.

- [ ] **Step 13: Commit**

```bash
git add Apps/macOS/Sources/SettingsNavigation.swift Apps/macOS/Sources/SettingsStore.swift \
        Apps/macOS/Sources/AppearancePane.swift Apps/macOS/Sources/GeneralPane.swift \
        Apps/macOS/Sources/SettingsView.swift Apps/macOS/Sources/SettingsSearch.swift \
        Apps/macOS/Tests/SettingsSearchTests.swift
git commit -m "feat: promote Appearance to its own settings pane with preview tiles"
```

---

### Task 3: Share About's branding content between the window and a future embedded page

Splits `AboutView` into a shared `AboutContent` (hero image, logo, tagline, version, credit, license)
plus a small `AboutPalette`, with `AboutView` (the standalone window) now composed from `AboutContent`,
and a new `AboutPaneContent` for later embedding in General's sub-page (Task 5). No behavior change to
the standalone window.

**Files:**
- Modify: `Apps/macOS/Sources/AboutView.swift`
- Modify: `Apps/macOS/Tests/AboutViewTests.swift`

**Interfaces:**
- Produces: `AboutContent: View` (no init args); `AboutContent.creditText: String`;
  `AboutContent.versionText: String?`; `AboutPaneContent: View` (no init args, wraps `AboutContent` for
  embedding). `AboutView(onDone: () -> Void)` keeps its existing signature.

- [ ] **Step 1: Write the failing test**

In `Apps/macOS/Tests/AboutViewTests.swift`, change the reference from `AboutView.creditText` to
`AboutContent.creditText` (the statics move to the shared content view):

```swift
import XCTest
@testable import TimeTug

final class AboutViewTests: XCTestCase {
    func testCreditNamesTheAuthor() {
        XCTAssertTrue(AboutContent.creditText.contains("Scott O"))
        XCTAssertTrue(AboutContent.creditText.hasPrefix("Created by"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test -only-testing:TimeTugTests/AboutViewTests`
Expected: FAIL — compile error, `AboutContent` doesn't exist yet.

- [ ] **Step 3: Replace `AboutView.swift`**

Replace all of `Apps/macOS/Sources/AboutView.swift` with:

```swift
import SwiftUI

/// Shared branding content for the About window and the About page embedded in General settings: hero
/// image, logo lockup, tagline, version, credit, and license line.
struct AboutContent: View {
    @Environment(\.colorScheme) private var colorScheme
    private var palette: AboutPalette { colorScheme == .dark ? .dark : .light }

    var body: some View {
        VStack(spacing: 14) {
            Image("AboutHero")
                .resizable()
                .aspectRatio(928.0 / 445.0, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .accessibilityHidden(true)
            // The lockup image already carries the name and tagline, so expose
            // them to VoiceOver as one label instead of showing duplicate text.
            Image("LogoLockup")
                .resizable()
                .aspectRatio(2, contentMode: .fit)
                .frame(width: 220)
                .accessibilityHidden(true)
                .overlay(
                    Color.clear
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("TimeTug. A tug when time needs your attention.")
                )
            Text("Never hyperfocus through another meeting.")
                .font(.callout)
                .foregroundStyle(palette.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Capsule().fill(palette.pill))
            if let version = AboutContent.versionText {
                Text(version).font(.callout).foregroundStyle(palette.secondary)
            }
            Text(AboutContent.creditText)
                .font(.callout.weight(.medium)).foregroundStyle(palette.primary)
            Text("Source available under MIT with the Commons Clause.")
                .font(.footnote).foregroundStyle(palette.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("About TimeTug")
    }

    /// Author credit shown in the About window (also in the README).
    static let creditText = "Created by Scott O\u{2019}Bryan"

    /// "Version X (build Y)" from the bundle; nil when the version is missing.
    static var versionText: String? {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String, !version.isEmpty else { return nil }
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty else { return "Version \(version)" }
        return "Version \(version) (build \(build))"
    }
}

/// Colors for `AboutContent`, shared by the standalone window and the embedded About page.
private struct AboutPalette {
    let background, primary, secondary, pill: Color
    static let light = AboutPalette(
        background: Color(red: 1.0, green: 0.973, blue: 0.94),
        primary: Color(red: 0.11, green: 0.16, blue: 0.33),
        secondary: Color(red: 0.36, green: 0.42, blue: 0.55),
        pill: Color(red: 0.87, green: 0.92, blue: 1.0))
    static let dark = AboutPalette(
        background: Color(red: 0.07, green: 0.10, blue: 0.19),
        primary: Color(red: 0.94, green: 0.96, blue: 1.0),
        secondary: Color(red: 0.65, green: 0.71, blue: 0.83),
        pill: Color(red: 0.16, green: 0.24, blue: 0.42))
}

/// The standalone About window's content, opened from the right-click menu bar menu (unchanged
/// behavior). Follows `NSApp.appearance` (Light/Dark/Auto) via `AboutWindowController`.
struct AboutView: View {
    let onDone: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private static let brandBlue = Color(red: 0.18, green: 0.48, blue: 0.96)
    private var palette: AboutPalette { colorScheme == .dark ? .dark : .light }

    var body: some View {
        VStack(spacing: 14) {
            AboutContent()
            Button("Done") { onDone() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Self.brandBlue)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 460)
        .background(palette.background)
    }
}

/// The About page embedded in General settings (reached via the "About" row). No window chrome or Done
/// button — the settings window's own back button dismisses it.
struct AboutPaneContent: View {
    var body: some View {
        AboutContent()
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test -only-testing:TimeTugTests/AboutViewTests`
Expected: PASS.

- [ ] **Step 5: Build the whole app target**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`. `AboutPaneContent` is unused until Task 5 — that's expected, not an
error (Swift doesn't warn on unused top-level types).

- [ ] **Step 6: Manual verification**

Right-click the menu bar icon → "About TimeTug" still opens the same standalone window, pixel-identical
to before (hero image, logo, tagline, version, credit, license, Done button), in both light and dark
mode.

- [ ] **Step 7: Commit**

```bash
git add Apps/macOS/Sources/AboutView.swift Apps/macOS/Tests/AboutViewTests.swift
git commit -m "refactor: split About's branding content out of the standalone window"
```

---

### Task 4: Add `GeneralDestination` and search-reveal support for General's sub-pages

Adds the destination enum and the `generalPath` navigation state that `GeneralPane` (Task 5) will bind
its `NavigationStack` to, and extends `SettingsNavigation.reveal(_:)` so searching for a Software-Update
setting also drills into that sub-page (not just selects the General pane).

**Files:**
- Modify: `Apps/macOS/Sources/SettingsNavigation.swift`
- Test: `Apps/macOS/Tests/SettingsSearchTests.swift`

**Interfaces:**
- Consumes: `SettingsSearchItem` (existing, `id: String`, `pane: SettingsPane`, from `SettingsSearch.swift`).
- Produces: `enum GeneralDestination: Hashable { case about, softwareUpdate }`;
  `SettingsNavigation.generalPath: [GeneralDestination]` (published); `reveal(_:)` now also updates
  `generalPath`.

- [ ] **Step 1: Write the failing tests**

Add to `Apps/macOS/Tests/SettingsSearchTests.swift`:

```swift
    @MainActor func testRevealingASoftwareUpdateItemDrillsIntoItsSubPage() {
        let navigation = SettingsNavigation()
        let item = SettingsSearch.catalog.first { $0.id == "beta-updates" }!
        navigation.reveal(item)
        XCTAssertEqual(navigation.pane, .general)
        XCTAssertEqual(navigation.generalPath, [.softwareUpdate])
    }

    @MainActor func testRevealingANonSoftwareUpdateItemPopsToTheGeneralHub() {
        let navigation = SettingsNavigation()
        navigation.generalPath = [.softwareUpdate]
        let item = SettingsSearch.catalog.first { $0.id == "launch-at-login" }!
        navigation.reveal(item)
        XCTAssertEqual(navigation.generalPath, [])
    }

    @MainActor func testRevealingAnAppearanceItemAlsoPopsGeneralToItsHub() {
        let navigation = SettingsNavigation()
        navigation.generalPath = [.softwareUpdate]
        let item = SettingsSearch.catalog.first { $0.id == "appearance" }!
        navigation.reveal(item)
        XCTAssertEqual(navigation.pane, .appearance)
        XCTAssertEqual(navigation.generalPath, [])
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test -only-testing:TimeTugTests/SettingsSearchTests`
Expected: FAIL — compile error, `GeneralDestination` and `generalPath` don't exist yet.

- [ ] **Step 3: Add `GeneralDestination` and `generalPath`, and extend `reveal(_:)`**

In `Apps/macOS/Sources/SettingsNavigation.swift`, add the new enum after the `SettingsPane` enum, and
update the `SettingsNavigation` class:

```swift
/// A drill-down destination reachable from the General settings hub.
enum GeneralDestination: Hashable {
    case about
    case softwareUpdate
}

@MainActor
final class SettingsNavigation: ObservableObject {
    static let highlightDuration: Duration = .milliseconds(1500)

    @Published var pane: SettingsPane = .general
    @Published var generalPath: [GeneralDestination] = []
    @Published var highlightedID: String?
    private var clearTask: Task<Void, Never>?

    /// Switches to the item's pane and briefly highlights its control. If the item lives inside a
    /// General sub-page, also drills into it; otherwise pops General back to its hub so the highlighted
    /// control on the hub is actually visible.
    func reveal(_ item: SettingsSearchItem) {
        pane = item.pane
        generalPath = Self.generalDestination(for: item.id).map { [$0] } ?? []
        highlightedID = item.id
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: Self.highlightDuration)
            guard !Task.isCancelled else { return }
            self?.highlightedID = nil
        }
    }

    private static func generalDestination(for id: String) -> GeneralDestination? {
        switch id {
        case "software-update", "automatic-updates", "beta-updates": .softwareUpdate
        default: nil
        }
    }
}
```

(Leave `SettingsHighlight` and the `settingsHighlight` extension below it unchanged.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test -only-testing:TimeTugTests/SettingsSearchTests`
Expected: all pass, including the three new tests and `testDefaultPaneIsGeneral`.

- [ ] **Step 5: Build the whole app target**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`. `generalPath` isn't read by any view yet — expected until Task 5.

- [ ] **Step 6: Commit**

```bash
git add Apps/macOS/Sources/SettingsNavigation.swift Apps/macOS/Tests/SettingsSearchTests.swift
git commit -m "feat: add GeneralDestination and search-reveal support for General sub-pages"
```

---

### Task 5: Restructure `GeneralPane` into a hub with About and Software Update sub-pages

The main event: `GeneralPane` becomes a `NavigationStack` bound to `navigation.generalPath`. Its hub page
gets two new rows — About (pushes `AboutPaneContent`) and Software Update (pushes the relocated
`UpdatesSection`) — each with a standard SwiftUI back button once pushed. App and Shortcut sections stay
on the hub, unchanged.

**Files:**
- Modify: `Apps/macOS/Sources/GeneralPane.swift`

**Interfaces:**
- Consumes: `GeneralDestination` (Task 4), `AboutPaneContent` (Task 3), `SettingsRowIcon` (Task 1),
  `UpdatesSection(updates:navigation:)` (existing, unchanged), `UpdateController.currentVersion: String`
  (existing — confirm in `Apps/macOS/Sources/UpdateController.swift` if unsure of the exact property
  name before using it).

- [ ] **Step 1: Replace `GeneralPane.swift`**

Replace all of `Apps/macOS/Sources/GeneralPane.swift` with:

```swift
import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var updates: UpdateController
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    /// Set while we programmatically revert `launchAtLogin`, so the resulting
    /// `.onChange` doesn't try to register/unregister again.
    @State private var isReverting = false

    var body: some View {
        NavigationStack(path: $navigation.generalPath) {
            hub
                .navigationDestination(for: GeneralDestination.self) { destination in
                    switch destination {
                    case .about:
                        Form { AboutPaneContent() }
                            .formStyle(.grouped)
                            .navigationTitle("About")
                    case .softwareUpdate:
                        Form { UpdatesSection(updates: updates, navigation: navigation) }
                            .formStyle(.grouped)
                            .navigationTitle("Software Update")
                    }
                }
        }
    }

    private var hub: some View {
        Form {
            Section {
                NavigationLink(value: GeneralDestination.about) {
                    Label {
                        Text("About")
                    } icon: {
                        Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                            .resizable()
                            .frame(width: 22, height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))
                    }
                }
                NavigationLink(value: GeneralDestination.softwareUpdate) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Software Update")
                            Text("TimeTug \(updates.currentVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        SettingsRowIcon(systemImage: "arrow.triangle.2.circlepath", color: .blue)
                    }
                }
            }
            Section("App") {
                Toggle(SettingsText.launchAtLogin, isOn: $launchAtLogin)
                    .settingsHighlight("launch-at-login", navigation: navigation)
                    .onChange(of: launchAtLogin) { _, enabled in
                        if isReverting {
                            isReverting = false
                            return
                        }
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            launchError = nil
                        } catch {
                            launchError = "Couldn't change launch at login: \(error.localizedDescription)"
                            let actual = SMAppService.mainApp.status == .enabled
                            if actual != launchAtLogin {
                                isReverting = true
                                launchAtLogin = actual
                            }
                        }
                    }
                if let launchError {
                    Text(launchError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            Section("Shortcut") {
                VStack(alignment: .leading, spacing: 4) {
                    KeyboardShortcuts.Recorder(SettingsText.popupShortcut, name: .togglePopup)
                        .settingsHighlight("popup-shortcut", navigation: navigation)
                    Text("Press a shortcut to show or hide the popup from anywhere. Click ✕ to clear it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            let actual = SMAppService.mainApp.status == .enabled
            if actual != launchAtLogin {
                isReverting = true
                launchAtLogin = actual
            }
        }
    }
}
```

`UpdateController.currentVersion: String` (declared in `Apps/macOS/Sources/UpdateController.swift:20`)
is confirmed correct for the `Text("TimeTug \(updates.currentVersion)")` line above — no need to
re-check it.

- [ ] **Step 2: Build**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run the full app test suite**

Run: `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test`
Expected: all tests pass, including every test touched in Tasks 2–4.

- [ ] **Step 4: Manual verification**

Open Settings on the General pane:
- Two rows at the top: "About" (app icon, no secondary text) and "Software Update" (refresh-icon square,
  secondary text "TimeTug <version>"), each with a trailing chevron.
- Tapping "About" pushes a page titled "About" with a working back button (toolbar chevron, and Cmd-[ /
  swipe-back if applicable) showing the full hero/logo/tagline/version/credit/license content.
- Tapping "Software Update" pushes a page titled "Software Update" with a working back button, showing
  the same status/Check-for-Updates/Automatic/Beta controls that used to be inline.
- App and Shortcut sections are still on the hub, working exactly as before (Launch at Login toggle,
  shortcut recorder).
- Search "beta" → selecting the result lands on the Software Update sub-page with the Beta toggle
  highlighted (not just the General hub).
- Search "startup" → selecting the result lands on the General hub with Launch at Login highlighted (if
  you were previously on the Software Update sub-page, confirm it pops back to the hub).
- Right-click the menu bar icon → "About TimeTug" still opens the separate standalone window, unaffected.

- [ ] **Step 5: Commit**

```bash
git add Apps/macOS/Sources/GeneralPane.swift
git commit -m "feat: restructure General into a hub with About and Software Update sub-pages"
```

---

### Task 6: Update the manual test checklist

Add an entry to the manual-tests checklist so this drill-down navigation and the new tiles get checked
on future manual QA passes, matching how other window/status-item behavior in this app is tracked.

**Files:**
- Modify: `docs/manual-tests/macos-checklist.md`

- [ ] **Step 1: Read the current checklist**

```bash
cat docs/manual-tests/macos-checklist.md
```

- [ ] **Step 2: Add a new checklist section**

Add a new section (matching the file's existing heading/list style) covering:
- Settings sidebar shows General, Appearance, Accounts, Calendars, Tug Rules in that order.
- General → About pushes the About sub-page with a working back button; content matches the standalone
  About window (right-click menu bar icon → About TimeTug).
- General → Software Update pushes the Software Update sub-page with a working back button; Check for
  Updates, Automatic, and Beta controls all work as before.
- Appearance pane: Menu Bar Text tiles change the real menu bar; Popup Cards tiles change the real
  popup's card style; Light/Dark/Auto tiles change the app's appearance. Verify in both light and dark
  system appearance.
- Sidebar search reveals controls correctly: a Software-Update-related query lands inside the Software
  Update sub-page (not just the General hub); an Appearance-related query lands on the Appearance pane.
- VoiceOver reads sensible labels for the new Menu Bar Text and Popup Cards tiles (selected state
  included).

- [ ] **Step 3: Commit**

```bash
git add docs/manual-tests/macos-checklist.md
git commit -m "docs: add manual checklist entries for the macOS-style General tab"
```

---

## Self-Review Notes

- **Spec coverage:** Navigation structure (Tasks 2, 4, 5), About sub-page sharing code with the
  standalone window (Task 3), Software Update sub-page (Task 5), Appearance pane with all three tile
  groups (Task 2), search-catalog repointing and reveal-through-sub-pages (Tasks 2, 4). Out-of-scope
  items (accent color, menu bar glyph legibility, browser-style history) are not implemented, matching
  the spec.
- **Placeholder scan:** No TBD/TODO. `UpdateController.currentVersion` was verified against the actual
  source (`UpdateController.swift:20`) before being used in Task 5, not guessed.
- **Type consistency:** `GeneralDestination` (Task 4) matches its use in `GeneralPane`'s
  `.navigationDestination(for:)` (Task 5). `SettingsRowIcon(systemImage:color:)` (Task 1) matches its use
  in `GeneralPane`'s Software Update row (Task 5). `AboutPaneContent` (Task 3) matches its use in
  `GeneralPane`'s About destination (Task 5). `MenuBarDisplayMode.title` (Task 2) matches its use in
  `MenuBarModeTile` (Task 2, same task).
- **Scope:** Six tasks, each independently buildable and testable, all serving the one spec. Not split
  further into separate plans — this is a single cohesive UI restructuring.
