import Foundation
import MicrosoftCalendar

/// The Microsoft Entra app registration's client id (a public client, so no secret), injected at build time from the
/// git-ignored MicrosoftOAuth.xcconfig into Info.plist. Without it (CI PR builds, fresh checkouts) Microsoft is not
/// offered and everything else works.
enum MicrosoftOAuthSettings {
    static func config(from info: [String: Any]?) -> MicrosoftOAuthConfig? {
        guard let raw = (info?["TimeTugMicrosoftClientID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, !raw.hasPrefix("$(") else { return nil }
        return MicrosoftOAuthConfig(clientID: raw)
    }

    static func config(bundle: Bundle = .main) -> MicrosoftOAuthConfig? { config(from: bundle.infoDictionary) }
}
