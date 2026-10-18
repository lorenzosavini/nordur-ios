import Foundation

// Validated space-weather state from nordur-api (/api/aurora), which ingests
// NOAA SWPC, GFZ Potsdam and NASA CCMC, normalises timestamps/units, checks
// freshness and records provenance. If the backend is unreachable the app
// falls back to NOAA directly (Kp forecast + OVATION), with fewer features.

struct SourceStatus: Decodable {
    let status: String          // ok · stale · error
    let error: String?
    let provider: String?
    let endpoint: String?
    let fetchedAt: String?
    let observedAt: String?
    let validAt: String?
    let ageMinutes: Double?

    var isOK: Bool { status == "ok" }
}

struct AuroraState: Decodable {
    struct KpSection: Decodable {
        struct Block: Decodable, Identifiable {
            var id: String { t }
            let t: String
            let kind: String               // observed · estimated · predicted (NOAA labels)
            let noaa: Double
            let gfz: Double?
            let gfzStatus: String?
            let value: Double
            let nowcast: Double?
            let nasa: Double?
            let enlilCloud: Bool?
            let driver: String
            let leadHours: Double?
            let reliability: String?
            var start: Date? { DateParse.iso(t) }
            var isObserved: Bool { kind == "observed" }
        }
        struct Point: Decodable { let t: String; let kp: Double; var date: Date? { DateParse.iso(t) } }
        struct Estimated: Decodable { let t: String; let kp: Double; let series: [Point]?; var date: Date? { DateParse.iso(t) } }
        struct GFZ: Decodable { let t: String; let kp: Double; let status: String?; var date: Date? { DateParse.iso(t) } }
        let blocks: [Block]
        let estimated: Estimated?
        let gfz: [GFZ]
    }

    struct SolarWind: Decodable {
        struct Values: Decodable { let bz: Double?; let by: Double?; let bt: Double?; let v: Double?; let n: Double?; let temp: Double?; let pdyn: Double? }
        struct Average: Decodable { let bz: Double?; let by: Double?; let bt: Double?; let v: Double?; let n: Double?; let pdyn: Double?; let samples: Int }
        struct Extremes: Decodable { let bzMin: Double?; let bzMax: Double?; let vMax: Double?; let nMax: Double?; let pdynMax: Double? }
        struct South: Decodable { let continuousMinutes: Int; let fraction60: Double?; let fractionBelow5: Double?; let fractionBelow10: Double? }
        struct Shock: Decodable { let t: Double; let dv: Double; let densityRatio: Double; let fieldRatio: Double; var date: Date { Date(timeIntervalSince1970: t / 1000) } }
        struct Propagation: Decodable { let distanceKm: Double; let speedKmS: Double; let minutes: Double; let uncertaintyMinutes: Double; let ephemerisTime: String? }
        struct Coupling: Decodable { let newell30: Double?; let newell60: Double? }
        struct Nowcast: Decodable {
            struct Step: Decodable {
                let t: String; let minutes: Int; let known: Bool; let bz: Double?; let v: Double?; let n: Double?; let newellKp: Double?
                var date: Date? { DateParse.iso(t) }
            }
            let coveredMinutes: Int
            let steps: [Step]
            var inputs: [NowcastInput] {
                steps.compactMap { s in s.date.map { NowcastInput(date: $0, minutes: s.minutes, known: s.known, bz: s.bz, speed: s.v, newellKp: s.newellKp) } }
            }
        }

        let spacecraft: String?
        let lastSample: Double
        let ageMinutes: Double?
        let samples: Int
        let flaggedFraction: Double?
        let latest: Values
        let averages: [String: Average]
        let extremes60: Extremes
        let bzSouth: South
        let pressureTrend: Double?
        let coupling: Coupling?
        let newellKp: Double?
        let shocks: [Shock]
        let propagation: Propagation?
        let nowcast: Nowcast?
        let series: [[Double?]]

