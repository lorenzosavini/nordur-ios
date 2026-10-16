import Foundation

// Space weather cross-check for the aurora forecast.
//
// Sources
//   NOAA SWPC  – estimated planetary Kp every minute, observed 3-hour Kp,
//                3-day Kp forecast, NOAA G scales, alerts/warnings,
//                hemispheric power (OVATION), real-time solar wind at L1.
//   NASA CCMC  – DONKI: geomagnetic storms and WSA-ENLIL CME arrivals with the
//                Kp range NASA expects at impact.
//   Norður     – Kp derived from the solar wind with the Newell (2007) coupling
//                function: about 30–60 minutes of lead time on the ground.
//
// The blended Kp starts, for each 3-hour block, from the NOAA forecast; the
// blocks of the next 3 hours are averaged with the live measurements, and any
// block crossed by a CME that NASA expects at Earth is raised to NASA's Kp.

// MARK: - Models

struct SolarWindSample {
    let date: Date
    let bt: Double?
    let by: Double?
    let bz: Double
    let speed: Double?
    let density: Double?
}

struct SolarWindSeries {
    let spacecraft: String?
    let samples: [SolarWindSample]

    var latest: SolarWindSample? { samples.last }

    /// Mean of the last `minutes` of a value.
    func mean(_ minutes: Double, _ value: (SolarWindSample) -> Double?) -> Double? {
        guard let end = samples.last?.date else { return nil }
        let window = samples.filter { $0.date >= end.addingTimeInterval(-minutes * 60) }.compactMap(value)
        return window.isEmpty ? nil : window.reduce(0, +) / Double(window.count)
    }

    /// Minutes the solar wind takes from L1 (~1.5 million km) to Earth.
    var leadMinutes: Double? {
        guard let v = mean(30, { $0.speed }), v > 100 else { return nil }
        return 1_500_000 / v / 60
    }

    /// Kp estimated from the solar wind (Newell et al. 2007):
    ///   Kp = 0.05 + 2.244e-4 · dΦ/dt + 2.844e-6 · √n · v²
    ///   dΦ/dt = v^4/3 · Bt^2/3 · sin^8/3(θc/2), θc = atan2(By, Bz) (GSM)
    func newellKp(minutes: Double = 60) -> Double? {
        guard let end = samples.last?.date else { return nil }
        let window = samples.filter { $0.date >= end.addingTimeInterval(-minutes * 60) }
        let terms: [(Double, Double)] = window.compactMap { s in
            guard let v = s.speed, let by = s.by else { return nil }
            let bt = (by * by + s.bz * s.bz).squareRoot()
            let theta = atan2(by, s.bz)
            let coupling = pow(v, 4.0 / 3) * pow(bt, 2.0 / 3) * pow(abs(sin(theta / 2)), 8.0 / 3)
            let pressure = (s.density ?? 5).squareRoot() * v * v
            return (coupling, pressure)
        }
        guard terms.count >= 10 else { return nil }
        let coupling = terms.map(\.0).reduce(0, +) / Double(terms.count)
        let pressure = terms.map(\.1).reduce(0, +) / Double(terms.count)
        return min(9, max(0, 0.05 + 2.244e-4 * coupling + 2.844e-6 * pressure))
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
        let durationHours: Double?
        let glancing: Bool
        let kp: KpRange?
        let modelRun: String?
        let link: String?
        var arrivalDate: Date? { DonkiDigest.date(arrival) }
        var launchDate: Date? { DonkiDigest.date(launched) }
        /// Kp expected while the CME passes: the middle of NASA's range, the low end for a glancing blow.
        var expectedKp: Double? { kp.map { glancing ? $0.min : ($0.min + $0.max) / 2 } }
    }
    struct Flare: Decodable, Identifiable {
        let id: String
        let peak: String?
        let classType: String
        let region: Int?
        var peakDate: Date? { DonkiDigest.date(peak) }
    }

    let generated: String?
    let stale: Bool?
    let storms: [Storm]
    let arrivals: [Arrival]
    let flares: [Flare]

    /// DONKI writes "2026-10-14T03:00Z" (no seconds).
    static func date(_ raw: String?) -> Date? {
        guard var text = raw else { return nil }
        if text.range(of: #"T\d{2}:\d{2}Z$"#, options: .regularExpression) != nil {
            text = String(text.dropLast()) + ":00Z"
        }
        return DateParse.iso(text)
    }

