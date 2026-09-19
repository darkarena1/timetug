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
struct SetDisableTugIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Disable Tug"
    @Parameter(title: "Disable Tug") var value: Bool

    func perform() async throws -> some IntentResult {
        SharedSettings.appGroup.set(value, for: .disableTug)
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
            ControlWidgetToggle("Use Intelligence", isOn: state.isOn, action: SetUseIntelligenceIntent()) { on in
                Label(state.isAvailable ? (on ? "On" : "Off") : "Unavailable", systemImage: "sparkles")
            }
            .disabled(!state.isAvailable)
        }
        .displayName("Use Intelligence")
        .description("Find duplicate meetings with on-device Apple Intelligence.")
    }
}

@available(macOS 26.0, *)
struct DisableTugControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.timetug.control.disableTug", provider: BoolValueProvider(key: .disableTug, defaultValue: false)
        ) { isOn in
            ControlWidgetToggle("Disable Tug", isOn: isOn, action: SetDisableTugIntent()) { on in
                Label(on ? "Tug off" : "Tug on", systemImage: on ? "bell.slash.fill" : "bell.fill")
            }
        }
        .displayName("Disable Tug")
        .description("Pause takeovers and pre-meeting popups.")
    }
}
