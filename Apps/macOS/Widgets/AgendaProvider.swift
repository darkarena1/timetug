import TimeTugCore
import WidgetKit

struct AgendaEntry: TimelineEntry {
    let date: Date
    /// nil when the app has not written a snapshot yet.
    let snapshot: WidgetSnapshot?
}

struct AgendaProvider: TimelineProvider {
    func placeholder(in context: Context) -> AgendaEntry {
        AgendaEntry(date: .now, snapshot: .sample(now: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (AgendaEntry) -> Void) {
        let stored = WidgetSnapshotStore().read()
        completion(AgendaEntry(date: .now, snapshot: context.isPreview && stored == nil ? .sample(now: .now) : stored))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AgendaEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshotStore().read()
        var dates = [now]
        if let snapshot {
            dates += WidgetTimeline.changeDates(snapshot: snapshot, now: now, calendar: .current, limit: 40)
        }
        let entries = dates.map { AgendaEntry(date: $0, snapshot: snapshot) }
        // The app reloads timelines when events change; this is the safety net if it is not running.
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
    }
}

extension WidgetSnapshot {
    /// Gallery and placeholder content.
    static func sample(now: Date) -> WidgetSnapshot {
        func event(_ title: String, _ offset: TimeInterval, _ minutes: Int) -> WidgetEvent {
            WidgetEvent(id: title, title: title, start: now.addingTimeInterval(offset),
                        end: now.addingTimeInterval(offset + Double(minutes) * 60), colorHex: "#4C8DF6")
        }
        return WidgetSnapshot(generatedAt: now, events: [
            event("Design review", 900, 30), event("1:1", 5400, 30), event("Planning", 10800, 60),
        ])
    }
}
