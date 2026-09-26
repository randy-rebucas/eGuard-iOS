import SwiftUI

/// A compact duration label styled like the eGuard dashboard values.
struct TodayActivityView: View {
    let summary: String

    var body: some View {
        Text(summary)
            .font(.system(.subheadline, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .accessibilityLabel("Activity today: \(summary)")
    }
}

#Preview {
    TodayActivityView(summary: "2h 14m")
}
