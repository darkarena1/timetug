#if !APPSTORE
import Foundation
import Sparkle

/// Production updater: Sparkle's standard controller with our channel policy.
final class SparkleUpdater: NSObject, UpdaterDriving, SPUUpdaterDelegate {
    private let includeBetas: () -> Bool
    private var controller: SPUStandardUpdaterController!
    var onUpdateCycleFinished: (() -> Void)?

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

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        onUpdateCycleFinished?()
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        UpdateController.allowedChannels(includeBetas: includeBetas())
    }
}
#endif
