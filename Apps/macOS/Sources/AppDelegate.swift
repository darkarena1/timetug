import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private let arbiter = InstanceArbiter()
    private var yieldObserver: InstanceSignals.Observer?
    private var collisionObserver: InstanceSignals.Observer?
    /// The other copy to tell the user about, kept until the coordinator exists.
    private var pendingCollision: InstanceInfo?

    /// The unit tests run inside this app. They must never start the real coordinator or touch the user's real files,
    /// preferences or App Group (an empty default written there would stop the one-time copy from old preferences).
    private var isTestHost: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !isTestHost else { return }
        // Before anything reads or writes state: a second copy must leave without side effects.
        switch arbiter.arbitrate() {
        case .exit:
            exit(0)
        case .run(let replaced):
            pendingCollision = replaced
        }
        AppSupportFiles.migrateIfNeeded()
        GroupDefaults.migrate(from: .standard, to: GroupDefaults.suite)
        yieldObserver = InstanceSignals.Observer(name: InstanceSignals.yieldName) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.arbiter.shouldYield() else { return }
                NSApp.terminate(nil)
            }
        }
        collisionObserver = InstanceSignals.Observer(name: InstanceSignals.collisionName) { [weak self] in
            DispatchQueue.main.async { self?.showCollisionFromFile() }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isTestHost else { return }
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        if let other = pendingCollision { coordinator.noteCollision(with: other) }
        pendingCollision = nil
        Task { await coordinator.start() }
    }

    private func showCollisionFromFile() {
        let files = InstanceFiles.default
        guard let other = files.read(files.collisionURL) else { return }
        if let coordinator { coordinator.noteCollision(with: other) } else { pendingCollision = other }
    }
}
