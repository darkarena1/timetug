import SwiftUI
import TimeTugCore
import WidgetKit

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.timetug.widget.today", provider: AgendaProvider()) { entry in
            TodayView(entry: entry).containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Today's meetings in order.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TodayView: View {
    let entry: AgendaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.isStale(now: entry.date) {
            content(WidgetTimeline.today(snapshot: snapshot, now: entry.date, calendar: .current))
        } else {
            OpenAppPlaceholder()
        }
    }

    @ViewBuilder
    private func content(_ rows: [WidgetTimeline.TodayRow]) -> some View {
        let capacity = family == .systemLarge ? 8 : 2
        let visible = WidgetTimeline.visibleToday(rows: rows, capacity: capacity)
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.date, format: .dateTime.weekday(.wide).month().day())
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if visible.isEmpty {
                Spacer()
                Text("Nothing on today").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(visible.prefix(capacity)) { rowView($0) }
                if visible.count > capacity {
                    Text("+\(visible.count - capacity) more").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func rowView(_ row: WidgetTimeline.TodayRow) -> some View {
        let event = row.event
        let label = HStack(spacing: 8) {
            Capsule().fill(Color(hex: event.colorHex)).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title).font(.callout.weight(row.state == .current ? .semibold : .regular)).lineLimit(1)
                if event.isAllDay {
                    Text("All day").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("\(Text(event.start, style: .time)) – \(Text(event.end, style: .time))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if row.state == .current { Circle().fill(Color(hex: event.colorHex)).frame(width: 7, height: 7) }
        }
        .opacity(row.state == .past ? 0.45 : 1)
        return Group {
            if let url = event.joinURL, row.state != .past { Link(destination: url) { label } } else { label }
        }
    }
}
