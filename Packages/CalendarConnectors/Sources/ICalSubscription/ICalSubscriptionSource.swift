import CalendarCore
import Foundation
import ICalendar

/// What the source has loaded: the parsed feed, the bytes it came from (to spot a change) and what the server said
/// about that version.
actor FeedState {
    private(set) var feed: ParsedFeed?
    private(set) var body: Data?
    private(set) var validators: FeedValidators?
    private(set) var fetchedAt: Date?
    private var issued = 0
    private var storedGeneration = 0
    private var reportedBody: Data?
    private var reportedGeneration = 0

    /// Taken when a fetch starts, so a fetch that finishes after a newer one can be told apart.
    func nextGeneration() -> Int {
        issued += 1
        return issued
    }

    /// Keeps the feed only if no newer fetch has stored one already.
    func store(feed: ParsedFeed, body: Data, validators: FeedValidators, generation: Int, at date: Date) {
        guard generation > storedGeneration else { return }
        storedGeneration = generation
        self.feed = feed
        self.body = body
        self.validators = validators
        fetchedAt = date
    }

    /// What `checkForChanges` last saw, independent of what `events(in:)` loaded. The first report has no earlier one, so
    /// `prior` (the body held when the check began) stands in for it. A check whose fetch is older than one already
    /// reported says nothing, so overlapping checks report a change once and never report one backwards.
    func report(_ body: Data, generation: Int, prior: Data?) -> Bool {
        guard generation > reportedGeneration else { return false }
        reportedGeneration = generation
        let last = reportedBody ?? prior
        reportedBody = body
        return last != nil && last != body
    }

    /// The feed is unchanged: keep what is held and restart its age.
    func unchanged(validators: FeedValidators?, at date: Date) {
        if let validators, validators.etag != nil || validators.lastModified != nil { self.validators = validators }
        fetchedAt = date
    }
}

/// One iCal subscription link: a read-only calendar of whatever the feed holds, re-read when it is older than `maxAge`.
public final class ICalSubscriptionSource: PollingCalendarSource {
    static let calendarID = "feed"

    private let connection: Connection
    private let link: @Sendable () async throws -> URL
    private let fetcher: FeedFetcher
    private let monitor: ChangeMonitor
    private let maxAge: TimeInterval
    private let now: @Sendable () -> Date
    private let defaultZone: TimeZone
    private let state = FeedState()

    /// `link` is read on every fetch, so a replaced link (after `reauthorize`) is picked up without rebuilding the source.
    init(
        connection: Connection, link: @escaping @Sendable () async throws -> URL, transport: any HTTPTransport,
        monitor: ChangeMonitor, maxAge: TimeInterval, now: @escaping @Sendable () -> Date, defaultZone: TimeZone
    ) {
        self.connection = connection
        self.link = link
        self.fetcher = FeedFetcher(transport: transport)
        self.monitor = monitor
        self.maxAge = maxAge
        self.now = now
        self.defaultZone = defaultZone
    }

    public var id: String { connection.sourceID }
    public var displayName: String { connection.displayName }

    public var capabilities: SourceCapabilities {
        SourceCapabilities(providedFields: [.series, .uidScope, .provider, .calendarTimeZone], syncKind: .token)
    }

    public func calendars() async throws -> [CalendarDescriptor] {
        let feed = try await currentFeed()
        return [CalendarDescriptor(
            id: Self.calendarID, title: feed.name ?? connection.displayName, service: .iCalSubscription, colorHex: feed.colorHex,
            permissions: CalendarPermissions(canViewDetails: true, canEdit: false), isDefault: false,
            timeZone: feed.timeZone ?? defaultZone, accountName: connection.displayName, kind: .subscribed, provider: .subscription)]
    }

    public func events(in interval: DateInterval) async throws -> [CalendarEvent] {
        let feed = try await currentFeed()
        let zone = feed.timeZone ?? defaultZone
        var events: [CalendarEvent] = []
        for item in feed.resources {
            let context = EventReadContext(
                calendarID: Self.calendarID, resourceName: item.name, etag: nil, sourceID: id, calendarZone: zone, selfAddresses: [])
            events += EventReader.events(in: item.resource, overlapping: interval, context: context)
        }
        return events.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    public func changes() -> AsyncStream<CalendarChange> { monitor.changes(polling: self) }

    /// Re-reads the feed. The first check with nothing loaded yet is the baseline and reports nothing; a feed loaded
    /// earlier by `events(in:)` counts as the baseline, so a change since then is reported.
    public func checkForChanges() async throws -> CalendarChange? {
        let prior = await state.body
        let fetched = try await refresh()
        let changed = await state.report(fetched.body, generation: fetched.generation, prior: prior)
        return changed ? .eventsChanged(calendarIDs: [Self.calendarID]) : nil
    }

    private func currentFeed() async throws -> ParsedFeed {
        if let feed = await state.feed, let fetchedAt = await state.fetchedAt, now().timeIntervalSince(fetchedAt) < maxAge { return feed }
        try await refresh()
        guard let feed = await state.feed else { throw SourceError.invalidResponse("the feed has not loaded") }
        return feed
    }

    /// Fetches the feed (conditionally when the server gave validators) and returns the body the server holds, with the
    /// generation the fetch started under. A body that is not a calendar throws and leaves the last good feed in place; a
    /// fetch that finishes after a newer one does not replace what that one stored.
    @discardableResult
    private func refresh() async throws -> (body: Data, generation: Int) {
        let url = try await link()
        let generation = await state.nextGeneration()
        let previous = await state.body
        let validators = await state.validators.flatMap { $0.etag != nil || $0.lastModified != nil ? $0 : nil }
        switch try await fetcher.fetch(url, validators: previous == nil ? nil : validators) {
        case .notModified:
            await state.unchanged(validators: nil, at: now())
            return (previous ?? Data(), generation)
        case .body(let data, let newValidators):
            if let previous, previous == data {
                await state.unchanged(validators: newValidators, at: now())
                return (data, generation)
            }
            let feed = try FeedParser.parse(data)
            await state.store(feed: feed, body: data, validators: newValidators, generation: generation, at: now())
            return (data, generation)
        }
    }
}
