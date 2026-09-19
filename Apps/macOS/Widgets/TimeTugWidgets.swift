import SwiftUI
import WidgetKit

@main
struct TimeTugWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextUpWidget()
        TodayWidget()
    }
}
