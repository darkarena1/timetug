import TimeTugCore

/// Words for the state of the on-device duplicate finder. nil means show nothing.
enum InferenceStatusText {
    static func make(_ status: InferenceStatus) -> String? {
        switch status {
        case .disabled: nil
        case .noEngine: "No on-device model is available on this Mac. Using rules only."
        case .unavailable(let reason): "The on-device model isn't available (\(reason)). Using rules only."
        case .notOnDevice: "That engine doesn't run on your device, so it isn't used. Using rules only."
        case .active(let engine): "Using \(engine.displayName)."
        }
    }
}
