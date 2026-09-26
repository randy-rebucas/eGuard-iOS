import Foundation

/// Wraps Apple's Family Controls authorization so the rest of eGuard never assumes it was granted.
@MainActor
protocol ParentalControlAuthorizationService: AnyObject {
    /// The current status. Always re-read this before acting; it can change outside the app.
    var authorizationStatus: ParentalControlAuthorizationStatus { get }

    /// Which family member the next request is for.
    var memberKind: FamilyMemberKind { get set }

    /// Re-reads the status from the system.
    func refreshAuthorizationStatus()

    /// Presents Apple's official authorization flow for `memberKind`.
    func requestAuthorization() async throws

    /// Revokes eGuard's authorization.
    func revokeAuthorization() async throws
}
