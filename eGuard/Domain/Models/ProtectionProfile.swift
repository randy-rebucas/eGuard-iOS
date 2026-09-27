import Foundation

/// The protection profiles shared with the Android implementation. Names must not change.
nonisolated enum ProtectionProfile: String, Codable, CaseIterable, Identifiable, Sendable {
    case balanced
    case protected
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: "Balanced"
        case .protected: "Protected"
        case .custom: "Custom"
        }
    }

    var summary: String {
        switch self {
        case .balanced: "Everyday protection with reasonable limits."
        case .protected: "Stronger protection for younger children."
        case .custom: "Configure everything yourself."
        }
    }

    var symbolName: String {
        switch self {
        case .balanced: "scalemass.fill"
        case .protected: "checkmark.shield.fill"
        case .custom: "gearshape.fill"
        }
    }
}
