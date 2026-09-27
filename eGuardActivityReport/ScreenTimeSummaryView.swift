import Charts
import SwiftUI

/// The Screen Time screen body: usage ring, activity bars, and top apps.
/// Styled to match the eGuard design tokens without importing the app module.
struct ScreenTimeSummaryView: View {
    let summary: ScreenTimeSummary

    private let primary = Color(red: 0x2F / 255, green: 0x6F / 255, blue: 0xED / 255)
    private let surface = Color(.secondarySystemGroupedBackground)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ring
            if !summary.buckets.isEmpty {
                chart
            }
            topApps
        }
    }

    private var ring: some View {
        let ratio = min(summary.totalSeconds / (3 * 3600), 1)
        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(primary.opacity(0.15), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: ratio)
                    .stroke(primary, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(summary.totalText)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    Text(summary.isHourly ? "today" : "in this period")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 160, height: 160)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Screen time \(summary.totalText)")
        }
        .frame(maxWidth: .infinity)
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summary.isHourly ? "Activity by hour" : "Activity by day")
                .font(.system(.subheadline, weight: .semibold))
            Chart(summary.buckets) { bucket in
                BarMark(
                    x: .value("Time", bucket.label),
                    y: .value("Minutes", bucket.seconds / 60)
                )
                .foregroundStyle(primary.gradient)
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: summary.isHourly ? 5 : 7)) { _ in
                    AxisValueLabel().font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) {
                            Text(minutes >= 60 ? "\(Int(minutes / 60))h" : "\(Int(minutes))m")
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 150)
        }
        .padding(16)
        .background(surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var topApps: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Usage")
                .font(.system(.headline, design: .rounded, weight: .semibold))
            if summary.apps.isEmpty {
                Text(summary.isEmpty ? "No activity recorded yet." : "No per-app details available.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                let maxSeconds = summary.apps.first?.seconds ?? 1
                ForEach(summary.apps) { app in
                    HStack(spacing: 12) {
                        Text(String(app.name.prefix(1)).uppercased())
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(primary)
                            .frame(width: 32, height: 32)
                            .background(primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text(app.name)
                            .font(.system(.subheadline, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        ProgressView(value: app.seconds, total: max(maxSeconds, 1))
                            .tint(primary)
                            .frame(width: 70)
                        Text(ScreenTimeSummary.format(app.seconds))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(16)
        .background(surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    ScreenTimeSummaryView(summary: ScreenTimeSummary(
        totalSeconds: 8040,
        buckets: (0..<12).map { ScreenTimeSummary.Bucket(id: $0, label: "\($0 + 7)", start: .now, seconds: Double($0 % 4) * 900) },
        apps: [
            .init(id: "a", name: "YouTube", seconds: 3240),
            .init(id: "b", name: "Roblox", seconds: 2520),
            .init(id: "c", name: "Chrome", seconds: 1680),
        ]
    ))
    .padding()
}
