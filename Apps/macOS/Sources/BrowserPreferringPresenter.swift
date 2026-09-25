import CalendarApple
import Foundation

/// Wraps the web-authentication sheet with a hidden switch that sends sign-in to the default browser
/// instead. Google reviewers need a browser address bar showing the OAuth client ID in the demo video,
/// which the sheet does not show. Set it with
/// `defaults write com.timetug.app oauth.useBrowser.v1 -bool true` (remove it with `defaults delete`).
/// The switch is read on every sign-in, so no restart is needed.
struct BrowserPreferringPresenter: AuthorizationPresenting {
    static let defaultsKey = "oauth.useBrowser.v1"

    let sheet: any AuthorizationPresenting
    let useBrowser: @Sendable () -> Bool

    init(sheet: any AuthorizationPresenting,
         useBrowser: @escaping @Sendable () -> Bool = { UserDefaults.standard.bool(forKey: BrowserPreferringPresenter.defaultsKey) }) {
        self.sheet = sheet
        self.useBrowser = useBrowser
    }

    /// Declining (false) makes the loopback flow open the authorization URL in the default browser.
    func present(_ url: URL, completionScheme: String, onEnded: @escaping @Sendable (Error?) -> Void) async -> Bool {
        if useBrowser() { return false }
        return await sheet.present(url, completionScheme: completionScheme, onEnded: onEnded)
    }

    func dismiss() async { await sheet.dismiss() }
}
