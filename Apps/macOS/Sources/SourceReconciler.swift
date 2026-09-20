import CalendarCore
import Foundation
import TimeTugCore

/// Decides which sources exist (EventKit if enabled, then one per stored account), keeps each running source's
/// change listener alive, and replaces sources when asked. Sources are identified by their own `id`.
@MainActor
final class SourceReconciler {
    struct Update {
        let sources: [any TimeTugCore.CalendarSource]
        /// Build errors by connection id, for the Accounts pane.
        let failures: [ConnectionID: String]
    }

    private struct Entry {
        let source: any TimeTugCore.CalendarSource
        let listener: Task<Void, Never>
    }

    private static let eventKitKey = "\u{0}eventkit"
    private let buildAccount: (Connection) throws -> any TimeTugCore.CalendarSource
    private let buildEventKit: () -> any TimeTugCore.CalendarSource
    private let onChange: @MainActor () async -> Void
    private var entries: [String: Entry] = [:]   // keyed by connection id, or `eventKitKey`

    init(
        buildAccount: @escaping (Connection) throws -> any TimeTugCore.CalendarSource,
        buildEventKit: @escaping () -> any TimeTugCore.CalendarSource,
        onChange: @escaping @MainActor () async -> Void
    ) {
        self.buildAccount = buildAccount
        self.buildEventKit = buildEventKit
        self.onChange = onChange
    }

    func sourceID(forConnection id: ConnectionID) -> String? { entries[id]?.source.id }

    func reconcile(connections: [Connection], eventKitEnabled: Bool) -> Update {
        apply(connections: connections, eventKitEnabled: eventKitEnabled, rebuilding: nil)
    }

    /// After a successful re-sign-in: builds a fresh source for `connection` and restarts its listener (a source's
    /// change stream ends after `.sourceFailed`, so an unchanged id would otherwise never poll again).
    func rebuild(_ connection: Connection, connections: [Connection], eventKitEnabled: Bool) -> Update {
        apply(connections: connections, eventKitEnabled: eventKitEnabled, rebuilding: connection.connectionID)
    }

    func stop() {
        entries.values.forEach { $0.listener.cancel() }
        entries = [:]
    }

    private func apply(connections: [Connection], eventKitEnabled: Bool, rebuilding: ConnectionID?) -> Update {
        var wanted: [String] = []
        var failures: [ConnectionID: String] = [:]
        if eventKitEnabled {
            wanted.append(Self.eventKitKey)
            if entries[Self.eventKitKey] == nil { entries[Self.eventKitKey] = start(buildEventKit()) }
        }
        for connection in connections {
            let key = connection.connectionID
            if key == rebuilding {
                // Build the replacement first: a failed build must not take down the source that still works.
                do {
                    let replacement = start(try buildAccount(connection))
                    entries[key]?.listener.cancel()
                    entries[key] = replacement
                } catch {
                    failures[key] = String(describing: error)
                }
            } else if entries[key] == nil {
                do { entries[key] = start(try buildAccount(connection)) }
                catch { failures[key] = String(describing: error); continue }
            }
            if entries[key] == nil { continue }
            wanted.append(key)
        }
        for key in entries.keys where !wanted.contains(key) {
            entries[key]?.listener.cancel()
            entries[key] = nil
        }
        return Update(sources: wanted.compactMap { entries[$0]?.source }, failures: failures)
    }

    private func start(_ source: any TimeTugCore.CalendarSource) -> Entry {
        let onChange = onChange
        let listener = Task { @MainActor in
            for await _ in source.changes() {
                // A removed source's listener may still see a buffered change before cancellation lands.
                if Task.isCancelled { break }
                await onChange()
            }
        }
        return Entry(source: source, listener: listener)
    }
}
