import Foundation

/// Provider-specific text for the Join button.
enum JoinLabel {
    private static let providers: [(name: String, hosts: [String])] = [
        ("Join Zoom", ["zoom.us", "zoom.com"]),
        ("Join Google Meet", ["meet.google.com"]),
        ("Join Teams", ["teams.microsoft.com", "teams.live.com"]),
        ("Join Webex", ["webex.com"]),
        ("Join Slack huddle", ["app.slack.com"]),
    ]

    static func text(for url: URL) -> String {
        if url.scheme?.lowercased() == "zoommtg" { return "Join Zoom" }
        let host = url.host?.lowercased() ?? ""
        for provider in providers where provider.hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return provider.name
        }
        return "Join meeting"
    }
}
