import Foundation

// Fuel stations and EV chargers from OpenStreetMap (Overpass API). Downloaded
// once and kept on the device so they are available without coverage —
// the East and the Westfjords have long stretches without a station.

struct FuelStation: Identifiable, Hashable, Codable {
    enum Kind: String, Codable { case fuel, charger }

    let id: Int
    let kind: Kind
    let name: String
    let brand: String?
    let openingHours: String?
    let coordinate: Coordinate
}

enum FuelStations {
    private static let cacheKey = "osm_fuel_iceland"
    private static let endpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
    ]

    /// Uses the on-device copy when younger than `maxAge`, otherwise downloads.
    static func all(maxAge: TimeInterval = 30 * 24 * 3600) async throws -> Fetched<[FuelStation]> {
        if let cached = DiskCache.read(cacheKey), Date().timeIntervalSince(cached.date) < maxAge,
           let stations = try? parse(cached.data) {
            return Fetched(value: stations, date: cached.date, isStale: false)
        }
        return try await download()
    }

    static func download() async throws -> Fetched<[FuelStation]> {
        let query = """
        [out:json][timeout:60];
        (nwr["amenity"="fuel"](63.2,-24.6,66.6,-13.4);
         nwr["amenity"="charging_station"](63.2,-24.6,66.6,-13.4););
        out center tags;
        """
        var lastError: Error = HTTPError.status(0)
        for endpoint in endpoints {
            do {
                let url = try HTTP.url(endpoint, ["data": query])
                let fetched = try await HTTP.get(url, cacheKey: cacheKey)
                let stations = try parse(fetched.value)
                if !stations.isEmpty { return Fetched(value: stations, date: fetched.date, isStale: fetched.isStale) }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    static func parse(_ data: Data) throws -> [FuelStation] {
        struct Response: Decodable { let elements: [Element] }
        struct Element: Decodable {
            let id: Int
            let lat: Double?
            let lon: Double?
            let center: Center?
            let tags: [String: String]?
        }
        struct Center: Decodable { let lat: Double; let lon: Double }

        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.elements.compactMap { element in
            guard let lat = element.lat ?? element.center?.lat, let lon = element.lon ?? element.center?.lon else { return nil }
            let tags = element.tags ?? [:]
            let kind: FuelStation.Kind = tags["amenity"] == "charging_station" ? .charger : .fuel
            let brand = tags["brand"] ?? tags["operator"]
            let name = tags["name"] ?? brand ?? (kind == .fuel ? "Distributore" : "Ricarica")
            return FuelStation(id: element.id, kind: kind, name: name, brand: brand,
                               openingHours: tags["opening_hours"], coordinate: Coordinate(lat: lat, lon: lon))
        }
    }

    static func nearest(_ stations: [FuelStation], to point: Coordinate, kind: FuelStation.Kind, limit: Int) -> [(station: FuelStation, km: Double)] {
        Array(stations.filter { $0.kind == kind }
            .map { (station: $0, km: Geo.distanceKm($0.coordinate, point)) }
            .sorted { $0.km < $1.km }
            .prefix(limit))
    }
}
