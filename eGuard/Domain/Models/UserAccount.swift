import CryptoKit
import Foundation

/// How the parent signed up. Accounts live only on this device; eGuard has no server.
nonisolated enum AccountProvider: String, Codable, Sendable {
    case email
    case apple
    case google

    var title: String {
        switch self {
        case .email: "Email"
        case .apple: "Apple"
        case .google: "Google"
        }
    }
}

/// The parent's local account.
nonisolated struct UserAccount: Codable, Equatable, Sendable {
    var fullName: String
    var email: String
    var provider: AccountProvider
    var createdAt: Date
    /// Salted SHA-256 of the password, present only for email accounts.
    var passwordHash: String?
    var passwordSalt: String?

    init(
        fullName: String,
        email: String,
        provider: AccountProvider = .email,
        createdAt: Date = .now,
        passwordHash: String? = nil,
        passwordSalt: String? = nil
    ) {
        self.fullName = fullName
        self.email = email
        self.provider = provider
        self.createdAt = createdAt
        self.passwordHash = passwordHash
        self.passwordSalt = passwordSalt
    }

    /// The parent's first name, used in greetings.
    var firstName: String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: " ").first.map(String.init) ?? trimmed
    }

    var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func verify(password: String) -> Bool {
        guard let passwordHash, let passwordSalt else { return false }
        return AccountValidator.hash(password: password, salt: passwordSalt) == passwordHash
    }
}

/// Plain-language validation shared by Create Account and Sign In.
nonisolated enum AccountValidator {
    static func validateName(_ name: String) -> String? {
        name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 ? nil : "Enter your full name."
    }

    static func validateEmail(_ email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil ? nil : "Enter a valid email address."
    }

    static func validatePassword(_ password: String) -> String? {
        password.count >= 8 ? nil : "Use at least 8 characters."
    }

    static func makeSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString()
    }

    static func hash(password: String, salt: String) -> String {
        let digest = SHA256.hash(data: Data((salt + password).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Builds an email account with a freshly salted password hash.
    static func makeEmailAccount(fullName: String, email: String, password: String) -> UserAccount {
        let salt = makeSalt()
        return UserAccount(
            fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            provider: .email,
            passwordHash: hash(password: password, salt: salt),
            passwordSalt: salt
        )
    }
}

/// Sign-in failures in the parent's language.
nonisolated enum AccountError: LocalizedError, Equatable, Sendable {
    case noAccount
    case wrongPassword
    case emailMismatch
    case providerUnavailable(AccountProvider)

    var errorDescription: String? {
        switch self {
        case .noAccount: "No eGuard account exists on this device yet. Create one to get started."
        case .wrongPassword: "That password doesn't match. Try again."
        case .emailMismatch: "That email doesn't match the account on this device."
        case .providerUnavailable(let provider): "\(provider.title) sign-in isn't available on this device right now."
        }
    }
}
