import Darwin
import Foundation

/// An exclusive advisory lock on a file. Held until the object is released or the process ends, so a crash never
/// leaves a stale lock.
final class InstanceLock {
    private let descriptor: Int32

    private init(descriptor: Int32) { self.descriptor = descriptor }

    /// nil when another process (or another holder in this one) has the lock, or the file cannot be opened.
    static func acquire(at url: URL) -> InstanceLock? {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        return InstanceLock(descriptor: descriptor)
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}

/// The small files the instances use to find each other, all in one folder.
struct InstanceFiles {
    let directory: URL

    init(directory: URL) { self.directory = directory }

    /// The same folder the app's other state lives in, so an ad-hoc dev build never collides with an installed one.
    static var `default`: InstanceFiles { InstanceFiles(directory: AppSupportFiles.directory()) }

    var lockURL: URL { directory.appendingPathComponent("instance.lock") }
    /// Who holds the lock.
    var recordURL: URL { directory.appendingPathComponent("instance.json") }
    /// A newcomer's request that the holder quit (the newcomer's own info).
    var handoffURL: URL { directory.appendingPathComponent("instance-handoff.json") }
    /// A copy that was opened and left; the survivor shows the notice about it.
    var collisionURL: URL { directory.appendingPathComponent("instance-collision.json") }

    func read(_ url: URL) -> InstanceInfo? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(InstanceInfo.self, from: $0) }
    }

    func write(_ info: InstanceInfo, to url: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(info).write(to: url, options: .atomic)
    }
}
