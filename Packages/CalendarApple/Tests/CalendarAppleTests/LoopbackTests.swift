import CalendarCore
import Foundation
import Network
import Testing
@testable import CalendarApple

@Test func redirectURLParsesOAuthRedirectsOnly() {
    let ok = Data("GET /?code=abc&state=xyz HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8)
    #expect(LoopbackRequest.redirectURL(from: ok, port: 5000)?.absoluteString == "http://127.0.0.1:5000/?code=abc&state=xyz")
    let denied = Data("GET /?error=access_denied&state=xyz HTTP/1.1\r\n\r\n".utf8)
    #expect(LoopbackRequest.redirectURL(from: denied, port: 5000) != nil)
    #expect(LoopbackRequest.redirectURL(from: Data("GET /favicon.ico HTTP/1.1\r\n\r\n".utf8), port: 5000) == nil)
    #expect(LoopbackRequest.redirectURL(from: Data("POST /?code=a HTTP/1.1\r\n\r\n".utf8), port: 5000) == nil)
    #expect(LoopbackRequest.redirectURL(from: Data("garbage".utf8), port: 5000) == nil)
}

private func interaction(timeout: Duration = .seconds(5), opened: @escaping @Sendable (URL) -> Void = { _ in }) -> LoopbackAuthorizationInteraction {
    LoopbackAuthorizationInteraction(openURL: { url in opened(url); return true }, timeout: timeout)
}

@Test func sessionReceivesTheRedirectOnLoopback() async throws {
    let session = try await interaction().beginOAuthRedirect()
    #expect(session.redirectURI.host == "127.0.0.1" && session.redirectURI.port != nil)
    let waiting = Task { try await session.authorize(at: URL(string: "https://accounts.example/auth")!) }
    try await Task.sleep(for: .milliseconds(100))
    let (body, response) = try await URLSession.shared.data(from: URL(string: session.redirectURI.absoluteString + "/?code=abc&state=xyz")!)
    #expect((response as? HTTPURLResponse)?.statusCode == 200)
    #expect(String(decoding: body, as: UTF8.self).contains("close this window"))
    let received = try await waiting.value
    #expect(URLComponents(url: received, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "code" }?.value == "abc")
    await session.close()
}

@Test func redirectArrivingBeforeAuthorizeWaitsIsNotLost() async throws {
    let session = try await interaction().beginOAuthRedirect()
    _ = try await URLSession.shared.data(from: URL(string: session.redirectURI.absoluteString + "/?code=early&state=s")!)
    let received = try await session.authorize(at: URL(string: "https://accounts.example/auth")!)
    #expect(received.query?.contains("code=early") == true)
    await session.close()
}

@Test func authorizeTimesOut() async throws {
    let session = try await interaction(timeout: .milliseconds(200)).beginOAuthRedirect()
    await #expect(throws: LoopbackError.timedOut) { try await session.authorize(at: URL(string: "https://accounts.example/auth")!) }
    await session.close()
}

@Test func closeFreesThePortAndIsIdempotent() async throws {
    let session = try await interaction().beginOAuthRedirect()
    await session.close()
    await session.close()
    await #expect(throws: (any Error).self) {
        _ = try await URLSession.shared.data(from: URL(string: session.redirectURI.absoluteString + "/?code=x&state=y")!)
    }
}

@Test func promptCredentialsIsUnavailableUnlessInjected() async {
    await #expect(throws: LoopbackError.credentialPromptUnavailable) {
        _ = try await interaction().promptCredentials([CredentialField(key: "u", label: "User")])
    }
}

@Test func secondConcurrentAuthorizeFailsFastAndFirstStillCompletes() async throws {
    let session = try await interaction().beginOAuthRedirect()
    let first = Task { try await session.authorize(at: URL(string: "https://accounts.example/auth")!) }
    try await Task.sleep(for: .milliseconds(200))
    await #expect(throws: LoopbackError.alreadyWaiting) { try await session.authorize(at: URL(string: "https://accounts.example/auth")!) }
    _ = try await URLSession.shared.data(from: URL(string: session.redirectURI.absoluteString + "/?code=one&state=s")!)
    let received = try await first.value
    #expect(received.query?.contains("code=one") == true)
    await session.close()
}