        var lastDate: Date { Date(timeIntervalSince1970: lastSample / 1000) }
        func average(_ minutes: Int) -> Average? { averages[String(minutes)] }
    }

    struct Ovation: Decodable, AuroraField {
        let observationTime: String?
        let forecastTime: String?
        let latMin: Int
        let rows: Int
        let grid: [Int]
        var validAt: Date? { DateParse.iso(forecastTime) }
        var observedAt: Date? { DateParse.iso(observationTime) }
        func value(lat: Int, lon: Int) -> Double? {
            guard lat >= latMin, lat < latMin + rows else { return nil }
            let x = ((lon % 360) + 360) % 360
            let i = (lat - latMin) * 360 + x
            return grid.indices.contains(i) ? Double(grid[i]) : nil
        }
    }

    struct Enlil: Decodable {
        struct Sample: Decodable { let t: String; let v: Double; let n: Double; let pdyn: Double; let cloud: Bool; var date: Date? { DateParse.iso(t) } }
        struct Arrival: Decodable { let t: String; let peakSpeed: Double; var date: Date? { DateParse.iso(t) } }
        let modelStart: String?
        let modelEnd: String?
        let samples: [Sample]
        let cmeArrivals: [Arrival]
    }

    struct Scale: Decodable { let index: Int; let date: String?; let g: Int; let gText: String?; let forecast: Bool }

    struct Alert: Decodable, Identifiable {
        let id: String
        let code: String?
        let issued: String?
        let validTo: String?
        var headline: String
        let kp: Int?
        let g: Int?
        let active: Bool?
        var issuedDate: Date? { DateParse.iso(issued) }
        /// The headline in the app language: NOAA writes in English, so only the Italian interface translates it.
        var italian: String {
            var t = headline
            guard Bundle.main.preferredLocalizations.first == "it" else { return t }
            for (en, it) in [("EXTENDED WARNING:", "Avviso esteso:"), ("WARNING:", "Avviso:"), ("ALERT:", "Allerta:"), ("WATCH:", "Sorveglianza:"),
                             ("SUMMARY:", "Riepilogo:"), ("Geomagnetic K-index of", "indice K geomagnetico"), ("or greater", "o superiore"),
                             ("expected", "previsto"), ("Geomagnetic Storm Category", "tempesta geomagnetica"), ("Predicted", "prevista"),
                             ("Geomagnetic Sudden Impulse", "impulso geomagnetico improvviso")] { t = t.replacingOccurrences(of: en, with: it) }
            return t
        }
    }

    struct HemisphericPower: Decodable {
        struct Latest: Decodable { let observed: String?; let forecast: String?; let north: Double?; let south: Double? }
        struct Point: Decodable { let t: String?; let gw: Double? }
        let latest: Latest?
        let series: [Point]
    }

    /// GFZ Hp30: the Kp scale over 30 minutes.
    struct Hp30Point: Decodable { let t: String; let hp30: Double; var date: Date? { DateParse.iso(t) } }

    /// Ground magnetometer nearest to Iceland in real time (Narsarsuaq, Greenland):
    /// range of the horizontal field in the last hour and its level 0…3.
    struct Magnetometer: Decodable {
        struct Point: Decodable { let t: String; let h: Double; var date: Date? { DateParse.iso(t) } }
        let station: String
        let observed: String?
        let rangeNt: Double
        let level: Int
        let series: [Point]?
        var observedDate: Date? { observed.flatMap(DateParse.iso) }
        var levelLabel: String {
            switch level {
            case 3: return String(localized: "Tempesta magnetica")
            case 2: return String(localized: "Campo disturbato: aurora probabile")
            case 1: return String(localized: "Campo attivo")
            default: return String(localized: "Campo calmo")
            }
        }
    }

