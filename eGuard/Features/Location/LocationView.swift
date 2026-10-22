import MapKit
import SwiftUI

/// 14 Location, from `GET /children/{id}/location`. Sharing is a protection (`LOCATION`), so the
/// toggle routes to the protection editor. Saved places (`GET /places`) draw as circles and name visits.
struct LocationView: View {
    let childId: String

    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var state: LoadState<LocationResponse> = .loading
    @State private var places: [SavedPlace] = []
    @State private var position: MapCameraPosition = .automatic
    @State private var isShowingAllVisits = false
    @State private var placeEditor: PlaceEditorSheet.Mode?
    @State private var placeToRemove: SavedPlace?
    @State private var placesError: String?
    @State private var isPlanLocked = false
    /// Set once the server refused to add or change a place (`403 plan_required`): Free lists and removes only.
    @State private var placesPlanLocked = false

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
                placesCard
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
        .sheet(item: $placeEditor) { mode in
            PlaceEditorSheet(mode: mode) {
                Task { await loadLocation() }
            } onPlanLocked: {
                placesPlanLocked = true
            }
        }
        .confirmationDialog("Remove \(placeToRemove?.name ?? "this place")?", isPresented: Binding(get: { placeToRemove != nil }, set: { if !$0 { placeToRemove = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await removePlace() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Visits there lose its name unless another saved place covers them.")
        }
    }

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
        // Places list on every plan, so a family that moved to Free can still remove them.
        places = (try? await model.api.places()) ?? places
        if let current = state.value?.current {
            let span = max(current.accuracyM ?? 0, 300) * 4
            position = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: current.lat, longitude: current.lng), latitudinalMeters: span, longitudinalMeters: span))
        }
    }

    private func removePlace() async {
        guard let place = placeToRemove else { return }
        do {
            try await model.api.deletePlace(id: place.id)
            placesError = nil
            await loadLocation()
        } catch {
            placesError = error.localizedDescription
        }
        placeToRemove = nil
    }

    private func sharingCard(_ response: LocationResponse) -> some View {
        EGuardCard {
            HStack(spacing: EGuardSpacing.sm) {
                IconTile(symbolName: response.sharing ? "checkmark" : "location.slash", tint: response.sharing ? EGuardColors.success : EGuardColors.neutral, filled: response.sharing)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Location sharing").font(EGuardTypography.label)
                    // Names the device eGuard is waiting on when no device has reported whether it shares.
                    Text(response.stateDescription)
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
                // Saved places: a circle of `radiusM` with its name.
                ForEach(places) { place in
                    let center = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng)
                    MapCircle(center: center, radius: Double(place.radiusM))
                        .foregroundStyle(EGuardColors.tilePurple.opacity(0.12))
                        .stroke(EGuardColors.tilePurple.opacity(0.5), lineWidth: 1)
                    Annotation(place.name, coordinate: center) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.white, EGuardColors.tilePurple)
                    }
                }
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

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: EGuardSpacing.xs) {
                        Text(response.current?.placeLabel.map { "Near \($0)" } ?? (response.current == nil ? "Locating…" : "Current location"))
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
                Spacer()
                if let current = response.current, current.placeId == nil, canAddPlaces {
                    Button("Name this place") { placeEditor = .create(lat: current.lat, lng: current.lng, suggestedName: nil) }
                        .font(EGuardTypography.label)
                        .foregroundStyle(EGuardColors.primary)
                        .accessibilityIdentifier("location.namePlace")
                }
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
                            .contextMenu {
                                if visit.canBeNamed, canAddPlaces {
                                    Button("Name this place", systemImage: "mappin.and.ellipse") {
                                        placeEditor = .create(lat: visit.lat, lng: visit.lng, suggestedName: nil)
                                    }
                                }
                            }
                        if visit.id != response.history.visits.last?.id { Divider() }
                    }
                    if response.history.more == true {
                        Button("More visits from today and yesterday") { isShowingAllVisits = true }
                            .font(EGuardTypography.label)
                            .foregroundStyle(EGuardColors.primary)
                    }
                }
            }
        }
    }

    /// Adding and changing places needs eGuard Plus or above; the API also refuses a 31st place.
    private var canAddPlaces: Bool { !placesPlanLocked && places.count < SavedPlace.maximumCount }

    /// Home, School and other places the parents named. Any parent can manage them.
    private var placesCard: some View {
        VStack(alignment: .leading, spacing: EGuardSpacing.sm) {
            SectionHeader(title: "Saved places", actionTitle: canAddPlaces ? "Add a place" : nil) {
                // Start the pin at the child's location, else the first place, else Manila.
                let start = state.value?.current.map { ($0.lat, $0.lng) } ?? places.first.map { ($0.lat, $0.lng) } ?? (14.5995, 120.9842)
                placeEditor = .create(lat: start.0, lng: start.1, suggestedName: nil)
            }
            EGuardCard {
                if places.isEmpty {
                    Text("Name Home and School so the map and visits say where your child is. A place can be anywhere, so you can set up School before the first day.")
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
                ForEach(places) { place in
                    HStack(spacing: EGuardSpacing.sm) {
                        IconTile(symbolName: "mappin.circle.fill", tint: EGuardColors.tilePurple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name).font(EGuardTypography.label)
                            Text(placeDetail(place))
                                .font(EGuardTypography.caption)
                                .foregroundStyle(EGuardColors.textSecondary)
                        }
                        Spacer()
                        Menu {
                            if canAddPlaces {
                                Button("Edit", systemImage: "pencil") { placeEditor = .edit(place) }
                            }
                            Button("Remove", systemImage: "trash", role: .destructive) { placeToRemove = place }
                        } label: {
                            Image(systemName: "ellipsis.circle").foregroundStyle(EGuardColors.neutral)
                        }
                        .accessibilityLabel("Options for \(place.name)")
                    }
                    .padding(.vertical, EGuardSpacing.xxs)
                    .accessibilityIdentifier("location.place.\(place.id)")
                    if place.id != places.last?.id { Divider() }
                }
                if placesPlanLocked {
                    Text(APIClient.storeSafeMessage("Saved places aren't included in your plan. Places saved before can still be removed.", status: 403))
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
                InlineError(message: placesError)
            }
        }
    }

    private func placeDetail(_ place: SavedPlace) -> String {
        var parts = ["\(place.radiusM) m around"]
        if place.arrives && place.leaves {
            parts.append("arrive and leave alerts")
        } else if place.arrives {
            parts.append("arrival alerts")
        } else if place.leaves {
            parts.append("leaving alerts")
        }
        return parts.joined(separator: " · ")
    }
}

