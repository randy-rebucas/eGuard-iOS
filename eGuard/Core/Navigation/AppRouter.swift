import Foundation
import Observation

/// Every destination reachable from the root NavigationStack.
nonisolated enum AppRoute: Hashable, Sendable {
    // Account
    case createAccount
    case signIn

    // Onboarding
    case childDevice
    case protectionProfile
    case recommendedSetup
    case configureSettings
    case healthCheck
    case complete

    // Protection management
    case manageProtection
    case healthReview
    case authorization
    case featureDetail(ProtectionFeature)

    // Child and activity
    case childProfile
    case screenTime
    case appsManagement
    case location

    // App sections
    case alerts
    case settings
    case account
    case notifications
    case privacy
    case about
    case subscription
    case helpSupport
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
}
