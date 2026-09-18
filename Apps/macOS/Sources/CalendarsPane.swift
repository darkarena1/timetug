import SwiftUI
import TimeTugCore

struct CalendarsPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: AppModel
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose which calendars can take over your screen.")
                .font(.callout).foregroundStyle(.secondary)
            Toggle(SettingsText.skipAllDay, isOn: $settings.takeover.skipAllDayEvents)
                .settingsHighlight("skip-all-day", navigation: navigation)
            calendarList
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("Takeover needs the calendar shown in the list: turning on Takeover shows it, and hiding it turns Takeover off.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private var calendarList: some View {
        Group {
            if model.calendars.isEmpty {
                Text("No calendars found. Check calendar access in System Settings.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(model.calendars) { calendar in
                        HStack {
                            Text(calendar.title)
                            Spacer()
                            Toggle("Takeover", isOn: takeover(calendar.key))
                            Toggle("Show in list", isOn: shown(calendar.key))
                        }
                        .toggleStyle(.checkbox)
                        .settingsHighlight(SettingsSearch.calendarIDPrefix + calendar.key, navigation: navigation)
                        .id(calendar.key)
                    }
                    .listStyle(.plain)
                    .onAppear { scroll(proxy, to: navigation.highlightedID) }
                    .onChange(of: navigation.highlightedID) { _, id in scroll(proxy, to: id) }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
    }

    private func scroll(_ proxy: ScrollViewProxy, to highlightID: String?) {
        guard let highlightID, highlightID.hasPrefix(SettingsSearch.calendarIDPrefix) else { return }
        let key = String(highlightID.dropFirst(SettingsSearch.calendarIDPrefix.count))
        withAnimation { proxy.scrollTo(key, anchor: .center) }
    }

    private func takeover(_ key: String) -> Binding<Bool> {
        Binding(
            get: { settings.takeover.takeoverCalendarKeys.contains(key) },
            set: { settings.takeover.setTakeover($0, forCalendar: key) }
        )
    }

    private func shown(_ key: String) -> Binding<Bool> {
        Binding(
            get: { settings.takeover.isShownInList(key) },
            set: { settings.takeover.setShownInList($0, forCalendar: key) }
        )
    }
}
