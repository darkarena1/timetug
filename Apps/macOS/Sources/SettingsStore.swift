import Foundation
import TimeTugCore

enum MenuBarDisplayMode: String, CaseIterable, Codable {
    case iconOnly, nextMeeting, countdown
}

/// Persists settings in UserDefaults. Core defines the shape; storage is the app's concern.
@MainActor
final class SettingsStore: ObservableObject {
    private static let takeoverKey = "takeoverSettings.v1"
    private static let modeKey = "menuBarMode.v1"
    private static let appearanceKey = "appearanceMode.v1"
    private let defaults: UserDefaults

    @Published var takeover: TakeoverSettings {
        didSet { save() }
    }
    @Published var menuBarMode: MenuBarDisplayMode {
        didSet { defaults.set(menuBarMode.rawValue, forKey: Self.modeKey) }
    }
    @Published var appearanceMode: AppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: Self.appearanceKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.takeover = defaults.data(forKey: Self.takeoverKey)
            .flatMap { try? JSONDecoder().decode(TakeoverSettings.self, from: $0) } ?? TakeoverSettings()
        self.menuBarMode = defaults.string(forKey: Self.modeKey)
            .flatMap(MenuBarDisplayMode.init(rawValue:)) ?? .iconOnly
        self.appearanceMode = defaults.string(forKey: Self.appearanceKey)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .auto
    }

    private func save() {
        if let data = try? JSONEncoder().encode(takeover) {
            defaults.set(data, forKey: Self.takeoverKey)
        }
    }
}
