import Contacts
import Foundation
import Testing
@testable import EventKitSource

private final class FakeAccess: ContactsAccess, @unchecked Sendable {
    let lock = NSLock()
    var status: ContactsAuthorization
    var grants: Bool
    private(set) var requests = 0
    init(_ status: ContactsAuthorization, grants: Bool = true) { self.status = status; self.grants = grants }
    var authorization: ContactsAuthorization { lock.withLock { status } }
    func requestAccess() async -> Bool {
        lock.withLock { requests += 1 }
        return grants
    }
}

private final class FakeLookup: ContactEmailLookup, @unchecked Sendable {
    let lock = NSLock()
    var byURL: [String: [String]]
    private(set) var calls = 0
    init(_ byURL: [String: [String]]) { self.byURL = byURL }
    func emails(matching predicate: NSPredicate) -> [String] {
        lock.withLock { calls += 1 }
        return byURL[predicate.predicateFormat] ?? []
    }
}

/// The fake lookup keys results by the predicate's text, which is the participant URL here.
private func participant(_ url: String) -> UnresolvedParticipant {
    UnresolvedParticipant(url: url, predicate: NSPredicate(format: "%@ == %@", url, url))
}
private func key(_ url: String) -> String { NSPredicate(format: "%@ == %@", url, url).predicateFormat }

@Test func anUnresolvedParticipantGetsItsEmailFromTheLookup() {
    let resolver = ContactEmailResolver(access: FakeAccess(.authorized), lookup: FakeLookup([key("urn:uuid:1"): ["bo@work.test", "bo@home.test"]]), center: NotificationCenter())
    #expect(resolver.emails(for: [participant("urn:uuid:1")]) == ["urn:uuid:1": ["bo@work.test", "bo@home.test"]])
}

@Test func theEmailWhoseDomainAnotherPersonInTheEventUsesIsPreferred() {
    let emails = ["bo@home.test", "bo@work.test"]
    #expect(ContactEmailResolver.choose(emails, preferredDomains: ["work.test"]) == "bo@work.test")
    #expect(ContactEmailResolver.choose(emails, preferredDomains: ["other.test"]) == "bo@home.test")   // the contact's first
    #expect(ContactEmailResolver.choose([], preferredDomains: ["work.test"]) == nil)
}

@Test func eachAddressIsLookedUpOnceAndAContactsChangeClearsTheCache() {
    let center = NotificationCenter()
    let lookup = FakeLookup([key("urn:uuid:1"): ["bo@x.test"]])
    let resolver = ContactEmailResolver(access: FakeAccess(.authorized), lookup: lookup, center: center)
    _ = resolver.emails(for: [participant("urn:uuid:1")])
    _ = resolver.emails(for: [participant("urn:uuid:1")])
    #expect(lookup.calls == 1)
    center.post(name: .CNContactStoreDidChange, object: nil)
    _ = resolver.emails(for: [participant("urn:uuid:1")])
    #expect(lookup.calls == 2)
}

@Test func deniedAccessSkipsTheLookupAndNeverAsks() {
    let access = FakeAccess(.denied)
    let lookup = FakeLookup([:])
    let resolver = ContactEmailResolver(access: access, lookup: lookup, center: NotificationCenter())
    #expect(resolver.emails(for: [participant("urn:uuid:1")]).isEmpty)
    #expect(access.requests == 0 && lookup.calls == 0)
}

@Test func undecidedAccessReturnsAtOnceStartsOneRequestAndAnnouncesAGrant() async {
    let center = NotificationCenter()
    let access = FakeAccess(.notDetermined)
    let resolver = ContactEmailResolver(access: access, lookup: FakeLookup([:]), center: center)
    let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
        let box = Once(continuation)
        let token = center.addObserver(forName: ContactEmailResolver.accessGranted, object: nil, queue: nil) { _ in box.resume(true) }
        #expect(resolver.emails(for: [participant("urn:uuid:1")]).isEmpty)   // returns at once, without waiting for the prompt
        _ = resolver.emails(for: [participant("urn:uuid:2")])                 // a second read does not ask again
        Task { try? await Task.sleep(for: .seconds(5)); box.resume(false); center.removeObserver(token) }
    }
    #expect(granted)
    #expect(access.requests == 1)
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }
    func resume(_ value: Bool) {
        let c = lock.withLock { () -> CheckedContinuation<Bool, Never>? in defer { continuation = nil }; return continuation }
        c?.resume(returning: value)
    }
}
