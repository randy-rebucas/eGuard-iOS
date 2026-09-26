import FamilyControls
import Foundation
import OSLog
import Observation

/// The live Family Controls implementation. Status is always re-read from the system, never assumed.
@Observable
final class FamilyControlsAuthorizationService: ParentalControlAuthorizationService {
    private(set) var authorizationStatus: ParentalControlAuthorizationStatus = .notDetermined
    var memberKind: FamilyMemberKind = .child

    private let center = AuthorizationCenter.shared

    init() {
        refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = Self.map(center.authorizationStatus)
    }

    func requestAuthorization() async throws {
        let member: FamilyControlsMember = memberKind == .child ? .child : .individual
        do {
            try await center.requestAuthorization(for: member)
        } catch let error as FamilyControlsError {
            refreshAuthorizationStatus()
            EGuardLog.authorization.error("Family Controls authorization failed: \(String(describing: error), privacy: .public)")
            throw Self.map(error)
        } catch {
            refreshAuthorizationStatus()
            throw ParentalControlAuthorizationError.unknown(error.localizedDescription)
        }
        refreshAuthorizationStatus()
        EGuardLog.authorization.info("Family Controls authorization completed.")
    }

    func revokeAuthorization() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.revokeAuthorization { result in
                continuation.resume(with: result)
            }
        }
        refreshAuthorizationStatus()
    }

    // MARK: - Mapping

    static func map(_ status: AuthorizationStatus) -> ParentalControlAuthorizationStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .approved: .approved
        case .approvedWithDataAccess: .approvedWithDataAccess
        @unknown default: .notDetermined
        }
    }

    static func map(_ error: FamilyControlsError) -> ParentalControlAuthorizationError {
        switch error {
        case .invalidAccountType: .invalidAccountType
        case .authorizationConflict: .authorizationConflict
        case .authorizationCanceled: .canceled
        case .unavailable: .unavailable
        case .restricted: .restricted
        case .networkError: .networkError
        case .authenticationMethodUnavailable: .passcodeRequired
        case .invalidArgument: .unknown("The authorization request was invalid.")
        default: .unknown(error.localizedDescription)
        }
    }
}

/// A controllable implementation for previews, the simulator, and UI tests.
@Observable
final class MockAuthorizationService: ParentalControlAuthorizationService {
    enum Behavior {
        case approve
        case deny
        case fail(ParentalControlAuthorizationError)
    }

    private(set) var authorizationStatus: ParentalControlAuthorizationStatus
    var memberKind: FamilyMemberKind = .child
    var behavior: Behavior
    private(set) var requestCount = 0

    init(status: ParentalControlAuthorizationStatus = .notDetermined, behavior: Behavior = .approve) {
        self.authorizationStatus = status
        self.behavior = behavior
    }

    func refreshAuthorizationStatus() {}

    func requestAuthorization() async throws {
        requestCount += 1
        switch behavior {
        case .approve:
            authorizationStatus = .approved
        case .deny:
            authorizationStatus = .denied
        case .fail(let error):
            throw error
        }
    }

    func revokeAuthorization() async throws {
        authorizationStatus = .notDetermined
    }
}
