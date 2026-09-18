import Foundation
import TimeTugCore

/// Observable state the SwiftUI views render.
@MainActor
final class AppModel: ObservableObject {
    @Published var agenda: DayAgenda = .empty
    @Published var calendars: [CalendarInfo] = []
    @Published var statuses: [String: SourceStatus] = [:]
    @Published var sourceNames: [String: String] = [:]
}
