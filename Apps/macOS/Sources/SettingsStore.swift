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
    private static let cardStyleKey = "popupCardStyle.v1"
    private static let inferenceKey = "dedupInference.v1"
    private let defaults: UserDefaults
    let shared: SharedSettings

    @Published var takeover: TakeoverSettings {
        didSet {
            save()
            // Mirror only what changed: unrelated edits must not overwrite a pending external toggle.
            if takeover.skipAllDayEvents != oldValue.skipAllDayEvents {
                shared.set(takeover.skipAllDayEvents, for: .skipAllDay)
            }
            if takeover.disabled != oldValue.disabled {
                shared.set(takeover.disabled, for: .disableTug)
            }
        }
    }
    @Published var menuBarMode: MenuBarDisplayMode {
        didSet { defaults.set(menuBarMode.rawValue, forKey: Self.modeKey) }
    }
    @Published var appearanceMode: AppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: Self.appearanceKey) }
    }
    @Published var popupCardStyle: PopupCardStyle {
        didSet { defaults.set(popupCardStyle.rawValue, forKey: Self.cardStyleKey) }
    }
    @Published var inferenceEnabled: Bool {
        didSet {
            defaults.set(inferenceEnabled, forKey: Self.inferenceKey)
            if oldValue != inferenceEnabled {
                shared.set(inferenceEnabled, for: .useIntelligence)
            }
        }
    }

    init(defaults: UserDefaults = .standard, shared: SharedSettings? = nil) {
        self.defaults = defaults
        let shared = shared ?? SharedSettings(defaults: defaults)
        self.shared = shared
        var loaded = defaults.data(forKey: Self.takeoverKey)
            .flatMap { try? JSONDecoder().decode(TakeoverSettings.self, from: $0) } ?? TakeoverSettings()
        if let skip = shared.bool(.skipAllDay) { loaded.skipAllDayEvents = skip }
        if let disabled = shared.bool(.disableTug) { loaded.disabled = disabled }
        self.takeover = loaded
        self.menuBarMode = defaults.string(forKey: Self.modeKey)
            .flatMap(MenuBarDisplayMode.init(rawValue:)) ?? .iconOnly
        self.appearanceMode = defaults.string(forKey: Self.appearanceKey)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .auto
        self.popupCardStyle = defaults.string(forKey: Self.cardStyleKey)
            .flatMap(PopupCardStyle.init(rawValue:))
            .flatMap { PopupCardStyle.available.contains($0) ? $0 : nil } ?? PopupCardStyle.defaultStyle
        self.inferenceEnabled = shared.bool(.useIntelligence) ?? defaults.bool(forKey: Self.inferenceKey)
        // One-time migration: seed the suite so widgets and controls see current values.
        mirrorToShared()
        shared.set(inferenceEnabled, for: .useIntelligence)
    }

    /// Applies values a Control Center toggle wrote to the shared suite while the app was running.
    func reloadFromShared() {
        // Read everything first: assigning `takeover` mirrors back into the suite and would clobber unread keys.
        let skip = shared.bool(.skipAllDay)
        let disabled = shared.bool(.disableTug)
        let intelligence = shared.bool(.useIntelligence)
        var updated = takeover
        if let skip { updated.skipAllDayEvents = skip }
        if let disabled { updated.disabled = disabled }
        if updated != takeover { takeover = updated }
        if let intelligence, intelligence != inferenceEnabled { inferenceEnabled = intelligence }
    }

    private func mirrorToShared() {
        shared.set(takeover.skipAllDayEvents, for: .skipAllDay)
        shared.set(takeover.disabled, for: .disableTug)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(takeover) {
            defaults.set(data, forKey: Self.takeoverKey)
        }
    }
}
