import Foundation

/// How the event cards in the popup are drawn.
enum PopupCardStyle: String, CaseIterable, Codable {
    /// Native Liquid Glass (macOS 26+).
    case glass
    /// System translucent material with a hairline border; works on every supported macOS.
    case frosted
    /// Opaque brand fills.
    case solid

    var title: String {
        switch self {
        case .glass: "Glass"
        case .frosted: "Frosted"
        case .solid: "Solid"
        }
    }

    static var available: [PopupCardStyle] {
        if #available(macOS 26.0, *) { return [.glass, .frosted, .solid] }
        return [.frosted, .solid]
    }

    static var defaultStyle: PopupCardStyle {
        if #available(macOS 26.0, *) { return .glass }
        return .frosted
    }
}
