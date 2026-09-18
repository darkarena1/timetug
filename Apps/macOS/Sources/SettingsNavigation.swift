import SwiftUI

enum SettingsPane: String, CaseIterable, Hashable, Identifiable {
    case general, calendars, tugRules

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .calendars: "Calendars"
        case .tugRules: "Tug Rules"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .calendars: "calendar"
        case .tugRules: "bolt.fill"
        }
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    static let highlightDuration: Duration = .milliseconds(1500)

    @Published var pane: SettingsPane = .general
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
