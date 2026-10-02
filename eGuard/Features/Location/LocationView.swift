import MapKit
import SwiftUI

/// 14 Location, from `GET /children/{id}/location`. Sharing is a protection (`LOCATION`), so the
/// toggle routes to the protection editor.
struct LocationView: View {
    let childId: String

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var state: LoadState<LocationResponse> = .loading
    @State private var position: MapCameraPosition = .automatic
    @State private var isShowingAllVisits = false

    var body: some View {
        EGuardScreen {
            switch state {
            case .loading:
                LoadingCard()
            case .failed(let message):
                if isPlanLocked {
                    EGuardCard {
                        EmptyStateView(symbolName: "lock.fill", title: "Not on your plan", message: message, tint: EGuardColors.neutral)
                    }
                } else {
                    ErrorCard(message: message) { Task { await loadLocation() } }
                }
            case .loaded(let response):
                sharingCard(response)
                switch response.locationState {
                case .located, .waiting:
                    mapCard(response)
                    visitsCard(response)
                case .noDevices:
                    EGuardCard {
                        EmptyStateView(symbolName: "iphone.slash", title: "No devices yet", message: "Pair a device to see where it is.", tint: EGuardColors.neutral)
                    }
                case .sharingOff, .planRequired:
                    EGuardCard {
                        EmptyStateView(
                            symbolName: "location.slash",
                            title: "Location sharing is off",
                            message: "Turn on the Location protection to see where the device is. On iPhone this is a guided step in Settings.",
                            tint: EGuardColors.success
                        )
                    }
                }
            }
        } actions: {
            if !isPlanLocked {
                Button(state.value?.sharing == true ? "Change Location Sharing" : "Turn On Location Sharing") {
                    router.push(.protectionEditor(childId: childId, key: "LOCATION"))
                }
                .buttonStyle(.eGuardPrimary)
                .accessibilityIdentifier("location.toggle")
            }
        }
        .navigationTitle("Location")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadLocation() }
        .refreshable { await loadLocation() }
        .sheet(isPresented: $isShowingAllVisits) {
            VisitsHistoryView(childId: childId)
        }
    }

    @State private var isPlanLocked = false

    private func loadLocation() async {
        if state.value == nil { state = .loading }
        isPlanLocked = false
        do {
            state = .loaded(try await model.api.location(childId: childId))
        } catch let error as APIError where error.code == "plan_required" {
            isPlanLocked = true
            state = .failed(error.localizedDescription)
        } catch {
            state = .failed(error.localizedDescription)
        }
        if let current = state.value?.current {
            let span = max(current.accuracyM ?? 0, 300) * 4
            position = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: current.lat, longitude: current.lng), latitudinalMeters: span, longitudinalMeters: span))
        }
    }

    private func sharingCard(_ response: LocationResponse) -> some View {
        EGuardCard {
            HStack(spacing: EGuardSpacing.sm) {
                IconTile(symbolName: response.sharing ? "checkmark" : "location.slash", tint: response.sharing ? EGuardColors.success : EGuardColors.neutral, filled: response.sharing)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Location sharing").font(EGuardTypography.label)
                    Text(response.locationState.title)
                        .font(EGuardTypography.caption)
                        .foregroundStyle(response.sharing ? EGuardColors.success : EGuardColors.textSecondary)
                }
                Spacer()
                ForEach(response.devices) { device in
                    Image(systemName: device.hasLocation ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                        .foregroundStyle(device.hasLocation ? EGuardColors.success : EGuardColors.neutral)
                        .accessibilityLabel("\(device.name) \(device.hasLocation ? "sharing" : "not sharing")")
                }
            }
        }
    }

    private func mapCard(_ response: LocationResponse) -> some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
            Map(position: $position) {
                if let current = response.current {
                    let coordinate = CLLocationCoordinate2D(latitude: current.lat, longitude: current.lng)
                    let tint = current.isFresh ? EGuardColors.primary : EGuardColors.neutral
                    Annotation(current.deviceName, coordinate: coordinate) {
                        Image(systemName: "figure.child.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white, tint)
                    }
                    // An approximate fix (over 200 m) draws its accuracy circle so it isn't read as exact.
                    MapCircle(center: coordinate, radius: current.accuracyM ?? 250)
                        .foregroundStyle(tint.opacity(current.isApproximate ? 0.2 : 0.12))
                        .stroke(tint.opacity(0.4), lineWidth: 1)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 240)
            .clipShape(EGuardShapes.card)
            .overlay(alignment: .center) {
                if response.current == nil {
                    Text("Waiting for the first location…")
                        .font(EGuardTypography.caption)
                        .padding(EGuardSpacing.sm)
                        .background(.regularMaterial, in: EGuardShapes.button)
                }
            }
            .accessibilityLabel("Map of the device's current location")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: EGuardSpacing.xs) {
                    Text(response.current?.placeLabel.map { "Near \($0)" } ?? "Locating…")
                        .font(EGuardTypography.label)
                    if let current = response.current, current.isApproximate {
                        StatusPill(text: "Approximate", tint: EGuardColors.warning)
                    }
                    if let current = response.current, current.isFresh {
                        StatusPill(text: "Live", tint: EGuardColors.success)
                    }
                }
                Text(response.current?.freshnessLabel ?? "No location yet")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
        }
    }

    private func visitsCard(_ response: LocationResponse) -> some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
            SectionHeader(title: "Today", actionTitle: response.history.enabled ? "View All" : nil) { isShowingAllVisits = true }
            EGuardCard {
                if !response.history.enabled {
                    Label("Location history is off", systemImage: "clock.arrow.circlepath")
                        .font(EGuardTypography.headline)
                    Text("The family admin can turn it on under Settings › Privacy to keep a list of places the device visited.")
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.textSecondary)
                    if model.user?.isAdmin == true {
                        Button("Open Privacy Settings") { router.push(.privacy) }
                            .buttonStyle(.eGuardSecondary)
                    }
                } else if response.history.visits.isEmpty {
                    Text("No places recorded yet today.")
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.textSecondary)
                } else {
                    ForEach(response.history.visits) { visit in
                        VisitRow(visit: visit)
                        if visit.id != response.history.visits.last?.id { Divider() }
                    }
                }
            }
        }
    }
}

