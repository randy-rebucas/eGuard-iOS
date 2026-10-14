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
        // Ask to Buy is a Family Sharing setting Apple does not expose to apps, so only blocking denies installs.
        try applyInstallApproval(.appApproval, required: policy == .blocked)
    }

    func applyInstallApproval(_ reason: InstallApprovalReason, required: Bool) throws {
        var reasons = installApprovalReasons
        if required {
            reasons.insert(reason)
        } else {
            reasons.remove(reason)
        }
        installApprovalReasons = reasons
        store.application.denyAppInstallation = reasons.isEmpty ? nil : true
    }

    /// Kept in the App Group, beside the store it explains, so it survives relaunches.
    private var installApprovalReasons: Set<InstallApprovalReason> {
        get {
            let raw = EGuardShared.sharedDefaults?.stringArray(forKey: EGuardShared.DefaultsKey.installApprovalReasons) ?? []
            return Set(raw.compactMap(InstallApprovalReason.init(rawValue:)))
        }
        set {
            if newValue.isEmpty {
                EGuardShared.sharedDefaults?.removeObject(forKey: EGuardShared.DefaultsKey.installApprovalReasons)
            } else {
                EGuardShared.sharedDefaults?.set(newValue.map(\.rawValue).sorted(), forKey: EGuardShared.DefaultsKey.installApprovalReasons)
            }
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

    func applyAutomaticDateAndTime(require: Bool) throws {
        store.dateAndTime.requireAutomaticDateAndTime = require ? true : nil
    }

    func clearAllRestrictions() {
        store.clearAllSettings()
        installApprovalReasons = []
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
        snapshot.maximumAppRating = store.appStore.maximumRating
        snapshot.movieRating = store.media.maximumMovieRating
        snapshot.tvRating = store.media.maximumTVShowRating
        snapshot.installApprovalReasons = installApprovalReasons
        snapshot.requiresAutomaticDateAndTime = store.dateAndTime.requireAutomaticDateAndTime
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
        try applyInstallApproval(.appApproval, required: policy == .blocked)
    }

    func applyInstallApproval(_ reason: InstallApprovalReason, required: Bool) throws {
        try failIfNeeded()
        if required {
            state.installApprovalReasons.insert(reason)
        } else {
            state.installApprovalReasons.remove(reason)
        }
        state.denyAppInstallation = state.installApprovalReasons.isEmpty ? nil : true
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

    func applyMaximumAppRating(age: Int?) throws {
        try failIfNeeded()
        // Round-trip through Apple's rating values exactly like the live service.
        state.maximumAppRating = age.map { RatingTiers.rating(forAge: $0, in: RatingTiers.appStore) }
        state.maximumAppRatingAge = state.maximumAppRating.flatMap { RatingTiers.age(forRating: $0, in: RatingTiers.appStore) }
    }

    func applyContentRating(age: Int?) throws {
        try failIfNeeded()
        state.movieRating = age.map { RatingTiers.rating(forAge: $0, in: RatingTiers.movies) }
        state.tvRating = age.map { RatingTiers.rating(forAge: $0, in: RatingTiers.tv) }
        state.contentRatingAge = state.movieRating.flatMap { RatingTiers.age(forRating: $0, in: RatingTiers.movies) }
        state.denyExplicitContent = age.map { $0 < 18 ? true : nil } ?? nil
    }

    func applyAppRemoval(deny: Bool) throws {
        try failIfNeeded()
        state.denyAppRemoval = deny ? true : nil
    }

    func applyAutomaticDateAndTime(require: Bool) throws {
        try failIfNeeded()
        state.requiresAutomaticDateAndTime = require ? true : nil
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
