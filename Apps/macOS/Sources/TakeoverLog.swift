import Foundation
import OSLog
import TimeTugCore

/// Thin wrapper over os.Logger. Event titles are private; ids and reasons are public.
/// Read with: log show --predicate 'subsystem == "com.timetug.app" AND category == "takeover"' --last 1h
enum TakeoverLog {
    private static let logger = Logger(subsystem: "com.timetug.app", category: "takeover")

    /// Why a takeover is shown: "lead time", "late after wake", "snooze expired".
    static func presented(reason: String, event: TimeTugCalendarEvent) {
        logger.info("present (\(reason, privacy: .public)) id=\(event.id, privacy: .public) title=\(event.title, privacy: .private)")
    }

    static func suppressed(_ reason: TakeoverGuard.Reason, event: TimeTugCalendarEvent) {
        logger.info("suppress (\(reason.rawValue, privacy: .public)) id=\(event.id, privacy: .public) title=\(event.title, privacy: .private)")
    }

    static func ledgerLoaded(count: Int) {
        logger.info("ledger loaded (\(count, privacy: .public) fired)")
    }

    static func ledgerLoadFailed(_ error: Error) {
        logger.error("ledger unreadable, starting empty: \(error.localizedDescription, privacy: .public)")
    }

    static func ledgerSaveFailed(_ error: Error? = nil) {
        logger.error("ledger save failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
    }

    static func acknowledgedOnLaunch(count: Int) {
        logger.info("acknowledged \(count, privacy: .public) in-progress meeting(s) on launch")
    }
}
