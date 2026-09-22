import SwiftUI
import TimeTugCore

struct CalendarsPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: AppModel
    @ObservedObject var accounts: AccountsController
    @ObservedObject var navigation: SettingsNavigation
    let onForgetCorrections: () -> Void
    @State private var systemExpanded = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Choose which calendars are allowed to tug you away from your work.")
                        .font(.callout).foregroundStyle(.secondary)
                        .padding(.bottom, 12)
                    if model.calendars.isEmpty {
                        emptyState
                    } else {
                        calendarSections
                    }
                    optionsCard
                }
                .padding(16)
            }
            .onAppear { reveal(navigation.highlightedID, proxy) }
            .onChange(of: navigation.highlightedID) { _, id in reveal(id, proxy) }
        }
    }

    // MARK: Layout

    private static let eyeWidth: CGFloat = 30
    private static let switchWidth: CGFloat = 44

    private var layout: CalendarLayout {
        CalendarSections.make(
            calendars: model.calendars, connections: accounts.accounts,
            sourceIDFor: { accounts.statusKey(for: $0) }, takeoverKeys: settings.takeover.takeoverCalendarKeys)
    }

    private var emptyState: some View {
        Text(settings.eventKitEnabled
             ? "No calendars found. Check calendar access in System Settings."
             : "No calendars to show. Turn on Apple Calendar or add an account in Accounts.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 160)
    }

    @ViewBuilder private var calendarSections: some View {
        let layout = layout
        columnHeader
        ForEach(layout.sections) { section in
            sectionHeader(section)
            card {
                ForEach(section.groups) { group in
                    groupRow(group, named: section.showsGroupNames)
                    ForEach(group.calendars) { calendar in calendarRow(calendar) }
                }
            }
        }
        if !layout.system.isEmpty {
            systemDisclosure(layout.system)
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 10) {
            Text("Tug calendars").font(.subheadline.weight(.medium))
            Spacer()
            Text("Show").frame(width: Self.eyeWidth)
            Text(SettingsText.tugCheckbox).frame(width: Self.switchWidth)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
        .accessibilityHidden(true)
    }

    private func sectionHeader(_ section: CalendarSection) -> some View {
        HStack(spacing: 8) {
            sectionIcon(section.origin)
            Text(section.title).font(.subheadline.weight(.medium))
            Text("\u{00B7} \(section.subtitle)").font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    @ViewBuilder private func sectionIcon(_ origin: CalendarSection.Origin) -> some View {
        switch origin {
        case .appleCalendar: Image(systemName: "calendar").frame(width: 20, height: 20)
        case .account(let kindID): ProviderIcon(kindID: kindID, size: 20)
        case .other: Image(systemName: "questionmark.circle").frame(width: 20, height: 20)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
    }

    // MARK: Rows

    /// The account line inside a card: its name and one switch for every calendar under it.
    private func groupRow(_ group: CalendarGroup, named: Bool) -> some View {
        let keys = group.calendars.map(\.key)
        let all = Binding(
            get: { keys.allSatisfy { settings.takeover.takeoverCalendarKeys.contains($0) } },
            set: { on in
                var updated = settings.takeover
                updated.setTakeover(on, forCalendars: keys)
                settings.takeover = updated
            })
        return HStack(spacing: 10) {
            Text(named ? group.account : "All calendars")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text("All").font(.caption2).foregroundStyle(.secondary)
            Toggle("", isOn: all)
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                .accessibilityLabel("Tug for every calendar in \(group.account)")
                .frame(width: Self.switchWidth)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color(nsColor: .quaternarySystemFill))
    }

    private func calendarRow(_ calendar: CalendarInfo) -> some View {
        let tug = takeover(calendar.key)
        let isShown = shown(calendar.key)
        return VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Circle().fill(Color(hex: calendar.colorHex) ?? .secondary).frame(width: 10, height: 10)
                Text(calendar.title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Button { isShown.wrappedValue.toggle() } label: {
                    Image(systemName: isShown.wrappedValue ? "eye" : "eye.slash").frame(width: Self.eyeWidth)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(tug.wrappedValue)
                .help(tug.wrappedValue ? "Shown while Tug is on" : (isShown.wrappedValue ? "Hide from the list" : "Show in the list"))
                .accessibilityLabel("Show \(calendar.title) in list")
                .accessibilityValue(isShown.wrappedValue ? "On" : "Off")
                Toggle("", isOn: tug)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .accessibilityLabel("Tug for \(calendar.title)")
                    .frame(width: Self.switchWidth)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
        }
        .settingsHighlight(SettingsSearch.calendarIDPrefix + calendar.key, navigation: navigation)
        .id(calendar.key)
    }

    private func systemDisclosure(_ calendars: [CalendarInfo]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 16)
            card {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { systemExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(systemExpanded ? 90 : 0))
                            .frame(width: 12)
                        Text("Subscribed and system calendars")
                        Spacer()
                        Text("\(calendars.count)").foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if systemExpanded {
                    ForEach(calendars) { calendarRow($0) }
                }
            }
        }
    }

    // MARK: Options

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Options").font(.subheadline.weight(.medium))
                .padding(.horizontal, 4).padding(.top, 20).padding(.bottom, 6)
            card {
                HStack {
                    Text(SettingsText.skipAllDay)
                    Spacer()
                    Toggle("", isOn: $settings.takeover.skipAllDayEvents)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .accessibilityLabel(SettingsText.skipAllDay)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .settingsHighlight("skip-all-day", navigation: navigation)
                Divider()
                duplicatesControl
            }
        }
    }

    private var duplicatesControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(SettingsText.dedupInference)
                BetaBadge().help(Self.inferenceExplanation)
                Spacer(minLength: 0)
                Toggle("", isOn: $settings.inferenceEnabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .accessibilityLabel(SettingsText.dedupInference)
            }
            .help(Self.inferenceExplanation)
            if settings.inferenceEnabled {
                if let status = InferenceStatusText.make(model.inferenceStatus) {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
                Text(Self.inferenceExplanation).font(.footnote).foregroundStyle(.secondary)
                Button("Forget learned corrections", action: onForgetCorrections)
                    .buttonStyle(.link).font(.footnote)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .settingsHighlight("dedup-inference", navigation: navigation)
    }

    static let inferenceExplanation = "When this is on, Apple Intelligence will attempt to merge events that may have different start times and descriptions if they seem similar. It runs on your Mac and nothing leaves it."

    // MARK: Bindings and search

    /// Scrolls to a searched calendar, opening the system group first when that is where it lives.
    private func reveal(_ highlightID: String?, _ proxy: ScrollViewProxy) {
        guard let highlightID, highlightID.hasPrefix(SettingsSearch.calendarIDPrefix) else { return }
        let key = String(highlightID.dropFirst(SettingsSearch.calendarIDPrefix.count))
        if layout.system.contains(where: { $0.key == key }) { systemExpanded = true }
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
