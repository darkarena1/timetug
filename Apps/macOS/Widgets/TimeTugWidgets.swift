import SwiftUI
import WidgetKit

struct SpikeEntry: TimelineEntry { let date: Date; let text: String }

struct SpikeProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpikeEntry { SpikeEntry(date: .now, text: "placeholder") }
    func getSnapshot(in context: Context, completion: @escaping (SpikeEntry) -> Void) { completion(read()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SpikeEntry>) -> Void) {
        completion(Timeline(entries: [read()], policy: .after(.now.addingTimeInterval(300))))
    }
    private func read() -> SpikeEntry {
        let url = AppGroup.containerURL?.appendingPathComponent("spike.txt")
        let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "NO CONTAINER OR FILE"
        return SpikeEntry(date: .now, text: text)
    }
}

struct SpikeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TimeTugSpike", provider: SpikeProvider()) { entry in
            Text(entry.text).containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Spike")
    }
}

@main
struct TimeTugWidgetBundle: WidgetBundle {
    var body: some Widget { SpikeWidget() }
}
