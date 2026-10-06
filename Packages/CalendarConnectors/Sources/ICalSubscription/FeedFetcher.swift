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
    private static let unreachable = "the feed could not be reached"
    private static let refusedRedirect = "the feed moved somewhere TimeTug will not follow"

    let transport: any HTTPTransport

    func fetch(_ url: URL, validators: FeedValidators? = nil) async throws -> FeedResponse {
        var current = url
        for hop in 0...Self.maxRedirects {
            var headers = ["Accept": "text/calendar, text/plain;q=0.5, */*;q=0.1"]
            // Validators describe the version the original link served; a redirect target never validated it.
            if hop == 0 {
                if let etag = validators?.etag { headers["If-None-Match"] = etag }
                if let modified = validators?.lastModified { headers["If-Modified-Since"] = modified }
            }
            let conditional = headers["If-None-Match"] != nil || headers["If-Modified-Since"] != nil
            let response = try await send(HTTPRequest(url: current, headers: headers))
            switch response.status {
            case 200:
                guard response.body.count <= Self.maxBytes else { throw SourceError.invalidResponse("the feed is too large") }
                return .body(response.body, FeedValidators(etag: response.header("etag"), lastModified: response.header("last-modified")))
            case 304 where conditional:
                return .notModified
            case 301, 302, 303, 307, 308:
                guard let location = response.header("location"), let next = URL(string: location, relativeTo: current)?.absoluteURL,
                      next.scheme?.lowercased() == "https", next.user == nil, next.password == nil else { throw SourceError.invalidResponse(Self.refusedRedirect) }
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

    /// The transport's failure, without the link. `SourceError.network` is the transport's contract, but a message (or a
    /// stray error such as a `URLError`) can carry the address, and the address is a credential.
    private func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        do { return try await transport.send(request) }
        catch is CancellationError { throw CancellationError() }
        catch SourceError.network(let message) {
            let path = request.url.path
            let leaks = message.contains(request.url.absoluteString) || (path.count > 1 && message.contains(path))
            throw SourceError.network(leaks ? Self.unreachable : message)
        } catch let error as SourceError { throw error }
        catch { throw SourceError.network(Self.unreachable) }
    }
}
