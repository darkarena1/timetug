import ServiceManagement
import SwiftUI
import TimeTugCore

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: AppModel
    let onTestTakeover: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    /// Set while we programmatically revert `launchAtLogin`, so the resulting
    /// `.onChange` doesn't try to register/unregister again.
    @State private var isReverting = false

    var body: some View {
        Form {
            Section("Takeover") {
                Stepper(value: leadMinutes, in: 0...30) {
                    Text(settings.takeover.leadTime == 0
                         ? "Lead time: at start"
                         : "Lead time: \(Int(settings.takeover.leadTime / 60)) min before")
                }
                Toggle("Only events with a video link", isOn: $settings.takeover.requireConferenceLink)
                Toggle("Skip all-day events (also hides them from the list)", isOn: $settings.takeover.skipAllDayEvents)
                Toggle("Skip events with no other attendees", isOn: $settings.takeover.skipSoloEvents)
                Toggle("Skip declined events", isOn: $settings.takeover.skipDeclinedEvents)
                Button("Test takeover", action: onTestTakeover)
            }

            Section("Menu bar") {
                Picker("Next to the icon", selection: $settings.menuBarMode) {
                    Text("Icon only").tag(MenuBarDisplayMode.iconOnly)
                    Text("Next meeting").tag(MenuBarDisplayMode.nextMeeting)
                    Text("Countdown only").tag(MenuBarDisplayMode.countdown)
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
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

            Section("Calendars") {
                if model.calendars.isEmpty {
                    Text("No calendars found. Check calendar access in System Settings.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.calendars) { calendar in
                    HStack {
                        Text(calendar.title)
                        Spacer()
                        Toggle("Takeover", isOn: takeover(calendar.key))
                        Toggle("Show in list", isOn: shown(calendar.key))
                    }
                    .toggleStyle(.checkbox)
                }
                Text("Takeover needs the calendar shown in the list: turning on Takeover shows it, and hiding it turns Takeover off.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
        .onAppear {
            let actual = SMAppService.mainApp.status == .enabled
            if actual != launchAtLogin {
                isReverting = true
                launchAtLogin = actual
            }
        }
    }

    private var leadMinutes: Binding<Int> {
        Binding(
            get: { Int(settings.takeover.leadTime / 60) },
            set: { settings.takeover.leadTime = TimeInterval($0 * 60) }
        )
    }

    private func takeover(_ key: String) -> Binding<Bool> {
        Binding(
            get: { settings.takeover.takeoverCalendarKeys.contains(key) },
            set: { settings.takeover.setTakeover($0, forCalendar: key) }
        )
    }

    private func shown(_ key: String) -> Binding<Bool> {
        Binding(
            get: { settings.takeover.isShownInList(key) },
            set: { settings.takeover.setShownInList($0, forCalendar: key) }
        )
    }
}
