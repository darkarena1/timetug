import Foundation
import TimeTugCore

/// Which menu bar icon to show: the template icon, or the color puppy while a tug-worthy meeting is near.
enum MenuBarIconState: Equatable {
    case idle
    case soon

    /// How far ahead of the start the icon turns color.
    static let soonWindow: TimeInterval = 10 * 60

    /// `.soon` when the next pending takeover starts within `soonWindow` (or already started and not ended).
    static func resolve(events: [CalendarEvent], settings: TakeoverSettings,
                        ledger: TakeoverLedger, now: Date) -> MenuBarIconState {
        guard let next = Scheduler.next(events: events, settings: settings, ledger: ledger, now: now),
              next.event.start.timeIntervalSince(now) <= soonWindow else { return .idle }
        return .soon
    }
}
