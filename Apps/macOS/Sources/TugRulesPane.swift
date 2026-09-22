import SwiftUI

struct TugRulesPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var navigation: SettingsNavigation
    let onTestTug: () -> Void

    var body: some View {
        Form {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(SettingsText.enableTug, isOn: $settings.takeover.enabled)
                    .settingsHighlight("enable-tug", navigation: navigation)
                Text("Turn off to pause takeovers. Your agenda, menu bar and widgets keep working.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Picker(SettingsText.leadTime, selection: leadMinutes) {
                    ForEach(LeadTimeOptions.options(including: settings.takeover.leadTime)) { option in
                        Text(option.title).tag(option.minutes)
                    }
                }
                .pickerStyle(.menu)
                Text("How long before a meeting starts TimeTug tugs you.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .settingsHighlight("lead-time", navigation: navigation)
            // Control and info line share one row so the grouped Form draws no divider between them
            // (`listRowSeparator` is ignored for macOS grouped forms).
            VStack(alignment: .leading, spacing: 4) {
                Toggle(SettingsText.videoLink, isOn: $settings.takeover.requireConferenceLink)
                    .settingsHighlight("video-link", navigation: navigation)
                if settings.takeover.requireConferenceLink {
                    warning("Meetings without a link won't tug you.")
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Toggle(SettingsText.requireAttendees, isOn: $settings.takeover.requireOtherAttendees)
                    .settingsHighlight("require-attendees", navigation: navigation)
                if settings.takeover.requireOtherAttendees {
                    warning("Meetings without other attendees won't tug you.")
                }
            }
            Button(SettingsText.testTug, action: onTestTug)
                .settingsHighlight("test-takeover", navigation: navigation)
        }
        .formStyle(.grouped)
    }

    private func warning(_ text: String) -> some View {
        Label {
            Text(text)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange.opacity(0.85))
        }
        .font(.footnote)
    }

    private var leadMinutes: Binding<Int> {
        Binding(
            get: { Int((settings.takeover.leadTime / 60).rounded()) },
            set: { settings.takeover.leadTime = TimeInterval($0 * 60) }
        )
    }
}
