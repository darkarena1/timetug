import SwiftUI

struct AppearancePane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        Form {
            Section(SettingsText.menuBarText) {
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
            Section(SettingsText.popupCards) {
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

/// A selectable miniature menu bar preview: the `clock` SF Symbol (as `StatusItemController` draws
/// it) plus sample text for `mode`, so people can see what each Menu Bar Text option actually looks
/// like before picking it.
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
        .accessibilityLabel("\(mode.title) menu bar text")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var preview: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock")
                .resizable()
                .frame(width: 14, height: 14)
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

    /// Illustrative only — not a real event. Matches `TimeFormatting.statusTitle`'s real format:
    /// next-meeting combines title and remaining time; countdown shows the remaining time alone.
    private var sampleText: String? {
        switch mode {
        case .iconOnly: nil
        case .nextMeeting: "Team Sync · 12m"
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
        .accessibilityLabel("\(style.title) popup cards")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Uses the real `CardSurface` modifier — the same glass/frosted/solid materials the popup itself
    /// renders — rather than an approximation, so the picker shows exactly what each style looks like.
    @ViewBuilder private var preview: some View {
        ZStack(alignment: .leading) {
            Color.clear.modifier(CardSurface(style: style, isNext: false, palette: palette, strongBorder: false))
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
