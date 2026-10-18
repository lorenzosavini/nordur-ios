import Foundation

/// One GPS fix of a recorded drive.
struct TrackPoint: Codable, Hashable {
    let t: Date
    let lat: Double
    let lon: Double
    let alt: Double?
    /// m/s, negative when unknown.
    let speed: Double
    let course: Double?
    let accuracy: Double

    var coordinate: Coordinate { Coordinate(lat: lat, lon: lon) }
    var kmh: Double { max(0, speed) * 3.6 }
}

struct DriveSettings: Codable, Equatable {
    var consumption: Double = 7.5        // l/100 km (or kWh/100 km)
    var fuelPrice: Double = 330          // ISK per litre
    var speedLimit: Double = 90          // km/h, Icelandic limit on paved rural roads
    var speedAlerts: Bool = true
    var spokenAlerts: Bool = true
    var odometer: Double?                // last known car odometer (km)

    private static let key = "driveSettings"

    static func load() -> DriveSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(DriveSettings.self, from: data) else { return DriveSettings() }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

/// Running statistics; updated point by point so long drives stay cheap.
struct DriveStats: Codable, Equatable {
    var distanceMeters: Double = 0
    var movingSeconds: Double = 0
    var maxSpeed: Double = 0              // m/s
    var elevationGain: Double = 0
    var elevationLoss: Double = 0
    var minAltitude: Double?
    var maxAltitude: Double?
    var stops: Int = 0
    var speedingSeconds: Double = 0
    var speedingMaxKmh: Double = 0
    /// Altitude at which the last climb/descent was counted (hysteresis).
    var altitudeAnchor: Double?

    var km: Double { distanceMeters / 1000 }
    var maxKmh: Double { maxSpeed * 3.6 }

    func averageKmh(totalSeconds: Double) -> Double {
        totalSeconds > 0 ? km / (totalSeconds / 3600) : 0
    }

    var movingAverageKmh: Double {
        movingSeconds > 0 ? km / (movingSeconds / 3600) : 0
    }

    func fuelLitres(_ settings: DriveSettings) -> Double { km * settings.consumption / 100 }
    func fuelCost(_ settings: DriveSettings) -> Double { fuelLitres(settings) * settings.fuelPrice }
}

struct DriveSession: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var start: Date
    var end: Date?
    var odometerStart: Double?
    var notes: String = ""
    var points: [TrackPoint] = []
    var stats = DriveStats()
    /// Seconds spent paused, excluded from the duration.
    var pausedSeconds: Double = 0
    /// Imported activities: where from ("Garmin Connect", "Apple Watch", "GPX"), the kind
    /// of activity ("Corsa", "Bici"…), heart rate and energy, and the source's id (no duplicates).
    var source: String?
    var activity: String?
    var heartRateAvg: Double?
    var heartRateMax: Double?
    var energyKcal: Double?
    var importID: String?

    /// Recorded by Norður in a car (not an imported run, ride or hike).
    var isDrive: Bool { activity == nil }

    static func == (lhs: DriveSession, rhs: DriveSession) -> Bool { lhs.id == rhs.id && lhs.points.count == rhs.points.count && lhs.end == rhs.end && lhs.name == rhs.name }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var isFinished: Bool { end != nil }

    func durationSeconds(now: Date = Date()) -> Double {
        max(0, (end ?? now).timeIntervalSince(start) - pausedSeconds)
    }

    var odometerEnd: Double? { odometerStart.map { $0 + stats.km } }
}

/// Filters GPS noise and accumulates statistics.
enum DriveMath {
    static let maxAccuracy = 35.0        // metres; worse fixes are ignored
    static let movingThreshold = 1.5     // m/s (~5 km/h)
    static let stopSeconds = 120.0       // standing still this long counts as a stop

    /// Returns false when the point is rejected.
    @discardableResult
    static func append(_ point: TrackPoint, to session: inout DriveSession, settings: DriveSettings) -> Bool {
        guard point.accuracy >= 0, point.accuracy <= maxAccuracy else { return false }
        guard let last = session.points.last else {
            // The first fix anchors the altitude: the climb from the start counts too.
            if let alt = point.alt {
                session.stats.altitudeAnchor = alt
                session.stats.minAltitude = alt
                session.stats.maxAltitude = alt
            }
            session.points.append(point)
            return true
        }
        let dt = point.t.timeIntervalSince(last.t)
        guard dt > 0 else { return false }
        let meters = Geo.distanceKm(last.coordinate, point.coordinate) * 1000
        // Teleport filter: faster than 250 km/h between fixes is a GPS jump.
        guard meters / dt < 70 else { return false }

        // Too close to the last stored fix: wait, so distance and time are
        // measured from the stored point and never counted twice.
        if meters < 10 && dt < 30 {
            if point.speed >= 0 && point.accuracy <= 20 {
                session.stats.maxSpeed = max(session.stats.maxSpeed, point.speed)
            }
            return true
        }

        let speed = point.speed >= 0 ? point.speed : meters / dt
        let moving = speed >= movingThreshold
        var stats = session.stats
        // When standing still, small drifts of a few metres are GPS noise.
        if moving || meters > max(point.accuracy, 10) {
            stats.distanceMeters += meters
        }
        if moving {
            stats.movingSeconds += dt
            // A stop is counted when we start moving after standing still long enough.
            if stillDuration(before: last, in: session.points) >= stopSeconds { stats.stops += 1 }
        }
        if point.speed >= 0 && point.accuracy <= 20 {
            stats.maxSpeed = max(stats.maxSpeed, point.speed)
        }
        if let alt = point.alt, point.accuracy <= 20 {
            // Count climbs/descents only once they exceed 3 m from the anchor, so
            // GPS altitude jitter does not inflate the totals but slow climbs add up.
            let anchor = stats.altitudeAnchor ?? alt
            let delta = alt - anchor
            if delta >= 3 { stats.elevationGain += delta; stats.altitudeAnchor = alt }
            else if delta <= -3 { stats.elevationLoss -= delta; stats.altitudeAnchor = alt }
            else if stats.altitudeAnchor == nil { stats.altitudeAnchor = alt }
        }
        if let alt = point.alt {
            stats.minAltitude = min(stats.minAltitude ?? alt, alt)
            stats.maxAltitude = max(stats.maxAltitude ?? alt, alt)
        }
        if speed * 3.6 > settings.speedLimit + 3 {
            stats.speedingSeconds += dt
            stats.speedingMaxKmh = max(stats.speedingMaxKmh, speed * 3.6)
        }
        session.stats = stats
        session.points.append(point)
        return true
    }

