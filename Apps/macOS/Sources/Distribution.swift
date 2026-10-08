import Foundation

/// How this build reached the Mac. The App Store target sets the `APPSTORE` compilation condition.
enum Distribution: String, Codable {
    case direct, appStore

    static var current: Distribution {
        #if APPSTORE
        .appStore
        #else
        .direct
        #endif
    }

    /// The App Store updates its own apps; Sparkle is not allowed there.
    var supportsInAppUpdates: Bool { self == .direct }

    /// How the build is named to the user ("another copy of TimeTug (App Store 2.0.0)").
    var label: String { self == .appStore ? "App Store" : "downloaded" }
}
