import Foundation

/// The kind of Apple device the child uses.
nonisolated enum DevicePlatform: String, Codable, CaseIterable, Identifiable, Sendable {
    case iPhone
    case iPad

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iPhone: "iPhone"
        case .iPad: "iPad"
        }
    }

    var operatingSystemName: String {
        switch self {
        case .iPhone: "iOS"
        case .iPad: "iPadOS"
        }
    }

    var symbolName: String {
        switch self {
        case .iPhone: "iphone"
        case .iPad: "ipad"
        }
    }
}

/// How the child's Apple account relates to the parent's family.
/// Family Controls behaves differently for a child account in Family Sharing versus the device owner.
nonisolated enum FamilyRelationshipStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case childInFamilySharing
    case thisDeviceOwner
    case notSure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .childInFamilySharing: "Child account in Family Sharing"
        case .thisDeviceOwner: "This device's own account"
        case .notSure: "I'm not sure"
        }
    }

    var explanation: String {
        switch self {
        case .childInFamilySharing:
            "The child is signed in with a child Apple Account that belongs to your Family Sharing group. A parent or guardian approves eGuard."
        case .thisDeviceOwner:
            "The device is signed in with the account of the person using it. The device owner approves eGuard with Face ID, Touch ID, or a passcode."
        case .notSure:
            "eGuard will explain the Apple requirements before asking for permission."
        }
    }

    /// Whether Apple's Family Sharing prerequisites are known to be satisfied.
    var hasKnownPrerequisites: Bool {
        self != .notSure
    }

    var memberKind: FamilyMemberKind {
        switch self {
        case .childInFamilySharing, .notSure: .child
        case .thisDeviceOwner: .individual
        }
    }
}

/// The child eGuard is protecting.
nonisolated struct ChildProfile: Codable, Equatable, Sendable {
    static let ageRange: ClosedRange<Int> = 4...17

    var name: String
    var age: Int
    var device: DevicePlatform
    var relationship: FamilyRelationshipStatus

    init(
        name: String = "",
        age: Int = 12,
        device: DevicePlatform = .iPhone,
        relationship: FamilyRelationshipStatus = .childInFamilySharing
    ) {
        self.name = name
        self.age = age
        self.device = device
        self.relationship = relationship
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        !trimmedName.isEmpty && Self.ageRange.contains(age)
    }

    var ageDescription: String {
        "\(age) years old"
    }
}
