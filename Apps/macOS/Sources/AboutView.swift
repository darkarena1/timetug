import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 10) {
            Image("LogoLockup")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 235, height: 118)
                .accessibilityHidden(true)
            Text("TimeTug").font(.title.bold())
            if let version = Self.versionText {
                Text(version).font(.callout).foregroundStyle(.secondary)
            }
            Text("A tug when time needs your attention.")
                .multilineTextAlignment(.center)
            Text("Never hyperfocus through another meeting.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Released under the MIT License.")
                .font(.footnote).foregroundStyle(.secondary)
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .padding(.top, 6)
        }
        .padding(24)
        .frame(width: 360)
    }

    /// "Version X (build Y)" from the bundle; nil when the version is missing.
    static var versionText: String? {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String, !version.isEmpty else { return nil }
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty else { return "Version \(version)" }
        return "Version \(version) (build \(build))"
    }
}
