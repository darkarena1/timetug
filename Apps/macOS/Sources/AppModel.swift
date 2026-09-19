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
    /// State of the optional on-device duplicate finder, for the Calendars pane.
    @Published var inferenceStatus: InferenceStatus = .disabled
    /// Look-alike events kept separate (event id -> others), for the popup's manual "Merge".
    @Published var candidates: [String: [CalendarEvent]] = [:]
    /// How the popup cards are drawn; mirrors the setting.
    @Published var popupCardStyle: PopupCardStyle = .defaultStyle
}
