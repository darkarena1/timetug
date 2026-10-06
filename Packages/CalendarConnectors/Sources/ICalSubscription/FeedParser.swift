import CalendarCore
import Foundation
import ICalendar

/// One UID's events from a feed (a master plus its overrides) as the resource the shared `EventReader` expects.
struct FeedResource: Sendable {
    let name: String
    let resource: EventResource
}

struct ParsedFeed: Sendable {
    var name: String?
    var colorHex: String?
    var timeZone: TimeZone?
    var resources: [FeedResource]
}

enum FeedParser {
    private static let notACalendar = "that link did not return a calendar"

    /// A feed is one `VCALENDAR` holding many events, while `EventResource` holds one UID's events. Events are grouped by
    /// `UID` (first-seen order); each group shares the calendar's header and `VTIMEZONE`s. A feed with no events is valid.
    static func parse(_ data: Data) throws -> ParsedFeed {
        let calendar: ICalComponent
        do { calendar = try ICalParser.parse(data) } catch { throw SourceError.invalidResponse(notACalendar) }
        guard calendar.name == "VCALENDAR" else { throw SourceError.invalidResponse(notACalendar) }

        let zones = calendar.components(named: "VTIMEZONE")
        var order: [String] = []
        var groups: [String: [ICalComponent]] = [:]
        for event in calendar.components(named: "VEVENT") {
            let uid = event.property("UID")?.text.nonEmpty ?? syntheticUID(for: event)
            if groups[uid] == nil { order.append(uid) }
            groups[uid, default: []].append(event)
        }
        var resources: [FeedResource] = []
        for uid in order {
            let wrapper = ICalComponent(name: "VCALENDAR", properties: calendar.properties, components: zones + (groups[uid] ?? []))
            guard let resource = try? EventResource(calendar: wrapper) else { continue }
            resources.append(FeedResource(name: resourceName(for: uid), resource: resource))
        }
        return ParsedFeed(
            name: calendar.property("X-WR-CALNAME")?.text.nonEmpty,
            colorHex: colorText(calendar.property("X-APPLE-CALENDAR-COLOR")?.value ?? calendar.property("COLOR")?.value),
            timeZone: calendar.property("X-WR-TIMEZONE").flatMap { TimeZone(identifier: $0.value) },
            resources: resources)
    }

    /// The UID as one URL-safe path segment: it is the base of every event id, which joins an occurrence's start with `#`.
    static func resourceName(for uid: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~@")
        return uid.addingPercentEncoding(withAllowedCharacters: allowed) ?? uid
    }

    /// A UID for an event that has none: stable across reads because it comes only from the event's start and title.
    static func syntheticUID(for event: ICalComponent) -> String {
        let basis = (event.property("DTSTART")?.value ?? "") + "|" + (event.property("SUMMARY")?.value ?? "")
        return "feed-" + fnv1aHex(basis)
    }

    /// FNV-1a, 64 bit. Not for security: it only keeps a made-up UID the same from one read to the next.
    private static func fnv1aHex(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    /// `#RRGGBBAA` (Apple) is trimmed to `#RRGGBB`; the descriptor validates the rest.
    private static func colorText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        return raw.hasPrefix("#") && raw.count == 9 ? String(raw.prefix(7)) : raw
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
