import Foundation

/// Identifiers shared by the app and the widget extension. The id is team-prefixed so a
/// Developer ID build needs no provisioning profile for the group.
enum AppGroup {
    static let identifier = "YYA6ZKMD36.com.timetug.shared"

    /// nil when the app is not signed with a team identity that owns the group (ad-hoc builds).
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
