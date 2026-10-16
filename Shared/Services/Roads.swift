import Foundation

// Vegagerðin — Icelandic Road and Coastal Administration open data
// (the same feeds behind umferdin.is): surface condition of every road
// segment and live readings from ~200 roadside weather stations.

struct RoadSegment: Decodable, Identifiable {
    let IdButur: Double
    let StuttNafnButs: String?
    let FulltNafnButs: String?
    let AstandYfirbord: String?
    let AstandLysing: String?
    let AstandLysingEn: String?
    let FrkvLysingEn: String?
    let AsthungiLysingEn: String?
    let DagsSkrad: String?

    var id: Int { Int(IdButur) }
    var name: String { FulltNafnButs ?? StuttNafnButs ?? "Tratto \(id)" }
    var conditionText: String { AstandLysingEn ?? AstandLysing ?? "Sconosciuto" }
    var updated: Date? { DateParse.iso(DagsSkrad) }

    /// nil when the segment is not serviced or its state is unknown.
    var risk: Risk? { RoadCondition.risk(AstandYfirbord) }

    var conditionItalian: String { RoadCondition.italian(AstandYfirbord) ?? conditionText }
}

struct RoadStation: Decodable, Identifiable {
    let Nr: Double
    let Nafn: String?
    let Breidd: Double?
    let Lengd: Double?
    let Haed: Double?
    let Dags: String?
    let VindattAscEng: String?
    let Vindhradi: Double?
    let Vindhvida: Double?
    let Hiti: Double?
    let Veghiti: Double?
    let Raki: Double?
    let UmfSum: Double?
    let IdButur1: Double?
    let IdButur2: Double?

    var id: Int { Int(Nr) }
    var name: String { Nafn ?? "Stazione \(id)" }
    var coordinate: Coordinate? {
        guard let Breidd, let Lengd, Breidd != 0 else { return nil }
        return Coordinate(lat: Breidd, lon: Lengd)
    }
    var date: Date? { DateParse.roadStation(Dags) }
    var windDirection: String { VindattAscEng?.trimmingCharacters(in: .whitespaces) ?? "" }

    var windRisk: Risk { Risk.wind(mean: Vindhradi, gust: Vindhvida) }

    var surfaceRisk: Risk {
        guard let road = Veghiti else { return .ok }
        if road <= 0 && (Raki ?? 0) >= 80 { return .warning }
        if road <= 0.5 { return .caution }
        return .ok
    }

    var risk: Risk { max(windRisk, surfaceRisk) }

    var segmentIDs: [Int] { [IdButur1, IdButur2].compactMap { $0.map { Int($0) } } }

    /// Reading older than 3 hours is likely a station outage.
    var isOutdated: Bool {
        guard let date else { return true }
        return Date().timeIntervalSince(date) > 3 * 3600
    }
}

enum RoadCondition {
    static func risk(_ code: String?) -> Risk? {
        guard let code = code?.uppercased() else { return nil }
        switch code {
        case "GREIDFAERT": return .ok
        case "EKKI_I_THJONUSTU", "OTHEKKT": return nil
        case "HALKUBLETTIR", "KRAP", "BLAUTT", "HALKUBLETTIR_OG_SKAFRENNINGUR": return .caution
        case "HALKA", "SNJOTHEKJA", "THUNGFAERT", "SKAFRENNINGUR", "FAERT_FJALLABILUM": return .warning
        case "FLUGHALT", "OFAERT", "OFAERT_ANNAD", "LOKAD", "OFAERT_VEDUR": return .danger
        default:
            if code.contains("OFAERT") || code.contains("LOKAD") { return .danger }
            if code.contains("HALK") || code.contains("SNJO") || code.contains("THUNG") { return .warning }
            return .caution
        }
    }

    static func italian(_ code: String?) -> String? {
        switch code?.uppercased() {
        case "GREIDFAERT": return "Percorribile"
        case "HALKUBLETTIR": return "Tratti ghiacciati"
        case "HALKA": return "Strada scivolosa"
        case "FLUGHALT": return "Estremamente scivolosa"
        case "KRAP": return "Neve bagnata"
        case "SNJOTHEKJA": return "Neve sulla carreggiata"
        case "THUNGFAERT": return "Percorribilità difficile"
        case "SKAFRENNINGUR": return "Neve soffiata dal vento"
        case "FAERT_FJALLABILUM": return "Solo veicoli 4x4 da montagna"
        case "OFAERT", "OFAERT_ANNAD", "OFAERT_VEDUR": return "Impraticabile"
        case "LOKAD": return "Chiusa"
        case "EKKI_I_THJONUSTU": return "Non mantenuta in questo periodo"
        case "OTHEKKT": return "Stato sconosciuto"
        default: return nil
        }
    }
}

struct NearbyStation: Identifiable {
    let station: RoadStation
    let distance: Double
    var id: Int { station.id }
}

struct RoadNetwork {
    let segments: [RoadSegment]
    let stations: [RoadStation]
    let segmentsByID: [Int: RoadSegment]

    init(segments: [RoadSegment], stations: [RoadStation]) {
        self.segments = segments
        self.stations = stations
        var map: [Int: RoadSegment] = [:]
        for segment in segments { map[segment.id] = segment }
        self.segmentsByID = map
    }

    /// Segments with something worth knowing, worst first.
    var problemSegments: [RoadSegment] {
        segments
            .filter { ($0.risk ?? .ok) > .ok }
            .sorted {
                let l = $0.risk ?? .ok, r = $1.risk ?? .ok
                if l != r { return l > r }
                return $0.name < $1.name
            }
    }

    func segments(for station: RoadStation) -> [RoadSegment] {
        station.segmentIDs.compactMap { segmentsByID[$0] }
    }

    func nearestStations(to point: Coordinate, count: Int) -> [NearbyStation] {
        let nearby = stations.compactMap { station -> NearbyStation? in
            guard let c = station.coordinate, !station.isOutdated,
                  station.Vindhradi != nil || station.Hiti != nil || station.Veghiti != nil else { return nil }
            return NearbyStation(station: station, distance: Geo.distanceKm(point, c))
        }
        return Array(nearby.sorted { $0.distance < $1.distance }.prefix(count))
    }

    /// Stations within `corridorKm` of the straight line between two places,
    /// with the condition of the road segment each one watches.
    func corridor(from a: Coordinate, to b: Coordinate, corridorKm: Double = 20) -> [RoadStation] {
        stations.filter { station in
            guard let c = station.coordinate, !station.isOutdated else { return false }
            return Geo.distanceToSegmentKm(c, a, b) <= corridorKm
        }
    }

    func worstRisk(of station: RoadStation) -> Risk {
        let segmentRisk = segments(for: station).compactMap(\.risk).max() ?? .ok
        return max(station.risk, segmentRisk)
    }
}

enum Roads {
    static func network() async throws -> Fetched<RoadNetwork> {
        guard let segmentsURL = URL(string: "https://gagnaveita.vegagerdin.is/api/faerd2017_1"),
              let stationsURL = URL(string: "https://gagnaveita.vegagerdin.is/api/vedur2014_1") else { throw HTTPError.invalidURL }
        async let segments = HTTP.json([RoadSegment].self, from: segmentsURL, cacheKey: "roads_segments")
        async let stations = HTTP.json([RoadStation].self, from: stationsURL, cacheKey: "roads_stations")
        let (s, w) = try await (segments, stations)
        return Fetched(
            value: RoadNetwork(segments: s.value, stations: w.value),
            date: min(s.date, w.date),
            isStale: s.isStale || w.isStale
        )
    }
}
