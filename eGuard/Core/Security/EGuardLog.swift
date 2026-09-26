import Foundation
import OSLog

/// Central loggers. Rules: never log the child's name, selections, or any account details.
/// Interpolated values default to `.private`, so only static event descriptions are visible.
nonisolated enum EGuardLog {
    static let app = Logger(subsystem: subsystem, category: "app")
    static let configuration = Logger(subsystem: subsystem, category: "configuration")
    static let authorization = Logger(subsystem: subsystem, category: "authorization")

    private static let subsystem = Bundle.main.bundleIdentifier ?? "eGuard"
}
