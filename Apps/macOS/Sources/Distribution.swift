import Foundation

/// Which build of TimeTug this is. The App Store build sets `TimeTugDistribution` to `appStore` in its Info.plist.
enum Distribution: String, Codable {
    case direct, appStore

    static var current: Distribution {
        (Bundle.main.object(forInfoDictionaryKey: "TimeTugDistribution") as? String).flatMap(Distribution.init(rawValue:)) ?? .direct
    }

    /// How the user knows this build: "downloaded" or "App Store".
    var label: String { self == .appStore ? "App Store" : "downloaded" }
}
