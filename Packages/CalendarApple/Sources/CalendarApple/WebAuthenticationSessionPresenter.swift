import AppKit
import AuthenticationServices
import Foundation

/// Shows the authorization page in the system's web-authentication sheet (`ASWebAuthenticationSession`),
/// which can close itself when the page redirects to the completion scheme. Everything touching the
/// session runs on the main actor.
public final class WebAuthenticationSessionPresenter: NSObject, AuthorizationPresenting, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    private let anchor: @Sendable @MainActor () -> NSWindow?
    private struct Presentation {
        let id: UInt64
        let session: ASWebAuthenticationSession
        let onEnded: @Sendable (Error?) -> Void
    }

    /// Main-actor only.
    private var active: Presentation?
    /// Main-actor only.
    private var nextID: UInt64 = 0

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
            let ending = active
            active = nil
            ending?.session.cancel()
        }
    }

    @MainActor
    private func start(_ url: URL, completionScheme: String, onEnded: @escaping @Sendable (Error?) -> Void) -> Bool {
        // A superseded flow must still end, or it waits for its own timeout.
        if let superseded = active {
            active = nil
            superseded.session.cancel()
            superseded.onEnded(CancellationError())
        }
        nextID += 1
        let id = nextID
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: completionScheme) { [weak self] callbackURL, error in
            // The handler may arrive off the main actor; only the presentation this handler belongs to may end the flow.
            Task { @MainActor in
                guard let self, let current = self.active, current.id == id else { return }
                self.active = nil
                current.onEnded(callbackURL != nil ? nil : (error ?? CancellationError()))
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        active = Presentation(id: id, session: session, onEnded: onEnded)
        if session.start() { return true }
        active = nil
        return false
    }

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            anchor() ?? NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
        }
    }
}
