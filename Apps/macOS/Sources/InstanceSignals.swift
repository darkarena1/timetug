import Foundation

protocol InstanceSignaling {
    func postYield()
    func postCollision()
}

/// Cross-process nudges between TimeTug copies, as Darwin notifications (no payload; the data is in `InstanceFiles`).
struct InstanceSignals: InstanceSignaling {
    static let yieldName = "com.timetug.instance.yield"
    static let collisionName = "com.timetug.instance.collision"

    func postYield() { Self.post(Self.yieldName) }
    func postCollision() { Self.post(Self.collisionName) }

    private static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }

    /// The handler may run on any thread. Keep the observer alive for the process lifetime.
    final class Observer {
        private let name: String
        private let handler: () -> Void

        init(name: String, handler: @escaping () -> Void) {
            self.name = name
            self.handler = handler
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
                { _, observer, _, _, _ in
                    guard let observer else { return }
                    Unmanaged<Observer>.fromOpaque(observer).takeUnretainedValue().handler()
                },
                name as CFString, nil, .deliverImmediately)
        }

        deinit {
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(), nil, nil)
        }
    }
}
