import DeviceActivity
import ExtensionKit
import SwiftUI

/// Renders privacy-preserving activity summaries for the eGuard dashboard.
/// The extension runs in Apple's sandbox and cannot send data anywhere.
@main
struct eGuardActivityReport: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TodayActivityReport { summary in
            TodayActivityView(summary: summary)
        }
    }
}
