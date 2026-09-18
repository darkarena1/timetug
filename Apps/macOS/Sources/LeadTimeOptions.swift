import Foundation

struct LeadTimeOption: Hashable, Identifiable {
    let minutes: Int
    let title: String
    var id: Int { minutes }
}

enum LeadTimeOptions {
    static let baseMinutes = [0, 1, 2, 3, 5, 10, 15, 20, 30]

    /// The standard choices plus the currently saved lead time when it is not one of them.
    static func options(including current: TimeInterval) -> [LeadTimeOption] {
        let saved = max(0, Int((current / 60).rounded()))
        let all = Set(baseMinutes + [saved]).sorted()
        return all.map { LeadTimeOption(minutes: $0, title: title(for: $0)) }
    }

    static func title(for minutes: Int) -> String {
        switch minutes {
        case 0: "At start"
        case 1: "1 minute"
        default: "\(minutes) minutes"
        }
    }
}
