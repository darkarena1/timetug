import Foundation
import Testing
import TimeTugCore
@testable import AppleIntelligenceInference

private func event(_ title: String, location: String? = nil, notes: String? = nil,
                   calendar: String? = nil, account: String? = nil, names: [String] = []) -> AdjudicationEvent {
    var info: CalendarInfo?
    if let calendar { info = CalendarInfo(sourceID: "s", calendarID: "c", title: calendar, accountName: account) }
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let source = CalendarEvent(
        sourceEventID: "1", sourceID: "s", calendarID: "c", title: title, start: start,
        end: start.addingTimeInterval(3600), location: location, notes: notes,
        attendees: names.map { Attendee(name: $0, email: "\($0)@example.com") })
    return AdjudicationEvent(source, calendar: info)
}

private func request(lessons: [Lesson] = []) -> AdjudicationRequest {
    AdjudicationRequest(
        id: "r1",
        first: event("Intermountain Health", location: "1234 Main St", notes: "Bring card", calendar: "Work", account: "Exchange", names: ["Dr Lee"]),
        second: event("Scott: Doctor", calendar: "Personal", account: "iCloud"),
        lessons: lessons)
}

@Test func promptListsBothEntriesWithTheirDetails() {
    let prompt = PromptBuilder.prompt(for: request(), timeZone: TimeZone(identifier: "UTC")!)
    #expect(prompt.contains("Intermountain Health"))
    #expect(prompt.contains("Scott: Doctor"))
    #expect(prompt.contains("1234 Main St"))
    #expect(prompt.contains("Bring card"))
    #expect(prompt.contains("Work (Exchange)"))
    #expect(prompt.contains("Dr Lee"))
}

@Test func promptNeverContainsEmailAddresses() {
    let prompt = PromptBuilder.prompt(for: request(), timeZone: TimeZone(identifier: "UTC")!)
    #expect(!prompt.contains("@"))
}

@Test func promptOmitsMissingFieldsAndLessonsSectionWhenEmpty() {
    let prompt = PromptBuilder.prompt(for: request(), timeZone: TimeZone(identifier: "UTC")!)
    #expect(!prompt.contains("Earlier corrections"))
    #expect(prompt.components(separatedBy: "Location:").count == 2)   // only the first entry has one
}

@Test func promptIncludesLessonsAsOneLineEach() {
    var book = LessonBook()
    book.record(MergedMember(title: "Doctor", calendarKey: "s/a", contentKey: "k1", details: "bare"),
                MergedMember(title: "Clinic", calendarKey: "s/b", contentKey: "k2", details: "location"),
                decision: .same, now: Date(timeIntervalSince1970: 1_800_000_000))
    let prompt = PromptBuilder.prompt(for: request(lessons: book.lessons), timeZone: TimeZone(identifier: "UTC")!)
    #expect(prompt.contains("Earlier corrections"))
    #expect(prompt.contains("\"clinic\""))
    #expect(prompt.contains("the same appointment"))
}

@Test func instructionsAskForAConservativeAnswer() {
    #expect(PromptBuilder.instructions.contains("unsure"))
    #expect(PromptBuilder.instructions.contains("different people"))
}
