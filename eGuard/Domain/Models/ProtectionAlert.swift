import Foundation

/// The filter groups on the Alerts screen.
nonisolated enum AlertCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case protection
    case apps
    case location

    var id: String { rawValue }

    var title: String {
        switch self {
        case .protection: "Protection"
        case .apps: "Apps"
        case .location: "Location"
        }
    }
}

/// Something eGuard wants the parent to know about. Alerts are generated locally from
/// verified state changes and never from guesses about the child's behavior.
nonisolated struct ProtectionAlert: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let category: AlertCategory
    let title: String
    let detail: String
    let date: Date
    let feature: ProtectionFeature?
    var isRead: Bool

    init(
        id: UUID = UUID(),
        category: AlertCategory,
        title: String,
        detail: String,
        date: Date = .now,
        feature: ProtectionFeature? = nil,
        isRead: Bool = false
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.detail = detail
        self.date = date
        self.feature = feature
        self.isRead = isRead
    }

    var symbolName: String {
        if let feature { return feature.symbolName }
        return switch category {
        case .protection: "shield.lefthalf.filled"
        case .apps: "square.grid.2x2.fill"
        case .location: "location.fill"
        }
    }

    /// Alerts about the same feature and title on the same day are duplicates.
    func isDuplicate(of other: ProtectionAlert, calendar: Calendar = .current) -> Bool {
        title == other.title && feature == other.feature && category == other.category
            && calendar.isDate(date, inSameDayAs: other.date)
    }
}

/// Builds alerts from a health report. Kept pure so it is easy to test.
nonisolated enum AlertGenerator {
    static let maximumStored = 100

    static func alerts(from report: ConfigurationHealthReport, deviceName: String) -> [ProtectionAlert] {
        report.checks.compactMap { check in
            switch check.status {
            case .actionRequired:
                ProtectionAlert(
                    category: .protection,
                    title: "\(check.feature.title) needs attention",
                    detail: check.explanation ?? "\(check.feature.title) is no longer active on \(deviceName).",
                    date: report.generatedAt,
                    feature: check.feature
                )
            case .notConfigured:
                ProtectionAlert(
                    category: .protection,
                    title: "\(check.feature.title) not configured",
                    detail: deviceName,
                    date: report.generatedAt,
                    feature: check.feature
                )
            case .warning:
                ProtectionAlert(
                    category: .apps,
                    title: "Choose apps for \(check.feature.title)",
                    detail: check.explanation ?? deviceName,
                    date: report.generatedAt,
                    feature: check.feature
                )
            case .pass, .unsupported:
                nil
            }
        }
    }

    /// Appends new alerts, dropping same-day duplicates and keeping the list bounded.
    static func merge(_ new: [ProtectionAlert], into existing: [ProtectionAlert]) -> [ProtectionAlert] {
        var result = existing
        for alert in new where !result.contains(where: { $0.isDuplicate(of: alert) }) {
            result.append(alert)
        }
        result.sort { $0.date > $1.date }
        if result.count > maximumStored {
            result.removeLast(result.count - maximumStored)
        }
        return result
    }
}
