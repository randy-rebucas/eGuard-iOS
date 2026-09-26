import Foundation

/// Step-by-step instructions for a setting Apple requires the parent to finish in Settings.
nonisolated struct GuidedInstructions: Equatable, Sendable {
    let feature: ProtectionFeature
    let settingsPath: String
    let steps: [String]
    let cannotVerifyNote: String
}

/// Opens the Settings app and describes guided flows.
@MainActor
protocol SystemSettingsService: AnyObject {
    /// The URL that opens this app's page in Settings, or `nil` when unavailable.
    var settingsURL: URL? { get }

    func instructions(for feature: ProtectionFeature) -> GuidedInstructions
}
