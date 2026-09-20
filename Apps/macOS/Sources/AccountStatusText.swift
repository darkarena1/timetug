import TimeTugCore

enum AccountStatusText {
    static func make(_ status: SourceStatus?) -> String {
        switch status {
        case .ok?: "Connected"
        case .authExpired?: "Sign in again"
        case .needsPermission?: "Calendar access is off"
        case .failing?: "Can't reach this calendar right now"
        case nil: "Connecting…"
        }
    }
}
