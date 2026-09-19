import TimeTugCore

extension InferenceStatus {
    /// False only when on-device intelligence definitively cannot run here. A user-disabled feature
    /// (`.disabled`) says nothing about the hardware, so it counts as available.
    var isAvailableOnThisMac: Bool {
        switch self {
        case .disabled, .active: true
        case .noEngine, .unavailable, .notOnDevice: false
        }
    }
}