    var upcoming: [Arrival] {
        arrivals.filter { ($0.arrivalDate ?? .distantPast) > Date().addingTimeInterval(-24 * 3600) }
    }
}

struct GeomagScale {
    let date: Date?
    let level: Int        // G0…G5
    let isForecast: Bool
}

struct SpaceAlert: Identifiable {
    let id: String
    let issued: Date?
    let title: String
    let kp: Int?
}

/// One 3-hour block of the blended Kp.
struct KpBlendPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let noaa: Double?
    let nasa: Double?
    let nowcast: Double?
    let value: Double
    let isObserved: Bool

    var driver: String {
        if isObserved { return "Osservato NOAA" }
        if let nasa, nasa >= value - 0.01, nasa > (noaa ?? 0) { return "CME NASA" }
        if let nowcast, abs(nowcast - (noaa ?? nowcast)) >= 0.3 { return "Misure attuali" }
        return "Previsione NOAA"
    }
}

struct SpaceIntel {
    var kpNow: Double?                 // NOAA 1-minute estimated Kp
    var kpNowTime: Date?
    var kpObserved: KpPoint?           // last official 3-hour Kp
    var solarWind: SolarWindSeries?
    var solarWindKp: Double?           // Newell, last 60 min
    var solarWindTrend: Double?        // Newell, last 20 min
    var hemisphericPower: Double?      // GW, north
    var scales: [GeomagScale] = []
    var alerts: [SpaceAlert] = []
    var donki: DonkiDigest?
    var donkiStale = false
    var blend: [KpBlendPoint] = []

    /// Points in the shape the aurora outlook expects.
    var blendedKp: [KpPoint] { blend.map { KpPoint(date: $0.date, kp: $0.value, kind: $0.isObserved ? "observed" : "blend") } }

    /// Best current estimate. The ground-based NOAA estimate is a measurement and
    /// counts double; the solar-wind Kp is a statistical fit (good for trends,
    /// biased in quiet conditions) and counts once.
    var consensusNow: Double? { SpaceIntel.weighted([(kpNow, 2), (solarWindKp, 1)]) }

    static func weighted(_ items: [(Double?, Double)]) -> Double? {
        let present = items.compactMap { item in item.0.map { ($0, item.1) } }
        let total = present.map(\.1).reduce(0, +)
        guard total > 0 else { return nil }
        return present.map { $0.0 * $0.1 }.reduce(0, +) / total
    }

    /// How far apart the sources are right now (Kp units).
    var spread: Double? {
        let values = [kpNow, solarWindKp, blend.first { $0.date <= Date() && Date() < $0.date.addingTimeInterval(3 * 3600) }?.noaa].compactMap { $0 }
        guard values.count >= 2, let lo = values.min(), let hi = values.max() else { return nil }
        return hi - lo
    }

    var maxBlendNext24h: KpBlendPoint? {
        let end = Date().addingTimeInterval(24 * 3600)
        return blend.filter { $0.date.addingTimeInterval(3 * 3600) > Date() && $0.date < end }.max { $0.value < $1.value }
    }

    var currentScale: Int { scales.first { !$0.isForecast }?.level ?? 0 }
}

// MARK: - Fetching

enum SpaceIntelService {
    static let api = "https://nordur-api.vercel.app/api"

    static func load(kpForecast: [KpPoint]) async -> SpaceIntel {
        async let oneMinute = attempt { try await kp1m() }
        async let observed = attempt { try await kpObserved() }
        async let wind = attempt { try await solarWind() }
        async let power = attempt { try await hemisphericPower() }
        async let scales = attempt { try await noaaScales() }
        async let alerts = attempt { try await swpcAlerts() }
        async let donki = attempt { try await donkiDigest() }

        var intel = SpaceIntel()
        if case .success(let k) = await oneMinute { intel.kpNow = k.kp; intel.kpNowTime = k.date }
        if case .success(let o) = await observed { intel.kpObserved = o }
        if case .success(let w) = await wind {
            intel.solarWind = w
            intel.solarWindKp = w.newellKp(minutes: 60)
            intel.solarWindTrend = w.newellKp(minutes: 20)
        }
        if case .success(let p) = await power { intel.hemisphericPower = p }
        if case .success(let s) = await scales { intel.scales = s }
        if case .success(let a) = await alerts { intel.alerts = a }
        if case .success(let d) = await donki { intel.donki = d; intel.donkiStale = d.stale ?? false }
        intel.blend = blend(forecast: kpForecast, intel: intel)
        return intel
    }

