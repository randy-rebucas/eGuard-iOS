import CryptoKit
import Foundation
import Security

/// A one-time nonce for Sign in with Apple. The SHA-256 hash goes into the authorization request so
/// the identity token Apple returns is bound to this sign-in; the raw value goes to the eGuard server
/// so it can check the binding and refuse a replayed token.
nonisolated struct AppleNonce: Equatable, Sendable {
    let raw: String

    init() {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // SecRandom failing is extraordinary; fall back to the system generator rather than a fixed value.
            bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        }
        raw = bytes.map { String(format: "%02x", $0) }.joined()
    }

    init(raw: String) {
        self.raw = raw
    }

    /// Hex SHA-256 of the raw nonce, the form Apple expects on `ASAuthorizationAppleIDRequest.nonce`.
    var hashed: String {
        SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
