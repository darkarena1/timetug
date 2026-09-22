import AppIntents
import SwiftUI
import WidgetKit

// MARK: Intents (run in the extension process; the app is told through a Darwin notification)

@available(macOS 26.0, *)
struct SetSkipAllDayIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Skip All Day Events"
    @Parameter(title: "Skip All Day Events") var value: Bool

    func perform() async throws -> some IntentResult {
        SharedSettings.appGroup.set(value, for: .skipAllDay)
        SettingsChangeSignal.post()
        return .result()
    }
}

@available(macOS 26.0, *)
struct SetUseIntelligenceIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Use Intelligence"
    @Parameter(title: "Use Intelligence") var value: Bool

    func perform() async throws -> some IntentResult {
        SharedSettings.appGroup.set(value, for: .useIntelligence)
        SettingsChangeSignal.post()
        return .result()
    }
}

@available(macOS 26.0, *)
struct SetEnableTugIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Enable Tug"
    @Parameter(title: "Enable Tug") var value: Bool

    func perform() async throws -> some IntentResult {
        SharedSettings.appGroup.set(value, for: .enableTug)
        SettingsChangeSignal.post()
        return .result()
    }
}

// MARK: Value providers

@available(macOS 26.0, *)
struct BoolValueProvider: ControlValueProvider {
    let key: SharedSettings.Key
    let defaultValue: Bool

    var previewValue: Bool { defaultValue }
    func currentValue() async throws -> Bool { SharedSettings.appGroup.bool(key) ?? defaultValue }
}

@available(macOS 26.0, *)
struct IntelligenceState: Hashable {
    let isOn: Bool
    let isAvailable: Bool
}

@available(macOS 26.0, *)
struct IntelligenceValueProvider: ControlValueProvider {
    var previewValue: IntelligenceState { IntelligenceState(isOn: false, isAvailable: true) }
    func currentValue() async throws -> IntelligenceState {
        let settings = SharedSettings.appGroup
        return IntelligenceState(isOn: settings.bool(.useIntelligence) ?? false,
                                 isAvailable: settings.bool(.inferenceAvailable) ?? true)
    }
}

// MARK: Controls

@available(macOS 26.0, *)
struct SkipAllDayControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.timetug.control.skipAllDay", provider: BoolValueProvider(key: .skipAllDay, defaultValue: true)
        ) { isOn in
            ControlWidgetToggle("Skip All Day Events", isOn: isOn, action: SetSkipAllDayIntent()) { on in
                Label(on ? "On" : "Off", systemImage: "calendar.badge.minus")
            }
        }
        .displayName("Skip All Day Events")
        .description("Hide all-day events from TimeTug's list and widgets.")
    }
}

@available(macOS 26.0, *)
struct UseIntelligenceControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.timetug.control.useIntelligence", provider: IntelligenceValueProvider()) { state in
            ControlWidgetToggle("Use Intelligence", isOn: state.isOn && state.isAvailable, action: SetUseIntelligenceIntent()) { on in
                Label(state.isAvailable ? (on ? "On" : "Off") : "Unavailable", systemImage: "sparkles")
            }
            .disabled(!state.isAvailable)
        }
        .displayName("Use Intelligence")
        .description("Find duplicate meetings with on-device Apple Intelligence.")
    }
}

@available(macOS 26.0, *)
struct EnableTugControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.timetug.control.enableTug", provider: BoolValueProvider(key: .enableTug, defaultValue: true)
        ) { isOn in
            ControlWidgetToggle("Enable Tug", isOn: isOn, action: SetEnableTugIntent()) { on in
                Label(on ? "Tug on" : "Tug off", systemImage: on ? "bell.fill" : "bell.slash.fill")
            }
        }
        .displayName("Enable Tug")
        .description("Turn off to pause takeovers and pre-meeting popups.")
    }
}