    // MARK: Blend

    static func blend(forecast: [KpPoint], intel: SpaceIntel, now: Date = Date()) -> [KpBlendPoint] {
        let arrivals = intel.donki?.upcoming ?? []
        return forecast.filter { $0.date.addingTimeInterval(3 * 3600) > now.addingTimeInterval(-24 * 3600) }.map { point in
            let start = point.date, end = point.date.addingTimeInterval(3 * 3600)
            if !point.isForecast {
                return KpBlendPoint(date: start, noaa: point.kp, nasa: nil, nowcast: nil, value: point.kp, isObserved: true)
            }
            // NASA: CME passing during this block (shock arrival → arrival + duration, default 18 h).
            let nasa = arrivals.compactMap { a -> Double? in
                guard let arrival = a.arrivalDate, let kp = a.expectedKp else { return nil }
                let leave = arrival.addingTimeInterval((a.durationHours ?? 18) * 3600)
                // ENLIL arrival times are ±7 h: open the window 6 h early.
                return (arrival.addingTimeInterval(-6 * 3600) < end && start < leave) ? kp : nil
            }.max()
            // Nowcast, for the blocks that start within 3 h: the NOAA forecast averaged
            // with what the ground (×2) and the solar wind (×1) say now.
            let nowcast: Double? = start < now.addingTimeInterval(3 * 3600)
                ? SpaceIntel.weighted([(point.kp, 1), (intel.kpNow, 2), (intel.solarWindKp, 1)]) : nil
            // A CME forecast by NASA can only raise the expectation.
            let value = max(nowcast ?? point.kp, nasa ?? 0)
            return KpBlendPoint(date: start, noaa: point.kp, nasa: nasa, nowcast: nowcast, value: value, isObserved: false)
        }
    }

    // MARK: NOAA

    private static func url(_ s: String) throws -> URL {
        guard let url = URL(string: s) else { throw HTTPError.invalidURL }
        return url
    }

    static func kp1m() async throws -> (kp: Double, date: Date) {
        struct Row: Decodable { let time_tag: String; let estimated_kp: Double? }
        let rows = try await HTTP.json([Row].self, from: url("https://services.swpc.noaa.gov/json/planetary_k_index_1m.json"), cacheKey: "swpc_kp1m").value
        guard let last = rows.last(where: { $0.estimated_kp != nil }), let kp = last.estimated_kp,
              let date = DateParse.iso(last.time_tag) else { throw HTTPError.status(204) }
        return (kp, date)
    }

    static func kpObserved() async throws -> KpPoint {
        struct Row: Decodable { let time_tag: String; let Kp: Double? }
        let rows = try await HTTP.json([Row].self, from: url("https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json"), cacheKey: "swpc_kp_obs").value
        guard let last = rows.last(where: { $0.Kp != nil }), let kp = last.Kp, let date = DateParse.iso(last.time_tag) else { throw HTTPError.status(204) }
        return KpPoint(date: date, kp: kp, kind: "observed")
    }

    /// Compact series from nordur-api; falls back to NOAA's one-value summaries.
    static func solarWind() async throws -> SolarWindSeries {
        struct Compact: Decodable { let spacecraft: String?; let mag: [[Double?]]; let plasma: [[Double?]] }
        do {
            let compact = try await HTTP.json(Compact.self, from: url("\(api)/solarwind"), cacheKey: "nordur_solarwind").value
            var plasma: [Int: (Double?, Double?)] = [:]
            for row in compact.plasma where row.count >= 3 { if let t = row[0] { plasma[Int(t) / 60] = (row[1], row[2]) } }
            var lastPlasma: (Double?, Double?) = (nil, nil)
            let samples: [SolarWindSample] = compact.mag.compactMap { row in
                guard row.count >= 4, let t = row[0], let bz = row[3] else { return nil }
                if let p = plasma[Int(t) / 60] { lastPlasma = p }
                return SolarWindSample(date: Date(timeIntervalSince1970: t), bt: row[1], by: row[2], bz: bz,
                                       speed: lastPlasma.0, density: lastPlasma.1)
            }
            return SolarWindSeries(spacecraft: compact.spacecraft, samples: samples)
        } catch {
            let summary = try await SpaceWeather.solarWind().value
            guard let bz = summary.bz else { throw error }
            return SolarWindSeries(spacecraft: nil, samples: [SolarWindSample(date: summary.date ?? Date(), bt: summary.bt, by: nil,
                                                                                bz: bz, speed: summary.speed, density: nil)])
        }
    }

