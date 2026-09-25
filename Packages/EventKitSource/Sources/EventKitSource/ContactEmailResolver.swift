import Contacts
import EventKit
import Foundation

enum ContactsAuthorization { case notDetermined, denied, authorized }

/// Contacts permission, behind a protocol so tests do not touch the real store. Only `.authorized` counts as granted.
protocol ContactsAccess: Sendable {
    var authorization: ContactsAuthorization { get }
    func requestAccess() async -> Bool
}

/// Looks up the emails of the contact a participant stands for. `EKParticipant.contactPredicate` is the precise key.
protocol ContactEmailLookup: Sendable {
    func emails(matching predicate: NSPredicate) -> [String]
}

struct SystemContactsAccess: ContactsAccess {
    var authorization: ContactsAuthorization {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func requestAccess() async -> Bool { (try? await CNContactStore().requestAccess(for: .contacts)) ?? false }
}

struct SystemContactEmailLookup: ContactEmailLookup {
    func emails(matching predicate: NSPredicate) -> [String] {
        let keys = [CNContactEmailAddressesKey as CNKeyDescriptor]
        guard let contacts = try? CNContactStore().unifiedContacts(matching: predicate, keysToFetch: keys), let contact = contacts.first else { return [] }
        return contact.emailAddresses.map { String($0.value).lowercased() }
    }
}

/// A participant EventKit gave no email for (a `urn:uuid:`, a CalDAV or iCloud principal URL, an Exchange path).
struct UnresolvedParticipant: @unchecked Sendable {
    let url: String
    let predicate: NSPredicate
}

/// Turns such participants into emails through Contacts, inside the connector (not injected by the host).
/// - Access is requested automatically the first time it is needed, but never blocks a read: with access undecided the
///   request starts in the background, the read returns at once with those emails nil, and a grant posts
///   `accessGranted` so the source tells its host to fetch again.
/// - Denied or restricted access skips the lookup and never asks again.
/// - Results are cached per participant URL (each address is looked up once) and cleared when Contacts changes.
final class ContactEmailResolver: @unchecked Sendable {
    static let accessGranted = Notification.Name("EventKitSource.contactsAccessGranted")

    private let access: ContactsAccess
    private let lookup: ContactEmailLookup
    private let center: NotificationCenter
    private let lock = NSLock()
    private var cache: [String: [String]] = [:]
    private var requested = false
    private var observer: NSObjectProtocol?

    init(access: ContactsAccess = SystemContactsAccess(), lookup: ContactEmailLookup = SystemContactEmailLookup(),
         center: NotificationCenter = .default) {
        self.access = access
        self.lookup = lookup
        self.center = center
        observer = center.addObserver(forName: .CNContactStoreDidChange, object: nil, queue: nil) { [weak self] _ in
            self?.clearCache()
        }
    }

    deinit { if let observer { center.removeObserver(observer) } }

    func clearCache() { lock.withLock { cache.removeAll() } }

    /// The emails of each participant's contact, keyed by participant URL (an empty list: no contact or no email).
    /// Empty when access is not granted.
    func emails(for participants: [UnresolvedParticipant]) -> [String: [String]] {
        guard !participants.isEmpty else { return [:] }
        switch access.authorization {
        case .denied:
            return [:]
        case .notDetermined:
            startRequestOnce()
            return [:]
        case .authorized:
            var result: [String: [String]] = [:]
            for participant in participants {
                let cached = lock.withLock { cache[participant.url] }
                if let cached { result[participant.url] = cached; continue }
                let found = lookup.emails(matching: participant.predicate)
                lock.withLock { cache[participant.url] = found }
                result[participant.url] = found
            }
            return result
        }
    }

    private func startRequestOnce() {
        let start = lock.withLock { () -> Bool in
            if requested { return false }
            requested = true
            return true
        }
        guard start else { return }
        let access = access, center = center
        Task.detached {
            if await access.requestAccess() { center.post(name: Self.accessGranted, object: nil) }
        }
    }

    /// Prefers an email whose domain another person in the same event uses (a contact with a work and a home address),
    /// otherwise the contact's first email.
    static func choose(_ emails: [String], preferredDomains: Set<String>) -> String? {
        if let match = emails.first(where: { email in email.split(separator: "@").last.map { preferredDomains.contains(String($0)) } ?? false }) {
            return match
        }
        return emails.first
    }
}
