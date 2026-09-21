import AppKit
import AuthenticationServices
import Foundation

/// Shows the authorization page in the system's web-authentication sheet (`ASWebAuthenticationSession`),
/// which can close itself when the page redirects to the completion scheme. Everything touching the
/// session runs on the main actor.
public final class WebAuthenticationSessionPresenter: NSObject, AuthorizationPresenting, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    private let anchor: @Sendable @MainActor () -> NSWindow?
    /// Main-actor only.
    private var session: ASWebAuthenticationSession?

    public init(anchor: @escaping @Sendable @MainActor () -> NSWindow?) {
        self.anchor = anchor
    }

    public func present(_ url: URL, completionScheme: String, onEnded: @escaping @Sendable (Error?) -> Void) async -> Bool {
        await MainActor.run { start(url, completionScheme: completionScheme, onEnded: onEnded) }
    }

    public func dismiss() async {
        await MainActor.run {
            // Drop the reference first: `cancel()` reports `canceledLogin` to the handler, which must
            // not reach `onEnded` once the flow is already over.
            let ending = session
            session = nil
            ending?.cancel()
        }
    }

    @MainActor
    private func start(_ url: URL, completionScheme: String, onEnded: @escaping @Sendable (Error?) -> Void) -> Bool {
        session?.cancel()
        session = nil
        var created: ASWebAuthenticationSession?
        created = ASWebAuthenticationSession(url: url, callbackURLScheme: completionScheme) { [weak self] callbackURL, error in
            // The handler may arrive off the main actor; only the session this handler belongs to may end the flow.
            Task { @MainActor in
                guard let self, let created, self.session === created else { return }
                self.session = nil
                onEnded(callbackURL != nil ? nil : (error ?? CancellationError()))
            }
        }
        guard let created else { return false }
        created.presentationContextProvider = self
        created.prefersEphemeralWebBrowserSession = false
        session = created
        if created.start() { return true }
        session = nil
        return false
    }

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            anchor() ?? NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
        }
    }
}
