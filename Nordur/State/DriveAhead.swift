import Foundation

/// What lies ahead while recording a drive, for the Live Activity: the next
/// stop (with remaining km and arrival time) and the next fuel station.
@MainActor
enum DriveAhead {
    struct Stop { let name: String; let km: Double; let eta: Date? }
    struct Fuel { let name: String; let km: Double }

    /// The destination set in the drive screen (along its route), otherwise
    /// today's trip stop (straight line × 1.3, like the trip screen). Nothing
    /// once you are there.
    static func nextStop(from position: Coordinate, averageKmh: Double, now: Date = Date()) -> Stop? {
        let watch = RoadWatch.shared
        if let destination = watch.destination {
            let remaining = watch.remainingKm ?? Geo.distanceKm(position, destination.coordinate) * 1.3
            guard remaining > 0.5 else { return nil }
            var seconds: TimeInterval
            if watch.routeTotalKm > 0, watch.routeTravelTime > 0 {
                seconds = watch.routeTravelTime * remaining / watch.routeTotalKm
            } else {
                seconds = remaining / max(averageKmh, 60) * 3600
            }
            seconds = max(seconds, 60)
            return Stop(name: destination.name, km: remaining, eta: now.addingTimeInterval(seconds))
        }
        guard let today = WidgetSync.tripToday, today.isToday, today.byRoad else { return nil }
        let remaining = Geo.distanceKm(position, today.destination) * 1.3
        guard remaining > 1 else { return nil }
        return Stop(name: today.toName, km: remaining, eta: now.addingTimeInterval(remaining / max(averageKmh, 60) * 3600))
    }

    private static var routeFuel: [(station: FuelStation, routeKm: Double)] = []
    private static var routeFuelKey = ""

    /// Along the planned route: the first station within 2 km of it past the
    /// current position. Without a route: the nearest station within 50° of
    /// the heading (or simply the nearest when the heading is unknown).
    static func nextFuel(from position: Coordinate, course: Double?) -> Fuel? {
        let stations = (AlertCenter.shared.model?.fuel?.value ?? []).filter { $0.kind == .fuel }
        guard !stations.isEmpty else { return nil }
        let watch = RoadWatch.shared
        if watch.route.count >= 2, watch.routeKm.count == watch.route.count, let remaining = watch.remainingKm {
            let key = "\(watch.route.count)-\(Int(watch.routeTotalKm * 10))"
            if key != routeFuelKey {
                routeFuel = mapToRoute(stations, route: watch.route, routeKm: watch.routeKm)
                routeFuelKey = key
            }
            let current = watch.routeTotalKm - remaining
            guard let next = routeFuel.first(where: { $0.routeKm > current + 0.3 }) else { return nil }
            return Fuel(name: next.station.name, km: next.routeKm - current)
        }
        let near = stations.map { (station: $0, km: Geo.distanceKm(position, $0.coordinate)) }.filter { $0.km <= 150 }
        if let course {
            let ahead = near.filter { $0.km < 0.3 || angle(bearing(position, $0.station.coordinate), course) <= 50 }
            if let best = ahead.min(by: { $0.km < $1.km }) { return Fuel(name: best.station.name, km: best.km) }
        }
        return near.min(by: { $0.km < $1.km }).map { Fuel(name: $0.station.name, km: $0.km) }
    }

    private static func mapToRoute(_ stations: [FuelStation], route: [Coordinate], routeKm: [Double]) -> [(station: FuelStation, routeKm: Double)] {
        var result: [(station: FuelStation, routeKm: Double)] = []
        for station in stations {
            var best = Double.infinity
            var at = 0.0
            for i in 1..<route.count {
                let d = Geo.distanceToSegmentKm(station.coordinate, route[i - 1], route[i])
                if d < best { best = d; at = routeKm[i - 1] + Geo.distanceKm(route[i - 1], station.coordinate) }
            }
            if best <= 2 { result.append((station, at)) }
        }
        return result.sorted { $0.routeKm < $1.routeKm }
    }

    /// Initial bearing from a to b, degrees clockwise from north.
    static func bearing(_ a: Coordinate, _ b: Coordinate) -> Double {
        let φ1 = a.lat * .pi / 180, φ2 = b.lat * .pi / 180
        let Δλ = (b.lon - a.lon) * .pi / 180
        let y = sin(Δλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func angle(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }
}
