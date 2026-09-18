import SwiftUI
import TimeTugCore

struct DropdownView: View {
    @ObservedObject var model: AppModel
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(problems, id: \.sourceID) { problem in
                ProblemRow(message: problem.message, showsPrivacyLink: problem.status == .needsPermission)
            }
            if model.agenda.items.isEmpty {
                Text("No events today")
                    .foregroundStyle(.secondary)
                    .padding(20)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(model.agenda.items) { EventRow(item: $0) }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 420)
            }
            Divider()
            HStack {
                Spacer()
                Button("Settings…", action: onOpenSettings).buttonStyle(.link)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .frame(width: 340)
    }

    private struct Problem { let sourceID: String; let status: SourceStatus; let message: String }

    private var problems: [Problem] {
        model.statuses.compactMap { sourceID, status in
            let name = model.sourceNames[sourceID] ?? sourceID
            switch status {
            case .ok: return nil
            case .needsPermission: return Problem(sourceID: sourceID, status: status, message: "\(name) access denied")
            case .authExpired: return Problem(sourceID: sourceID, status: status, message: "\(name) needs you to sign in again")
            case .failing(let reason): return Problem(sourceID: sourceID, status: status, message: "\(name) failed: \(reason)")
            }
        }
        .sorted { $0.sourceID < $1.sourceID }
    }
}

private struct ProblemRow: View {
    let message: String
    let showsPrivacyLink: Bool

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.callout)
            Spacer()
            if showsPrivacyLink {
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                }
                .buttonStyle(.link)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.12))
    }
}

private struct EventRow: View {
    let item: DayAgenda.Item

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Group {
                if item.event.isAllDay {
                    Text("All day")
                } else {
                    Text(item.event.start, style: .time)
                }
            }
            .font(.callout.monospacedDigit())
            .frame(width: 64, alignment: .leading)

            Text(item.event.title)
                .fontWeight(item.state == .current ? .semibold : .regular)
                .lineLimit(1)
            Spacer(minLength: 0)
            if item.state == .current {
                Circle().fill(.tint).frame(width: 7, height: 7)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .foregroundStyle(item.state == .past ? .secondary : .primary)
        .opacity(item.state == .past ? 0.55 : 1)
    }
}
