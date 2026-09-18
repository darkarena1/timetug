import SwiftUI

enum SettingsPane: String, CaseIterable, Hashable, Identifiable {
    case takeover, calendars, menuBar, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .takeover: "Takeover"
        case .calendars: "Calendars"
        case .menuBar: "Menu Bar"
        case .general: "General"
        }
    }

    var systemImage: String {
        switch self {
        case .takeover: "bolt.fill"
        case .calendars: "calendar"
        case .menuBar: "menubar.rectangle"
        case .general: "gearshape"
        }
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    static let highlightDuration: Duration = .milliseconds(1500)

    @Published var pane: SettingsPane = .takeover
    @Published var highlightedID: String?
    private var clearTask: Task<Void, Never>?

    /// Switches to the item's pane and briefly highlights its control.
    func reveal(_ item: SettingsSearchItem) {
        pane = item.pane
        highlightedID = item.id
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: Self.highlightDuration)
            guard !Task.isCancelled else { return }
            self?.highlightedID = nil
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
