import Foundation

// Supermarkets, mini-markets, shopping centres and the state liquor stores
// (Vínbúðin, the only place that sells wine and spirits) from OpenStreetMap.
// Downloaded once and kept on the device like the fuel stations: outside the
// towns the next shop can be 100 km away and close early.

struct Shop: Identifiable, Hashable, Codable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case supermarket, convenience, mall, alcohol

        var id: String { rawValue }

        var label: String {
            switch self {
            case .supermarket: return String(localized: "Supermercato")
            case .convenience: return String(localized: "Minimarket")
            case .mall: return String(localized: "Centro commerciale")
            case .alcohol: return String(localized: "Vínbúðin (alcolici)")
            }
        }

        var symbol: String {
            switch self {
            case .supermarket: return "cart.fill"
            case .convenience: return "basket.fill"
            case .mall: return "bag.fill"
            case .alcohol: return "wineglass.fill"
            }
        }
    }

    let id: Int
    let kind: Kind
    let name: String
    let brand: String?
    let openingHours: String?
    let coordinate: Coordinate
    var town: String?

    /// The discount chains (Bónus, Krónan, Nettó, Prís): the cheapest places to stock up.
    var isBudget: Bool {
        let n = (brand ?? name).lowercased()
        return ["bónus", "bonus", "krónan", "kronan", "nettó", "netto", "prís"].contains { n.hasPrefix($0) }
    }

    var hours: OpeningHours? { openingHours.flatMap(OpeningHours.init) }

    var place: Place { Place(name: name, coordinate: coordinate, subtitle: town ?? kind.label) }
}

/// A shop and how far it is from the place asked about.
struct NearShop: Identifiable {
    let shop: Shop
    let km: Double
    var id: Int { shop.id }
}

enum Shops {
    private static let cacheKey = "osm_shops_iceland"
    private static let endpoints = [
        // nordur-api keeps a weekly copy: fast, and works when the public servers are busy.
        "https://nordur-api.vercel.app/api/roads?shops=1",
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    ]

    /// Uses the on-device copy when younger than `maxAge`, otherwise downloads.
    static func all(maxAge: TimeInterval = 30 * 24 * 3600) async throws -> Fetched<[Shop]> {
        if let cached = DiskCache.read(cacheKey), Date().timeIntervalSince(cached.date) < OSMCopy.maxAge(cached.data, maxAge),
           let shops = try? parse(cached.data), !shops.isEmpty {
            return Fetched(value: shops, date: cached.date, isStale: false)
        }
        return try await download()
    }

    static func download() async throws -> Fetched<[Shop]> {
        let query = """
        [out:json][timeout:90];
        (nwr["shop"~"^(supermarket|convenience|mall|alcohol|department_store)$"](63.2,-24.6,66.6,-13.4););
        out center tags;
        """
        var lastError: Error = HTTPError.status(0)
        for endpoint in endpoints {
            do {
                let url = endpoint.contains("nordur-api") ? URL(string: endpoint)! : try HTTP.url(endpoint, ["data": query])
                let fetched = try await HTTP.get(url, cacheKey: cacheKey)
                let shops = try parse(fetched.value)
                if !shops.isEmpty { return Fetched(value: shops, date: fetched.date, isStale: fetched.isStale) }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    static func parse(_ data: Data) throws -> [Shop] {
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
            let kind: Shop.Kind
            switch tags["shop"] {
            case "supermarket": kind = .supermarket
            case "convenience": kind = .convenience
            case "mall", "department_store": kind = .mall
            case "alcohol": kind = .alcohol
            default: return nil
            }
            let brand = tags["brand"] ?? tags["operator"]
            guard let name = tags["name"] ?? brand else { return nil }
            return Shop(id: element.id, kind: kind, name: name, brand: brand, openingHours: tags["opening_hours"],
                        coordinate: Coordinate(lat: lat, lon: lon), town: tags["addr:city"] ?? tags["addr:place"])
        }
    }

    static func nearest(_ shops: [Shop], to point: Coordinate, kinds: Set<Shop.Kind> = Set(Shop.Kind.allCases),
                        within km: Double = .infinity, limit: Int = .max) -> [NearShop] {
        Array(shops.filter { kinds.contains($0.kind) }
            .map { NearShop(shop: $0, km: Geo.distanceKm($0.coordinate, point)) }
            .filter { $0.km <= km }
            .sorted { $0.km < $1.km }
            .prefix(limit))
    }
}
