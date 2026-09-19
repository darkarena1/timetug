import SwiftUI
import TimeTugCore
import WidgetKit

struct NextUpWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.timetug.widget.nextUp", provider: AgendaProvider()) { entry in
            NextUpView(entry: entry).containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Next Up")
        .description("Your current or next meeting, and what follows.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NextUpView: View {
    let entry: AgendaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.isStale(now: entry.date) {
            content(WidgetTimeline.nextUp(snapshot: snapshot, now: entry.date, upcomingLimit: 4))
        } else {
            OpenAppPlaceholder()
        }
    }

    @ViewBuilder
    private func content(_ result: WidgetTimeline.NextUp) -> some View {
        let hero = result.current ?? result.upcoming.first
        let rest = result.current == nil ? Array(result.upcoming.dropFirst()) : result.upcoming
        if let hero {
            HStack(alignment: .top, spacing: 12) {
                heroView(hero, isCurrent: result.current != nil)
                if family == .systemMedium, !rest.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(rest.prefix(3)) { row($0) }
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(hero.joinURL)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle").font(.title2)
                Text("No more meetings").font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }

    private func heroView(_ event: WidgetEvent, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isCurrent ? "NOW" : "NEXT UP").font(.caption2.weight(.semibold)).foregroundStyle(Color(hex: event.colorHex))
            Text(event.title).font(.headline).lineLimit(3)
            Spacer(minLength: 0)
            if isCurrent {
                Text("Ends \(Text(event.end, style: .time))").font(.caption)
            } else {
                Text(event.start, style: .relative).font(.title3.monospacedDigit())
                Text(event.start, style: .time).font(.caption).foregroundStyle(.secondary)
            }
            if event.joinURL != nil {
                Label("Join", systemImage: "video.fill").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ event: WidgetEvent) -> some View {
        let label = HStack(spacing: 6) {
            Capsule().fill(Color(hex: event.colorHex)).frame(width: 3, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title).font(.caption.weight(.medium)).lineLimit(1)
                Text(event.start, style: .time).font(.caption2).foregroundStyle(.secondary)
            }
        }
        return Group {
            if let url = event.joinURL { Link(destination: url) { label } } else { label }
        }
    }
}
