import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private static let cream = Color(red: 1.0, green: 0.973, blue: 0.94)
    private static let navy = Color(red: 0.11, green: 0.16, blue: 0.33)
    private static let slate = Color(red: 0.36, green: 0.42, blue: 0.55)
    private static let paleBlue = Color(red: 0.87, green: 0.92, blue: 1.0)
    private static let brandBlue = Color(red: 0.18, green: 0.48, blue: 0.96)

    var body: some View {
        VStack(spacing: 14) {
            Image("AboutHero")
                .resizable()
                .aspectRatio(1.84, contentMode: .fill)
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
                .foregroundStyle(Self.navy)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Capsule().fill(Self.paleBlue))
            if let version = Self.versionText {
                Text(version).font(.callout).foregroundStyle(Self.slate)
            }
            Text("Released under the MIT License.")
                .font(.footnote).foregroundStyle(Self.slate)
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Self.brandBlue)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 460)
        .background(Self.cream)
        .preferredColorScheme(.light)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("About TimeTug")
    }

    /// "Version X (build Y)" from the bundle; nil when the version is missing.
    static var versionText: String? {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String, !version.isEmpty else { return nil }
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty else { return "Version \(version)" }
        return "Version \(version) (build \(build))"
    }
}
