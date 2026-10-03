import Foundation
import TimeTugCore

/// Chooses the next UI wake without rebuilding the agenda for every countdown second.
enum UITickPolicy {
    struct Wake {
        let date: Date
        let rebuildAgenda: Bool
    }

    static func next(now: Date, mode: MenuBarDisplayMode, nextEvent: TimeTugCalendarEvent?,
                     events: [TimeTugCalendarEvent], leadTime: TimeInterval, calendar: Calendar) -> Wake? {
        var choices: [Wake] = []
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        choices.append(Wake(date: midnight, rebuildAgenda: true))
        for event in events {
            for boundary in [event.start, event.end] where boundary > now {
                choices.append(Wake(date: boundary, rebuildAgenda: true))
            }
            let agendaLead = event.start.addingTimeInterval(-leadTime)
            if agendaLead > now { choices.append(Wake(date: agendaLead, rebuildAgenda: true)) }
            let soon = event.start.addingTimeInterval(-MenuBarIconState.soonWindow)
            if soon > now { choices.append(Wake(date: soon, rebuildAgenda: false)) }
        }
        if mode != .iconOnly, let nextEvent, nextEvent.start > now {
            let remaining = nextEvent.start.timeIntervalSince(now)
            let unit: TimeInterval = remaining >= 60 ? 60 : 1
            let fraction = remaining.truncatingRemainder(dividingBy: unit)
            // `compact` truncates whole seconds, so an exact boundary changes just after now.
            let delay = fraction + 0.02
            choices.append(Wake(date: now.addingTimeInterval(delay), rebuildAgenda: false))
        }
        return choices.min { $0.date < $1.date }
    }
}
