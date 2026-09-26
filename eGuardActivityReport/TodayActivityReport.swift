import DeviceActivity
import ExtensionKit
import SwiftUI

extension DeviceActivityReport.Context {
    /// The dashboard requests this context. The string must match the app's copy.
    static let eGuardToday = Self("eGuard Today")
}

/// Sums the filtered activity into a single duration such as "2h 14m".
nonisolated struct TodayActivityReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .eGuardToday
    let content: (String) -> TodayActivityView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> String {
        let total = await data.flatMap { $0.activitySegments }.reduce(0) { partial, segment in
            partial + segment.totalActivityDuration
        }
        return Self.format(total)
    }

    static func format(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder)m" }
        return "\(hours)h \(remainder)m"
    }
}