/// One visit: a stay at a place, or a fix taken while passing by. Numbered on a day's route.
struct VisitRow: View {
    let visit: Visit
    var number: Int? = nil

    var body: some View {
        HStack(spacing: EGuardSpacing.sm) {
            if visit.isPassingBy {
                // Passing-by fixes are small dots, never counted as places visited.
                Circle()
                    .fill(EGuardColors.neutral)
                    .frame(width: 10, height: 10)
                    .frame(width: 40, height: 40)
            } else if let number {
                Text("\(number)")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(EGuardColors.success, in: Circle())
            } else {
                IconTile(symbolName: "mappin.circle.fill", tint: EGuardColors.success)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(visit.displayLabel)
                    .font(EGuardTypography.label)
                    .foregroundStyle(visit.isPassingBy ? EGuardColors.textSecondary : EGuardColors.textPrimary)
                Text(visit.spanLabel ?? visit.deviceName)
                    .font(EGuardTypography.caption)
                    .foregroundStyle(EGuardColors.textSecondary)
            }
            Spacer()
            Text(visit.timeLabel)
                .font(EGuardTypography.caption)
                .foregroundStyle(EGuardColors.textSecondary)
        }
        .padding(.vertical, EGuardSpacing.xxs)
        .accessibilityElement(children: .combine)
    }
}

/// "View All": every visit kept, grouped by day, from `GET /children/{id}/location/visits`;
/// or one day's route (`?day=`), oldest first with the stays numbered.
struct VisitsHistoryView: View {
    let childId: String

    /// Pages of every visit, or one day drawn as a route.
    private enum Mode: String, CaseIterable, Hashable {
        case all, day
        var title: String { self == .all ? "All visits" : "By day" }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .all
    @State private var day = Date.now
    @State private var visits: [Visit] = []
    @State private var nextBefore: Date?
    @State private var enabled = true
    @State private var retentionDays: Int?
    @State private var thinned = false
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

    /// The route's stays get numbers in order; passing-by fixes stay as dots.
    private var numberedRoute: [(Visit, Int?)] {
        var next = 1
        return visits.map { visit in
            guard !visit.isPassingBy else { return (visit, nil) }
            defer { next += 1 }
            return (visit, next)
        }
    }

