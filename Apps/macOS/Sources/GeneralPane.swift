import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var navigation: SettingsNavigation
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    /// Set while we programmatically revert `launchAtLogin`, so the resulting
    /// `.onChange` doesn't try to register/unregister again.
    @State private var isReverting = false
    @State private var showingAbout = false

    var body: some View {
        Form {
            Section("Menu bar") {
                Picker(SettingsText.menuBarText, selection: $settings.menuBarMode) {
                    Text("Icon only").tag(MenuBarDisplayMode.iconOnly)
                    Text("Next meeting").tag(MenuBarDisplayMode.nextMeeting)
                    Text("Countdown only").tag(MenuBarDisplayMode.countdown)
                }
                .settingsHighlight("menu-bar-text", navigation: navigation)
            }
            Section("App") {
                Toggle(SettingsText.launchAtLogin, isOn: $launchAtLogin)
                    .settingsHighlight("launch-at-login", navigation: navigation)
                    .onChange(of: launchAtLogin) { _, enabled in
                        if isReverting {
                            isReverting = false
                            return
                        }
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            launchError = nil
                        } catch {
                            launchError = "Couldn't change launch at login: \(error.localizedDescription)"
                            let actual = SMAppService.mainApp.status == .enabled
                            if actual != launchAtLogin {
                                isReverting = true
                                launchAtLogin = actual
                            }
                        }
                    }
                if let launchError {
                    Text(launchError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                Button(SettingsText.aboutButton) { showingAbout = true }
                    .settingsHighlight("about", navigation: navigation)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAbout) { AboutView() }
        .onAppear {
            let actual = SMAppService.mainApp.status == .enabled
            if actual != launchAtLogin {
                isReverting = true
                launchAtLogin = actual
            }
        }
    }
}
