import SwiftUI

/// Software Update controls laid out like System Settings: status, Check for Updates, Automatic, Beta.
struct UpdatesSection: View {
    @ObservedObject var updates: UpdateController
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        Section("Software Update") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TimeTug \(updates.currentVersion)").font(.headline)
                    Text(lastChecked).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Button(SettingsText.checkForUpdates) { updates.checkForUpdates() }
            }
            .settingsHighlight("software-update", navigation: navigation)
            VStack(alignment: .leading, spacing: 4) {
                Toggle(SettingsText.automaticUpdates, isOn: $updates.automaticallyChecks)
                    .settingsHighlight("automatic-updates", navigation: navigation)
                Text("TimeTug checks for new versions in the background and asks before installing.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Toggle(SettingsText.betaUpdates, isOn: $updates.includeBetas)
                    .settingsHighlight("beta-updates", navigation: navigation)
                Text("Get early builds before they are released. Turning this off keeps a beta until the next full release replaces it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var lastChecked: String {
        guard let date = updates.lastCheckDate else { return "Not checked yet" }
        return "Last checked " + date.formatted(date: .abbreviated, time: .shortened)
    }
}
