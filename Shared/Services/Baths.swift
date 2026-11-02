import Foundation

// Swimming pools, geothermal baths and natural hot springs from OpenStreetMap.
// The GitHub Action (tools/osm/fetch.py) publishes a weekly copy on the
// osm-data branch; the public Overpass servers are the fallback. Kept on the
// phone 30 days like shops and fuel, for use without coverage.
//
// Only what OpenStreetMap says is shown: opening hours and fee when tagged,
// never prices, temperatures or how crowded a place is.

struct Bath: Identifiable, Hashable, Codable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        /// Public swimming pools (sundlaug), sports centres with a pool, geothermal baths and lagoons.
        case pool
        /// Natural hot springs, in the open.
        case natural

        var id: String { rawValue }

        var label: String {
            switch self {
            case .pool: return String(localized: "Piscina pubblica")
            case .natural: return String(localized: "Sorgente naturale")
            }
        }

        var plural: String {
            switch self {
            case .pool: return String(localized: "Piscine pubbliche")
            case .natural: return String(localized: "Sorgenti naturali")
            }
        }

        var symbol: String {
            switch self {
            case .pool: return "figure.pool.swim"
            case .natural: return "drop.halffull"
            }
        }
    }

    let id: Int
    let kind: Kind
    let name: String
    let nameEnglish: String?
    /// What OpenStreetMap calls it ("Swimming pool", "Geothermal bath"…), in words.
    let detail: String
    let openingHours: String?
    /// OSM `fee`: true = paid entry, false = free; nil when not tagged (then nothing is shown).
    let fee: Bool?
    let website: String?
    let wikidata: String?
    let wikipedia: String?
    let coordinate: Coordinate

    var hours: OpeningHours? { openingHours.flatMap(OpeningHours.init) }
    var notable: Bool { wikidata != nil || wikipedia != nil }
    var place: Place { Place(name: name, coordinate: coordinate, subtitle: kind.label) }

    /// The same place as a sight, to add it to a stop of the trip like the others.
    var attraction: Attraction {
        Attraction(name: name, lat: coordinate.lat, lon: coordinate.lon, kind: .bath, minutes: kind == .pool ? 90 : 60,
                   region: kind.label, caution: kind == .natural ? Baths.safetyShort : nil, osmID: id, notable: notable,
                   detail: nameEnglish, wikidata: wikidata, wikipedia: wikipedia)
    }
}

/// A pool or spring and how far it is from the place asked about.
struct NearBath: Identifiable {
    let bath: Bath
    let km: Double
    var id: Int { bath.id }
}

enum Baths {
    private static let cacheKey = "osm_baths_iceland"
    static let overpassQuery = """
    [out:json][timeout:120];
    (nwr["leisure"="swimming_pool"]["name"]["access"!~"^(private|no|customers)$"](63.2,-24.6,66.6,-13.4);
     nwr["leisure"="sports_centre"]["sport"~"swimming"](63.2,-24.6,66.6,-13.4);
     nwr["amenity"="public_bath"](63.2,-24.6,66.6,-13.4);
     nwr["natural"="hot_spring"]["name"](63.2,-24.6,66.6,-13.4););
    out center tags;
    """
    private static let endpoints = [
        // The copy the GitHub Action publishes every week.
        "https://raw.githubusercontent.com/lorenzosavini/nordur-ios/osm-data/baths.json",
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    ]

    static let safetyShort = String(localized: "Acqua che può essere bollente: entra solo dove è sicuro e resta sui sentieri.")
    static let safety = String(localized: "Nelle aree geotermiche l'acqua può superare i 90 °C a pochi metri da una pozza tiepida, e il terreno vicino può cedere. Prova la temperatura prima di entrare, resta sui sentieri e dietro le corde, non lasciare i bambini da soli. D'inverno i sentieri sono spesso ghiacciati.")

