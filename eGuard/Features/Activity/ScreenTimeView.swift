import Charts
import SwiftUI

/// 12 Screen Time, from `GET /children/{id}/screen-time?period=`.
struct ScreenTimeView: View {
    let childId: String

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var period: ScreenTimePeriod = .today
    @State private var state: LoadState<ScreenTimeReport> = .loading
    /// nil until loaded, or when it couldn't be (the card is then hidden; the report still shows).
    @State private var extraTime: ExtraTime?
    @State private var extraTimeBusy = false
    @State private var extraTimeMessage: String?
    @State private var extraTimeError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EGuardSpacing.lg) {
                // "More time requested" alerts open here ("Review request"), so the answer comes first
                if let extraTime { extraTimeCard(extraTime) }

                // A lock on tabs the plan doesn't include, as the web's Reports page does
                PillSegmentedControl(options: ScreenTimePeriod.allCases, selection: $period) { p in
                    locked?.periods.contains(p.rawValue) == true ? "🔒 \(p.title)" : p.title
                }

                switch state {
                case .loading:
                    LoadingCard()
                case .failed(let message):
                    if isPlanLocked {
                        // 30-day reports need the plan's advanced reports. Neutral wording: no upgrade prompt on iOS.
                        EGuardCard {
                            EmptyStateView(symbolName: "lock.fill", title: "Not included in your plan", message: message, tint: EGuardColors.neutral)
                        }
                    } else {
                        ErrorCard(message: message) { Task { await loadReport() } }
                    }
                case .loaded(let report) where report.deviceCount == 0:
                    // Nothing sends screen time yet: an empty ring would read as "used nothing"
                    EGuardCard {
                        EmptyStateView(symbolName: "iphone", title: "No phone or tablet yet", message: "Pair a phone or tablet to see screen time. Browsers don't send it.", tint: EGuardColors.neutral)
                    }
                case .loaded(let report):
                    if let range = report.rangeLabel {
                        Text(range)
                            .font(EGuardTypography.caption)
                            .foregroundStyle(EGuardColors.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
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
        .task { await loadExtraTime() }
        .refreshable {
            await loadExtraTime()
            await loadReport()
        }
    }

    private func loadExtraTime() async {
        if let value = try? await model.api.extraTime(childId: childId) { extraTime = value }
    }

    private func extraTimeCard(_ extra: ExtraTime) -> some View {
        let running = extra.isRunning()
        return EGuardCard {
            Text("Extra time").font(EGuardTypography.headline)
            if let request = extra.request {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.body)
                        Text(request.askedAt.relativeDescription())
                            .font(EGuardTypography.caption)
                            .foregroundStyle(EGuardColors.textSecondary)
                    }
                } icon: {
                    Image(systemName: "hourglass")
                }
                .font(EGuardTypography.callout)
                .foregroundStyle(EGuardColors.warning)
                .accessibilityIdentifier("screenTime.timeRequest")
            }
            if running, let until = extra.until {
                Text("Extra time until \(until.formatted(date: .omitted, time: .shortened)).")
                    .font(EGuardTypography.callout)
            } else if extra.request == nil {
                Text("Lets your child keep using apps past a limit or bedtime for a while. Blocked apps stay blocked.")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
            HStack(spacing: EGuardSpacing.xs) {
                ForEach(extra.choices, id: \.self) { minutes in
                    Button("+\(minutes) min") { Task { await grant(minutes) } }
                        .buttonStyle(.eGuardSecondary)
                        .accessibilityIdentifier("screenTime.give\(minutes)")
                }
            }
            .disabled(extraTimeBusy)
            if running || extra.request != nil {
                Button(running ? "End now" : "Not now") { Task { await endExtraTime(wasRunning: running) } }
                    .buttonStyle(.eGuardSecondary)
                    .disabled(extraTimeBusy)
                    .accessibilityIdentifier("screenTime.endExtraTime")
            }
            if let extraTimeMessage {
                Text(extraTimeMessage)
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
            InlineError(message: extraTimeError)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screenTime.extraTime")
    }

    private func grant(_ minutes: Int) async {
        extraTimeBusy = true
        extraTimeError = nil
        defer { extraTimeBusy = false }
        do {
            let result = try await model.api.grantExtraTime(childId: childId, minutes: minutes)
            // Less than chosen when the 4-hour cap applies: say what was given
            let added = result.addedMinutes ?? minutes
            extraTimeMessage = added == 0
                ? "Extra time already runs 4 hours ahead, the most eGuard gives at once."
                : "\(added) more minutes\(added < minutes ? " (extra time runs at most 4 hours ahead)" : ""). The device picks it up within a few minutes."
            await loadExtraTime()
        } catch {
            extraTimeError = error.localizedDescription
        }
    }

    private func endExtraTime(wasRunning: Bool) async {
        extraTimeBusy = true
        extraTimeError = nil
        defer { extraTimeBusy = false }
        do {
            try await model.api.endExtraTime(childId: childId)
            extraTimeMessage = wasRunning ? "Extra time ended." : "Your child was told not now."
            await loadExtraTime()
        } catch {
            extraTimeError = error.localizedDescription
        }
    }

    @State private var isPlanLocked = false
    /// From the last report: tabs the plan doesn't include. Choosing one shows the lock without a request.
    @State private var locked: ScreenTimeLock?

    private func loadReport() async {
        if let locked, locked.periods.contains(period.rawValue) {
            isPlanLocked = true
            // The server's lock names the plan to buy: neutral wording on iOS, as for any 403 plan_required
            state = .failed(APIClient.storeSafeMessage(locked.message, status: 403, code: "plan_required"))
            return
        }
        state = .loading
        isPlanLocked = false
        do {
            let report = try await model.api.screenTime(childId: childId, period: period)
            // Every report says what's locked (nil after an upgrade)
            locked = report.locked
            state = .loaded(report)
        } catch let error as APIError where error.code == "plan_required" {
            isPlanLocked = true
            state = .failed(error.localizedDescription)
        } catch {
            state = .failed(error.localizedDescription)
        }
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
                    // 7/30 days: the average of complete days, against the weekday limit
                    Text(period == .today
                         ? (limit > 0 ? "of \(ProtectionConfigFormatter.duration(limit))" : "today")
                         : (limit > 0 ? "a day on average · limit \(ProtectionConfigFormatter.duration(limit))" : "a day on average"))
                        .multilineTextAlignment(.center)
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
            if report.hiddenAppCount > 0 {
                Text("\(report.hiddenAppCount) more app\(report.hiddenAppCount == 1 ? "" : "s") aren't named on your plan and are counted in Others.")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
            let top = report.apps.first?.minutes ?? 1
            ForEach(report.apps) { app in
                HStack(spacing: EGuardSpacing.sm) {
                    IconTile(symbolName: "app.fill", tint: app.approval == .blocked || app.approval == .filtered ? EGuardColors.danger : EGuardColors.primary, size: 32)
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
        guard let date = ScreenTimeReport.day(iso) else { return iso }
        var style = period == .week ? Date.FormatStyle.dateTime.weekday(.abbreviated) : Date.FormatStyle.dateTime.day()
        style.timeZone = TimeZone(identifier: "UTC")!
        return date.formatted(style)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ScreenTimeView(childId: "child_1")
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
#endif
