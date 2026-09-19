import Foundation
import TimeTugCore

/// Builds the text the on-device model sees. Pure, so it is fully testable. Titles, times, place,
/// attendee names, calendar titles and truncated notes only: Core already removed emails.
public enum PromptBuilder {
    public static let instructions = """
    You compare two calendar entries that come from different calendars and decide whether they \
    describe the same real-world appointment. Entries about different people or different places \
    are different appointments even at the same time. A short personal placeholder such as \
    "Scott: Doctor" can be the same appointment as a detailed entry such as "Intermountain Health" \
    when the details fit. A missing detail (no location, attendees or notes) is not evidence of a \
    mismatch: placeholders are often bare. Different lengths are normal, because one copy may \
    include travel or prep time. Conflicting people or places mean different appointments. \
    When you are unsure, answer unsure. Answer with exactly one word: same, different or unsure.

    Example 1. A: "Intermountain Health" 10:15-10:45, location 1234 Main St. B: "Scott: Doctor" \
    10:00-11:00, bare. Answer: same (a bare placeholder around the detailed visit).
    Example 2. A: "Scott: Doctor" 10:00-11:00, bare. B: "Kristin: Logan Dance" 10:00-11:00, bare. \
    Answer: different (no shared detail, and different people are named).
    Example 3. A: "Team offsite" 09:00-10:00, location Riverside Hall. B: "Lunch" 09:00-10:00, \
    bare. Answer: different (unrelated titles, and nothing ties the bare entry to that place).
    """

    public static func prompt(for request: AdjudicationRequest, timeZone: TimeZone = .current) -> String {
        var lines: [String] = []
        if !request.lessons.isEmpty {
            lines.append("Earlier corrections by the user (learn from them):")
            lines += request.lessons.map { "- " + describe($0) }
            lines.append("")
        }
        let formats = Formatters(timeZone: timeZone)
        lines.append("Entry A (more detail):")
        lines += describe(request.first, formats)
        lines.append("")
        lines.append("Entry B:")
        lines += describe(request.second, formats)
        lines.append("")
        lines += facts(for: request)
        lines.append("")
        lines.append("Are A and B the same appointment? Answer same, different or unsure.")
        return lines.joined(separator: "\n")
    }

    /// Built once per prompt; DateFormatter is expensive to create.
    private struct Formatters {
        let day = DateFormatter()
        let clock = DateFormatter()

        init(timeZone: TimeZone) {
            day.locale = Locale(identifier: "en_US_POSIX")
            day.timeZone = timeZone
            day.dateFormat = "yyyy-MM-dd HH:mm"
            clock.locale = day.locale
            clock.timeZone = timeZone
            clock.dateFormat = "HH:mm"
        }
    }

    private static func describe(_ event: AdjudicationEvent, _ formats: Formatters) -> [String] {
        var lines = ["  Title: \(event.title)", "  Time: \(formats.day.string(from: event.start)) to \(formats.clock.string(from: event.end))"]
        if let calendar = event.calendarTitle { lines.append("  Calendar: \(calendar)") }
        if let location = event.location, !location.isEmpty { lines.append("  Location: \(location)") }
        if !event.attendeeNames.isEmpty { lines.append("  Attendees: " + event.attendeeNames.joined(separator: ", ")) }
        if let notes = event.notes, !notes.isEmpty { lines.append("  Notes: \(notes)") }
        return lines
    }

    /// The rule-computed facts in plain words. Numbers only; no account names or addresses.
    private static func facts(for request: AdjudicationRequest) -> [String] {
        func gap(_ verb: String, _ minutes: Int) -> String {
            minutes == 0 ? "\(verb == "Starts" ? "Start" : "End") at the same time" : "\(verb) \(abs(minutes)) min apart"
        }
        func has(_ summary: String) -> String { summary == "bare" ? "none" : summary }
        let details: String
        switch (request.firstDetails, request.secondDetails) {
        case ("bare", "bare"): details = "Details: neither has any"
        default: details = "Details: A has \(has(request.firstDetails)), B has \(has(request.secondDetails))"
        }
        return [
            "Facts:",
            "- " + gap("Starts", request.startOffsetMinutes),
            "- " + gap("Ends", request.endOffsetMinutes),
            "- Overlap \(request.overlapMinutes) min",
            "- " + details,
            "- " + (request.hasConflictingDetails ? "Conflicting details were found" : "No conflicting details were found"),
        ]
    }

    private static func describe(_ lesson: Lesson) -> String {
        let verdict = lesson.decision == .same ? "the same appointment" : "different appointments"
        return "\"\(lesson.titleA)\" (\(lesson.signalsA)) and \"\(lesson.titleB)\" (\(lesson.signalsB)) were \(verdict)"
    }
}
