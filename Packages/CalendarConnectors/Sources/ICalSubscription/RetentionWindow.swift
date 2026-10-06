import Foundation

/// How far from now a feed's one-off events are kept. Events entirely outside `[now - daysBack, now + daysAhead]` are
/// dropped when the feed is read, and edits to them are not reported as changes. Recurring events are always kept: their
/// occurrences are expanded when asked for. Without a window (the library default) everything is kept.
public struct RetentionWindow: Sendable, Equatable {
    public var daysBack: Int
    public var daysAhead: Int

    public init(daysBack: Int, daysAhead: Int) {
        self.daysBack = max(0, daysBack)
        self.daysAhead = max(0, daysAhead)
    }

    func interval(at now: Date) -> DateInterval {
        DateInterval(start: now.addingTimeInterval(-Double(daysBack) * 86_400), end: now.addingTimeInterval(Double(daysAhead) * 86_400))
    }
}
