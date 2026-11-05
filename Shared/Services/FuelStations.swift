import Foundation

// Fuel stations: Gasvaktin first (the companies' own list, with prices), then
// the OpenStreetMap stations Gasvaktin does not have and the EV chargers.
// The OpenStreetMap list is downloaded once and kept on the device so it is
// available without coverage — the East and the Westfjords have long
// stretches without a station.

struct FuelStation: Identifiable, Hashable, Codable {
    enum Kind: String, Codable { case fuel, charger }

    let id: Int
    let kind: Kind
    let name: String
    let brand: String?
    let openingHours: String?
    let coordinate: Coordinate
    /// The Gasvaktin station this is (its prices), when it comes from Gasvaktin.
    var priceKey: String? = nil
}

enum FuelStations {
    private static let cacheKey = "osm_fuel_iceland"
    private static let endpoints = [
        // nordur-api keeps a copy (refreshed from the weekly GitHub Action): fast, and
        // it works when the public Overpass servers are busy or refuse the connection.
        "https://nordur-api.vercel.app/api/roads?osm=fuel",
        // The copy the GitHub Action publishes, when nordur-api is not reachable.
        "https://raw.githubusercontent.com/lorenzosavini/nordur-ios/osm-data/fuel.json",
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    ]

    /// Uses the on-device copy when younger than `maxAge`, otherwise downloads.
    static func all(maxAge: TimeInterval = 30 * 24 * 3600) async throws -> Fetched<[FuelStation]> {
        if let cached = DiskCache.read(cacheKey), Date().timeIntervalSince(cached.date) < OSMCopy.maxAge(cached.data, maxAge),
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
                let url = endpoint.contains("interpreter") ? try HTTP.url(endpoint, ["data": query]) : URL(string: endpoint)!
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

    /// One list: every Gasvaktin station (name, company, position, prices; the
    /// opening hours of the OpenStreetMap station at the same place), then the
    /// OpenStreetMap stations that match no Gasvaktin station, then the chargers.
    static func merge(osm: [FuelStation], prices: [FuelPrice]) -> [FuelStation] {
        guard !prices.isEmpty else { return osm }
        var hours: [String: (hours: String, km: Double)] = [:]
        var unmatched: [FuelStation] = []
        for station in osm {
            guard station.kind == .fuel else { unmatched.append(station); continue }
            if let price = FuelPrices.nearestMatch(station, in: prices) {
                if let h = station.openingHours, price.km < (hours[price.price.key]?.km ?? .infinity) {
                    hours[price.price.key] = (h, price.km)
                }
            } else {
                unmatched.append(station)
            }
        }
        let priced = prices.map { p in
            let name = p.name.lowercased().contains(p.company.lowercased()) ? p.name : "\(p.company) \(p.name)"
            return FuelStation(id: stableID(p.key), kind: .fuel, name: name, brand: p.company,
                               openingHours: hours[p.key]?.hours, coordinate: p.coordinate, priceKey: p.key)
        }
        return priced + unmatched
    }

    /// A fixed negative id for a Gasvaktin key (OpenStreetMap ids are positive).
    static func stableID(_ key: String) -> Int {
        var hash: UInt64 = 5381
        for byte in key.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return -Int(hash % UInt64(Int32.max)) - 1
    }

    static func nearest(_ stations: [FuelStation], to point: Coordinate, kind: FuelStation.Kind, limit: Int) -> [(station: FuelStation, km: Double)] {
        Array(stations.filter { $0.kind == kind }
            .map { (station: $0, km: Geo.distanceKm($0.coordinate, point)) }
            .sorted { $0.km < $1.km }
            .prefix(limit))
    }
}
