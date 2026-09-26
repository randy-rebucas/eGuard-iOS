import Foundation

/// What a set of selected apps or websites is used for.
nonisolated enum SelectionPurpose: String, Codable, CaseIterable, Identifiable, Sendable {
    case gaming
    case socialApps
    case restrictedApps
    case websites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gaming: "Gaming"
        case .socialApps: "Social Apps"
        case .restrictedApps: "Always Shielded Apps"
        case .websites: "Websites"
        }
    }

    var instruction: String {
        switch self {
        case .gaming: "Choose the games this daily allowance applies to."
        case .socialApps: "Choose the social apps this daily allowance applies to."
        case .restrictedApps: "Choose apps that should stay shielded at all times."
        case .websites: "Choose website categories or sites to block."
        }
    }
}

/// A privacy-preserving record of a parent's app or website selection.
/// Apple only exposes opaque tokens, so eGuard stores the encoded selection and counts.
nonisolated struct ActivitySelectionSnapshot: Codable, Equatable, Sendable {
    var encodedSelection: Data?
    var applicationCount = 0
    var categoryCount = 0
    var webDomainCount = 0

    static let empty = ActivitySelectionSnapshot()

    var isEmpty: Bool {
        applicationCount == 0 && categoryCount == 0 && webDomainCount == 0
    }

    /// A friendly label such as "3 apps, 1 category". Internal identifiers are never shown.
    var summary: String {
        guard !isEmpty else { return "Nothing selected" }
        var parts: [String] = []
        if applicationCount > 0 { parts.append(applicationCount == 1 ? "1 app" : "\(applicationCount) apps") }
        if categoryCount > 0 { parts.append(categoryCount == 1 ? "1 category" : "\(categoryCount) categories") }
        if webDomainCount > 0 { parts.append(webDomainCount == 1 ? "1 website" : "\(webDomainCount) websites") }
        return parts.joined(separator: ", ")
    }
}

/// All selections a parent has made, keyed by purpose.
nonisolated struct ProtectionSelections: Codable, Equatable, Sendable {
    var gaming = ActivitySelectionSnapshot.empty
    var socialApps = ActivitySelectionSnapshot.empty
    var restrictedApps = ActivitySelectionSnapshot.empty
    var websites = ActivitySelectionSnapshot.empty

    subscript(purpose: SelectionPurpose) -> ActivitySelectionSnapshot {
        get {
            switch purpose {
            case .gaming: gaming
            case .socialApps: socialApps
            case .restrictedApps: restrictedApps
            case .websites: websites
            }
        }
        set {
            switch purpose {
            case .gaming: gaming = newValue
            case .socialApps: socialApps = newValue
            case .restrictedApps: restrictedApps = newValue
            case .websites: websites = newValue
            }
        }
    }
}