    private static func stillDuration(before last: TrackPoint, in points: [TrackPoint]) -> Double {
        var earliest = last.t
        for p in points.reversed() {
            if p.speed >= movingThreshold { break }
            earliest = p.t
        }
        return last.t.timeIntervalSince(earliest)
    }

    /// Keeps at most `maxPoints` evenly spaced points for drawing.
    static func downsample(_ points: [TrackPoint], maxPoints: Int = 1500) -> [TrackPoint] {
        guard points.count > maxPoints, maxPoints > 1 else { return points }
        let step = Double(points.count - 1) / Double(maxPoints - 1)
        return (0..<maxPoints).map { points[Int((Double($0) * step).rounded())] }
    }

    /// Splits the track into runs of similar speed for colouring the map line.
    static func speedRuns(_ points: [TrackPoint]) -> [(bucket: Int, points: [TrackPoint])] {
        var runs: [(bucket: Int, points: [TrackPoint])] = []
        for p in points {
            let bucket = speedBucket(p.kmh)
            if var lastRun = runs.last, lastRun.bucket == bucket {
                lastRun.points.append(p)
                runs[runs.count - 1] = lastRun
            } else {
                // Overlap one point so segments join without gaps.
                var pts = [p]
                if let previous = runs.last?.points.last { pts.insert(previous, at: 0) }
                runs.append((bucket, pts))
            }
        }
        return runs
    }

    /// 0: <30, 1: 30–60, 2: 60–80, 3: 80–95, 4: >95 km/h
    static func speedBucket(_ kmh: Double) -> Int {
        if kmh < 30 { return 0 }
        if kmh < 60 { return 1 }
        if kmh < 80 { return 2 }
        if kmh < 95 { return 3 }
        return 4
    }

    /// Kilometres driven per calendar day across sessions.
    struct DayTotal: Identifiable {
        let day: Date
        let km: Double
        var id: Date { day }
    }

    static func kmPerDay(_ sessions: [DriveSession], calendar: Calendar = .current) -> [DayTotal] {
        var totals: [Date: Double] = [:]
        for s in sessions {
            let day = calendar.startOfDay(for: s.start)
            totals[day, default: 0] += s.stats.km
        }
        return totals.map { DayTotal(day: $0.key, km: $0.value) }.sorted { $0.day < $1.day }
    }

    /// A session built from points recorded elsewhere (Apple Health, a GPX file),
    /// with the same noise filter and statistics as a drive recorded here.
    static func imported(name: String, points: [TrackPoint], start: Date? = nil, end: Date? = nil,
                         settings: DriveSettings = DriveSettings()) -> DriveSession {
        let sorted = points.sorted { $0.t < $1.t }
        var session = DriveSession(name: name, start: start ?? sorted.first?.t ?? Date())
        var noLimit = settings
        noLimit.speedLimit = 1000
        for point in sorted { append(point, to: &session, settings: noLimit) }
        session.end = end ?? sorted.last?.t ?? session.start
        return session
    }

    static func gpx(_ session: DriveSession) -> String {
        let iso = ISO8601DateFormatter()
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Nordur" xmlns="http://www.topografix.com/GPX/1/1">
        <metadata><name>\(escape(session.name))</name><time>\(iso.string(from: session.start))</time></metadata>
        <trk><name>\(escape(session.name))</name><trkseg>

        """
        for p in session.points {
            out += "<trkpt lat=\"\(p.lat)\" lon=\"\(p.lon)\">"
            if let alt = p.alt { out += "<ele>\(String(format: "%.1f", alt))</ele>" }
            out += "<time>\(iso.string(from: p.t))</time>"
            if p.speed >= 0 { out += "<extensions><speed>\(String(format: "%.2f", p.speed))</speed></extensions>" }
            out += "</trkpt>\n"
        }
        out += "</trkseg></trk></gpx>\n"
        return out
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}
