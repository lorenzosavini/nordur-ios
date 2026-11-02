import Foundation

/// Today's leg of the trip, written by the app and read by the "Tappa di oggi"
/// widget (and by the drive Live Activity for the next stop). Everything is
/// computed in the app: the widget only draws it.
struct TripTodaySnapshot: Codable, Equatable {
    struct Alert: Codable, Equatable, Hashable {
        var title: String
        var severity: Int      // Risk raw value
    }

    var stopID: UUID
    /// True when you arrive at the stop today; false when this is the next stop on a later day.
    var isToday: Bool
    /// The travel day (start of the day, Iceland time).
    var day: Date
    var fromName: String?
    var toName: String
    var toLat: Double
    var toLon: Double
    var transport: String
    /// Road distance estimate (straight line × 1.3 by car or bus), as in the trip screen.
    var km: Double?
    var driveMinutes: Int?
    /// Latest departure to arrive with daylight (30 min margin), by car or bus.
    var departBy: Date?
    /// The drive is longer than the daylight: leave at first light.
    var departAtDawn: Bool
    var sunrise: Date?
    var sunset: Date?
    /// Most relevant first: IMO warnings, roads, wind at the destination.
    var alerts: [Alert]

    var destination: Coordinate { Coordinate(lat: toLat, lon: toLon) }
    var byRoad: Bool { transport == Transport.car.rawValue || transport == Transport.bus.rawValue }
    var deepLink: URL { URL(string: "nordur://stop/\(stopID.uuidString)")! }

    /// Departure that keeps the arrival in daylight (sunrise at the start, sunset at the end).
    static func departure(sunrise: Date?, sunset: Date?, driveMinutes: Int) -> (date: Date?, atDawn: Bool) {
        guard let sunset else { return (nil, false) }
        let latest = sunset.addingTimeInterval(-Double(driveMinutes + 30) * 60)
        if let sunrise, latest < sunrise { return (sunrise, true) }
        return (latest, false)
    }
}

/// What the app last wrote: `snapshot` nil means "no trip ahead", while a
/// missing file means the app has not written anything yet.
struct TripTodayFile: Codable, Equatable {
    var snapshot: TripTodaySnapshot?
    var written: Date
}

/// Files shared between the app and the widget extension through the App Group.
/// Without the App Group (a build signed without it) `container` is nil and
/// the widget asks to open the app instead.
enum SharedStore {
    static let defaultGroup = "group.it.lorenzosavini.nordur"
    static let tripTodayName = "trip-today.json"

    /// The group in the signed profile when there is one (a re-signed build may
    /// carry a renamed group), otherwise the one in the entitlements file.
    static let groupID: String = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let key = text.range(of: "<key>com.apple.security.application-groups</key>") else { return defaultGroup }
        let rest = text[key.upperBound...].prefix(600)
        guard let open = rest.range(of: "<string>"), let close = rest.range(of: "</string>", range: open.upperBound..<rest.endIndex) else {
            return defaultGroup
        }
        let group = String(rest[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return group.isEmpty || group.contains("*") ? defaultGroup : group
    }()

    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }

    static func readTripToday() -> TripTodayFile? {
        guard let url = container?.appendingPathComponent(tripTodayName),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(TripTodayFile.self, from: data)
    }

    @discardableResult
    static func writeTripToday(_ file: TripTodayFile) -> Bool {
        guard let url = container?.appendingPathComponent(tripTodayName) else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(file) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
