import Foundation
import Observation

/// Every destination reachable from the root NavigationStack.
nonisolated enum AppRoute: Hashable, Sendable {
    // Choosing a side and signing in
    case welcome
    case childSetup
    case createAccount
    case signIn
    case forgotPassword
    case twoFactorCode(TwoFactorChallenge)

    // Links from eGuard emails
    case resetPassword(token: String)
    case verifyEmailLink(token: String)
    case acceptInvite(token: String)

    // Onboarding
    case addChild
    case editChild(childId: String)
    case protectionProfile(childId: String)
    case recommendedSetup(childId: String, profile: String)
    case setupProgress(childId: String, profile: String, overrides: [JSONValue], categoryLimits: [CategoryLimitUpdate]? = nil)
    case healthCheck(childId: String?, isOnboarding: Bool)
    case complete(childId: String, batchId: String?)

    // Protections
    case protections(childId: String)
    case protectionEditor(childId: String, key: String)

    // Child and activity
    case childProfile(childId: String)
    case screenTime(childId: String)
    /// `requestId` opens the Pending tab with that website request in view.
    case appsManagement(childId: String, requestId: String? = nil)
    case location(childId: String)
    case deviceDetail(deviceId: String)
    case browserPolicy(childId: String)

    // App sections
    case alerts
    case settings
    case account
    case changePassword
    case sessions
    case twoFactor
    case linkedSignIns
    case deleteAccount
    case family
    case organizations
    case setUpChildDevice
    case notifications
    case privacy
    case about
    case subscription
    case helpSupport
    case helpArticle(slug: String)
    case supportTicket
}

/// The bottom tabs of the main app.
nonisolated enum MainTab: String, CaseIterable, Identifiable, Sendable {
    case home
    case children
    case devices
    case alerts
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .children: "Children"
        case .devices: "Devices"
        case .alerts: "Alerts"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .home: "house.fill"
        case .children: "person.2.fill"
        case .devices: "iphone"
        case .alerts: "bell.fill"
        case .settings: "gearshape.fill"
        }
    }
}

/// Owns the navigation path so view models can navigate without knowing about views.
@Observable
final class AppRouter {
    var path: [AppRoute] = []
    var selectedTab: MainTab = .home

    init(path: [AppRoute] = []) {
        self.path = path
    }

    func push(_ route: AppRoute) {
        path.append(route)
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func popToRoot() {
        path.removeAll()
    }

    /// Returns to the root and shows the given tab.
    func show(_ tab: MainTab) {
        selectedTab = tab
        popToRoot()
    }

    /// Routes an alert's action button as the API describes.
    func open(_ action: AlertAction) {
        switch action.type {
        case "FIX_SETTING":
            if let childId = action.childId, let key = action.key { push(.protectionEditor(childId: childId, key: key)) }
        case "VIEW_DEVICE":
            if let deviceId = action.deviceId { push(.deviceDetail(deviceId: deviceId)) }
        case "REVIEW_APPS":
            if let childId = action.childId { push(.appsManagement(childId: childId)) }
        case "VIEW_SCREEN_TIME":
            if let childId = action.childId { push(.screenTime(childId: childId)) }
        case "VIEW_HISTORY":
            if let childId = action.childId { push(.childProfile(childId: childId)) }
        case "MANAGE_SUBSCRIPTION":
            push(.subscription)
        case "VIEW_LOCATION":
            if let childId = action.childId { push(.location(childId: childId)) }
        case "REVIEW_SITE_REQUEST":
            if let childId = action.childId { push(.appsManagement(childId: childId, requestId: action.requestId)) }
        case "VIEW_BROWSERS":
            // With a child, that child's browser protection; without one, the family's browsers list.
            if let childId = action.childId { push(.browserPolicy(childId: childId)) } else { show(.devices) }
        case "VIEW_ORGANIZATIONS":
            push(.organizations)
        case "VIEW_FAMILY":
            push(.family)
        default:
            // Unknown types get no button (`AlertAction.isKnown`), so this is only reached by stale UI.
            break
        }
    }

    /// Opens a link from an eGuard email on the parent side.
    func open(_ link: DeepLink) {
        popToRoot()
        switch link {
        case .verifyEmail(let token): push(.verifyEmailLink(token: token))
        case .resetPassword(let token): push(.resetPassword(token: token))
        case .acceptInvite(let token): push(.acceptInvite(token: token))
        }
    }
}
