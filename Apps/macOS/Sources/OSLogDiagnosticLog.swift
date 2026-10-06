import CalendarCore
import Foundation
import os

/// How one `DiagnosticEvent` is written to the system log: a public part and a private part, so each can be
/// interpolated with its own static privacy (OSLog needs the privacy at compile time, not per value).
struct OSLogRendering: Equatable {
    /// `name` followed by the public fields (`events=12`), and the names of private fields as `uid=<private>`.
    var publicText: String
    /// The private fields with their values (`uid=abc`), space separated; empty when there are none.
    var privateText: String

    /// One piece of the message with its privacy flag, in field order.
    struct Piece: Equatable {
        var text: String
        var isPrivate: Bool
    }

    static func pieces(for event: DiagnosticEvent) -> [Piece] {
        [Piece(text: event.name, isPrivate: false)]
            + event.fields.map { Piece(text: "\($0.name)=\($0.unredactedText)", isPrivate: $0.isPrivate) }
    }

    init(event: DiagnosticEvent) {
        let all = Self.pieces(for: event)
        publicText = all.filter { !$0.isPrivate }.map(\.text).joined(separator: " ")
        privateText = all.filter(\.isPrivate).map(\.text).joined(separator: " ")
    }
}

/// Writes diagnostic events to the unified system log under subsystem `com.timetug.app`, category = the event's category.
final class OSLogDiagnosticLog: DiagnosticLog, @unchecked Sendable {
    static let subsystem = "com.timetug.app"

    private let lock = NSLock()
    private var loggers: [String: Logger] = [:]

    static func osLogType(for level: DiagnosticLevel) -> OSLogType {
        switch level {
        case .debug: .debug
        case .info: .info
        case .notice: .default
        case .warning: .error
        case .error: .fault
        }
    }

    private func logger(for category: String) -> Logger {
        lock.withLock {
            if let existing = loggers[category] { return existing }
            let created = Logger(subsystem: Self.subsystem, category: category)
            loggers[category] = created
            return created
        }
    }

    func record(_ event: DiagnosticEvent) {
        let rendering = OSLogRendering(event: event)
        let logger = logger(for: event.category)
        let type = Self.osLogType(for: event.level)
        if rendering.privateText.isEmpty {
            logger.log(level: type, "\(rendering.publicText, privacy: .public)")
        } else {
            logger.log(level: type, "\(rendering.publicText, privacy: .public) \(rendering.privateText, privacy: .private)")
        }
    }
}
