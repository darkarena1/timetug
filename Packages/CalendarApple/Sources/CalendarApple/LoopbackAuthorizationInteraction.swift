import CalendarCore
import Foundation
import Network

public enum LoopbackError: Error, Equatable {
    case couldNotOpenBrowser, timedOut, cancelled, credentialPromptUnavailable
    case listenerFailed(String)
    case alreadyWaiting
}

/// OAuth via a loopback redirect: listens on 127.0.0.1 (ephemeral port), hands the authorization URL to the
/// host's `openURL` (TimeTug passes NSWorkspace) and returns the redirect it receives. Swap it for your own
/// `AuthorizationInteraction` on other hosts.
public struct LoopbackAuthorizationInteraction: AuthorizationInteraction {
    public typealias OpenURL = @Sendable (URL) async -> Bool
    public typealias PromptCredentials = @Sendable ([CredentialField]) async throws -> [String: String]

    private let openURL: OpenURL
    private let prompt: PromptCredentials?
    private let timeout: Duration

    public init(openURL: @escaping OpenURL, promptCredentials: PromptCredentials? = nil, timeout: Duration = .seconds(300)) {
        self.openURL = openURL
        self.prompt = promptCredentials
        self.timeout = timeout
    }

    public func beginOAuthRedirect() async throws -> any OAuthRedirectSession {
        try await LoopbackSession.start(openURL: openURL, timeout: timeout)
    }

    public func promptCredentials(_ fields: [CredentialField]) async throws -> [String: String] {
        guard let prompt else { throw LoopbackError.credentialPromptUnavailable }
        return try await prompt(fields)
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func run(_ body: () -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}

final class LoopbackSession: OAuthRedirectSession, @unchecked Sendable {
    private var boundPort: UInt16 = 0
    private var waitClaimed = false
    var redirectURI: URL {
        lock.lock(); defer { lock.unlock() }
        return boundPort == 0 ? URL(string: "http://127.0.0.1")! : URL(string: "http://127.0.0.1:\(boundPort)")!
    }
    private var port: UInt16 {
        lock.lock(); defer { lock.unlock() }
        return boundPort
    }
    private let listener: NWListener
    private let openURL: LoopbackAuthorizationInteraction.OpenURL
    private let timeout: Duration
    private let queue = DispatchQueue(label: "com.timetug.calendarapple.loopback")
    private let lock = NSLock()
    private var pending: CheckedContinuation<URL, Error>?
    private var received: Result<URL, Error>?

    private init(listener: NWListener, openURL: @escaping LoopbackAuthorizationInteraction.OpenURL, timeout: Duration) {
        self.listener = listener
        self.openURL = openURL
        self.timeout = timeout
    }

    static func start(openURL: @escaping LoopbackAuthorizationInteraction.OpenURL, timeout: Duration) async throws -> LoopbackSession {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        let listener: NWListener
        do { listener = try NWListener(using: parameters) } catch { throw LoopbackError.listenerFailed(String(describing: error)) }
        let session = LoopbackSession(listener: listener, openURL: openURL, timeout: timeout)
        listener.newConnectionHandler = { [weak session] connection in session?.accept(connection) }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let once = Once()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let raw = listener.port?.rawValue {
                        once.run {
                            session.publish(port: raw)
                            continuation.resume(returning: raw)
                        }
                    }
                case .failed(let error):
                    once.run { continuation.resume(throwing: LoopbackError.listenerFailed(String(describing: error))) }
                case .cancelled:
                    once.run { continuation.resume(throwing: LoopbackError.cancelled) }
                default: break
                }
            }
            listener.start(queue: session.queue)
        }
        _ = port
        return session
    }

    private func publish(port: UInt16) {
        lock.lock(); defer { lock.unlock() }
        boundPort = port
    }

    func authorize(at authorizationURL: URL) async throws -> URL {
        guard await openURL(authorizationURL) else { throw LoopbackError.couldNotOpenBrowser }
        let timeout = timeout
        return try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask { try await self.waitForRedirect() }
            group.addTask { try await Task.sleep(for: timeout); throw LoopbackError.timedOut }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    func close() async {
        listener.cancel()
        deliver(.failure(LoopbackError.cancelled))
    }

    private func deliver(_ result: Result<URL, Error>) {
        lock.lock(); defer { lock.unlock() }
        if let pending {
            self.pending = nil
            pending.resume(with: result)
        } else if received == nil {
            received = result
        }
    }

    private func waitForRedirect() async throws -> URL {
        lock.lock()
        if waitClaimed { lock.unlock(); throw LoopbackError.alreadyWaiting }
        waitClaimed = true
        lock.unlock()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                lock.lock()
                if let early = received {
                    received = nil
                    lock.unlock()
                    continuation.resume(with: early)
                } else {
                    pending = continuation
                    lock.unlock()
                }
            }
        } onCancel: {
            self.deliver(.failure(LoopbackError.cancelled))
        }
    }

    private static let page = """
    <!doctype html><meta charset="utf-8"><title>TimeTug</title>\
    <body style="font-family:-apple-system,sans-serif;text-align:center;margin-top:20vh">\
    <h2>You're signed in</h2><p>You can close this window and return to TimeTug.</p></body>
    """

    private static let maxRequestBytes = 16_384

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maxRequestBytes) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            let lineComplete = buffer.range(of: Data("\r\n".utf8)) != nil
            if !lineComplete {
                if error != nil || isComplete || buffer.count >= Self.maxRequestBytes {
                    self.respond(on: connection, redirect: nil)
                } else {
                    self.receiveRequest(on: connection, buffer: buffer)
                }
                return
            }
            let redirect = LoopbackRequest.redirectURL(from: buffer, port: self.port)
            self.respond(on: connection, redirect: redirect)
            if let redirect { self.deliver(.success(redirect)) }
        }
    }

    private func respond(on connection: NWConnection, redirect: URL?) {
        let status = redirect == nil ? "404 Not Found" : "200 OK"
        let body = redirect == nil ? "" : Self.page
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data((head + body).utf8), contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { _ in connection.cancel() })
    }
}
