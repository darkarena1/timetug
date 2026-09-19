import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: AppModel
    @ObservedObject var navigation: SettingsNavigation
    let onTestTug: () -> Void
    let onForgetCorrections: () -> Void
    @State private var query = ""

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 220)
        } detail: {
            detail
        }
        .searchable(text: $query, placement: .sidebar)
        .frame(minWidth: 720, idealWidth: 780, minHeight: 460, idealHeight: 560)
    }

    private var results: [SettingsSearchItem] {
        SettingsSearch.results(for: query, calendars: model.calendars)
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder private var sidebar: some View {
        if isSearching {
            List(results) { item in
                Button { navigation.reveal(item) } label: {
                    Label {
                        VStack(alignment: .leading) {
                            Text(item.title).foregroundStyle(.primary)
                            Text(item.pane.title).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        PaneIcon(pane: item.pane)
                    }
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView("No results", systemImage: "magnifyingglass")
                }
            }
        } else {
            List(SettingsPane.allCases, selection: $navigation.pane) { pane in
                Label { Text(pane.title).foregroundStyle(.primary) } icon: { PaneIcon(pane: pane) }
                    .tag(pane)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch navigation.pane {
        case .general:
            GeneralPane(settings: settings, navigation: navigation)
        case .calendars:
            CalendarsPane(settings: settings, model: model, navigation: navigation, onForgetCorrections: onForgetCorrections)
        case .tugRules:
            TugRulesPane(settings: settings, navigation: navigation, onTestTug: onTestTug)
        }
    }
}