@Test func requestSplitAcrossChunksIsReassembled() async throws {
    let session = try await interaction().beginOAuthRedirect()
    let waiting = Task { try await session.authorize(at: URL(string: "https://accounts.example/auth")!) }
    try await Task.sleep(for: .milliseconds(100))
    let port = NWEndpoint.Port(rawValue: UInt16(session.redirectURI.port!))!
    let client = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
    client.start(queue: DispatchQueue(label: "test.client"))
    func send(_ text: String) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            client.send(content: Data(text.utf8), completion: .contentProcessed { _ in c.resume() })
        }
    }
    await send("GET /?co")
    try await Task.sleep(for: .milliseconds(100))
    await send("de=abc&state=xyz HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
    let watchdog = Task { try await Task.sleep(for: .seconds(5)); waiting.cancel() }
    defer { watchdog.cancel(); client.cancel() }
    let received = try await waiting.value
    #expect(received.query?.contains("code=abc") == true)
    await session.close()
}

// MARK: - Presenter seam

/// Raw HTTP GET that does not follow redirects; returns the response head and body text.
private func rawGET(_ redirectURI: URL, path: String) async throws -> String {
    let port = NWEndpoint.Port(rawValue: UInt16(redirectURI.port!))!
    let client = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
    client.start(queue: DispatchQueue(label: "test.rawget"))
    defer { client.cancel() }
    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
        client.send(content: Data("GET \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8), completion: .contentProcessed { _ in c.resume() })
    }
    var response = Data()
    while true {
        let (data, done): (Data?, Bool) = await withCheckedContinuation { c in
            client.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                c.resume(returning: (data, isComplete || error != nil))
            }
        }
        if let data { response.append(data) }
        if done { break }
    }
    return String(decoding: response, as: UTF8.self)
}

private final class FakePresenter: AuthorizationPresenting, @unchecked Sendable {
    enum Mode { case hitListener(URL), endWith(Error?), refuse }
    private let lock = NSLock()
    private let mode: Mode
    private var _dismissals = 0
    private var _response: String?
    private var _completionScheme: String?
    private var _onEnded: (@Sendable (Error?) -> Void)?
    init(_ mode: Mode) { self.mode = mode }
    var dismissals: Int { lock.lock(); defer { lock.unlock() }; return _dismissals }
    var response: String? { lock.lock(); defer { lock.unlock() }; return _response }
    var completionScheme: String? { lock.lock(); defer { lock.unlock() }; return _completionScheme }
    var onEnded: (@Sendable (Error?) -> Void)? { lock.lock(); defer { lock.unlock() }; return _onEnded }

    func present(_ url: URL, completionScheme: String, onEnded: @escaping @Sendable (Error?) -> Void) async -> Bool {
        record(scheme: completionScheme, onEnded: onEnded)
        switch mode {
        case .refuse: return false
        case .endWith(let error):
            Task { try? await Task.sleep(for: .milliseconds(50)); onEnded(error) }
            return true
        case .hitListener(let redirectURI):
            Task {
                let text = try? await rawGET(redirectURI, path: "/?code=abc&state=xyz")
                self.record(response: text)
            }
            return true
        }
    }
    func dismiss() async { recordDismissal() }
    private func record(scheme: String, onEnded: @escaping @Sendable (Error?) -> Void) {
        lock.lock(); defer { lock.unlock() }
        _completionScheme = scheme; _onEnded = onEnded
    }
    private func record(response: String?) { lock.lock(); defer { lock.unlock() }; _response = response }
    private func recordDismissal() { lock.lock(); defer { lock.unlock() }; _dismissals += 1 }
}

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return _count }
    func hit() { lock.lock(); _count += 1; lock.unlock() }
}

