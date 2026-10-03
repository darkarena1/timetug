import CalendarCore
import Foundation

/// Final app-layer guard before opening a URL supplied by a calendar.
enum SafeJoin {
    @discardableResult
    static func open(_ url: URL, using opener: (URL) -> Void) -> Bool {
        guard JoinURLPolicy.isAllowed(url) else { return false }
        opener(url)
        return true
    }
}
