import CalendarCore
import Foundation

/// The app-wide diagnostics log: events go to the system log and to a short in-memory ring buffer that backs
/// "Copy Diagnostics". Nothing is written to disk or sent anywhere.
final class AppDiagnostics: @unchecked Sendable {
    static let shared = AppDiagnostics()

    private let buffer: RingBufferDiagnosticLog
    let log: any DiagnosticLog
    private let appVersion: String
    private let appBuild: String
    private let now: @Sendable () -> Date

    init(capacity: Int = 500, extra: [any DiagnosticLog] = [], bundle: Bundle = .main, now: @escaping @Sendable () -> Date = { Date() }) {
        let buffer = RingBufferDiagnosticLog(capacity: capacity)
        self.buffer = buffer
        self.log = FanOutDiagnosticLog([OSLogDiagnosticLog(), buffer] + extra)
        self.appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        self.appBuild = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        self.now = now
    }

    /// A plain-text report safe to share: private fields show `<private>`.
    func report() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        let header = [
            "TimeTug diagnostics",
            "App version: \(appVersion) (\(appBuild))",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Generated: \(formatter.string(from: now()))",
            "",
        ]
        return (header + [buffer.render(includePrivate: false)]).joined(separator: "\n")
    }

    func clear() { buffer.clear() }
}
