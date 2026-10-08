import Foundation

/// Who a running (or starting) TimeTug is. Written next to the instance lock so a newcomer can compare itself with the
/// holder.
struct InstanceInfo: Codable, Equatable {
    let bundleID: String
    let version: String
    let build: String
    let distribution: Distribution

    static var current: InstanceInfo {
        let bundle = Bundle.main
        return InstanceInfo(
            bundleID: bundle.bundleIdentifier ?? "com.timetug.app",
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            distribution: .current)
    }
}

/// Which of two TimeTug copies keeps running: the one built later.
///
/// The build number is a UTC timestamp shared by every channel (`scripts/ci/compute-versions.sh`), so it orders betas,
/// releases and App Store uploads alike. The version string cannot: a beta is named after the release it follows
/// (`1.4.1-beta.<timestamp>` is built after `1.4.1`), which semantic version order would put below it.
enum InstanceArbitration {
    enum Decision: Equatable {
        /// The newcomer is newer: ask the running copy to quit, then take over.
        case askHolderToQuit
        /// The newcomer is older, equal, or the holder is unknown: the newcomer leaves.
        case exit
    }

    /// A missing or unreadable build number counts as 0, so it loses to any real build.
    static func isNewer(_ a: InstanceInfo, than b: InstanceInfo) -> Bool {
        (Int(a.build) ?? 0) > (Int(b.build) ?? 0)
    }

    static func decide(me: InstanceInfo, holder: InstanceInfo?) -> Decision {
        guard let holder else { return .exit }
        return isNewer(me, than: holder) ? .askHolderToQuit : .exit
    }
}
