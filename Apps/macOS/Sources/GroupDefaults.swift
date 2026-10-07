import Foundation

/// The preferences every TimeTug build shares, stored in the App Group suite. Sparkle's keys, the beta opt-in and the
/// global shortcut stay in each build's own `UserDefaults.standard`.
enum GroupDefaults {
    static let suite = UserDefaults(suiteName: AppGroup.identifier) ?? .standard

    /// The keys that move. Keep in step with `SettingsStore` and `BrowserPreferringPresenter.defaultsKey`.
    static let keys = [
        "takeoverSettings.v1", "menuBarMode.v1", "appearanceMode.v1", "popupCardStyle.v1",
        "dedupInference.v1", "eventKitEnabled.v1", "oauth.useBrowser.v1",
    ]
    private static let migratedKey = "groupDefaultsMigrated.v1"

    /// Copies each known key from `source` that the group does not have yet. Runs once per source (the flag lives in
    /// `source`, so a second build with its own old values still gets its turn without ever overwriting the group).
    static func migrate(from source: UserDefaults, to group: UserDefaults) {
        guard source !== group, !source.bool(forKey: migratedKey) else { return }
        for key in keys where group.object(forKey: key) == nil {
            if let value = source.object(forKey: key) { group.set(value, forKey: key) }
        }
        source.set(true, forKey: migratedKey)
    }
}
