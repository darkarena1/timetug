import SwiftUI

struct TugRulesPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var navigation: SettingsNavigation
    let onTestTug: () -> Void

    private static let accent = Color(red: 1.0, green: 0.62, blue: 0.10)

    var body: some View {
        Form {
            Section {
                hero.listRowBackground(Self.accent.opacity(0.08))
            }

            Section("Timing") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label { Text(SettingsText.leadTime) } icon: { SettingsRowIcon(systemImage: "clock", color: .blue) }
                        Spacer()
                        Picker("", selection: leadMinutes) {
                            ForEach(LeadTimeOptions.options(including: settings.takeover.leadTime)) { option in
                                Text(option.title).tag(option.minutes)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    Text("How long before a meeting starts TimeTug tugs you.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .settingsHighlight("lead-time", navigation: navigation)
            }

            Section("Requirements") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $settings.takeover.requireConferenceLink) {
                        Label { Text(SettingsText.videoLink) } icon: { SettingsRowIcon(systemImage: "video.fill", color: .purple) }
                    }
                    .settingsHighlight("video-link", navigation: navigation)
                    if settings.takeover.requireConferenceLink {
                        warning("Meetings without a link won't tug you.")
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $settings.takeover.requireOtherAttendees) {
                        Label { Text(SettingsText.requireAttendees) } icon: { SettingsRowIcon(systemImage: "person.2.fill", color: .green) }
                    }
                    .settingsHighlight("require-attendees", navigation: navigation)
                    if settings.takeover.requireOtherAttendees {
                        warning("Meetings without other attendees won't tug you.")
                    }
                }
            }

            Section("Test") {
                Button(action: onTestTug) {
                    Label { Text(SettingsText.testTug) } icon: { SettingsRowIcon(systemImage: "play.fill", color: .gray) }
                }
                .settingsHighlight("test-takeover", navigation: navigation)
            }
        }
        .formStyle(.grouped)
    }

    private var hero: some View {
        HStack(spacing: 14) {
            SettingsRowIcon(systemImage: "bolt.fill", color: Self.accent, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tug").font(.headline)
                Text(settings.takeover.enabled
                     ? "Pulls your attention to meetings before they start."
                     : "Off — your agenda, menu bar and widgets keep working.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Toggle(SettingsText.enableTug, isOn: $settings.takeover.enabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.vertical, 4)
        .settingsHighlight("enable-tug", navigation: navigation)
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
