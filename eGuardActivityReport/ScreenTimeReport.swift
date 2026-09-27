import DeviceActivity
import ExtensionKit
import ManagedSettings
import SwiftUI

extension DeviceActivityReport.Context {
    /// The Screen Time screen requests this context. The string must match the app's copy.
    static let eGuardScreenTime = Self("eGuard Screen Time")
}

/// Everything the Screen Time view needs, computed inside the sandbox.
nonisolated struct ScreenTimeSummary: Sendable {
    struct Bucket: Identifiable, Sendable {
        let id: Int
        let label: String
        let start: Date
        let seconds: TimeInterval
    }

    struct AppUsage: Identifiable, Sendable {
        let id: String
        let name: String
        let seconds: TimeInterval
    }

    var totalSeconds: TimeInterval = 0
    var buckets: [Bucket] = []
    var apps: [AppUsage] = []
    var isHourly = true

    var isEmpty: Bool { totalSeconds == 0 }

    var totalText: String { Self.format(totalSeconds) }

    static func format(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder)m" }
        return "\(hours)h \(remainder)m"
    }
}

/// Aggregates total time, per-segment buckets, and the top apps for the Screen Time screen.
nonisolated struct ScreenTimeReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .eGuardScreenTime
    let content: (ScreenTimeSummary) -> ScreenTimeSummaryView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> ScreenTimeSummary {
        var summary = ScreenTimeSummary()
        var bucketSeconds: [Date: TimeInterval] = [:]
        var appSeconds: [String: (name: String, seconds: TimeInterval)] = [:]
        var isHourly = true

        for await device in data {
            if case .daily = device.segmentInterval { isHourly = false }
            if case .weekly = device.segmentInterval { isHourly = false }
            for await segment in device.activitySegments {
                summary.totalSeconds += segment.totalActivityDuration
                bucketSeconds[segment.dateInterval.start, default: 0] += segment.totalActivityDuration
                for await category in segment.categories {
                    for await application in category.applications {
                        let key = application.application.bundleIdentifier
                            ?? application.application.localizedDisplayName
                            ?? UUID().uuidString
                        let name = application.application.localizedDisplayName ?? "App"
                        let existing = appSeconds[key]?.seconds ?? 0
                        appSeconds[key] = (name, existing + application.totalActivityDuration)
                    }
                }
            }
        }

        summary.isHourly = isHourly
        let formatter = Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated))
        summary.buckets = bucketSeconds.keys.sorted().enumerated().map { index, start in
            ScreenTimeSummary.Bucket(
                id: index,
                label: isHourly ? start.formatted(formatter) : start.formatted(.dateTime.weekday(.abbreviated)),
                start: start,
                seconds: bucketSeconds[start] ?? 0
            )
        }
        summary.apps = appSeconds
            .map { ScreenTimeSummary.AppUsage(id: $0.key, name: $0.value.name, seconds: $0.value.seconds) }
            .sorted { $0.seconds > $1.seconds }
            .prefix(6)
            .map { $0 }
        return summary
    }
}