struct VisitRow: View {
    let visit: Visit

    var body: some View {
        HStack(spacing: EGuardSpacing.sm) {
            IconTile(symbolName: "mappin.circle.fill", tint: EGuardColors.success)
            VStack(alignment: .leading, spacing: 2) {
                Text(visit.placeLabel).font(EGuardTypography.label)
                Text(visit.deviceName).font(EGuardTypography.caption).foregroundStyle(EGuardColors.textSecondary)
            }
            Spacer()
            Text(visit.timeLabel)
                .font(EGuardTypography.caption)
                .foregroundStyle(EGuardColors.textSecondary)
        }
        .padding(.vertical, EGuardSpacing.xxs)
    }
}

/// "View All": every visit kept, grouped by day, from `GET /children/{id}/location/visits`.
struct VisitsHistoryView: View {
    let childId: String

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var visits: [Visit] = []
    @State private var nextBefore: Date?
    @State private var enabled = true
    @State private var retentionDays: Int?
    @State private var error: String?
    @State private var isLoading = true

    private var groups: [(DayGroup, [Visit])] {
        var order: [DayGroup] = []
        var buckets: [DayGroup: [Visit]] = [:]
        for visit in visits {
            if buckets[visit.day] == nil { order.append(visit.day) }
            buckets[visit.day, default: []].append(visit)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            EGuardScreen {
                if isLoading {
                    LoadingCard()
                } else if let error {
                    ErrorCard(message: error) { Task { await loadPage(reset: true) } }
                } else if !enabled {
                    EmptyStateView(symbolName: "clock.arrow.circlepath", title: "Location history is off", message: "Turn it on under Settings › Privacy.")
                } else if visits.isEmpty {
                    EmptyStateView(symbolName: "mappin.slash", title: "No visits yet", message: "Places appear here as the device moves around.")
                } else {
                    ForEach(groups, id: \.0.key) { day, dayVisits in
                        VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
                            SectionHeader(title: day.label)
                            EGuardCard {
                                ForEach(dayVisits) { visit in
                                    VisitRow(visit: visit)
                                    if visit.id != dayVisits.last?.id { Divider() }
                                }
                            }
                        }
                    }
                    if nextBefore != nil {
                        Button("Load more") { Task { await loadPage(reset: false) } }
                            .buttonStyle(.eGuardSecondary)
                    }
                    if let retentionDays {
                        Text("Visits are kept for \(retentionDays) days.")
                            .font(EGuardTypography.caption)
                            .foregroundStyle(EGuardColors.textSecondary)
                    }
                }
            } actions: {
                Button("Done") { dismiss() }
                    .buttonStyle(.eGuardSecondary)
            }
            .navigationTitle("All visits")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadPage(reset: true) }
        }
    }

    private func loadPage(reset: Bool) async {
        isLoading = reset
        do {
            let page = try await model.api.visits(childId: childId, before: reset ? nil : nextBefore)
            enabled = page.enabled
            retentionDays = page.retentionDays
            visits = reset ? page.visits : visits + page.visits
            nextBefore = page.nextBefore
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        LocationView(childId: "child_1")
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
