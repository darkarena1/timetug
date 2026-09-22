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
    private static let eventKitKey = "eventKitEnabled.v1"
    private let defaults: UserDefaults
    let shared: SharedSettings
    /// True while `reloadFromShared()` assigns values that came from the suite; the observers must not write them back.
    private var isApplyingSharedValues = false

    @Published var takeover: TakeoverSettings {
        didSet {
            save()
            guard !isApplyingSharedValues else { return }
            // Mirror only what changed: unrelated edits must not overwrite a pending external toggle.
            if takeover.skipAllDayEvents != oldValue.skipAllDayEvents {
                shared.set(takeover.skipAllDayEvents, for: .skipAllDay)
            }
            if takeover.enabled != oldValue.enabled {
                shared.set(takeover.enabled, for: .enableTug)
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
    @Published var eventKitEnabled: Bool {
        didSet { defaults.set(eventKitEnabled, forKey: Self.eventKitKey) }
    }
    @Published var inferenceEnabled: Bool {
        didSet {
            defaults.set(inferenceEnabled, forKey: Self.inferenceKey)
            if !isApplyingSharedValues, oldValue != inferenceEnabled {
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
        if let enabled = shared.bool(.enableTug) { loaded.enabled = enabled }
        self.takeover = loaded
        self.menuBarMode = defaults.string(forKey: Self.modeKey)
            .flatMap(MenuBarDisplayMode.init(rawValue:)) ?? .iconOnly
        self.appearanceMode = defaults.string(forKey: Self.appearanceKey)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .auto
        self.popupCardStyle = defaults.string(forKey: Self.cardStyleKey)
            .flatMap(PopupCardStyle.init(rawValue:))
            .flatMap { PopupCardStyle.available.contains($0) ? $0 : nil } ?? PopupCardStyle.defaultStyle
        self.inferenceEnabled = shared.bool(.useIntelligence) ?? defaults.bool(forKey: Self.inferenceKey)
        self.eventKitEnabled = defaults.object(forKey: Self.eventKitKey) as? Bool ?? true
        // One-time migration: seed the suite so widgets and controls see current values.
        mirrorToShared()
        shared.set(inferenceEnabled, for: .useIntelligence)
    }

    /// Applies values a Control Center toggle wrote to the shared suite while the app was running.
    func reloadFromShared() {
        // Read everything first: assigning `takeover` mirrors back into the suite and would clobber unread keys.
        let skip = shared.bool(.skipAllDay)
        let enabled = shared.bool(.enableTug)
        let intelligence = shared.bool(.useIntelligence)
        isApplyingSharedValues = true
        defer { isApplyingSharedValues = false }
        var updated = takeover
        if let skip { updated.skipAllDayEvents = skip }
        if let enabled { updated.enabled = enabled }
        if updated != takeover { takeover = updated }
        if let intelligence, intelligence != inferenceEnabled { inferenceEnabled = intelligence }
    }

    private func mirrorToShared() {
        shared.set(takeover.skipAllDayEvents, for: .skipAllDay)
        shared.set(takeover.enabled, for: .enableTug)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(takeover) {
            defaults.set(data, forKey: Self.takeoverKey)
        }
    }
}
