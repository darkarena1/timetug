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
            Spacer(minLength: 0)
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
                    .frame(width: 140, height: 88)
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

    private var preview: some View {
        // Render at popup proportions, then shrink the whole scene so type, borders and radii
        // scale together. These examples never read the user's calendars or appointments.
        CardGroup(style: style) {
            VStack(spacing: 8) {
                sampleCard(title: "Team Sync", time: "10:00\nAM", details: "10:00 – 11:00 AM · Work", isNext: true)
                sampleCard(title: "Call Mom", time: "6:00\nPM", details: "6:00 – 7:00 PM · Personal", isNext: false)
            }
        }
        .padding(14)
        .frame(width: 280, height: 176)
        .background(Color(nsColor: .windowBackgroundColor))
        .scaleEffect(0.5)
        .frame(width: 140, height: 88)
        .accessibilityHidden(true)
    }

    private func sampleCard(title: String, time: String, details: String, isNext: Bool) -> some View {
        HStack(spacing: 8) {
            Text(time)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .multilineTextAlignment(.trailing)
                .foregroundStyle(style == .solid ? palette.secondary : .secondary)
                .frame(width: 36, alignment: .trailing)
            Capsule().fill(palette.blue).frame(width: 4, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(style == .solid ? palette.primary : .primary)
                    if isNext {
                        Text("in 15m")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.chipText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(palette.chipBackground, in: Capsule())
                    }
                }
                Text(details)
                    .font(.system(size: 12))
                    .foregroundStyle(style == .solid ? palette.secondary : .secondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .modifier(CardSurface(style: style, isNext: isNext, palette: palette, strongBorder: false))
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
                    .frame(width: 140, height: 88)
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
        ZStack {
            switch mode {
            case .light: desktop(isDark: false)
            case .dark: desktop(isDark: true)
            case .auto:
                desktop(isDark: false)
                desktop(isDark: true)
                    .mask(alignment: .trailing) {
                        Rectangle().frame(width: 70)
                    }
            }
        }
        .accessibilityHidden(true)
    }

    /// A decorative desktop, drawn in points so it stays crisp on every display.
    private func desktop(isDark: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: isDark
                           ? [Color(red: 0.25, green: 0.16, blue: 0.60), Color(red: 0.02, green: 0.05, blue: 0.19)]
                           : [Color(red: 0.65, green: 0.87, blue: 0.94), Color(red: 0.02, green: 0.32, blue: 0.65)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Path { path in
                path.move(to: CGPoint(x: -20, y: 84))
                path.addCurve(to: CGPoint(x: 160, y: -12),
                              control1: CGPoint(x: 30, y: -5), control2: CGPoint(x: 91, y: 66))
                path.addLine(to: CGPoint(x: 160, y: 35))
                path.addCurve(to: CGPoint(x: -20, y: 110),
                              control1: CGPoint(x: 60, y: 9), control2: CGPoint(x: 55, y: 108))
                path.closeSubpath()
            }
            .fill(LinearGradient(colors: [.cyan.opacity(isDark ? 0.55 : 0.85), .blue, Color(red: 0.07, green: 0.09, blue: 0.43)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            Path { path in
                path.move(to: CGPoint(x: -10, y: 78))
                path.addCurve(to: CGPoint(x: 150, y: 6),
                              control1: CGPoint(x: 42, y: 51), control2: CGPoint(x: 79, y: 57))
            }
            .stroke(LinearGradient(colors: [.white.opacity(0.05), .cyan.opacity(0.8), .white.opacity(0.15)],
                                   startPoint: .bottomLeading, endPoint: .topTrailing), lineWidth: 2)

            // Menu bar and small menu marks provide scale without any personal content.
            HStack(spacing: 4) {
                Image(systemName: "apple.logo").font(.system(size: 6))
                Capsule().frame(width: 13, height: 2)
                Capsule().frame(width: 9, height: 2)
                Spacer()
                Capsule().frame(width: 10, height: 2)
            }
            .foregroundStyle(isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.55))
            .padding(.horizontal, 7)
            .frame(height: 11)
            .background(isDark ? Color.black.opacity(0.25) : Color.white.opacity(0.45))

            // The foreground window extends past the thumbnail, like the system's previews.
            VStack(spacing: 0) {
                HStack(spacing: 5) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { color in
                        Circle().fill(color).frame(width: 7, height: 7)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 23)
                .background(isDark ? Color(white: 0.15) : Color(white: 0.94))
                Rectangle().fill(isDark ? Color(white: 0.07) : Color.white)
            }
            .frame(width: 115, height: 61)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(isDark ? 0.12 : 0.65)))
            .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
            .offset(x: 39, y: 49)

            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.0, green: 0.48, blue: 1.0)).frame(height: 11)
                Capsule().fill(.white.opacity(isDark ? 0.25 : 0.65)).frame(width: 42, height: 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(4)
            .frame(width: 73, height: 29)
            .background(isDark ? Color(red: 0.08, green: 0.10, blue: 0.30) : Color(red: 0.66, green: 0.84, blue: 0.96),
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(isDark ? 0.3 : 0.8)))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .offset(x: 6, y: 17)
        }
        .frame(width: 140, height: 88)
        .clipped()
    }
}
