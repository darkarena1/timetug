import Foundation

/// Wording and thresholds for the takeover screen. Pure functions so they can be tested with fixed values.
enum TakeoverText {
    enum Kind: Equatable { case countdown, startingNow, started }
    enum Tone: Equatable { case calm, urgent, late }

    struct Headline: Equatable {
        let kind: Kind
        /// "Starts in" for a countdown; nil otherwise.
        let label: String?
        /// "4:05", "Starting now", "Started 3 min ago".
        let value: String
        let tone: Tone
    }

    /// Seconds a countdown stays urgent, and after start how long "Starting now" shows.
    static let urgentThreshold: TimeInterval = 60

    /// What to show `seconds` before the start (negative once the meeting has started).
    static func headline(startsIn seconds: TimeInterval) -> Headline {
        if seconds > 0 {
            return Headline(kind: .countdown, label: "Starts in", value: clock(seconds),
                            tone: seconds > urgentThreshold ? .calm : .urgent)
        }
        let elapsed = -seconds
        if elapsed < urgentThreshold {
            return Headline(kind: .startingNow, label: nil, value: "Starting now", tone: .urgent)
        }
        let ago = elapsed >= 3600 ? TimeFormatting.compact(elapsed) : "\(Int(elapsed / 60)) min"
        return Headline(kind: .started, label: nil, value: "Started \(ago) ago", tone: .late)
    }

    /// The headline as VoiceOver should say it: "Starts in 45 seconds".
    static func spokenHeadline(startsIn seconds: TimeInterval) -> String {
        if seconds > 0 {
            let total = Int(seconds.rounded(.up))
            let h = total / 3600, m = (total % 3600) / 60, s = total % 60
            var parts: [String] = []
            if h > 0 { parts.append(unit(h, "hour")) }
            if m > 0 { parts.append(unit(m, "minute")) }
            if s > 0 { parts.append(unit(s, "second")) }
            return "Starts in " + parts.joined(separator: " ")
        }
        let elapsed = -seconds
        if elapsed < urgentThreshold { return "Starting now" }
        return "Started \(PopupText.spokenDuration(elapsed)) ago"
    }

    /// "10:00 – 10:30 AM · Work · 6 people"; missing parts are left out.
    static func details(start: Date, end: Date, calendarTitle: String?, otherAttendees: Int,
                        locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        var parts = [PopupText.range(start, end, locale: locale, timeZone: timeZone)]
        if let calendarTitle, !calendarTitle.isEmpty { parts.append(calendarTitle) }
        if otherAttendees > 0 { parts.append("\(otherAttendees + 1) people") }
        return parts.joined(separator: " · ")
    }

    /// "Return joins · Esc dismisses · 1, 5 or 0 snoozes", listing only what applies.
    static func hints(hasJoin: Bool, snoozeOptions: [TimeInterval]) -> String {
        var parts: [String] = []
        if hasJoin { parts.append("Return joins") }
        parts.append("Esc dismisses")
        let keys = snoozeOptions.compactMap(snoozeKey(for:))
        switch keys.count {
        case 0: break
        case 1: parts.append("\(keys[0]) snoozes")
        default: parts.append("\(keys.dropLast().joined(separator: ", ")) or \(keys.last!) snoozes")
        }
        return parts.joined(separator: " · ")
    }

    /// The hint line for VoiceOver, where "0" is spelled out as 10 minutes.
    static func spokenHints(hasJoin: Bool, snoozeOptions: [TimeInterval]) -> String {
        var sentences: [String] = []
        if hasJoin { sentences.append("Return joins.") }
        sentences.append("Escape dismisses.")
        let snoozes = snoozeOptions.compactMap { seconds in
            snoozeKey(for: seconds).map { (key: $0, seconds: seconds) }
        }
        if !snoozes.isEmpty {
            let items = snoozes.enumerated().map { index, item in
                (index == 0 ? "\(item.key) snoozes for " : "\(item.key) for ") + snoozeTitle(item.seconds)
            }
            sentences.append(items.joined(separator: ", ") + ".")
        }
        return sentences.joined(separator: " ")
    }

    /// Number key that snoozes for `seconds`: 60 -> "1", 300 -> "5", 600 -> "0".
    static func snoozeKey(for seconds: TimeInterval) -> String? {
        switch seconds {
        case 60: return "1"
        case 300: return "5"
        case 600: return "0"
        default: return nil
        }
    }

    /// "1 minute", "5 minutes", "10 minutes".
    static func snoozeTitle(_ seconds: TimeInterval) -> String {
        unit(max(1, Int((seconds / 60).rounded())), "minute")
    }

    /// The VoiceOver announcement when the takeover appears.
    static func announcement(title: String, startsIn seconds: TimeInterval) -> String {
        if seconds > 0 { return "\(title) starts in \(PopupText.spokenDuration(seconds))" }
        let elapsed = -seconds
        if elapsed < urgentThreshold { return "\(title) is starting now" }
        return "\(title) started \(PopupText.spokenDuration(elapsed)) ago"
    }

    /// "4:05", or "1:05:00" from an hour up. Rounds up so the last second reads 0:01, not 0:00.
    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        guard total >= 3600 else { return TimeFormatting.clock(TimeInterval(total)) }
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private static func unit(_ n: Int, _ name: String) -> String { n == 1 ? "1 \(name)" : "\(n) \(name)s" }
}
