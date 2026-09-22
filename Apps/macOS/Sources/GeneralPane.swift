import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var updates: UpdateController
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    /// Set while we programmatically revert `launchAtLogin`, so the resulting
    /// `.onChange` doesn't try to register/unregister again.
    @State private var isReverting = false

    var body: some View {
        Form {
            UpdatesSection(updates: updates, navigation: navigation)
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
            }
            Section("Shortcut") {
                VStack(alignment: .leading, spacing: 4) {
                    KeyboardShortcuts.Recorder(SettingsText.popupShortcut, name: .togglePopup)
                        .settingsHighlight("popup-shortcut", navigation: navigation)
                    Text("Press a shortcut to show or hide the popup from anywhere. Click ✕ to clear it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            let actual = SMAppService.mainApp.status == .enabled
            if actual != launchAtLogin {
                isReverting = true
                launchAtLogin = actual
            }
        }
    }
}
