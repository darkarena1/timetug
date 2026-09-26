import AppKit
import CalendarCore
import SwiftUI
import TimeTugCore

struct AccountsPane: View {
    @ObservedObject var accounts: AccountsController
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: AppModel
    @ObservedObject var navigation: SettingsNavigation
    @State private var pendingRemoval: Connection?

    /// Providers on the roadmap but not yet wired to a real `ConnectorKind`. Shown greyed out so people
    /// know they're coming rather than assuming TimeTug only ever talks to Google.
    private static let placeholderProviders: [PlaceholderProvider] = [
        .init(name: "iCloud", systemImage: "icloud"),
        .init(name: "Fastmail", systemImage: "at"),
        .init(name: "Meetup", systemImage: "person.3"),
        .init(name: "Todoist", systemImage: "checklist"),
        .init(name: "Zoom", systemImage: "video"),
        .init(name: "Webex", systemImage: "video.fill"),
        .init(name: "Other CalDAV", systemImage: "link"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Choose where TimeTug reads your calendars from.")
                    .font(.callout).foregroundStyle(.secondary)
                appleCalendarCard

                Text("Connected Accounts").font(.headline).padding(.top, 4)
                connectedCard
                if accounts.isWorking { waitingRow }
                if let message = accounts.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.orange)
                }

                Text("Add an Account").font(.headline).padding(.top, 4)
                providerGrid
                if !accounts.unconfiguredKindIDs.isEmpty { configurationWarning }
            }
            .padding(16)
        }
        .settingsHighlight("accounts", navigation: navigation)
        .confirmationDialog(
            "Remove \(pendingRemoval?.displayName ?? "this account")?", isPresented: removalBinding, titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let connection = pendingRemoval {
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

    private var connectedCard: some View {
        VStack(spacing: 0) {
            if accounts.accounts.isEmpty {
                Text("No internet accounts yet. Add one below.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 10)
            } else {
                ForEach(Array(accounts.accounts.enumerated()), id: \.element.connectionID) { index, connection in
                    if index > 0 { Divider() }
                    accountRow(connection)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
    }

    private var appleCalendarCard: some View {
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
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel("Use \(SettingsText.appleCalendar)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
    }

    private func accountRow(_ connection: Connection) -> some View {
        let status = model.statuses[accounts.statusKey(for: connection)]
        let failure = accounts.buildFailures[connection.connectionID]
        return HStack(spacing: 10) {
            ProviderIcon(kindID: connection.kindID)
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
            Menu {
                Button("Remove Account", role: .destructive) { pendingRemoval = connection }
                    .disabled(accounts.isWorking)
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("\(connection.displayName) actions")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var providerGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(accounts.availableKinds, id: \.id) { kind in
                Button {
                    accounts.beginAddAccount(kindID: kind.id)
                } label: {
                    ProviderTile(name: kind.displayName) { ProviderIcon(kindID: kind.id, size: 36) }
                }
                .buttonStyle(.plain)
                .disabled(accounts.isWorking)
                .accessibilityLabel("Add \(kind.displayName) account")
            }
            ForEach(accounts.unconfiguredKindIDs, id: \.self) { kindID in
                ProviderTile(name: ProviderIcon.displayName(forKindID: kindID), badge: "Unavailable") {
                    ProviderIcon(kindID: kindID, size: 36)
                }
                .opacity(0.5)
                .accessibilityLabel("\(ProviderIcon.displayName(forKindID: kindID)), unavailable in this build")
            }
            ForEach(Self.placeholderProviders) { provider in
                ProviderTile(name: provider.name, badge: "Soon") {
                    Image(systemName: provider.systemImage)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color(nsColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .opacity(0.55)
                .accessibilityLabel("\(provider.name), coming soon")
            }
        }
    }

    private var configurationWarning: some View {
        Label {
            Text("This build is missing configuration for some account types, so they can't be added right now.")
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 2)
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

/// A provider not yet wired to a real connector — shown for the roadmap, never tappable.
private struct PlaceholderProvider: Identifiable {
    let name: String
    let systemImage: String
    var id: String { name }
}

/// One tile in the "Add an Account" grid: an icon, a name, and an optional status badge.
private struct ProviderTile<Icon: View>: View {
    let name: String
    var badge: String?
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        VStack(spacing: 8) {
            icon()
            Text(name).font(.caption).lineLimit(1)
            if let badge {
                Text(badge).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color(nsColor: .separatorColor)))
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
