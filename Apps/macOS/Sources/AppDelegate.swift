import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    /// The unit tests run inside this app. They must never start the real coordinator or touch the user's real files,
    /// preferences or App Group (an empty default written there would stop the one-time copy from old preferences).
    private var isTestHost: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !isTestHost else { return }
        AppSupportFiles.migrateIfNeeded()
        GroupDefaults.migrate(from: .standard, to: GroupDefaults.suite)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isTestHost else { return }
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        Task { await coordinator.start() }
    }
}
