import Foundation
import TimeTugCore

/// Builds the text the on-device model sees. Pure, so it is fully testable. Titles, times, place,
/// attendee names, calendar names and truncated notes only: Core already removed emails.
public enum PromptBuilder {
    public static let instructions = """
    You compare two calendar entries that come from different calendars and decide whether they \
    describe the same real-world appointment. Entries about different people or different places \
    are different appointments even at the same time. A short personal placeholder such as \
    "Scott: Doctor" can be the same appointment as a detailed entry such as "Intermountain Health" \
    when the details fit. If you cannot tell, answer unsure. Answer with exactly one word: same, \
    different or unsure.
    """

    public static func prompt(for request: AdjudicationRequest, timeZone: TimeZone = .current) -> String {
        var lines: [String] = []
        if !request.lessons.isEmpty {
            lines.append("Earlier corrections by the user (learn from them):")
            lines += request.lessons.map { "- " + describe($0) }
            lines.append("")
        }
        lines.append("Entry A (more detail):")
        lines += describe(request.first, timeZone: timeZone)
        lines.append("")
        lines.append("Entry B:")
        lines += describe(request.second, timeZone: timeZone)
        lines.append("")
        lines.append("Are A and B the same appointment? Answer same, different or unsure.")
        return lines.joined(separator: "\n")
    }

    private static func describe(_ event: AdjudicationEvent, timeZone: TimeZone) -> [String] {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = timeZone
        day.dateFormat = "yyyy-MM-dd HH:mm"
        let clock = DateFormatter()
        clock.locale = day.locale
        clock.timeZone = timeZone
        clock.dateFormat = "HH:mm"

        var lines = ["  Title: \(event.title)", "  Time: \(day.string(from: event.start)) to \(clock.string(from: event.end))"]
        if let calendar = event.calendarTitle {
            lines.append("  Calendar: " + [calendar, event.accountName.map { "(\($0))" }].compactMap { $0 }.joined(separator: " "))
        }
        if let location = event.location, !location.isEmpty { lines.append("  Location: \(location)") }
        if !event.attendeeNames.isEmpty { lines.append("  Attendees: " + event.attendeeNames.joined(separator: ", ")) }
        if let notes = event.notes, !notes.isEmpty { lines.append("  Notes: \(notes)") }
        return lines
    }

    private static func describe(_ lesson: Lesson) -> String {
        let verdict = lesson.decision == .same ? "the same appointment" : "different appointments"
        return "\"\(lesson.titleA)\" (\(lesson.signalsA)) and \"\(lesson.titleB)\" (\(lesson.signalsB)) were \(verdict)"
    }
}
