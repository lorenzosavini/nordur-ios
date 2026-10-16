import Foundation
import CoreLocation

struct Coordinate: Codable, Hashable {
    var lat: Double
    var lon: Double

    init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.lat = coordinate.latitude
        self.lon = coordinate.longitude
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Stable short key used for caching per-location requests.
    var key: String {
        String(format: "%.2f_%.2f", lat, lon)
    }
}

enum Geo {
    static let earthRadiusKm = 6371.0

    static func distanceKm(_ a: Coordinate, _ b: Coordinate) -> Double {
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLon = (b.lon - a.lon) * .pi / 180
        let lat1 = a.lat * .pi / 180
        let lat2 = b.lat * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusKm * asin(min(1, sqrt(h)))
    }

    /// Ray-casting point-in-polygon test (fine at country scale).
    static func contains(_ polygon: [Coordinate], _ point: Coordinate) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i], pj = polygon[j]
            if (pi.lat > point.lat) != (pj.lat > point.lat) {
                let crossLon = (pj.lon - pi.lon) * (point.lat - pi.lat) / (pj.lat - pi.lat) + pi.lon
                if point.lon < crossLon { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// Distance from `point` to the segment a–b, using a local flat projection.
    static func distanceToSegmentKm(_ point: Coordinate, _ a: Coordinate, _ b: Coordinate) -> Double {
        let kmPerLat = 111.32
        let kmPerLon = 111.32 * cos(point.lat * .pi / 180)
        let ax = (a.lon - point.lon) * kmPerLon, ay = (a.lat - point.lat) * kmPerLat
        let bx = (b.lon - point.lon) * kmPerLon, by = (b.lat - point.lat) * kmPerLat
        let dx = bx - ax, dy = by - ay
        let lengthSquared = dx * dx + dy * dy
        var t = lengthSquared > 0 ? -(ax * dx + ay * dy) / lengthSquared : 0
        t = max(0, min(1, t))
        let cx = ax + t * dx, cy = ay + t * dy
        return sqrt(cx * cx + cy * cy)
    }

    /// CAP polygons are "lat,lon lat,lon …".
    static func parseCAPPolygon(_ text: String) -> [Coordinate] {
        text.split(separator: " ").compactMap { pair in
            let parts = pair.split(separator: ",")
            guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
            return Coordinate(lat: lat, lon: lon)
        }
    }
}
