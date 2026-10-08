import Foundation

/// Who a running (or starting) TimeTug is. Written next to the instance lock so a newcomer can compare itself with the
/// holder.
struct InstanceInfo: Codable, Equatable {
    let bundleID: String
    let version: String
    let build: String
    let distribution: Distribution

    /// True for a build made on a developer's machine (Xcode or an untagged `build-release.sh`), which keeps the
    /// `0.0.0-dev` placeholder version. CI stamps every beta, release and store build with a real version.
    var isLocalBuild: Bool { version.hasSuffix("-dev") }

    static var current: InstanceInfo {
        let bundle = Bundle.main
        return InstanceInfo(
            bundleID: bundle.bundleIdentifier ?? "com.timetug.app",
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            distribution: .current)
    }
}

/// Which of two TimeTug copies keeps running: a locally built copy, otherwise the one built later. A developer who
/// launches their own build wants to see it, not the installed app.
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

    /// A local build outranks any other; otherwise the later build number wins. A missing or unreadable build number
    /// counts as 0, so it loses to any real build.
    static func isNewer(_ a: InstanceInfo, than b: InstanceInfo) -> Bool {
        if a.isLocalBuild != b.isLocalBuild { return a.isLocalBuild }
        return (Int(a.build) ?? 0) > (Int(b.build) ?? 0)
    }

    static func decide(me: InstanceInfo, holder: InstanceInfo?) -> Decision {
        guard let holder else { return .exit }
        return isNewer(me, than: holder) ? .askHolderToQuit : .exit
    }
}
