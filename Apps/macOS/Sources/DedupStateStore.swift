import Foundation
import OSLog
import TimeTugCore

/// Persists lessons and model verdicts as JSON so corrections survive a relaunch.
struct DedupStateStore {
    let url: URL
    private static let log = Logger(subsystem: "com.timetug.app", category: "dedup")

    /// `~/Library/Application Support/TimeTug/dedup-state.json`
    static var defaultURL: URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("TimeTug", isDirectory: true).appendingPathComponent("dedup-state.json")
    }

    init(url: URL = DedupStateStore.defaultURL) { self.url = url }

    /// Empty state for a missing or unreadable file (corruption is logged, never fatal).
    func load() -> DedupState {
        guard FileManager.default.fileExists(atPath: url.path) else { return DedupState() }
        do {
            return try JSONDecoder().decode(DedupState.self, from: Data(contentsOf: url))
        } catch {
            Self.log.error("Could not read dedup state: \(String(describing: error), privacy: .public)")
            return DedupState()
        }
    }

    /// False (and logged) when the file could not be written.
    @discardableResult
    func save(_ state: DedupState) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
            return true
        } catch {
            Self.log.error("Could not save dedup state: \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
