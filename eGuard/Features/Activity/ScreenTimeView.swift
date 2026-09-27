import Charts
import SwiftUI

/// 12 Screen Time, from `GET /children/{id}/screen-time?period=`.
struct ScreenTimeView: View {
    let childId: String

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var period: ScreenTimePeriod = .today
    @State private var state: LoadState<ScreenTimeReport> = .loading

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EGuardSpacing.lg) {
                PillSegmentedControl(options: ScreenTimePeriod.allCases, selection: $period) { $0.title }

                switch state {
                case .loading:
                    LoadingCard()
                case .failed(let message):
                    ErrorCard(message: message) { Task { await loadReport() } }
                case .loaded(let report):
                    ring(report)
                    if let hourly = report.hourly, hourly.contains(where: { $0 > 0 }) {
                        chart(title: "Activity by hour", data: hourly.enumerated().map { (label: hourLabel($0.offset), minutes: $0.element) })
                    } else if report.days.count > 1 {
                        chart(title: "Activity by day", data: report.days.map { (label: dayLabel($0.date), minutes: $0.minutes) })
                    }
                    appsCard(report)
                }
            }
            .padding(EGuardSpacing.md)
        }
        .background(EGuardColors.background)
        .navigationTitle("Screen Time")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: period) { await loadReport() }
    }

    private func loadReport() async {
        state = .loading
        state = await load { try await model.api.screenTime(childId: childId, period: period) }
    }

    private func ring(_ report: ScreenTimeReport) -> some View {
        let limit = report.limitMinutes ?? 0
        let value = period == .today ? report.totalMinutes : report.averageMinutes
        let progress = limit > 0 ? min(Double(value) / Double(limit), 1) : 0
        return EGuardCard {
            RingGauge(progress: progress, tint: progress >= 1 ? EGuardColors.warning : EGuardColors.primary, lineWidth: 14, size: 170) {
                VStack(spacing: 2) {
                    Text(ProtectionConfigFormatter.duration(value))
                        .font(EGuardTypography.metric)
                        .monospacedDigit()
                    Text(limit > 0 ? "of \(ProtectionConfigFormatter.duration(limit))" : (period == .today ? "today" : "per day"))
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("screenTime.total")

            if let change = report.changePercent {
                Label(
                    "\(abs(change))% \(change <= 0 ? "less" : "more") than \(period == .today ? "yesterday" : "the previous period")",
                    systemImage: change <= 0 ? "arrow.down.right" : "arrow.up.right"
                )
                .font(EGuardTypography.caption)
                .foregroundStyle(change <= 0 ? EGuardColors.success : EGuardColors.warning)
                .frame(maxWidth: .infinity)
            }
            if period != .today {
                Text("Total \(ProtectionConfigFormatter.duration(report.totalMinutes)) over \(report.days.count) days")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func chart(title: String, data: [(label: String, minutes: Int)]) -> some View {
        EGuardCard {
            Text(title).font(EGuardTypography.headline)
            Chart(Array(data.enumerated()), id: \.offset) { _, point in
                BarMark(x: .value("Time", point.label), y: .value("Minutes", point.minutes))
                    .foregroundStyle(EGuardColors.primary.gradient)
                    .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in AxisValueLabel().font(.caption2) }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let minutes = value.as(Int.self) {
                            Text(minutes >= 60 ? "\(minutes / 60)h" : "\(minutes)m").font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 160)
        }
    }

    private func appsCard(_ report: ScreenTimeReport) -> some View {
        EGuardCard {
            SectionHeader(title: "App Usage", actionTitle: "Manage") { router.push(.appsManagement(childId: childId)) }
            if report.apps.isEmpty {
                Text("No app activity in this period.")
                    .font(EGuardTypography.callout)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
            let top = report.apps.first?.minutes ?? 1
            ForEach(report.apps) { app in
                HStack(spacing: EGuardSpacing.sm) {
                    IconTile(symbolName: "app.fill", tint: app.approval == .blocked ? EGuardColors.danger : EGuardColors.primary, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(EGuardTypography.label)
                        if let limit = app.dailyLimitMinutes {
                            Text("Limit \(ProtectionConfigFormatter.duration(limit))/day").font(EGuardTypography.caption).foregroundStyle(EGuardColors.textSecondary)
                        }
                    }
                    Spacer()
                    ProgressView(value: Double(app.minutes), total: Double(max(top, 1)))
                        .tint(EGuardColors.primary)
                        .frame(width: 70)
                    Text(ProtectionConfigFormatter.duration(app.minutes))
                        .font(EGuardTypography.caption)
                        .monospacedDigit()
                        .foregroundStyle(EGuardColors.textSecondary)
                        .frame(width: 52, alignment: .trailing)
                }
                .padding(.vertical, EGuardSpacing.xxs)
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)))
    }

    private func dayLabel(_ iso: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: iso) else { return iso }
        return date.formatted(period == .week ? .dateTime.weekday(.abbreviated) : .dateTime.day())
    }
}

#Preview {
    NavigationStack {
        ScreenTimeView(childId: "child_1")
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
