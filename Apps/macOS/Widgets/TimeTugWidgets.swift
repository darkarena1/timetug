import SwiftUI
import WidgetKit

@main
struct TimeTugWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextUpWidget()
        TodayWidget()
        if #available(macOS 26.0, *) {
            SkipAllDayControl()
            UseIntelligenceControl()
            EnableTugControl()
        }
    }
}
