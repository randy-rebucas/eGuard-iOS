import Foundation

/// The health states shared with Android. This only describes configuration state, never behavior.
nonisolated enum HealthStatus: String, Codable, CaseIterable, Sendable {
    case pass = "PASS"
    case warning = "WARNING"
    case actionRequired = "ACTION_REQUIRED"
    case unsupported = "UNSUPPORTED"
    case notConfigured = "NOT_CONFIGURED"

    var title: String {
        switch self {
        case .pass: "Active"
        case .warning: "Needs review"
        case .actionRequired: "Action required"
        case .unsupported: "Not supported"
        case .notConfigured: "Not configured"
        }
    }

    /// Whether this state counts toward the health score denominator.
    var isEvaluated: Bool {
        self != .unsupported
    }

    var needsAttention: Bool {
        switch self {
        case .warning, .actionRequired, .notConfigured: true
        case .pass, .unsupported: false
        }
    }
}

/// The result of verifying one protection feature.
nonisolated struct ConfigurationCheck: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let feature: ProtectionFeature
    let status: HealthStatus
    let mode: ConfigurationMode
    let lastVerified: Date?
    let explanation: String?
    let remediation: String?

    init(
        id: UUID = UUID(),
        feature: ProtectionFeature,
        status: HealthStatus,
        mode: ConfigurationMode,
        lastVerified: Date? = nil,
        explanation: String? = nil,
        remediation: String? = nil
    ) {
        self.id = id
        self.feature = feature
        self.status = status
        self.mode = mode
        self.lastVerified = lastVerified
        self.explanation = explanation
        self.remediation = remediation
    }
}

/// The overall protection state shown on the dashboard.
nonisolated enum ProtectionState: String, Codable, Sendable {
    case active
    case needsAttention
    case notConfigured

    var title: String {
        switch self {
        case .active: "Active"
        case .needsAttention: "Needs attention"
        case .notConfigured: "Not configured"
        }
    }
}

/// Pure scoring rules for Configuration Health, kept separate so they are easy to test.
nonisolated enum HealthScoreCalculator {
    static func passedCount(_ checks: [ConfigurationCheck]) -> Int {
        checks.filter { $0.status == .pass }.count
    }

    static func evaluatedCount(_ checks: [ConfigurationCheck]) -> Int {
        checks.filter { $0.status.isEvaluated }.count
    }

    static func summary(passed: Int, total: Int) -> String {
        guard total > 0 else { return "No protections are configured yet." }
        if passed == total { return "All protections are active." }
        if passed == 0 { return "No protections are active yet." }
        let ratio = Double(passed) / Double(total)
        if ratio >= 0.7 { return "Most protections are active." }
        return "Several protections need attention."
    }

    static func attentionSummary(count: Int) -> String? {
        switch count {
        case 0: nil
        case 1: "One setting needs review"
        default: "\(count) settings need review"
        }
    }

    static func protectionState(passed: Int, total: Int) -> ProtectionState {
        if total == 0 { return .notConfigured }
        return passed == total ? .active : .needsAttention
    }
}

/// A complete Configuration Health result.
nonisolated struct ConfigurationHealthReport: Codable, Equatable, Sendable {
    let checks: [ConfigurationCheck]
    let generatedAt: Date

    var passedCount: Int { HealthScoreCalculator.passedCount(checks) }
    var evaluatedCount: Int { HealthScoreCalculator.evaluatedCount(checks) }
    var attentionChecks: [ConfigurationCheck] { checks.filter { $0.status.needsAttention } }
    var summary: String { HealthScoreCalculator.summary(passed: passedCount, total: evaluatedCount) }
    var attentionSummary: String? { HealthScoreCalculator.attentionSummary(count: attentionChecks.count) }
    var protectionState: ProtectionState {
        HealthScoreCalculator.protectionState(passed: passedCount, total: evaluatedCount)
    }
    var scoreText: String { "\(passedCount) / \(evaluatedCount)" }

    /// Whether any previously configured protection is no longer active.
    var hasDrift: Bool {
        checks.contains { $0.status == .actionRequired }
    }
}
