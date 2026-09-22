import CalendarCore
import Foundation
import TimeTugCore

/// One source's calendars for the Calendars pane: Apple Calendar, or one connected account.
struct CalendarSection: Hashable, Identifiable {
    enum Origin: Hashable {
        case appleCalendar
        case account(kindID: String)
        case other
    }

    let id: String
    let origin: Origin
    let title: String
    let subtitle: String
    let groups: [CalendarGroup]
    /// Apple Calendar holds several accounts (iCloud, Exchange, ...) and names them; a connected account is one thing.
    var showsGroupNames: Bool { origin == .appleCalendar }
}

/// What the pane lists: sections of everyday calendars, and the system-style ones (birthdays, subscribed feeds) apart.
struct CalendarLayout: Equatable {
    var sections: [CalendarSection]
    var system: [CalendarInfo]
}

enum CalendarSections {
    static let eventKitSourceID = "eventkit"

    /// System-style calendars are set apart unless Tug is on for them: a calendar that tugs always stays in the main list.
    static func make(
        calendars: [CalendarInfo], connections: [Connection], sourceIDFor: (Connection) -> String, takeoverKeys: Set<String>
    ) -> CalendarLayout {
        let system = calendars.filter { $0.kind != .standard && !takeoverKeys.contains($0.key) }
        let systemKeys = Set(system.map(\.key))
        let main = calendars.filter { !systemKeys.contains($0.key) }

        var sections: [CalendarSection] = []
        func add(id: String, origin: CalendarSection.Origin, title: String, subtitle: String) {
            let own = main.filter { $0.sourceID == id }
            guard !own.isEmpty else { return }
            sections.append(CalendarSection(id: id, origin: origin, title: title, subtitle: subtitle, groups: CalendarGrouping.groups(from: own)))
        }
        add(id: eventKitSourceID, origin: .appleCalendar, title: "Apple Calendar", subtitle: "Calendars on this Mac")
        var known: Set<String> = [eventKitSourceID]
        for connection in connections {
            let id = sourceIDFor(connection)
            known.insert(id)
            add(id: id, origin: .account(kindID: connection.kindID), title: ProviderIcon.displayName(forKindID: connection.kindID),
                subtitle: "\(connection.displayName) \u{00B7} connected directly")
        }
        for id in Set(main.map(\.sourceID)).subtracting(known).sorted() {
            add(id: id, origin: .other, title: "Other", subtitle: "Sources that are no longer connected")
        }
        return CalendarLayout(sections: sections, system: system)
    }
}
