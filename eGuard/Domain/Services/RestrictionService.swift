import Foundation

/// What eGuard can read back from the device's managed settings. `nil` means eGuard has not set the value.
nonisolated struct RestrictionSnapshot: Equatable, Sendable {
    var webContentLimited: Bool?
    var denyAppInstallation: Bool?
    var denyExplicitContent: Bool?
    var requirePasswordForPurchases: Bool?
    var denyAppRemoval: Bool?
    /// The age tier behind the App Store maximum rating, when eGuard set one.
    var maximumAppRatingAge: Int?
    /// The age tier behind the movie and TV rating caps, when eGuard set one.
    var contentRatingAge: Int?
    /// Apple's own values behind those (several server ages share one), for [RatingTiers.reportedAge].
    var maximumAppRating: Int?
    var movieRating: Int?
    var tvRating: Int?
    /// Which protections asked for App Store installs to be denied. Not an OS value: what eGuard last applied for
    /// each, so each protection reads back honestly while they share Apple's one switch.
    var installApprovalReasons: Set<InstallApprovalReason> = []
    /// "Set Automatically" for date and time can't be turned off.
    var requiresAutomaticDateAndTime: Bool?
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

/// A protection that needs a parent to approve installs. APP_APPROVAL and DOWNLOADS both map onto Apple's
/// `denyAppInstallation`, which stays on while either of them wants it.
nonisolated enum InstallApprovalReason: String, Codable, Hashable, Sendable {
    case appApproval
    case downloads
}

/// Applies and reads restrictions through Apple's Managed Settings framework.
@MainActor
protocol RestrictionService: AnyObject {
    func applyWebContent(_ level: WebContentLevel) throws
    func applyAppInstallation(_ policy: AppInstallationPolicy) throws
    /// Records whether `reason` needs installs denied, and denies App Store installation while any reason does.
    /// Applying one reason never lifts another's.
    func applyInstallApproval(_ reason: InstallApprovalReason, required: Bool) throws
    func applyExplicitContent(block: Bool) throws
    func applyPurchaseProtection(requirePassword: Bool) throws
    func applyAppRestrictions(_ selection: ActivitySelectionSnapshot) throws
    func applyWebsiteRestrictions(_ selection: ActivitySelectionSnapshot) throws
    /// Caps App Store downloads at the rating for this age tier; `nil` removes the cap.
    func applyMaximumAppRating(age: Int?) throws
    /// Caps movies and TV shows at the rating for this age tier and hides explicit media below 18; `nil` removes the caps.
    func applyContentRating(age: Int?) throws
    /// Stops the child from deleting apps, including eGuard.
    func applyAppRemoval(deny: Bool) throws
    /// Keeps date and time on "Set Automatically", so schedules can't be escaped by changing the clock.
    func applyAutomaticDateAndTime(require: Bool) throws
    func clearAllRestrictions()

    /// Reads the values eGuard currently applies. Used for verification and drift detection.
    func snapshot() -> RestrictionSnapshot
}

/// Maps the server's age tiers (4, 9, 12, 13, 16, 17, 18, as the web offers them) to Apple's rating values and
/// back, so a report returns exactly the tier the parent asked for when the device applied it.
nonisolated enum RatingTiers {
    /// App Store: 100 (4+), 200 (9+), 300 (12+), 600 (17+), 1000 (everything).
    static let appStore: [(age: Int, rating: Int)] = [(4, 100), (9, 200), (12, 300), (13, 300), (16, 600), (17, 600), (18, 1000)]
    /// Movies: 100 (G), 200 (PG), 300 (PG-13), 400 (R), 1000 (everything).
    static let movies: [(age: Int, rating: Int)] = [(4, 100), (9, 200), (13, 300), (16, 400), (17, 400), (18, 1000)]
    /// TV: 200 (TV-Y7), 300 (TV-G), 500 (TV-14), 600 (TV-MA), 1000 (everything).
    static let tv: [(age: Int, rating: Int)] = [(4, 200), (9, 300), (13, 500), (16, 600), (17, 600), (18, 1000)]

    static func rating(forAge age: Int, in table: [(age: Int, rating: Int)]) -> Int {
        table.last { $0.age <= max(age, 4) }?.rating ?? table[0].rating
    }

    static func age(forRating rating: Int, in table: [(age: Int, rating: Int)]) -> Int? {
        table.first { $0.rating == rating }?.age ?? table.last { $0.rating <= rating }?.age
    }

    /// The age to report for the device's [rating]: the one asked for when the device has its rating (12 and 13
    /// share Apple's 12+), otherwise the tier the rating stands for. Nil when no rating is set.
    static func reportedAge(requested: Int?, rating: Int?, in table: [(age: Int, rating: Int)]) -> Int? {
        guard let rating else { return nil }
        if let requested, Self.rating(forAge: requested, in: table) == rating { return requested }
        return age(forRating: rating, in: table)
    }
}
