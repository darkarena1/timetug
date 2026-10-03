import Foundation

enum LoopbackRequest {
    /// The full URL of an OAuth redirect: a `GET` whose target's query has `code` or `error`. Anything else
    /// (favicon, probes) is nil so the listener keeps waiting.
    static func redirectURL(from data: Data, port: UInt16, expectedPath: String, expectedState: String) -> URL? {
        guard let text = String(data: data, encoding: .utf8),
              let line = text.components(separatedBy: "\r\n").first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count == 3, parts[0] == "GET", parts[2] == "HTTP/1.1",
              parts[1].hasPrefix("/"), !parts[1].hasPrefix("//"),
              let components = URLComponents(string: "http://127.0.0.1:\(port)\(parts[1])"),
              components.path == expectedPath,
              components.host == "127.0.0.1", components.port == Int(port),
              let items = components.queryItems,
              items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == expectedState,
              items.filter({ $0.name == "code" }).count + items.filter({ $0.name == "error" }).count == 1 else { return nil }
        return components.url
    }
}
