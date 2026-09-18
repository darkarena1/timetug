import SwiftUI
import TimeTugCore

struct CalendarsPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: AppModel
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose which calendars are allowed to tug you away from your work.")
                .font(.callout).foregroundStyle(.secondary)
            Toggle(SettingsText.skipAllDay, isOn: $settings.takeover.skipAllDayEvents)
                .settingsHighlight("skip-all-day", navigation: navigation)
            calendarList
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("Tugging needs the calendar shown in the list: turning on Tug shows it, and hiding it turns Tug off.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private static let tugColumnWidth: CGFloat = 56
    private static let shownColumnWidth: CGFloat = 96
    private static let columnSpacing: CGFloat = 8
    private static let rowPadding: CGFloat = 12

    private var calendarList: some View {
        Group {
            if model.calendars.isEmpty {
                Text("No calendars found. Check calendar access in System Settings.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    headerRow
                    Divider()
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(CalendarGrouping.groups(from: model.calendars)) { group in
                                    Text(group.account)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, Self.rowPadding)
                                        .padding(.top, 10)
                                        .padding(.bottom, 4)
                                    ForEach(group.calendars) { calendar in
                                        calendarRow(calendar)
                                    }
                                }
                            }
                            .padding(.bottom, 8)
                        }
                        .onAppear { scroll(proxy, to: navigation.highlightedID) }
                        .onChange(of: navigation.highlightedID) { _, id in scroll(proxy, to: id) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
    }

    private var headerRow: some View {
        HStack(spacing: Self.columnSpacing) {
            Text("Calendar").frame(maxWidth: .infinity, alignment: .leading)
            Text(SettingsText.tugCheckbox).frame(width: Self.tugColumnWidth)
            Text("Show in list").frame(width: Self.shownColumnWidth)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Self.rowPadding)
        .padding(.vertical, 6)
        .accessibilityHidden(true)
    }

    private func calendarRow(_ calendar: CalendarInfo) -> some View {
        HStack(spacing: Self.columnSpacing) {
            Text(calendar.title)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: takeover(calendar.key))
                .labelsHidden()
                .toggleStyle(ContrastCheckboxStyle())
                .accessibilityLabel("Tug for \(calendar.title)")
                .frame(width: Self.tugColumnWidth)
            Toggle("", isOn: shown(calendar.key))
                .labelsHidden()
                .toggleStyle(ContrastCheckboxStyle())
                .accessibilityLabel("Show \(calendar.title) in list")
                .frame(width: Self.shownColumnWidth)
        }
        .padding(.horizontal, Self.rowPadding)
        .padding(.vertical, 4)
        .settingsHighlight(SettingsSearch.calendarIDPrefix + calendar.key, navigation: navigation)
        .id(calendar.key)
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
