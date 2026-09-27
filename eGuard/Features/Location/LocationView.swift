import CoreLocation
import MapKit
import SwiftUI

/// 14 Location. Shows where this device is while eGuard is open and location sharing is on.
struct LocationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var service = LocationService()
    @State private var position: MapCameraPosition = .automatic

    private var isSharing: Bool { model.preferences.isLocationSharingEnabled }

    var body: some View {
        EGuardScreen {
            sharingCard

            if isSharing {
                mapCard
                todayCard
            } else {
                EGuardCard {
                    EmptyStateView(
                        symbolName: "location.slash",
                        title: "Location sharing is off",
                        message: "Turn it on to see where \(model.childProfile?.deviceName ?? "this device") is while eGuard is open.",
                        tint: EGuardColors.success
                    )
                }
            }

            EGuardCard {
                Label("Location is read only while eGuard is open and stays on this device. Nothing is uploaded or shared.", systemImage: "lock.shield")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
        } actions: {
            if service.isDenied {
                Button("Open Settings to Allow Location") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.eGuardPrimary)
            }
        }
        .navigationTitle("Location")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            service.onVisit = { visit in model.recordVisit(visit) }
            if isSharing { service.start() }
        }
        .onDisappear { service.stop() }
        .onChange(of: service.currentLocation) { _, location in
            guard let location else { return }
            withAnimation {
                position = .region(MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: 1200,
                    longitudinalMeters: 1200
                ))
            }
        }
    }

    private var sharingCard: some View {
        EGuardCard {
            Toggle(isOn: Binding(
                get: { isSharing },
                set: { enabled in
                    model.setLocationSharing(enabled)
                    if enabled { service.start() } else { service.stop() }
                }
            )) {
                HStack(spacing: EGuardSpacing.sm) {
                    IconTile(symbolName: isSharing ? "checkmark" : "location.slash", tint: isSharing ? EGuardColors.success : EGuardColors.neutral, filled: isSharing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Location sharing")
                            .font(EGuardTypography.label)
                        Text(isSharing ? "Enabled" : "Off")
                            .font(EGuardTypography.caption)
                            .foregroundStyle(isSharing ? EGuardColors.success : EGuardColors.textSecondary)
                    }
                }
            }
            .tint(EGuardColors.success)
            .accessibilityIdentifier("location.toggle")

            if let message = service.errorMessage {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.warning)
            }
        }
    }

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
            Map(position: $position) {
                UserAnnotation()
                if let location = service.currentLocation {
                    MapCircle(center: location.coordinate, radius: 250)
                        .foregroundStyle(EGuardColors.primary.opacity(0.15))
                        .stroke(EGuardColors.primary.opacity(0.4), lineWidth: 1)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 240)
            .clipShape(EGuardShapes.card)
            .overlay(alignment: .center) {
                if service.currentLocation == nil {
                    ProgressView("Finding location…")
                        .padding(EGuardSpacing.sm)
                        .background(.regularMaterial, in: EGuardShapes.button)
                }
            }
            .accessibilityLabel("Map of the device's current location")

            VStack(alignment: .leading, spacing: 2) {
                Text(service.placeName.map { "Near \($0)" } ?? model.preferences.lastKnownPlace.map { "Last seen near \($0)" } ?? "Locating…")
                    .font(EGuardTypography.label)
                Text(model.preferences.lastLocationUpdate.map { "Last updated \($0.relativeDescription())" } ?? "Waiting for the first update")
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
        }
    }

    private var todayCard: some View {
        let visits = model.preferences.visits(on: .now)
        return VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
            SectionHeader(title: "Today")
            EGuardCard {
                if visits.isEmpty {
                    Text("No places recorded yet today.")
                        .font(EGuardTypography.callout)
                        .foregroundStyle(EGuardColors.textSecondary)
                } else {
                    ForEach(visits) { visit in
                        HStack(spacing: EGuardSpacing.sm) {
                            IconTile(symbolName: "mappin.circle.fill", tint: EGuardColors.success)
                            Text(visit.name)
                                .font(EGuardTypography.label)
                            Spacer()
                            Text(visit.date.formatted(date: .omitted, time: .shortened))
                                .font(EGuardTypography.caption)
                                .foregroundStyle(EGuardColors.textSecondary)
                        }
                        .padding(.vertical, EGuardSpacing.xxs)
                        if visit.id != visits.last?.id { Divider() }
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        LocationView()
    }
    .environment(AppModel.preview())
    .environment(AppRouter())
}
