import Foundation
import TimeTugCore

/// Persists the takeover ledger as JSON so a relaunch never repeats a takeover.
struct LedgerStore {
    let url: URL

    /// `~/Library/Application Support/TimeTug/takeover-ledger.json`
    static var defaultURL: URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("TimeTug", isDirectory: true)
            .appendingPathComponent("takeover-ledger.json")
    }

    init(url: URL = LedgerStore.defaultURL) { self.url = url }

    /// An empty ledger for a missing or unreadable file (corruption is logged, never fatal).
    func load() -> TakeoverLedger {
        guard FileManager.default.fileExists(atPath: url.path) else { return TakeoverLedger() }
        do {
            return try JSONDecoder().decode(TakeoverLedger.self, from: Data(contentsOf: url))
        } catch {
            TakeoverLog.ledgerLoadFailed(error)
            return TakeoverLedger()
        }
    }

    /// Prunes expired entries before encoding so the file never holds them. Returns false (and
    /// logs) when the file could not be written.
    @discardableResult
    func save(_ ledger: TakeoverLedger, now: Date) -> Bool {
        var pruned = ledger
        pruned.prune(now: now)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(pruned).write(to: url, options: .atomic)
            return true
        } catch {
            TakeoverLog.ledgerSaveFailed(error)
            return false
        }
    }
}
