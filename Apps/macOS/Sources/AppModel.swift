import Foundation
import TimeTugCore

/// Observable state the SwiftUI views render.
@MainActor
final class AppModel: ObservableObject {
    @Published var agenda: DayAgenda = .empty
    @Published var calendars: [CalendarInfo] = []
    @Published var statuses: [String: SourceStatus] = [:]
    @Published var sourceNames: [String: String] = [:]
    /// Takeover lead time, shown in the popup footer.
    @Published var leadTime: TimeInterval = 60
    /// How the popup cards are drawn; mirrors the setting.
    @Published var popupCardStyle: PopupCardStyle = .defaultStyle
}
