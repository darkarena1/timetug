import Foundation
import Sparkle

/// What the app needs from an updater. Tests use a fake; production uses Sparkle.
protocol UpdaterDriving: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var lastUpdateCheckDate: Date? { get }
    func checkForUpdates()
}

/// The Software Update state the Settings pane and the menu need. Sparkle owns the automatic-check
/// preference; the beta opt-in is ours and lives in UserDefaults.
@MainActor
final class UpdateController: ObservableObject {
    private static let betaKey = "updates.includeBetas.v1"
    private let driver: UpdaterDriving
    private let defaults: UserDefaults
    let currentVersion: String

    @Published var automaticallyChecks: Bool {
        didSet { driver.automaticallyChecksForUpdates = automaticallyChecks }
    }
    @Published var includeBetas: Bool {
        didSet { defaults.set(includeBetas, forKey: Self.betaKey) }
    }

    var lastCheckDate: Date? { driver.lastUpdateCheckDate }

    init(driver: UpdaterDriving, defaults: UserDefaults = .standard, currentVersion: String) {
        self.driver = driver
        self.defaults = defaults
        self.currentVersion = currentVersion
        self.automaticallyChecks = driver.automaticallyChecksForUpdates
        self.includeBetas = defaults.bool(forKey: Self.betaKey)
    }

    func checkForUpdates() { driver.checkForUpdates() }

    /// Sparkle channels this Mac may receive. Stable items have no channel and are always allowed.
    nonisolated static func allowedChannels(includeBetas: Bool) -> Set<String> {
        includeBetas ? ["beta"] : []
    }
}

/// Production updater: Sparkle's standard controller with our channel policy.
final class SparkleUpdater: NSObject, UpdaterDriving, SPUUpdaterDelegate {
    private let includeBetas: () -> Bool
    private var controller: SPUStandardUpdaterController!

    init(includeBetas: @escaping () -> Bool) {
        self.includeBetas = includeBetas
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
    var lastUpdateCheckDate: Date? { controller.updater.lastUpdateCheckDate }
    func checkForUpdates() { controller.checkForUpdates(nil) }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        UpdateController.allowedChannels(includeBetas: includeBetas())
    }
}
