import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var updates: UpdateController
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    /// Set while we programmatically revert `launchAtLogin`, so the resulting
    /// `.onChange` doesn't try to register/unregister again.
    @State private var isReverting = false

    var body: some View {
        NavigationStack(path: $navigation.generalPath) {
            hub
                .navigationDestination(for: GeneralDestination.self) { destination in
                    switch destination {
                    case .about:
                        Form { AboutPaneContent() }
                            .formStyle(.grouped)
                            .navigationTitle("About")
                    case .softwareUpdate:
                        Form { UpdatesSection(updates: updates, navigation: navigation) }
                            .formStyle(.grouped)
                            .navigationTitle("Software Update")
                    }
                }
        }
    }

    private var hub: some View {
        Form {
            Section {
                NavigationLink(value: GeneralDestination.about) {
                    Label {
                        Text("About")
                    } icon: {
                        Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                            .resizable()
                            .frame(width: 22, height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))
                    }
                }
                NavigationLink(value: GeneralDestination.softwareUpdate) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Software Update")
                            Text("TimeTug \(updates.currentVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        SettingsRowIcon(systemImage: "arrow.triangle.2.circlepath", color: .blue)
                    }
                }
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
