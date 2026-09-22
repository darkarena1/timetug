import SwiftUI

struct AboutView: View {
    let onDone: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private struct Palette {
        let background, primary, secondary, pill: Color
        static let light = Palette(
            background: Color(red: 1.0, green: 0.973, blue: 0.94),
            primary: Color(red: 0.11, green: 0.16, blue: 0.33),
            secondary: Color(red: 0.36, green: 0.42, blue: 0.55),
            pill: Color(red: 0.87, green: 0.92, blue: 1.0))
        static let dark = Palette(
            background: Color(red: 0.07, green: 0.10, blue: 0.19),
            primary: Color(red: 0.94, green: 0.96, blue: 1.0),
            secondary: Color(red: 0.65, green: 0.71, blue: 0.83),
            pill: Color(red: 0.16, green: 0.24, blue: 0.42))
    }

    private static let brandBlue = Color(red: 0.18, green: 0.48, blue: 0.96)

    private var palette: Palette { colorScheme == .dark ? .dark : .light }

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
            if let version = Self.versionText {
                Text(version).font(.callout).foregroundStyle(palette.secondary)
            }
            Text(Self.creditText)
                .font(.callout.weight(.medium)).foregroundStyle(palette.primary)
            Text("Source available under MIT with the Commons Clause.")
                .font(.footnote).foregroundStyle(palette.secondary)
            Button("Done") { onDone() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Self.brandBlue)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 460)
        .background(palette.background)
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
