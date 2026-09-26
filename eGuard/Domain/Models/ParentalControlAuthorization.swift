import Foundation

/// eGuard's view of Family Controls authorization. Mirrors Apple's states without depending on the framework.
nonisolated enum ParentalControlAuthorizationStatus: String, Codable, Sendable {
    case notDetermined
    case approved
    case approvedWithDataAccess
    case denied

    var isAuthorized: Bool {
        switch self {
        case .approved, .approvedWithDataAccess: true
        case .notDetermined, .denied: false
        }
    }

    var title: String {
        switch self {
        case .notDetermined: "Not requested"
        case .approved: "Approved"
        case .approvedWithDataAccess: "Approved with data access"
        case .denied: "Not granted"
        }
    }
}

/// Which family member the authorization request is for.
nonisolated enum FamilyMemberKind: String, Codable, Sendable {
    case child
    case individual
}

/// Friendly, non-technical authorization failures.
nonisolated enum ParentalControlAuthorizationError: LocalizedError, Equatable, Sendable {
    case invalidAccountType
    case authorizationConflict
    case canceled
    case unavailable
    case restricted
    case networkError
    case passcodeRequired
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidAccountType:
            "This device isn't signed in with a child account in your Family Sharing group. Check the account type and try again."
        case .authorizationConflict:
            "Another parental controls app is already authorized on this device. Remove it in Settings before continuing."
        case .canceled:
            "The authorization request was canceled."
        case .unavailable:
            "Apple's parental controls are not available on this device right now."
        case .restricted:
            "A restriction on this device prevents eGuard from using parental controls."
        case .networkError:
            "An internet connection is needed to complete authorization. Connect and try again."
        case .passcodeRequired:
            "Set a device passcode before authorizing eGuard."
        case .unknown(let message):
            message
        }
    }
}

/// Configuration failures surfaced to the parent in plain language.
nonisolated enum ProtectionConfigurationError: LocalizedError, Equatable, Sendable {
    case notAuthorized
    case selectionRequired
    case invalidSchedule
    case unsupported
    case platformError(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized: "eGuard is not authorized to configure parental controls yet."
        case .selectionRequired: "Choose at least one app or category first."
        case .invalidSchedule: "The schedule must cover at least fifteen minutes."
        case .unsupported: "Apple does not let apps configure this setting on this device."
        case .platformError(let message): message
        }
    }
}
