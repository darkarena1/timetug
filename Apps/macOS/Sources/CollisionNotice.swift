import Foundation

/// The quiet "you have two copies" hint shown by the copy that keeps running.
struct CollisionNotice: Equatable {
    /// Group-suite key holding the pair the user dismissed.
    static let dismissedKey = "collision.dismissedPair.v1"

    let message: String
    /// Stable for the same two builds from either side; a new version of either one makes a new pair.
    let pairKey: String

    static func make(survivor: InstanceInfo, other: InstanceInfo) -> CollisionNotice {
        func name(_ info: InstanceInfo) -> String { "\(info.distribution.label) \(info.version)" }
        let message = "Another copy of TimeTug (\(name(other))) was opened. Only one copy runs at a time, and this one "
            + "(\(name(survivor))) is the one running. Keeping just one installed avoids this."
        let key = [survivor, other].map { "\($0.distribution.rawValue)-\($0.version)" }.sorted().joined(separator: "+")
        return CollisionNotice(message: message, pairKey: key)
    }

    static func shouldShow(_ notice: CollisionNotice, dismissedPair: String?) -> Bool {
        notice.pairKey != dismissedPair
    }
}
