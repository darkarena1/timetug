import CalendarOAuth
import Foundation
import Testing
@testable import CalendarApple

@Test func cryptoKitHasherMatchesTheReferenceVectors() {
    let hasher = CryptoKitSHA256()
    #expect(hasher.sha256(Data("abc".utf8)).map { String(format: "%02x", $0) }.joined()
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    #expect(hasher.sha256(Data()) == PureSwiftSHA256().sha256(Data()))
}