    var body: some View {
        NavigationStack {
            EGuardScreen {
                PillSegmentedControl(options: Mode.allCases, selection: $mode) { $0.title }
                if mode == .day {
                    DatePicker("Day", selection: $day, in: ...Date.now, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .font(EGuardTypography.label)
                }

                if isLoading {
                    LoadingCard()
                } else if let error {
                    ErrorCard(message: error) { Task { await loadPage(reset: true) } }
                } else if !enabled {
                    EmptyStateView(symbolName: "clock.arrow.circlepath", title: "Location history is off", message: "Turn it on under Settings › Privacy.")
                } else if visits.isEmpty {
                    EmptyStateView(symbolName: "mappin.slash", title: mode == .day ? "Nowhere that day" : "No visits yet", message: mode == .day ? "No visits were recorded on this day." : "Places appear here as the device moves around.")
                } else if mode == .day {
                    EGuardCard {
                        ForEach(numberedRoute, id: \.0.id) { visit, number in
                            VisitRow(visit: visit, number: number)
                            if visit.id != visits.last?.id { Divider() }
                        }
                    }
                    if thinned {
                        Text("Some spots passed on the way are left out.")
                            .font(EGuardTypography.caption)
                            .foregroundStyle(EGuardColors.textSecondary)
                    }
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
            .task(id: mode) { await loadPage(reset: true) }
            .onChange(of: day) { _, _ in
                if mode == .day { Task { await loadPage(reset: true) } }
            }
        }
    }

    /// Calendar day as the API wants it, `YYYY-MM-DD`.
    private var dayKey: String { day.formatted(.iso8601.year().month().day()) }

    private func loadPage(reset: Bool) async {
        isLoading = reset
        do {
            let page: VisitsPage
            switch mode {
            case .all: page = try await model.api.visits(childId: childId, before: reset ? nil : nextBefore)
            case .day: page = try await model.api.visits(childId: childId, day: dayKey)
            }
            enabled = page.enabled
            retentionDays = page.retentionDays
            thinned = page.isThinned
            visits = reset ? page.visits : visits + page.visits
            nextBefore = page.nextBefore
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

/// Names a place (Home, School) at a tapped spot or a visit, or edits a saved one: `POST` / `PATCH /places`.
struct PlaceEditorSheet: View {
    enum Mode: Identifiable {
        case create(lat: Double, lng: Double, suggestedName: String?)
        case edit(SavedPlace)

        var id: String {
            switch self {
            case .create(let lat, let lng, _): "new-\(lat)-\(lng)"
            case .edit(let place): place.id
            }
        }
    }

    let mode: Mode
    let onSaved: () -> Void
    var onPlanLocked: (() -> Void)? = nil

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var radius: Int
    @State private var notifyArrive: Bool
    @State private var notifyLeave: Bool
    @State private var coordinate: CLLocationCoordinate2D
    @State private var latitudeText: String
    @State private var longitudeText: String
    @State private var position: MapCameraPosition
    @State private var error: String?
    @State private var isSaving = false

    init(mode: Mode, onSaved: @escaping () -> Void, onPlanLocked: (() -> Void)? = nil) {
        self.mode = mode
        self.onSaved = onSaved
        self.onPlanLocked = onPlanLocked
        let place: SavedPlace?
        let lat: Double
        let lng: Double
        switch mode {
        case .create(let newLat, let newLng, let suggested):
            place = nil
            lat = newLat
            lng = newLng
            _name = State(initialValue: suggested ?? "")
        case .edit(let saved):
            place = saved
            lat = saved.lat
            lng = saved.lng
            _name = State(initialValue: saved.name)
        }
        _radius = State(initialValue: place?.radiusM ?? SavedPlace.defaultRadius)
        _notifyArrive = State(initialValue: place?.arrives ?? false)
        _notifyLeave = State(initialValue: place?.leaves ?? false)
        _coordinate = State(initialValue: CLLocationCoordinate2D(latitude: lat, longitude: lng))
        _latitudeText = State(initialValue: String(format: "%.5f", lat))
        _longitudeText = State(initialValue: String(format: "%.5f", lng))
        _position = State(initialValue: .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lng), latitudinalMeters: 1200, longitudinalMeters: 1200)))
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            EGuardScreen {
                ScreenHeader(
                    title: isEditing ? "Edit place" : "Name this place",
                    subtitle: isEditing
                        ? "Renaming or resizing a place relabels the visits already kept."
                        : "Tap the map to move the pin. A location or visit inside the circle is labelled with this name."
                )

                if !isEditing {
                    MapReader { proxy in
                        Map(position: $position) {
                            MapCircle(center: coordinate, radius: Double(radius))
                                .foregroundStyle(EGuardColors.tilePurple.opacity(0.15))
                                .stroke(EGuardColors.tilePurple.opacity(0.6), lineWidth: 1)
                            Annotation(name.isEmpty ? "New place" : name, coordinate: coordinate) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(.white, EGuardColors.tilePurple)
                            }
                        }
                        .mapStyle(.standard(pointsOfInterest: .excludingAll))
                        .onTapGesture { point in
                            if let tapped = proxy.convert(point, from: .local) { setCoordinate(tapped) }
                        }
                    }
                    .frame(height: 220)
                    .clipShape(EGuardShapes.card)
                    .accessibilityLabel("Map to choose where the place is")
                }

                EGuardCard {
                    EGuardTextField(label: "Name", placeholder: "School", text: $name, symbolName: "mappin", autocapitalization: .words)
                    Picker("Size", selection: $radius) {
                        ForEach(SavedPlace.radiusOptions, id: \.self) { Text("\($0) m").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if !isEditing {
                        HStack(spacing: EGuardSpacing.sm) {
                            EGuardTextField(label: "Latitude", placeholder: "14.6507", text: $latitudeText, symbolName: "location", keyboard: .numbersAndPunctuation)
                            EGuardTextField(label: "Longitude", placeholder: "121.0494", text: $longitudeText, symbolName: "location", keyboard: .numbersAndPunctuation)
                        }
                    }
                    Toggle("Tell me when a child arrives", isOn: $notifyArrive).tint(EGuardColors.primary)
                    Toggle("Tell me when a child leaves", isOn: $notifyLeave).tint(EGuardColors.primary)
                    Text("Arrive and leave alerts work even with location history off.")
                        .font(EGuardTypography.caption)
                        .foregroundStyle(EGuardColors.textSecondary)
                }
                InlineError(message: error)
            } actions: {
                Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                    .buttonStyle(.eGuardPrimary)
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("place.save")
                Button("Cancel") { dismiss() }
                    .buttonStyle(.eGuardText)
            }
            .navigationTitle(isEditing ? "Edit place" : "Add a place")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: latitudeText) { _, _ in applyTypedCoordinate() }
            .onChange(of: longitudeText) { _, _ in applyTypedCoordinate() }
        }
    }

    private func setCoordinate(_ new: CLLocationCoordinate2D) {
        coordinate = new
        latitudeText = String(format: "%.5f", new.latitude)
        longitudeText = String(format: "%.5f", new.longitude)
    }

    /// Typed coordinates move the pin once both parse and are in range.
    private func applyTypedCoordinate() {
        guard let lat = Double(latitudeText), let lng = Double(longitudeText), (-90...90).contains(lat), (-180...180).contains(lng) else { return }
        if abs(lat - coordinate.latitude) > 0.000001 || abs(lng - coordinate.longitude) > 0.000001 {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        do {
            switch mode {
            case .create:
                _ = try await model.api.createPlace(NewPlace(name: trimmed, lat: coordinate.latitude, lng: coordinate.longitude, radiusM: radius, notifyArrive: notifyArrive, notifyLeave: notifyLeave))
            case .edit(let place):
                // Only what changed; the API wants at least one field.
                let patch = PlacePatch(
                    name: trimmed == place.name ? nil : trimmed,
                    radiusM: radius == place.radiusM ? nil : radius,
                    notifyArrive: notifyArrive == place.arrives ? nil : notifyArrive,
                    notifyLeave: notifyLeave == place.leaves ? nil : notifyLeave
                )
                if patch == PlacePatch() {
                    dismiss()
                    return
                }
                _ = try await model.api.updatePlace(id: place.id, patch: patch)
            }
            onSaved()
            dismiss()
        } catch let error as APIError where error.code == "plan_required" {
            self.error = APIClient.storeSafeMessage(error.localizedDescription, status: 403)
            onPlanLocked?()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        LocationView(childId: "child_1")
    }
    .environment(AppModel.live())
    .environment(AppRouter())
}
