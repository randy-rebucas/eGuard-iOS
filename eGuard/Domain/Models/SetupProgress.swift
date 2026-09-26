import Foundation

/// Where one feature is in the configuration flow.
nonisolated enum FeatureConfigurationState: Codable, Equatable, Sendable {
    case notConfigured
    case configured(Date)
    case awaitingReturn(Date)
    case confirmedByParent(Date)
    case failed(String)
    case skipped

    /// The status label shown on the eGuard feature card.
    var statusLabel: String {
        switch self {
        case .notConfigured: "Ready to configure"
        case .configured: "Configured"
        case .awaitingReturn: "Finish in Settings"
        case .confirmedByParent: "Marked complete by you"
        case .failed: "Could not configure"
        case .skipped: "Skipped for now"
        }
    }

    var isComplete: Bool {
        switch self {
        case .configured, .confirmedByParent: true
        default: false
        }
    }

    var completedAt: Date? {
        switch self {
        case .configured(let date), .confirmedByParent(let date): date
        default: nil
        }
    }

    var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// Progress through the setup flow, persisted so a parent can resume later or offline.
nonisolated struct SetupProgress: Codable, Equatable, Sendable {
    var featureStates: [ProtectionFeature: FeatureConfigurationState] = [:]
    var isSetupComplete = false
    var completedAt: Date?

    func state(for feature: ProtectionFeature) -> FeatureConfigurationState {
        featureStates[feature] ?? .notConfigured
    }

    mutating func set(_ state: FeatureConfigurationState, for feature: ProtectionFeature) {
        featureStates[feature] = state
    }

    func completedCount(of features: [ProtectionFeature]) -> Int {
        features.filter { state(for: $0).isComplete }.count
    }
}
