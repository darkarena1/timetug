import Foundation

/// Cross-process nudge: the extension posts it after writing `SharedSettings`; the app re-reads the values.
/// The notification carries no payload, so there is no write/read race.
enum SettingsChangeSignal {
    static let name = "com.timetug.settings-changed"

    static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }

    /// The handler may be called on any thread. Registers an unretained pointer: keep the observer alive for the
    /// process lifetime (or release it only when no notifications can be in flight).
    final class Observer {
        private let handler: () -> Void

        init(handler: @escaping () -> Void) {
            self.handler = handler
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
                { _, observer, _, _, _ in
                    guard let observer else { return }
                    Unmanaged<Observer>.fromOpaque(observer).takeUnretainedValue().handler()
                },
                SettingsChangeSignal.name as CFString, nil, .deliverImmediately)
        }

        deinit {
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(), nil, nil)
        }
    }
}
