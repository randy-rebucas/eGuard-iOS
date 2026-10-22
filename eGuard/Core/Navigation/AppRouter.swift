import Foundation
import Observation

/// Every destination reachable from the root NavigationStack.
nonisolated enum AppRoute: Hashable, Sendable {
    // Choosing a side and signing in
    case welcome
    case childSetup
    case createAccount
    /// Create Account's code step. The `signup` ticket lives only in the in-memory path.
    case signupCode(SignupStarted)
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
    /// `pending`: open on the Pending filter, where app and website requests are answered.
    /// `requestId`: the website request to bring into view there (from a `REVIEW_SITE_REQUEST` alert).
    case appsManagement(childId: String, pending: Bool = false, requestId: String? = nil)
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

    /// Whether `open(_:)` goes somewhere for this action.
    static func canOpen(_ action: AlertAction) -> Bool {
        (action.type == "VIEW_BROWSERS" && action.childId == nil) || route(for: action) != nil
    }

    /// Routes an alert's action button as the API describes. False when the app can't open it (an unknown type, or
    /// a missing id), so the caller can fall back instead of a tap that goes nowhere.
    @discardableResult
    func open(_ action: AlertAction) -> Bool {
        // A browser disconnected for security names no child: the Devices tab lists every browser
        if action.type == "VIEW_BROWSERS" && action.childId == nil {
            show(.devices)
            return true
        }
        guard let route = Self.route(for: action) else { return false }
        push(route)
        return true
    }

    static func route(for action: AlertAction) -> AppRoute? {
        let childId = action.childId
        switch action.type {
        case "FIX_SETTING":
            guard let childId, let key = action.key else { return nil }
            return .protectionEditor(childId: childId, key: key)
        case "VIEW_DEVICE":
            if let deviceId = action.deviceId { return .deviceDetail(deviceId: deviceId) }
            return childId.map { .childProfile(childId: $0) }
        case "REVIEW_APPS": return childId.map { .appsManagement(childId: $0, pending: true) }
        case "VIEW_SCREEN_TIME": return childId.map { .screenTime(childId: $0) }
        case "VIEW_HISTORY": return childId.map { .childProfile(childId: $0) }
        case "VIEW_LOCATION": return childId.map { .location(childId: $0) }
        // Website requests are answered with app requests, under Apps › Pending
        case "REVIEW_SITE_REQUEST": return childId.map { .appsManagement(childId: $0, pending: true, requestId: action.requestId) }
        case "VIEW_BROWSERS": return childId.map { .browserPolicy(childId: $0) }
        case "VIEW_ORGANIZATIONS": return .organizations
        case "VIEW_FAMILY": return .family
        case "MANAGE_SUBSCRIPTION": return .subscription
        default: return nil
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
