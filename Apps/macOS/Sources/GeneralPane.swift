import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    @ObservedObject var navigation: SettingsNavigation
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    /// Set while we programmatically revert `launchAtLogin`, so the resulting
    /// `.onChange` doesn't try to register/unregister again.
    @State private var isReverting = false

    var body: some View {
        Form {
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