    struct LongTerm: Decodable {
        struct Day: Decodable { let date: String; let f107: Double?; let ap: Double?; let kpMax: Double? }
        struct Day45: Decodable { let date: String; let ap: Double?; let f107: Double? }
        let outlook27: [Day]?
        let forecast45: [Day45]?
    }

    let generated: String?
    let sources: [String: SourceStatus]
    let kp: KpSection
    let solarWind: SolarWind?
    let ovation: Ovation?
    let enlil: Enlil?
    let scales: [Scale]?
    var alerts: [Alert]?
    let hemisphericPower: HemisphericPower?
    let hp30: [Hp30Point]?
    let magnetometer: Magnetometer?
    let donki: DonkiDigest?
    let longTerm: LongTerm?

    /// True when this state was assembled on the device from NOAA directly.
    var isFallback = false

    enum CodingKeys: String, CodingKey {
        case generated, sources, kp, solarWind, ovation, enlil, scales, alerts, hemisphericPower, hp30, magnetometer, donki, longTerm
    }

    func source(_ name: String) -> SourceStatus? { sources[name] }

    var kpBlocks: [KpBlock] {
        kp.blocks.compactMap { b in b.start.map { KpBlock(start: $0, value: b.value, isObserved: b.isObserved) } }
    }

    var currentBlock: KpSection.Block? {
        let now = Date()
        return kp.blocks.first { b in
            guard let s = b.start else { return false }
            return s <= now && now < s.addingTimeInterval(3 * 3600)
        }
    }
}

struct DonkiDigest: Decodable {
    struct StormKp: Decodable { let time: String?; let kp: Double?; let source: String? }
    struct Storm: Decodable, Identifiable {
        let id: String
        let start: String?
        let maxKp: Double?
        let kp: [StormKp]?
        let link: String?
        var startDate: Date? { DonkiDigest.date(start) }
    }
    struct KpRange: Decodable { let min: Double; let max: Double }
    struct Arrival: Decodable, Identifiable {
        let id: String
        let launched: String?
        let speed: Double?
        let halfAngle: Double?
        let arrival: String
        let arrivalUncertaintyHours: Double?
        let durationHours: Double?
        let glancing: Bool
        let kp: KpRange?
        let modelRun: String?
        let link: String?
        var arrivalDate: Date? { DonkiDigest.date(arrival) }
        var launchDate: Date? { DonkiDigest.date(launched) }
        /// Kp used for this CME: the low end of NASA's range (CCMC warns ENLIL runs tend to overestimate impacts).
        var expectedKp: Double? { kp?.min }
    }
    struct Flare: Decodable, Identifiable {
        let id: String
        let peak: String?
        let classType: String
        let region: Int?
        var peakDate: Date? { DonkiDigest.date(peak) }
    }

    let storms: [Storm]
    let arrivals: [Arrival]
    let flares: [Flare]

    static func date(_ raw: String?) -> Date? {
        guard var text = raw else { return nil }
        if text.range(of: #"T\d{2}:\d{2}Z$"#, options: .regularExpression) != nil { text = String(text.dropLast()) + ":00Z" }
        return DateParse.iso(text)
    }

    var upcoming: [Arrival] { arrivals.filter { ($0.arrivalDate ?? .distantPast) > Date().addingTimeInterval(-24 * 3600) } }
}

/// The NOAA grid fetched directly by the app (map, fallback) is a field too.
extension OvationGrid: AuroraField {
    var validAt: Date? { forecastTime }
    var observedAt: Date? { nil }
    func value(lat: Int, lon: Int) -> Double? { probability(at: Coordinate(lat: Double(lat), lon: Double(lon))) }
}

enum AuroraStateService {
    static let endpoint = URL(string: "https://nordur-api.vercel.app/api/aurora")!

    static func load() async throws -> Fetched<AuroraState> {
        let fetched = try await HTTP.get(endpoint, cacheKey: "nordur_aurora_state")
        return try fetched.map { try JSONDecoder().decode(AuroraState.self, from: $0) }
    }
}
