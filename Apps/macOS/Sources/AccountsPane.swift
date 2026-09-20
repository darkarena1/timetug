import AppKit
import CalendarCore
import SwiftUI
import TimeTugCore

struct AccountsPane: View {
    @ObservedObject var accounts: AccountsController
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: AppModel
    @ObservedObject var navigation: SettingsNavigation
    @State private var selection: ConnectionID?
    @State private var pendingRemoval: Connection?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose where TimeTug reads your calendars from.")
                .font(.callout).foregroundStyle(.secondary)
            list
            controls
            if accounts.isWorking { waitingRow }
            if let message = accounts.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.orange)
            }
        }
        .padding(16)
        .settingsHighlight("accounts", navigation: navigation)
        .confirmationDialog(
            "Remove \(pendingRemoval?.displayName ?? "this account")?", isPresented: removalBinding, titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let connection = pendingRemoval {
                    selection = nil
                    Task { await accounts.removeAccount(connectionID: connection.connectionID) }
                }
                pendingRemoval = nil
            }
        } message: {
            Text("Its calendars will no longer appear and their Tug and visibility choices are forgotten.")
        }
    }

    private var removalBinding: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }

    private var list: some View {
        List(selection: $selection) {
            appleCalendarRow
            ForEach(accounts.accounts) { connection in
                accountRow(connection).tag(connection.connectionID)
            }
        }
        .listStyle(.bordered)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appleCalendarRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar").frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(SettingsText.appleCalendar) (this Mac)")
                Text(settings.eventKitEnabled ? AccountStatusText.make(model.statuses["eventkit"]) : "Off")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if settings.eventKitEnabled, model.statuses["eventkit"] == .needsPermission {
                Button("Open System Settings") { Self.openCalendarPrivacySettings() }.buttonStyle(.link)
            }
            Toggle("Enabled", isOn: Binding(
                get: { settings.eventKitEnabled },
                set: { enabled in Task { await accounts.setEventKitEnabled(enabled) } }))
                .labelsHidden()
                .toggleStyle(ContrastCheckboxStyle())
                .accessibilityLabel("Use \(SettingsText.appleCalendar)")
        }
        .padding(.vertical, 4)
    }

    private func accountRow(_ connection: Connection) -> some View {
        let status = model.statuses[accounts.statusKey(for: connection)]
        let failure = accounts.buildFailures[connection.connectionID]
        return HStack(spacing: 10) {
            Image(systemName: "person.crop.circle").frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.displayName)
                Text(failure == nil ? AccountStatusText.make(status) : "Can't start this account")
                    .font(.caption).foregroundStyle(status == .authExpired || failure != nil ? .orange : .secondary)
            }
            Spacer()
            if status == .authExpired || failure != nil {
                Button("Sign in again") { accounts.beginReauthorize(connectionID: connection.connectionID) }
                    .disabled(accounts.isWorking)
            }
        }
        .padding(.vertical, 4)
    }

    private var controls: some View {
        HStack(spacing: 0) {
            Menu {
                if accounts.availableKinds.isEmpty {
                    Button("No account types are available in this build") {}.disabled(true)
                }
                ForEach(accounts.availableKinds, id: \.id) { kind in
                    Button(kind.displayName) { accounts.beginAddAccount(kindID: kind.id) }
                }
            } label: {
                Image(systemName: "plus").frame(width: 24, height: 20)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .fixedSize()
            .disabled(accounts.isWorking)
            .accessibilityLabel("Add account")
            Divider().frame(height: 16).padding(.horizontal, 4)
            Button {
                pendingRemoval = accounts.accounts.first { $0.connectionID == selection }
            } label: {
                Image(systemName: "minus").frame(width: 24, height: 20)
            }
            .buttonStyle(.borderless)
            .disabled(selection == nil || accounts.isWorking || !accounts.accounts.contains { $0.connectionID == selection })
            .accessibilityLabel("Remove account")
            Spacer()
        }
    }

    private var waitingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Waiting for your browser…").font(.callout)
            Button("Cancel") { accounts.cancelAuthorization() }.buttonStyle(.link)
        }
    }

    private static func openCalendarPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}
