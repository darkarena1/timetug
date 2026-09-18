import SwiftUI

struct TakeoverPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var navigation: SettingsNavigation
    let onTestTakeover: () -> Void

    var body: some View {
        Form {
            Stepper(value: leadMinutes, in: 0...30) {
                Text(settings.takeover.leadTime == 0
                     ? "\(SettingsText.leadTime): at start"
                     : "\(SettingsText.leadTime): \(Int(settings.takeover.leadTime / 60)) min before")
            }
            .settingsHighlight("lead-time", navigation: navigation)
            Toggle(SettingsText.videoLink, isOn: $settings.takeover.requireConferenceLink)
                .settingsHighlight("video-link", navigation: navigation)
            Toggle(SettingsText.skipSolo, isOn: $settings.takeover.skipSoloEvents)
                .settingsHighlight("skip-solo", navigation: navigation)
            Toggle(SettingsText.skipDeclined, isOn: $settings.takeover.skipDeclinedEvents)
                .settingsHighlight("skip-declined", navigation: navigation)
            Button(SettingsText.testTakeover, action: onTestTakeover)
                .settingsHighlight("test-takeover", navigation: navigation)
        }
        .formStyle(.grouped)
    }

    private var leadMinutes: Binding<Int> {
        Binding(
            get: { Int(settings.takeover.leadTime / 60) },
            set: { settings.takeover.leadTime = TimeInterval($0 * 60) }
        )
    }
}
