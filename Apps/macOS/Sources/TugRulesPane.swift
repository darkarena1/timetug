import SwiftUI

struct TugRulesPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var navigation: SettingsNavigation
    let onTestTug: () -> Void

    var body: some View {
        Form {
            VStack(alignment: .leading, spacing: 4) {
                Picker(SettingsText.leadTime, selection: leadMinutes) {
                    ForEach(LeadTimeOptions.options(including: settings.takeover.leadTime)) { option in
                        Text(option.title).tag(option.minutes)
                    }
                }
                .pickerStyle(.menu)
                Text("How long before a meeting starts TimeTug tugs you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingsHighlight("lead-time", navigation: navigation)
            Toggle(SettingsText.videoLink, isOn: $settings.takeover.requireConferenceLink)
                .settingsHighlight("video-link", navigation: navigation)
            if settings.takeover.requireConferenceLink {
                Label {
                    Text("Meetings without a link won't tug you.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.callout)
            }
            Toggle(SettingsText.skipSolo, isOn: $settings.takeover.skipSoloEvents)
                .settingsHighlight("skip-solo", navigation: navigation)
            Toggle(SettingsText.skipDeclined, isOn: $settings.takeover.skipDeclinedEvents)
                .settingsHighlight("skip-declined", navigation: navigation)
            Button(SettingsText.testTug, action: onTestTug)
                .settingsHighlight("test-takeover", navigation: navigation)
        }
        .formStyle(.grouped)
    }

    private var leadMinutes: Binding<Int> {
        Binding(
            get: { Int((settings.takeover.leadTime / 60).rounded()) },
            set: { settings.takeover.leadTime = TimeInterval($0 * 60) }
        )
    }
}
