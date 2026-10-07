import Foundation
import OSLog

/// Where TimeTug keeps its files. A team-signed build uses `<App Group container>/TimeTug/`, shared by every TimeTug
/// build and companion app of the team; an ad-hoc build (no group container) keeps using
/// `~/Library/Application Support/TimeTug/`.
enum AppSupportFiles {
    /// Everything this folder holds; these are copied into the group container once.
    static let names = ["accounts.json", "sync-state.json", "takeover-ledger.json", "dedup-state.json"]
    private static let log = Logger(subsystem: "com.timetug.app", category: "migration")

    static func legacyDirectory(fileManager: FileManager = .default) -> URL {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("TimeTug", isDirectory: true)
    }

    static func directory(groupContainer: URL? = AppGroup.containerURL, legacy: URL = legacyDirectory()) -> URL {
        groupContainer?.appendingPathComponent("TimeTug", isDirectory: true) ?? legacy
    }

    static func url(_ name: String) -> URL { directory().appendingPathComponent(name) }

    /// Copies each known file that exists in `legacy` and not yet in `destination`; never overwrites, never deletes the
    /// original. A failed copy is logged and retried on the next launch. Returns the names copied.
    @discardableResult
    static func migrateLegacyFiles(from legacy: URL, to destination: URL, fileManager: FileManager = .default) -> [String] {
        guard legacy.standardizedFileURL != destination.standardizedFileURL else { return [] }
        var copied: [String] = []
        for name in names {
            let source = legacy.appendingPathComponent(name)
            let target = destination.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path), !fileManager.fileExists(atPath: target.path) else { continue }
            let partial = destination.appendingPathComponent(name + ".partial")
            do {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                try? fileManager.removeItem(at: partial)
                try fileManager.copyItem(at: source, to: partial)
                try fileManager.moveItem(at: partial, to: target)
                copied.append(name)
            } catch {
                log.error("Could not copy \(name, privacy: .public) into the App Group: \(String(describing: error), privacy: .public)")
            }
        }
        return copied
    }

    static func migrateIfNeeded() {
        migrateLegacyFiles(from: legacyDirectory(), to: directory())
    }
}