private let authURL = URL(string: "https://accounts.example/auth")!

/// Starts a session, then hands the fake presenter the real redirect URI (the presenter is created first, so it is
/// told the port through `redirectURI`).
private func presenterSession(_ mode: (URL) -> FakePresenter.Mode, timeout: Duration = .seconds(5), opened: Recorder = Recorder())
    async throws -> (any OAuthRedirectSession, FakePresenter) {
    // The listener port is only known after start, so start a session on a throwaway interaction to learn nothing:
    // instead build the presenter lazily through a box.
    final class Box: @unchecked Sendable { var presenter: FakePresenter? }
    let box = Box()
    let proxy = ProxyPresenter { box.presenter }
    let interaction = LoopbackAuthorizationInteraction(openURL: { _ in opened.hit(); return true }, presenter: proxy, timeout: timeout)
    let session = try await interaction.beginOAuthRedirect()
    let presenter = FakePresenter(mode(session.redirectURI))
    box.presenter = presenter
    return (session, presenter)
}

private struct ProxyPresenter: AuthorizationPresenting {
    let target: @Sendable () -> FakePresenter?
    init(_ target: @escaping @Sendable () -> FakePresenter?) { self.target = target }
    func present(_ url: URL, completionScheme: String, onEnded: @escaping @Sendable (Error?) -> Void) async -> Bool {
        await target()?.present(url, completionScheme: completionScheme, onEnded: onEnded) ?? false
    }
    func dismiss() async { await target()?.dismiss() }
}

@Test func presenterSessionAnswersTheRedirectWith302ToTheCompletionScheme() async throws {
    let (session, presenter) = try await presenterSession { .hitListener($0) }
    let received = try await session.authorize(at: authURL)
    #expect(received.query?.contains("code=abc") == true)
    #expect(presenter.completionScheme == "timetug-oauth")
    try await Task.sleep(for: .milliseconds(300))
    let response = try #require(presenter.response)
    #expect(response.hasPrefix("HTTP/1.1 302"))
    #expect(response.contains("Location: timetug-oauth://done"))
    await session.close()
}

@Test func presenterCancellationEndsAuthorizeWithCancelledBeforeTheTimeout() async throws {
    let (session, _) = try await presenterSession({ _ in .endWith(CancellationError()) }, timeout: .seconds(3))
    await #expect(throws: LoopbackError.cancelled) { try await session.authorize(at: authURL) }
    await session.close()
}

@Test func presenterThatCannotStartFallsBackToOpenURLAndPlainPage() async throws {
    let opened = Recorder()
    let (session, presenter) = try await presenterSession({ _ in .refuse }, opened: opened)
    let waiting = Task { try await session.authorize(at: authURL) }
    try await Task.sleep(for: .milliseconds(100))
    #expect(opened.count == 1)
    let response = try await rawGET(session.redirectURI, path: "/?code=abc&state=xyz")
    #expect(response.hasPrefix("HTTP/1.1 200"))
    #expect(!response.contains("Location:"))
    _ = try await waiting.value
    #expect(presenter.completionScheme == "timetug-oauth")
    await session.close()
}

@Test func closeDismissesThePresenterOncePerCloseEvenAfterCompletion() async throws {
    let (session, presenter) = try await presenterSession { .hitListener($0) }
    _ = try await session.authorize(at: authURL)
    await session.close()
    #expect(presenter.dismissals == 1)
}

@Test func presenterEndedWithNilAfterTheRedirectDoesNotChangeTheResult() async throws {
    let (session, presenter) = try await presenterSession { .hitListener($0) }
    let received = try await session.authorize(at: authURL)
    presenter.onEnded?(nil)
    presenter.onEnded?(CancellationError())
    #expect(received.query?.contains("code=abc") == true)
    await session.close()
}