    /// Uses the on-device copy when younger than `maxAge`, otherwise downloads.
    static func all(maxAge: TimeInterval = 30 * 24 * 3600) async throws -> Fetched<[Bath]> {
        if let cached = DiskCache.read(cacheKey), Date().timeIntervalSince(cached.date) < OSMCopy.maxAge(cached.data, maxAge),
           let baths = try? parse(cached.data), !baths.isEmpty {
            return Fetched(value: baths, date: cached.date, isStale: false)
        }
        var lastError: Error = HTTPError.status(0)
        for endpoint in endpoints {
            do {
                let url = endpoint.contains("overpass") || endpoint.contains("interpreter")
                    ? try HTTP.url(endpoint, ["data": overpassQuery]) : URL(string: endpoint)!
                let fetched = try await HTTP.get(url, cacheKey: cacheKey)
                let baths = try parse(fetched.value)
                if !baths.isEmpty { return Fetched(value: baths, date: fetched.date, isStale: fetched.isStale) }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    static func parse(_ data: Data) throws -> [Bath] {
        struct Response: Decodable { let elements: [Element] }
        struct Element: Decodable {
            let id: Int
            let lat: Double?
            let lon: Double?
            let center: Center?
            let tags: [String: String]?
        }
        struct Center: Decodable { let lat: Double; let lon: Double }

        let elements = try JSONDecoder().decode(Response.self, from: data).elements
        var result: [Bath] = []
        for e in elements {
            guard let lat = e.lat ?? e.center?.lat, let lon = e.lon ?? e.center?.lon, let tags = e.tags,
                  let type = classify(tags) else { continue }
            let english = tags["name:en"].flatMap { $0 == tags["name"] ? nil : $0 }
            guard let name = tags["name"] ?? english else { continue }
            var fee: Bool?
            if tags["fee"]?.lowercased() == "yes" { fee = true } else if tags["fee"]?.lowercased() == "no" { fee = false }
            let bath = Bath(id: e.id, kind: type.kind, name: name, nameEnglish: english, detail: type.detail,
                            openingHours: tags["opening_hours"], fee: fee, website: tags["website"] ?? tags["contact:website"],
                            wikidata: tags["wikidata"], wikipedia: tags["wikipedia"], coordinate: Coordinate(lat: lat, lon: lon))
            result.append(bath)
        }
        return dedupe(result)
    }

    /// Which kind, or nil for what is not open to the public (hotel and private pools).
    static func classify(_ t: [String: String]) -> (kind: Bath.Kind, detail: String)? {
        let access = t["access"]?.lowercased() ?? ""
        if ["private", "no", "customers"].contains(access) { return nil }
        if t["natural"] == "hot_spring" {
            // A spring with a pool built for bathing is still a natural spring (no staff, no lifeguards).
            return (.natural, String(localized: "Sorgente calda"))
        }
        if t["amenity"] == "public_bath" { return (.pool, String(localized: "Bagni termali")) }
        if t["leisure"] == "sports_centre", (t["sport"] ?? "").contains("swimming") {
            return (.pool, String(localized: "Centro sportivo con piscina"))
        }
        if t["leisure"] == "swimming_pool" { return (.pool, String(localized: "Piscina")) }
        return nil
    }

    /// The same place mapped twice (the centre and its pool, a spring and its bath): one row.
    static func dedupe(_ baths: [Bath]) -> [Bath] {
        var kept: [Bath] = []
        for bath in baths.sorted(by: { ($0.notable ? 0 : 1, $0.openingHours == nil ? 1 : 0, $0.id) < ($1.notable ? 0 : 1, $1.openingHours == nil ? 1 : 0, $1.id) }) {
            let duplicate = kept.contains { other in
                Geo.distanceKm(other.coordinate, bath.coordinate) < 0.3
                    && (other.name.localizedCaseInsensitiveCompare(bath.name) == .orderedSame
                        || other.name.localizedCaseInsensitiveContains(bath.name)
                        || bath.name.localizedCaseInsensitiveContains(other.name)
                        || Geo.distanceKm(other.coordinate, bath.coordinate) < 0.08)
            }
            if !duplicate { kept.append(bath) }
        }
        return kept
    }

    static func nearest(_ baths: [Bath], to point: Coordinate, kinds: Set<Bath.Kind> = Set(Bath.Kind.allCases),
                        within km: Double = .infinity) -> [NearBath] {
        baths.filter { kinds.contains($0.kind) }
            .map { NearBath(bath: $0, km: Geo.distanceKm($0.coordinate, point)) }
            .filter { $0.km <= km }
            .sorted { $0.km < $1.km }
    }
}
