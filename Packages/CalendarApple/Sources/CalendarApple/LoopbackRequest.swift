import Foundation

enum LoopbackRequest {
    /// The full URL of an OAuth redirect: a `GET` whose target's query has `code` or `error`. Anything else
    /// (favicon, probes) is nil so the listener keeps waiting.
    static func redirectURL(from data: Data, port: UInt16) -> URL? {
        guard let text = String(data: data, encoding: .utf8),
              let line = text.components(separatedBy: "\r\n").first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let components = URLComponents(string: "http://127.0.0.1:\(port)\(parts[1])"),
              let items = components.queryItems,
              items.contains(where: { $0.name == "code" || $0.name == "error" }) else { return nil }
        return components.url
    }
}
