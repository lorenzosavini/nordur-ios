import Foundation

// Places to visit from OpenStreetMap — waterfalls, viewpoints, hot springs,
// geysers, caves, arches, volcanoes, glaciers, beaches, museums and pools —
// added to the app's own list of the main sights. nordur-api keeps a weekly
// copy (/api/roads?osm=sights); the phone keeps it 30 days, for use offline.

/// A place suggested for a stop: how far from where you sleep, and whether it is on the way there.
struct Suggestion: Identifiable {
    let sight: Attraction
    let km: Double
    let onTheWay: Bool
    var id: String { sight.id }
}

enum Sights {
    private static let cacheKey = "osm_sights_iceland"
    private static let endpoint = URL(string: "https://nordur-api.vercel.app/api/roads?osm=sights")!

    static func all(maxAge: TimeInterval = 30 * 24 * 3600) async throws -> Fetched<[Attraction]> {
        if let cached = DiskCache.read(cacheKey), Date().timeIntervalSince(cached.date) < maxAge,
           let sights = try? parse(cached.data), !sights.isEmpty {
            return Fetched(value: sights, date: cached.date, isStale: false)
        }
        let fetched = try await HTTP.get(endpoint, cacheKey: cacheKey)
        return Fetched(value: try parse(fetched.value), date: fetched.date, isStale: fetched.isStale)
    }

    static func parse(_ data: Data) throws -> [Attraction] {
        struct Response: Decodable { let elements: [Element] }
        struct Element: Decodable { let id: Int; let lat: Double; let lon: Double; let tags: [String: String] }
        return try JSONDecoder().decode(Response.self, from: data).elements.compactMap { e in
            guard let name = e.tags["name"], let type = classify(e.tags) else { return nil }
            let english = e.tags["name:en"].flatMap { $0 == name ? nil : $0 }
            let detail = [english, e.tags["description:en"] ?? e.tags["description"]].compactMap { $0 }.joined(separator: " · ")
            return Attraction(name: name, lat: e.lat, lon: e.lon, kind: type.kind, minutes: type.minutes, region: label(e.tags),
                              osmID: e.id, notable: e.tags["wikipedia"] != nil || e.tags["wikidata"] != nil,
                              detail: detail.isEmpty ? nil : detail)
        }
    }

    private static func classify(_ t: [String: String]) -> (kind: AttractionKind, minutes: Int)? {
        switch t["natural"] {
        case "waterfall": return (.waterfall, 30)
        case "hot_spring", "geyser": return (.geothermal, 40)
        case "glacier": return (.glacier, 45)
        case "beach": return (.beach, 30)
        case "cave_entrance", "arch", "volcano": return (.landscape, 40)
        default: break
        }
        if t["waterway"] == "waterfall" { return (.waterfall, 30) }
        if t["amenity"] == "public_bath" || t["leisure"] == "swimming_pool" { return (.bath, 90) }
        switch t["tourism"] {
        case "museum": return (.town, 60)
        case "viewpoint", "attraction": return (.landscape, 25)
        default: return nil
        }
    }

    /// What kind of place, in words ("Belvedere", "Grotta"…).
    private static func label(_ t: [String: String]) -> String {
        switch t["natural"] ?? t["tourism"] ?? t["amenity"] ?? t["leisure"] ?? t["waterway"] {
        case "waterfall": return String(localized: "Cascata")
        case "hot_spring": return String(localized: "Sorgente calda")
        case "geyser": return String(localized: "Geyser")
        case "glacier": return String(localized: "Ghiacciaio")
        case "beach": return String(localized: "Spiaggia")
        case "cave_entrance": return String(localized: "Grotta")
        case "arch": return String(localized: "Arco di roccia")
        case "volcano": return String(localized: "Vulcano")
        case "museum": return String(localized: "Museo")
        case "viewpoint": return String(localized: "Belvedere")
        case "public_bath", "swimming_pool": return String(localized: "Piscina e bagni termali")
        default: return String(localized: "Da vedere")
        }
    }

    /// The app's own list plus the OpenStreetMap places that are not already in it.
    static func merged(_ osm: [Attraction]) -> [Attraction] {
        let top = Attraction.catalog
        let extra = osm.filter { o in
            !top.contains { t in
                let km = Geo.distanceKm(t.coordinate, o.coordinate)
                return km < 0.4 || (km < 3 && (t.name.localizedCaseInsensitiveContains(o.name) || o.name.localizedCaseInsensitiveContains(t.name)))
            }
        }
        return top + extra
    }

    /// Suggestions for a stop: near where you sleep, or along the way from the
    /// previous stop by car; the best-known first, without those already planned.
    static func suggestions(in all: [Attraction], for stop: TripStop, previous: TripStop?, planned: [TripVisit],
                            limit: Int = 5) -> [Suggestion] {
        let from = stop.transport == .car ? previous?.place.coordinate : nil
        let scored: [(sight: Attraction, km: Double, onTheWay: Bool, score: Double)] = all.compactMap { a in
            if planned.contains(where: { Geo.distanceKm($0.place.coordinate, a.coordinate) < 0.5 }) { return nil }
            let km = Geo.distanceKm(stop.place.coordinate, a.coordinate)
            let off = from.map { Geo.distanceToSegmentKm(a.coordinate, $0, stop.place.coordinate) } ?? .infinity
            guard km <= 45 || off <= 10 else { return nil }
            let onTheWay = km > 45 || (off < km && off <= 10 && km > 15)
            let weight = a.isTop ? 3.0 : a.notable ? 1.5 : 0
            return (a, km, onTheWay, weight - min(km, off) / 25)
        }
        return scored.sorted { $0.score > $1.score }.prefix(limit).map { Suggestion(sight: $0.sight, km: $0.km, onTheWay: $0.onTheWay) }
    }
}
