import CalendarCore
import Foundation

/// What a server said about a version of the feed, sent back on the next request so an unchanged feed costs no body.
struct FeedValidators: Sendable, Equatable {
    var etag: String?
    var lastModified: String?
}

enum FeedResponse: Sendable {
    case notModified
    case body(Data, FeedValidators)
}

/// Downloads a feed. The transport must not follow redirects itself (`URLSessionTransport(followsRedirects: false)`), so
/// every hop is checked here: only `https`, at most `maxRedirects`. No message built here contains the link: it is a credential.
struct FeedFetcher: Sendable {
    static let maxBytes = 10 * 1024 * 1024
    static let maxRedirects = 5
    private static let refusedRedirect = "the feed moved somewhere TimeTug will not follow"

    let transport: any HTTPTransport

    func fetch(_ url: URL, validators: FeedValidators? = nil) async throws -> FeedResponse {
        var current = url
        for _ in 0...Self.maxRedirects {
            var headers = ["Accept": "text/calendar, text/plain;q=0.5, */*;q=0.1"]
            if let etag = validators?.etag { headers["If-None-Match"] = etag }
            if let modified = validators?.lastModified { headers["If-Modified-Since"] = modified }
            let response = try await transport.send(HTTPRequest(url: current, headers: headers))
            switch response.status {
            case 200:
                guard response.body.count <= Self.maxBytes else { throw SourceError.invalidResponse("the feed is too large") }
                return .body(response.body, FeedValidators(etag: response.header("etag"), lastModified: response.header("last-modified")))
            case 304 where validators != nil:
                return .notModified
            case 301, 302, 303, 307, 308:
                guard let location = response.header("location"), let next = URL(string: location, relativeTo: current)?.absoluteURL,
                      next.scheme?.lowercased() == "https" else { throw SourceError.invalidResponse(Self.refusedRedirect) }
                current = next
            case 401, 403, 404, 410:
                throw SourceError.authExpired
            case 429, 500...599:
                throw SourceError.server(status: response.status)
            default:
                throw SourceError.invalidResponse("the feed server answered \(response.status)")
            }
        }
        throw SourceError.invalidResponse("the feed redirected too many times")
    }
}
