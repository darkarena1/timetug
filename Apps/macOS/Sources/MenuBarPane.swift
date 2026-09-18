import SwiftUI

struct MenuBarPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        Form {
            Picker(SettingsText.menuBarText, selection: $settings.menuBarMode) {
                Text("Icon only").tag(MenuBarDisplayMode.iconOnly)
                Text("Next meeting").tag(MenuBarDisplayMode.nextMeeting)
                Text("Countdown only").tag(MenuBarDisplayMode.countdown)
            }
            .settingsHighlight("menu-bar-text", navigation: navigation)
        }
        .formStyle(.grouped)
    }
}
