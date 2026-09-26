import Foundation

/// What eGuard can read back from the device's managed settings. `nil` means eGuard has not set the value.
nonisolated struct RestrictionSnapshot: Equatable, Sendable {
    var webContentLimited: Bool?
    var denyAppInstallation: Bool?
    var denyExplicitContent: Bool?
    var requirePasswordForPurchases: Bool?
    var shieldedApplicationCount = 0
    var isApplicationCategoryShieldActive = false
    var shieldedWebDomainCount = 0
    var isWebDomainCategoryShieldActive = false

    static let empty = RestrictionSnapshot()

    var hasAppRestrictions: Bool {
        shieldedApplicationCount > 0 || isApplicationCategoryShieldActive
    }

    var hasWebsiteRestrictions: Bool {
        shieldedWebDomainCount > 0 || isWebDomainCategoryShieldActive
    }
}

/// Applies and reads restrictions through Apple's Managed Settings framework.
@MainActor
protocol RestrictionService: AnyObject {
    func applyWebContent(_ level: WebContentLevel) throws
    func applyAppInstallation(_ policy: AppInstallationPolicy) throws
    func applyExplicitContent(block: Bool) throws
    func applyPurchaseProtection(requirePassword: Bool) throws
    func applyAppRestrictions(_ selection: ActivitySelectionSnapshot) throws
    func applyWebsiteRestrictions(_ selection: ActivitySelectionSnapshot) throws
    func clearAllRestrictions()

    /// Reads the values eGuard currently applies. Used for verification and drift detection.
    func snapshot() -> RestrictionSnapshot
}