    static func hemisphericPower() async throws -> Double {
        let data = try await HTTP.get(url("https://services.swpc.noaa.gov/text/aurora-nowcast-hemi-power.txt"), cacheKey: "swpc_hemi").value
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").filter { !$0.hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let last = lines.last else { throw HTTPError.status(204) }
        let columns = last.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard columns.count >= 3, let north = Double(columns[2]) else { throw HTTPError.status(204) }
        return north
    }

    static func noaaScales() async throws -> [GeomagScale] {
        let data = try await HTTP.get(url("https://services.swpc.noaa.gov/products/noaa-scales.json"), cacheKey: "swpc_scales").value
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return [] }
        return json.compactMap { key, entry -> (Int, GeomagScale)? in
            guard let index = Int(key), index >= 0, let g = entry["G"] as? [String: Any] else { return nil }
            let level = Int((g["Scale"] as? String) ?? "") ?? 0
            let date = DateParse.iso("\(entry["DateStamp"] as? String ?? "")T\(entry["TimeStamp"] as? String ?? "00:00:00")")
            return (index, GeomagScale(date: date, level: level, isForecast: index > 0))
        }
        .sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// Geomagnetic K-index watches, warnings and alerts of the last 48 hours.
    static func swpcAlerts() async throws -> [SpaceAlert] {
        struct Row: Decodable { let product_id: String; let issue_datetime: String; let message: String }
        let rows = try await HTTP.json([Row].self, from: url("https://services.swpc.noaa.gov/products/alerts.json"), cacheKey: "swpc_alerts").value
        let cutoff = Date().addingTimeInterval(-48 * 3600)
        return rows.compactMap { row in
            let issued = DateParse.iso(row.issue_datetime)
            guard (issued ?? .distantPast) >= cutoff else { return nil }
            let lines = row.message.replacingOccurrences(of: "\r", with: "").split(separator: "\n").map(String.init)
            guard let headline = lines.first(where: { $0.hasPrefix("ALERT:") || $0.hasPrefix("WARNING:") || $0.hasPrefix("WATCH:") || $0.hasPrefix("EXTENDED WARNING:") || $0.hasPrefix("SUMMARY:") }),
                  headline.localizedCaseInsensitiveContains("geomagnetic") else { return nil }
            let kp = headline.range(of: #"K-index of (\d)"#, options: .regularExpression)
                .flatMap { Int(headline[$0].filter(\.isNumber)) }
            return SpaceAlert(id: "\(row.product_id)-\(row.issue_datetime)", issued: issued, title: translate(headline), kp: kp)
        }
        .sorted { ($0.issued ?? .distantPast) > ($1.issued ?? .distantPast) }
    }

    private static func translate(_ headline: String) -> String {
        var t = headline
        let table = [("EXTENDED WARNING:", "Avviso esteso:"), ("WARNING:", "Avviso:"), ("ALERT:", "Allerta:"), ("WATCH:", "Sorveglianza:"),
                     ("SUMMARY:", "Riepilogo:"), ("Geomagnetic K-index of", "indice K geomagnetico"), ("expected", "previsto"),
                     ("Geomagnetic Storm Category", "tempesta geomagnetica"), ("Predicted", "prevista"), ("Sudden Impulse", "impulso improvviso"),
                     ("reached", "raggiunto"), ("exceeded", "superato")]
        for (en, it) in table { t = t.replacingOccurrences(of: en, with: it) }
        return t
    }

    // MARK: NASA

    static func donkiDigest() async throws -> DonkiDigest {
        try await HTTP.json(DonkiDigest.self, from: url("\(api)/space"), cacheKey: "nordur_donki").value
    }
}
