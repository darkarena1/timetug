import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var navigation: SettingsNavigation
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    /// Set while we programmatically revert `launchAtLogin`, so the resulting
    /// `.onChange` doesn't try to register/unregister again.
    @State private var isReverting = false

    var body: some View {
        Form {
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
            Section("Menu bar") {
                Picker(SettingsText.menuBarText, selection: $settings.menuBarMode) {
                    Text("Icon only").tag(MenuBarDisplayMode.iconOnly)
                    Text("Next meeting").tag(MenuBarDisplayMode.nextMeeting)
                    Text("Countdown only").tag(MenuBarDisplayMode.countdown)
                }
                .settingsHighlight("menu-bar-text", navigation: navigation)
            }
            Section(SettingsText.appearance) {
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
                VStack(alignment: .leading, spacing: 4) {
                    Picker(SettingsText.popupCards, selection: $settings.popupCardStyle) {
                        ForEach(PopupCardStyle.available, id: \.self) { Text($0.title).tag($0) }
                    }
                    .settingsHighlight("popup-card-style", navigation: navigation)
                    Text(PopupCardStyle.available.contains(.glass)
                         ? "Glass uses the system's Liquid Glass. Frosted and Solid work everywhere."
                         : "Frosted is translucent; Solid is opaque.")
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

/// A selectable miniature window preview, like System Settings > Appearance.
private struct AppearanceTile: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                preview
                    .frame(width: 64, height: 44)
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
