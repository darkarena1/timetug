import Foundation

/// Files under `~/Library/Application Support/TimeTug/`, matching `LedgerStore`'s location rule.
enum AppSupportFiles {
    static func url(_ name: String) -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("TimeTug", isDirectory: true).appendingPathComponent(name)
    }
}
