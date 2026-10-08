import Foundation

/// Makes sure only one TimeTug runs. Call `arbitrate()` first thing at launch, before any window, status item or
/// calendar read; on `.exit` the process must end without doing anything else.
final class InstanceArbiter {
    enum Outcome: Equatable {
        /// This copy runs. `collidedWith` is the copy it replaced, if any (for the notice).
        case run(collidedWith: InstanceInfo?)
        case exit
    }

    private let me: InstanceInfo
    private let files: InstanceFiles
    private let signals: InstanceSignaling
    private let attempts: Int
    private let pause: () -> Void
    private var lock: InstanceLock?

    /// Waits up to `attempts` x `pause` (50 x 0.1 s = 5 s by default) for the holder to quit.
    init(me: InstanceInfo = .current, files: InstanceFiles = .default, signals: InstanceSignaling = InstanceSignals(),
         attempts: Int = 50, pause: @escaping () -> Void = { usleep(100_000) }) {
        self.me = me
        self.files = files
        self.signals = signals
        self.attempts = attempts
        self.pause = pause
    }

    func arbitrate() -> Outcome {
        if take() { return .run(collidedWith: nil) }
        let holder = files.read(files.recordURL)
        switch InstanceArbitration.decide(me: me, holder: holder) {
        case .exit:
            leaveNotice()
            return .exit
        case .askHolderToQuit:
            files.write(me, to: files.handoffURL)
            signals.postYield()
            for _ in 0..<attempts {
                pause()
                if take() { return .run(collidedWith: holder) }
            }
            leaveNotice()
            return .exit
        }
    }

    /// True when the running copy should quit because a newer one asked it to. A stale or equal request is ignored.
    func shouldYield() -> Bool {
        guard let requester = files.read(files.handoffURL) else { return false }
        return InstanceArbitration.isNewer(requester, than: me)
    }

    func release() { lock = nil }

    private func take() -> Bool {
        guard let acquired = InstanceLock.acquire(at: files.lockURL) else { return false }
        lock = acquired
        files.write(me, to: files.recordURL)
        return true
    }

    private func leaveNotice() {
        files.write(me, to: files.collisionURL)
        signals.postCollision()
    }
}
