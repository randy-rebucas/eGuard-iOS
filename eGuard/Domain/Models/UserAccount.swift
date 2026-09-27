import Foundation

/// Plain-language validation shared by Create Account, Sign In, and Account. Mirrors the API's rules.
nonisolated enum AccountValidator {
    static let minimumPasswordLength = 10

    static func validateName(_ name: String) -> String? {
        name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 ? nil : "Enter your full name."
    }

    static func validateEmail(_ email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil ? nil : "Enter a valid email address."
    }

    static func validatePassword(_ password: String) -> String? {
        password.count >= minimumPasswordLength ? nil : "Use at least \(minimumPasswordLength) characters."
    }

    static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Sign-in failures raised locally, before or instead of a server call.
nonisolated enum AccountError: LocalizedError, Equatable, Sendable {
    case providerUnavailable(SocialProvider)
    case guardianRequired

    var errorDescription: String? {
        switch self {
        case .providerUnavailable(let provider):
            "\(provider == .apple ? "Apple" : "Google") sign-in isn't available right now."
        case .guardianRequired:
            "Confirm that you're a parent or legal guardian, 18 or older, to continue."
        }
    }
}
