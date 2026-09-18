import AppKit

/// App-wide appearance choice. `.auto` means "no override": follow the OS.
enum AppearanceMode: String, CaseIterable, Codable {
    case auto, light, dark

    var title: String {
        switch self {
        case .auto: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// nil for `.auto` so `NSApp.appearance = nil` follows the system (including day/night switching).
    var nsAppearance: NSAppearance? {
        switch self {
        case .auto: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
