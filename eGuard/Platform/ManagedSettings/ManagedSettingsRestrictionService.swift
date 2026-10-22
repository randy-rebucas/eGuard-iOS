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

    func applyMaximumAppRating(age: Int?) throws {
        store.appStore.maximumRating = age.map { RatingTiers.rating(forAge: $0, in: RatingTiers.appStore) }
    }

    func applyContentRating(age: Int?) throws {
        guard let age else {
            store.media.maximumMovieRating = nil
            store.media.maximumTVShowRating = nil
            store.media.denyExplicitContent = nil
            return
        }
        store.media.maximumMovieRating = RatingTiers.rating(forAge: age, in: RatingTiers.movies)
        store.media.maximumTVShowRating = RatingTiers.rating(forAge: age, in: RatingTiers.tv)
        store.media.denyExplicitContent = age < 18 ? true : nil
    }

    func applyAppRemoval(deny: Bool) throws {
        store.application.denyAppRemoval = deny ? true : nil
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
        snapshot.denyAppRemoval = store.application.denyAppRemoval
        snapshot.maximumAppRatingAge = store.appStore.maximumRating.flatMap { RatingTiers.age(forRating: $0, in: RatingTiers.appStore) }
        snapshot.contentRatingAge = store.media.maximumMovieRating.flatMap { RatingTiers.age(forRating: $0, in: RatingTiers.movies) }
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
