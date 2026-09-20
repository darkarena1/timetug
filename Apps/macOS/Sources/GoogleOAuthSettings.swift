import Foundation
import GoogleCalendar

/// The Google Desktop OAuth client, injected at build time from the git-ignored GoogleOAuth.xcconfig into
/// Info.plist. Without it (CI, fresh checkouts) Google is not offered and everything else works.
enum GoogleOAuthSettings {
    static func config(from info: [String: Any]?) -> GoogleOAuthConfig? {
        func value(_ key: String) -> String? {
            guard let raw = (info?[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty, !raw.hasPrefix("$(") else { return nil }
            return raw
        }
        guard let id = value("TimeTugGoogleClientID"), let secret = value("TimeTugGoogleClientSecret") else { return nil }
        return GoogleOAuthConfig(clientID: id, clientSecret: secret)
    }

    static func config(bundle: Bundle = .main) -> GoogleOAuthConfig? { config(from: bundle.infoDictionary) }
}
