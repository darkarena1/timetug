import Foundation

/// Wording for the popup. Pure functions so they can be tested with a fixed locale and time zone.
enum PopupText {
    private static func formatter(_ template: String, _ locale: Locale, _ timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    /// "Thursday".
    static func weekday(now: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        formatter("EEEE", locale, timeZone).string(from: now)
    }

    /// "Sep 18 · 3 meetings left".
    static func summary(now: Date, meetingsLeft: Int, totalTimed: Int,
                        locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let date = formatter("MMMd", locale, timeZone).string(from: now)
        let tail: String
        if totalTimed == 0 { tail = "No meetings today" }
        else if meetingsLeft <= 0 { tail = "No meetings left" }
        else if meetingsLeft == 1 { tail = "1 meeting left" }
        else { tail = "\(meetingsLeft) meetings left" }
        return "\(date) · \(tail)"
    }

    /// "in 3h 40m".
    static func countdown(until start: Date, now: Date) -> String {
        "in " + TimeFormatting.compact(start.timeIntervalSince(now))
    }

    /// "Tugs you 1 min before".
    static func tugFooter(leadTime: TimeInterval) -> String {
        let minutes = Int((leadTime / 60).rounded())
        return minutes <= 0 ? "Tugs you at start" : "Tugs you \(minutes) min before"
    }

    /// Fraction elapsed, clamped to 0...1; 0 for empty or inverted ranges.
    static func progress(start: Date, end: Date, now: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(start) / total))
    }

    /// "30 min", "1 h", "1 h 30 min".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// "3 hours 40 minutes", for VoiceOver.
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        let h = minutes / 60, m = minutes % 60
        var parts: [String] = []
        if h > 0 { parts.append(h == 1 ? "1 hour" : "\(h) hours") }
        if m > 0 { parts.append(m == 1 ? "1 minute" : "\(m) minutes") }
        return parts.isEmpty ? "less than a minute" : parts.joined(separator: " ")
    }

    /// "7:15 PM". Uses a plain space so the text is stable across OS versions.
    static func clock(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        formatter("jmm", locale, timeZone).string(from: date).replacingOccurrences(of: "\u{202F}", with: " ")
    }

    /// "7:15 – 8:00 PM"; the AM/PM marker is written once when both ends share it.
    static func range(_ start: Date, _ end: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let f = formatter("jmm", locale, timeZone)
        let a = clock(start, locale: locale, timeZone: timeZone)
        let b = clock(end, locale: locale, timeZone: timeZone)
        for symbol in [f.amSymbol, f.pmSymbol].compactMap({ $0 }) where a.hasSuffix(" " + symbol) && b.hasSuffix(" " + symbol) {
            return String(a.dropLast(symbol.count + 1)) + " – " + b
        }
        return a + " – " + b
    }
}
