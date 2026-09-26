import FamilyControls
import Foundation
import Testing
@testable import MyApp

@Suite("Capability detection")
struct CapabilityTests {
    let settings = RecommendSetupUseCase().recommend(profile: .balanced, childAge: 12)

    @Test func automaticFeaturesOnSupportedDevice() {
        let resolver = CapabilityResolver(environment: .iPhone)
        #expect(resolver.capability(for: .downtime, settings: settings).mode == .automatic)
        #expect(resolver.capability(for: .webContent, settings: settings).mode == .automatic)
        #expect(resolver.capability(for: .purchases, settings: settings).mode == .automatic)
    }

    @Test func guidedFeaturesAreNeverClaimedAutomatic() {
        let resolver = CapabilityResolver(environment: .iPhone)
        #expect(resolver.capability(for: .screenTimePasscode, settings: settings).mode == .guided)
        #expect(resolver.capability(for: .appInstallation, settings: settings).mode == .guided)
    }

    @Test func appInstallationModeDependsOnPolicy() {
        let resolver = CapabilityResolver(environment: .iPhone)
        var blocked = settings
        blocked.appInstallation = .blocked
        #expect(resolver.capability(for: .appInstallation, settings: blocked).mode == .automatic)
    }

    @Test func unsupportedPlatformDowngradesAutomaticOnly() {
        let resolver = CapabilityResolver(environment: .unavailable)
        #expect(resolver.capability(for: .downtime, settings: settings).mode == .unsupported)
        #expect(resolver.capability(for: .screenTimePasscode, settings: settings).mode == .guided)
    }

    @Test func capabilitiesCoverOnlyEnabledFeatures() {
        let resolver = CapabilityResolver(environment: .iPhone)
        let features = resolver.capabilities(for: settings).map(\.feature)
        #expect(features == settings.enabledFeatures)
        #expect(!features.contains(.appRestrictions))
    }
}

@Suite("Authorization state")
struct AuthorizationStateTests {
    @Test func statusAuthorizationFlags() {
        #expect(!ParentalControlAuthorizationStatus.notDetermined.isAuthorized)
        #expect(!ParentalControlAuthorizationStatus.denied.isAuthorized)
        #expect(ParentalControlAuthorizationStatus.approved.isAuthorized)
        #expect(ParentalControlAuthorizationStatus.approvedWithDataAccess.isAuthorized)
    }

    @Test func familyControlsStatusMapping() {
        #expect(FamilyControlsAuthorizationService.map(AuthorizationStatus.notDetermined) == .notDetermined)
        #expect(FamilyControlsAuthorizationService.map(AuthorizationStatus.denied) == .denied)
        #expect(FamilyControlsAuthorizationService.map(AuthorizationStatus.approved) == .approved)
        #expect(FamilyControlsAuthorizationService.map(AuthorizationStatus.approvedWithDataAccess) == .approvedWithDataAccess)
    }

    @Test func familyControlsErrorMapping() {
        #expect(FamilyControlsAuthorizationService.map(FamilyControlsError.invalidAccountType) == .invalidAccountType)
        #expect(FamilyControlsAuthorizationService.map(FamilyControlsError.authorizationCanceled) == .canceled)
        #expect(FamilyControlsAuthorizationService.map(FamilyControlsError.networkError) == .networkError)
        #expect(FamilyControlsAuthorizationService.map(FamilyControlsError.authenticationMethodUnavailable) == .passcodeRequired)
    }

    @Test func mockApprovesAndDenies() async throws {
        let approving = MockAuthorizationService()
        try await approving.requestAuthorization()
        #expect(approving.authorizationStatus == .approved)

        let denying = MockAuthorizationService(behavior: .deny)
        try await denying.requestAuthorization()
        #expect(denying.authorizationStatus == .denied)
    }

    @Test func mockSurfacesFailures() async {
        let failing = MockAuthorizationService(behavior: .fail(.authorizationConflict))
        await #expect(throws: ParentalControlAuthorizationError.authorizationConflict) {
            try await failing.requestAuthorization()
        }
        #expect(failing.authorizationStatus == .notDetermined)
    }

    @Test func relationshipSelectsMemberKind() {
        #expect(FamilyRelationshipStatus.childInFamilySharing.memberKind == .child)
        #expect(FamilyRelationshipStatus.thisDeviceOwner.memberKind == .individual)
        #expect(!FamilyRelationshipStatus.notSure.hasKnownPrerequisites)
    }
}
