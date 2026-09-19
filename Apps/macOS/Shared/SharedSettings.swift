import Foundation

/// The booleans Control Center toggles and the app both edit, stored in the App Group suite.
struct SharedSettings {
    enum Key: String {
        case skipAllDay = "shared.skipAllDay"
        case useIntelligence = "shared.useIntelligence"
        case disableTug = "shared.disableTug"
        /// Written by the app: false when on-device intelligence cannot run on this Mac.
        case inferenceAvailable = "shared.inferenceAvailable"
    }

    static let appGroup = SharedSettings(defaults: UserDefaults(suiteName: AppGroup.identifier) ?? .standard)

    let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    /// nil when the key has never been written.
    func bool(_ key: Key) -> Bool? {
        defaults.object(forKey: key.rawValue) as? Bool
    }

    func set(_ value: Bool, for key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }
}
