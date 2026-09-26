import FamilyControls
import Foundation
import ManagedSettings

/// Applies restrictions with Apple's Managed Settings framework and reads them back for verification.
final class ManagedSettingsRestrictionService: RestrictionService {
    private let store = ManagedSettingsStore(named: EGuardShared.Store.restrictions)

    init() {}

    func applyWebContent(_ level: WebContentLevel) throws {
        switch level {
        case .limited:
            store.webContent.blockedByFilter = .auto()
        case .unrestricted:
            store.webContent.blockedByFilter = nil
        }
    }

    func applyAppInstallation(_ policy: AppInstallationPolicy) throws {
        switch policy {
        case .blocked:
            store.application.denyAppInstallation = true
        case .allowed, .parentApproval:
            // Ask to Buy is a Family Sharing setting Apple does not expose to apps.
            store.application.denyAppInstallation = nil
        }
    }

    func applyExplicitContent(block: Bool) throws {
        store.media.denyExplicitContent = block ? true : nil
    }

    func applyPurchaseProtection(requirePassword: Bool) throws {
        store.appStore.requirePasswordForPurchases = requirePassword ? true : nil
    }

    func applyAppRestrictions(_ selection: ActivitySelectionSnapshot) throws {
        guard let resolved = ActivitySelectionCodec.selection(from: selection) else {
            throw ProtectionConfigurationError.selectionRequired
        }
        store.shield.applications = resolved.applicationTokens.isEmpty ? nil : resolved.applicationTokens
        store.shield.applicationCategories = resolved.categoryTokens.isEmpty
            ? nil
            : .specific(resolved.categoryTokens)
    }

    func applyWebsiteRestrictions(_ selection: ActivitySelectionSnapshot) throws {
        guard let resolved = ActivitySelectionCodec.selection(from: selection), !selection.isEmpty else {
            store.shield.webDomains = nil
            store.shield.webDomainCategories = nil
            return
        }
        store.shield.webDomains = resolved.webDomainTokens.isEmpty ? nil : resolved.webDomainTokens
        store.shield.webDomainCategories = resolved.categoryTokens.isEmpty
            ? nil
            : .specific(resolved.categoryTokens)
    }

    func clearAllRestrictions() {
        store.clearAllSettings()
        ManagedSettingsStore(named: EGuardShared.Store.downtime).clearAllSettings()
        ManagedSettingsStore(named: EGuardShared.Store.dailyLimits).clearAllSettings()
    }

    func snapshot() -> RestrictionSnapshot {
        var snapshot = RestrictionSnapshot()
        if let policy = store.webContent.blockedByFilter {
            snapshot.webContentLimited = policy != WebContentSettings.FilterPolicy.none
        }
        snapshot.denyAppInstallation = store.application.denyAppInstallation
        snapshot.denyExplicitContent = store.media.denyExplicitContent
        snapshot.requirePasswordForPurchases = store.appStore.requirePasswordForPurchases
        snapshot.shieldedApplicationCount = store.shield.applications?.count ?? 0
        if let categories = store.shield.applicationCategories {
            snapshot.isApplicationCategoryShieldActive = categories != .none
        }
        snapshot.shieldedWebDomainCount = store.shield.webDomains?.count ?? 0
        if let categories = store.shield.webDomainCategories {
            snapshot.isWebDomainCategoryShieldActive = categories != .none
        }
        return snapshot
    }
}

/// In-memory implementation for previews, the simulator, and tests.
final class MockRestrictionService: RestrictionService {
    private(set) var state = RestrictionSnapshot()
    var errorToThrow: ProtectionConfigurationError?

    init(state: RestrictionSnapshot = .empty) {
        self.state = state
    }

    func applyWebContent(_ level: WebContentLevel) throws {
        try failIfNeeded()
        state.webContentLimited = level == .limited ? true : nil
    }

    func applyAppInstallation(_ policy: AppInstallationPolicy) throws {
        try failIfNeeded()
        state.denyAppInstallation = policy == .blocked ? true : nil
    }

    func applyExplicitContent(block: Bool) throws {
        try failIfNeeded()
        state.denyExplicitContent = block ? true : nil
    }

    func applyPurchaseProtection(requirePassword: Bool) throws {
        try failIfNeeded()
        state.requirePasswordForPurchases = requirePassword ? true : nil
    }

    func applyAppRestrictions(_ selection: ActivitySelectionSnapshot) throws {
        try failIfNeeded()
        state.shieldedApplicationCount = selection.applicationCount
        state.isApplicationCategoryShieldActive = selection.categoryCount > 0
    }

    func applyWebsiteRestrictions(_ selection: ActivitySelectionSnapshot) throws {
        try failIfNeeded()
        state.shieldedWebDomainCount = selection.webDomainCount
        state.isWebDomainCategoryShieldActive = selection.categoryCount > 0
    }

    func clearAllRestrictions() {
        state = .empty
    }

    func snapshot() -> RestrictionSnapshot {
        state
    }

    /// Simulates the system dropping eGuard's settings, e.g. after authorization is revoked.
    func simulateDrift() {
        state = .empty
    }

    private func failIfNeeded() throws {
        if let errorToThrow { throw errorToThrow }
    }
}
