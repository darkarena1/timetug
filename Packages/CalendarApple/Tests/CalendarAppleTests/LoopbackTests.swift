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
