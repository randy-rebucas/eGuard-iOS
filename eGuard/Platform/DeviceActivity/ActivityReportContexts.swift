import DeviceActivity
import Foundation
import SwiftUI

extension DeviceActivityReport.Context {
    /// A single duration such as "2h 14m". Rendered by the eGuardActivityReport extension.
    static let eGuardToday = Self("eGuard Today")

    /// A full screen-time summary: total, per-segment bars, and top apps. Rendered by the extension.
    static let eGuardScreenTime = Self("eGuard Screen Time")
}

/// The ranges offered on the Screen Time screen.
nonisolated enum ScreenTimeRange: String, CaseIterable, Identifiable, Sendable {
    case today
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .week: "7 Days"
        case .month: "30 Days"
        }
    }

    /// Hourly buckets for today, daily buckets for longer ranges.
    func segment(now: Date = .now, calendar: Calendar = .current) -> DeviceActivityFilter.SegmentInterval {
        let startOfToday = calendar.startOfDay(for: now)
        switch self {
        case .today:
            return .hourly(during: DateInterval(start: startOfToday, end: now))
        case .week:
            let start = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
            return .daily(during: DateInterval(start: start, end: now))
        case .month:
            let start = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday
            return .daily(during: DateInterval(start: start, end: now))
        }
    }
}
