import Foundation

/// What the app needs from an updater. Tests use a fake; production uses Sparkle.
protocol UpdaterDriving: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var lastUpdateCheckDate: Date? { get }
    /// Called when an update cycle ends (possibly off the main thread), so `lastUpdateCheckDate` can be re-read.
    var onUpdateCycleFinished: (() -> Void)? { get set }
    func checkForUpdates()
}

/// The Software Update state the Settings pane and the menu need. Sparkle owns the automatic-check
/// preference; the beta opt-in is ours and lives in UserDefaults.
@MainActor
final class UpdateController: ObservableObject {
    nonisolated static let betaKey = "updates.includeBetas.v1"
    private let driver: UpdaterDriving
    private let defaults: UserDefaults
    let currentVersion: String
    /// False in builds without an in-app updater (the App Store build): the Settings pane and menu hide Software Update.
    let isAvailable: Bool

    @Published var automaticallyChecks: Bool {
        didSet { driver.automaticallyChecksForUpdates = automaticallyChecks }
    }
    @Published var includeBetas: Bool {
        didSet { defaults.set(includeBetas, forKey: Self.betaKey) }
    }

    var lastCheckDate: Date? { driver.lastUpdateCheckDate }

    init(driver: UpdaterDriving, defaults: UserDefaults = .standard, currentVersion: String,
         isAvailable: Bool = Distribution.current.supportsInAppUpdates) {
        self.driver = driver
        self.defaults = defaults
        self.currentVersion = currentVersion
        self.isAvailable = isAvailable
        self.automaticallyChecks = driver.automaticallyChecksForUpdates
        self.includeBetas = defaults.bool(forKey: Self.betaKey)
        driver.onUpdateCycleFinished = { [weak self] in
            Task { @MainActor in self?.objectWillChange.send() }
        }
    }

    func checkForUpdates() { driver.checkForUpdates() }

    /// Sparkle channels this Mac may receive. Stable items have no channel and are always allowed.
    nonisolated static func allowedChannels(includeBetas: Bool) -> Set<String> {
        includeBetas ? ["beta"] : []
    }
}

/// Inert updater for the XCTest host, so the test run never starts live Sparkle.
final class NoOpUpdater: UpdaterDriving {
    var automaticallyChecksForUpdates = false
    var lastUpdateCheckDate: Date? { nil }
    var onUpdateCycleFinished: (() -> Void)?
    func checkForUpdates() {}
}
