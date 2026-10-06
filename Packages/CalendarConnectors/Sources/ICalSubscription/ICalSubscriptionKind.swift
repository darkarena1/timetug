import CalendarCore
import Foundation

/// A calendar subscription link (Meetup's Add to calendar links, a Google secret address, ...). One secret field: the
/// link. It is the credential, so it is stored only in the `CredentialStore`; the connection keeps just the host.
public struct ICalSubscriptionKind: ConnectorKind, CredentialPromptHelp {
    public static let kindID = "icalsub"
    static let linkKey = "link"
    private static let fields = [CredentialField(key: ICalSubscriptionKind.linkKey, label: "iCal link", isSecret: true)]

    private let transport: any HTTPTransport
    private let now: @Sendable () -> Date
    private let sleep: Sleeper
    private let pollInterval: Duration
    private let defaultZone: TimeZone

    public init(
        transport: any HTTPTransport = URLSessionTransport(followsRedirects: false), now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping Sleeper = defaultSleeper, pollInterval: Duration = .seconds(900), defaultZone: TimeZone = .current
    ) {
        self.transport = transport
        self.now = now
        self.sleep = sleep
        self.pollInterval = pollInterval
        self.defaultZone = defaultZone
    }

    public var id: String { Self.kindID }
    public var displayName: String { "iCal link" }
    public var supportedPlatforms: Platform { [.macOS, .iOS, .linux, .windows] }
    public var authorization: AuthorizationMethod { .password(fields: Self.fields) }
    public var credentialHelp: CredentialHelp? {
        CredentialHelp(
            text: "Paste a calendar subscription link (webcal:// or https://). Do not use a downloaded .ics file: it will not update. "
                + "In Meetup, open Your events, choose Add to calendar, and copy any link in the menu.",
            linkTitle: "Open Meetup Your events", url: URL(string: "https://www.meetup.com/your-events/"))
    }

    public func authorize(using interaction: any AuthorizationInteraction, credentials: any CredentialStore) async throws -> Connection {
        let (url, feed) = try await signIn(using: interaction)
        let host = url.host ?? ""
        let name = feed.name.map { "\($0) (\(host))" } ?? host
        let connection = Connection(kindID: id, connectionID: UUID().uuidString, displayName: name, config: ["host": host])
        try await credentials.setSecrets([Self.linkKey: url.absoluteString], for: connection.connectionID)
        return connection
    }

    /// Replaces the stored link (after the provider revoked or regenerated it). The old link stays if the new one fails.
    public func reauthorize(_ connection: Connection, using interaction: any AuthorizationInteraction, credentials: any CredentialStore) async throws -> Connection {
        let (url, _) = try await signIn(using: interaction)
        try await credentials.setSecrets([Self.linkKey: url.absoluteString], for: connection.connectionID)
        var updated = connection
        updated.config["host"] = url.host ?? ""
        return updated
    }

    public func makeSource(for connection: Connection, credentials: any CredentialStore, syncState: any SyncStateStore) throws -> any CalendarSource {
        let connectionID = connection.connectionID
        return ICalSubscriptionSource(
            connection: connection,
            link: {
                guard let text = try await credentials.secrets(for: connectionID)?[Self.linkKey], let url = URL(string: text) else {
                    throw SourceError.authExpired
                }
                return url
            },
            transport: transport, monitor: ChangeMonitor(interval: pollInterval, sleep: sleep),
            maxAge: Double(pollInterval.components.seconds), now: now, defaultZone: defaultZone)
    }

    /// Nothing is stored here: callers store the link only after the feed has loaded and parsed.
    private func signIn(using interaction: any AuthorizationInteraction) async throws -> (URL, ParsedFeed) {
        let values = try await interaction.promptCredentials(Self.fields)
        let url = try FeedLocation.url(from: values[Self.linkKey] ?? "")
        guard case .body(let data, _) = try await FeedFetcher(transport: transport).fetch(url) else {
            throw SourceError.invalidResponse("the feed did not answer")
        }
        return (url, try FeedParser.parse(data))
    }
}
