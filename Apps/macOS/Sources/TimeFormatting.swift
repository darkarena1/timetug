import Foundation
import TimeTugCore

/// macOS presentation text. Core supplies raw dates; wording and truncation live here.
enum TimeFormatting {
    /// "45s", "4m", "1h 5m".
    static func compact(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total >= 3600 { return "\(total / 3600)h \((total % 3600) / 60)m" }
        if total >= 60 { return "\(total / 60)m" }
        return "\(total)s"
    }

    /// "4:05".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Text next to the menu bar icon: nil for icon-only (or countdown with nothing upcoming), "No Meetings" for next-meeting mode with nothing upcoming.
    static func statusTitle(mode: MenuBarDisplayMode, next: TimeTugCalendarEvent?, now: Date) -> String? {
        guard mode != .iconOnly else { return nil }
        guard let next else { return mode == .nextMeeting ? "No Meetings" : nil }
        let remaining = compact(next.start.timeIntervalSince(now))
        switch mode {
        case .iconOnly: return nil
        case .countdown: return remaining
        case .nextMeeting:
            let title = next.title.count > 24 ? String(next.title.prefix(24)) + "…" : next.title
            return "\(title) · \(remaining)"
        }
    }
}
