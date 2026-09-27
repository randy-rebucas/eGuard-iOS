import Foundation

/// A place the child's device was seen while location sharing was on.
nonisolated struct LocationVisit: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let date: Date

    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double, date: Date = .now) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.date = date
    }

    /// Whether this visit is close enough to be the same place.
    func isNear(latitude: Double, longitude: Double) -> Bool {
        abs(self.latitude - latitude) < 0.002 && abs(self.longitude - longitude) < 0.002
    }
}

/// Parent-adjustable preferences that are not protection settings.
nonisolated struct AppPreferences: Codable, Equatable, Sendable {
    var isLocationSharingEnabled = false
    var lastKnownPlace: String?
    var lastLocationUpdate: Date?
    var visits: [LocationVisit] = []
    var protectionAlertsEnabled = true
    var appAlertsEnabled = true
    var weeklySummaryEnabled = false
    var hasSeenSplash = false

    static let maximumVisits = 30

    /// Records a visit, replacing a same-place visit from the same day.
    mutating func recordVisit(_ visit: LocationVisit, calendar: Calendar = .current) {
        if let index = visits.firstIndex(where: {
            $0.isNear(latitude: visit.latitude, longitude: visit.longitude) && calendar.isDate($0.date, inSameDayAs: visit.date)
        }) {
            visits[index] = visit
        } else {
            visits.insert(visit, at: 0)
        }
        visits.sort { $0.date > $1.date }
        if visits.count > Self.maximumVisits {
            visits.removeLast(visits.count - Self.maximumVisits)
        }
        lastKnownPlace = visit.name
        lastLocationUpdate = visit.date
    }

    func visits(on day: Date, calendar: Calendar = .current) -> [LocationVisit] {
        visits.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }
}
