import SwiftUI

enum SettingsPane: String, CaseIterable, Hashable, Identifiable {
    case general, appearance, accounts, calendars, tugRules

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .accounts: "Accounts"
        case .calendars: "Calendars"
        case .tugRules: "Tug Rules"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "circle.righthalf.filled"
        case .accounts: "person.crop.circle"
        case .calendars: "calendar"
        case .tugRules: "bolt.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .general: Color.gray
        case .appearance: Color(white: 0.3)
        case .accounts: Color(red: 0.20, green: 0.70, blue: 0.40)
        case .calendars: Color(red: 0.18, green: 0.48, blue: 0.96)
        case .tugRules: Color(red: 1.0, green: 0.62, blue: 0.10)
        }
    }
}

/// A drill-down destination reachable from the General settings hub.
enum GeneralDestination: Hashable {
    case about
    case softwareUpdate
}

@MainActor
final class SettingsNavigation: ObservableObject {
    static let highlightDuration: Duration = .milliseconds(1500)

    @Published var pane: SettingsPane = .general
    @Published var generalPath: [GeneralDestination] = []
    @Published var highlightedID: String?
    private var clearTask: Task<Void, Never>?

    /// Switches to the item's pane and briefly highlights its control. If the item lives inside a
    /// General sub-page, also drills into it; otherwise pops General back to its hub so the highlighted
    /// control on the hub is actually visible.
    func reveal(_ item: SettingsSearchItem) {
        pane = item.pane
        generalPath = Self.generalDestination(for: item.id).map { [$0] } ?? []
        highlightedID = item.id
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: Self.highlightDuration)
            guard !Task.isCancelled else { return }
            self?.highlightedID = nil
        }
    }

    private static func generalDestination(for id: String) -> GeneralDestination? {
        switch id {
        case "software-update", "automatic-updates", "beta-updates": .softwareUpdate
        default: nil
        }
    }
}

private struct SettingsHighlight: ViewModifier {
    let id: String
    @ObservedObject var navigation: SettingsNavigation

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(navigation.highlightedID == id ? 0.2 : 0))
                    .padding(-4)
            )
            .animation(.easeInOut(duration: 0.25), value: navigation.highlightedID)
    }
}

extension View {
    /// Tints this control's background while `navigation.highlightedID == id`.
    func settingsHighlight(_ id: String, navigation: SettingsNavigation) -> some View {
        modifier(SettingsHighlight(id: id, navigation: navigation))
    }
}
