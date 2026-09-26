import Foundation
import Observation

/// Every destination reachable from the root NavigationStack.
nonisolated enum AppRoute: Hashable, Sendable {
    case childDevice
    case protectionProfile
    case recommendedSetup
    case configureSettings
    case healthCheck
    case complete
    case manageProtection
    case healthReview
    case settings
    case authorization
    case featureDetail(ProtectionFeature)
}

/// Owns the navigation path so view models can navigate without knowing about views.
@Observable
final class AppRouter {
    var path: [AppRoute] = []

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
}
