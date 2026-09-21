import CalendarOAuth
import CryptoKit
import Foundation

/// CryptoKit-backed SHA-256 for hosts on Apple platforms; inject it in place of the library's pure-Swift default.
public struct CryptoKitSHA256: SHA256Hashing {
    public init() {}
    public func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }
}
