import Foundation

/// Hands out a valid access token, refreshing with the stored refresh token when it is about to expire.
/// Concurrent callers share one in-flight refresh. A rotated refresh token is written back to the store.
public actor AccessTokenProvider {
    public typealias RefreshFunction = @Sendable (String) async throws -> OAuthTokens
    public static let refreshTokenKey = "refresh_token"
    private static let safetyMargin: TimeInterval = 60

    private let connectionID: ConnectionID
    private let credentials: any CredentialStore
    private let refresh: RefreshFunction
    private let now: @Sendable () -> Date
    private var cached: OAuthTokens?
    private var inflight: Task<OAuthTokens, Error>?

    public init(
        connectionID: ConnectionID, credentials: any CredentialStore, refresh: @escaping RefreshFunction,
        now: @escaping @Sendable () -> Date, initial: OAuthTokens? = nil
    ) {
        self.connectionID = connectionID
        self.credentials = credentials
        self.refresh = refresh
        self.now = now
        self.cached = initial
    }

    public func accessToken() async throws -> String {
        if let cached, cached.expiresAt.timeIntervalSince(now()) > Self.safetyMargin { return cached.accessToken }
        return try await refreshShared().accessToken
    }

    /// Drops the cached token (call after a 401) so the next `accessToken()` refreshes.
    public func invalidate() { cached = nil }

    private func refreshShared() async throws -> OAuthTokens {
        if let inflight { return try await inflight.value }
        let task = Task { try await self.performRefresh() }
        inflight = task
        defer { inflight = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> OAuthTokens {
        var secrets = try await credentials.secrets(for: connectionID) ?? [:]
        guard let refreshToken = secrets[Self.refreshTokenKey] else { throw SourceError.authExpired }
        let tokens = try await refresh(refreshToken)
        cached = tokens
        if let rotated = tokens.refreshToken, rotated != refreshToken {
            secrets[Self.refreshTokenKey] = rotated
            try await credentials.setSecrets(secrets, for: connectionID)
        }
        return tokens
    }
}
