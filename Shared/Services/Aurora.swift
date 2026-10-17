import Foundation

// NOAA Space Weather Prediction Center (swpc.noaa.gov), fetched directly by the
// device: Kp forecast and OVATION for the map and as fallback when nordur-api
// is unreachable. The forecasting logic lives in AuroraEngine.swift.

struct KpPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let kp: Double
    let kind: String   // observed / estimated / predicted

    var isForecast: Bool { kind != "observed" }

    var risk: Risk {
        if kp >= 7 { return .danger }
        if kp >= 5 { return .warning }
        if kp >= 4 { return .caution }
        return .ok
    }
}

/// OVATION grid: probability (0–100) of visible aurora overhead per 1°×1° cell.
struct OvationGrid {
    let forecastTime: Date?
    fileprivate let values: [Double]   // index = lon * 181 + (lat + 90)

    func probability(at c: Coordinate) -> Double? {
        let lat = Int(c.lat.rounded())
        var lon = Int(c.lon.rounded()) % 360
        if lon < 0 { lon += 360 }
        guard (-90...90).contains(lat) else { return nil }
        let index = lon * 181 + (lat + 90)
        return values.indices.contains(index) ? values[index] : nil
    }

    /// Smoothly interpolated probability, for drawing the oval on a map.
    func interpolated(lat: Double, lon: Double) -> Double {
        guard lat > -90, lat < 90 else { return 0 }
        var x = lon.truncatingRemainder(dividingBy: 360)
        if x < 0 { x += 360 }
        let x0 = Int(x), y0 = Int(floor(lat))
        let tx = x - Double(x0), ty = lat - Double(y0)
        func v(_ lo: Int, _ la: Int) -> Double {
            let index = ((lo % 360 + 360) % 360) * 181 + (min(max(la, -90), 90) + 90)
            return values.indices.contains(index) ? values[index] : 0
        }
        let top = v(x0, y0) + (v(x0 + 1, y0) - v(x0, y0)) * tx
        let bottom = v(x0, y0 + 1) + (v(x0 + 1, y0 + 1) - v(x0, y0 + 1)) * tx
        return top + (bottom - top) * ty
    }

    /// Aurora is usually seen low on the poleward horizon before it is overhead:
    /// best probability within a few degrees towards the pole.
    func horizonProbability(at c: Coordinate, degrees: Int = 4) -> Double? {
        let step = c.lat >= 0 ? 1.0 : -1.0
        let samples = (0...degrees).compactMap { probability(at: Coordinate(lat: c.lat + Double($0) * step, lon: c.lon)) }
        return samples.max()
    }
}

extension OvationGrid {
    /// nordur-api's copy of the same run (30–90°N, 1° cells), used when NOAA
    /// cannot be reached from the device.
    init(backend o: AuroraState.Ovation) {
        var values = [Double](repeating: 0, count: 360 * 181)
        for row in 0..<o.rows where (-90...90).contains(o.latMin + row) {
            for lon in 0..<360 where o.grid.indices.contains(row * 360 + lon) {
                values[lon * 181 + (o.latMin + row + 90)] = Double(o.grid[row * 360 + lon])
            }
        }
        self.init(forecastTime: DateParse.iso(o.forecastTime), values: values)
    }
}

/// NOAA polar-view images of the northern oval, every 5 minutes over 24 h.
struct OvationFrame: Identifiable, Hashable {
    let time: Date
    let url: URL
    var id: Date { time }
}

extension SpaceWeather {
    static func ovationAnimation(lastHours: Double = 3, step: Int = 2) async throws -> [OvationFrame] {
        guard let url = URL(string: "https://services.swpc.noaa.gov/products/animations/ovation_north_24h.json") else { throw HTTPError.invalidURL }
        struct Raw: Decodable { let url: String; let time_tag: String }
        let raw = try await HTTP.json([Raw].self, from: url, cacheKey: "swpc_ovation_anim").value
        let cutoff = Date().addingTimeInterval(-lastHours * 3600)
        let frames = raw.compactMap { item -> OvationFrame? in
            guard let time = DateParse.iso(item.time_tag), time >= cutoff,
                  let full = URL(string: "https://services.swpc.noaa.gov" + item.url) else { return nil }
            return OvationFrame(time: time, url: full)
        }
        return stride(from: 0, to: frames.count, by: max(1, step)).map { frames[$0] } + (frames.last.map { [$0] } ?? [])
    }
}

struct SolarWind {
    let bz: Double?
    let bt: Double?
    let speed: Double?
    let date: Date?

    /// Southward (negative) Bz couples the solar wind to Earth's field.
    var favourable: Bool { (bz ?? 0) <= -5 && (speed ?? 0) >= 400 }
}

enum KpLookup {
    static func kp(at date: Date, in points: [KpPoint]) -> Double? {
        points.last { $0.date <= date && date < $0.date.addingTimeInterval(3 * 3600) }?.kp
    }
}

enum SpaceWeather {
    static func kpForecast() async throws -> Fetched<[KpPoint]> {
        guard let url = URL(string: "https://services.swpc.noaa.gov/products/noaa-planetary-k-index-forecast.json") else { throw HTTPError.invalidURL }
        let fetched = try await HTTP.get(url, cacheKey: "swpc_kp")
        return try fetched.map(parseKp)
    }

    /// Accepts both the current array-of-objects format and the older
    /// array-of-arrays format (first row = header).
    static func parseKp(_ data: Data) throws -> [KpPoint] {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let rows = json as? [Any] else { return [] }
        var points: [KpPoint] = []
        for row in rows {
            if let object = row as? [String: Any] {
                guard let date = DateParse.iso(object["time_tag"] as? String),
                      let kp = number(object["kp"]) else { continue }
                points.append(KpPoint(date: date, kp: kp, kind: (object["observed"] as? String) ?? "predicted"))
            } else if let array = row as? [Any], array.count >= 3 {
                guard let date = DateParse.iso(array[0] as? String), let kp = number(array[1]) else { continue }
                points.append(KpPoint(date: date, kp: kp, kind: (array[2] as? String) ?? "predicted"))
            }
        }
        return points.sorted { $0.date < $1.date }
    }

    static func ovation() async throws -> Fetched<OvationGrid> {
        guard let url = URL(string: "https://services.swpc.noaa.gov/json/ovation_aurora_latest.json") else { throw HTTPError.invalidURL }
        let fetched = try await HTTP.get(url, cacheKey: "swpc_ovation")
        return try fetched.map { data in
            struct Raw: Decodable {
                let forecastTime: String?
                let coordinates: [[Double]]
                enum CodingKeys: String, CodingKey {
                    case forecastTime = "Forecast Time"
                    case coordinates
                }
            }
            let raw = try JSONDecoder().decode(Raw.self, from: data)
            var values = [Double](repeating: 0, count: 360 * 181)
            for triple in raw.coordinates where triple.count >= 3 {
                let lon = Int(triple[0]), lat = Int(triple[1])
                guard (0..<360).contains(lon), (-90...90).contains(lat) else { continue }
                values[lon * 181 + (lat + 90)] = triple[2]
            }
            return OvationGrid(forecastTime: DateParse.iso(raw.forecastTime), values: values)
        }
    }

    static func solarWind() async throws -> Fetched<SolarWind> {
        guard let magURL = URL(string: "https://services.swpc.noaa.gov/products/summary/solar-wind-mag-field.json"),
              let speedURL = URL(string: "https://services.swpc.noaa.gov/products/summary/solar-wind-speed.json") else { throw HTTPError.invalidURL }
        async let mag = HTTP.get(magURL, cacheKey: "swpc_mag")
        async let speed = HTTP.get(speedURL, cacheKey: "swpc_speed")
        let (m, s) = try await (mag, speed)
        let magObject = firstObject(m.value)
        let speedObject = firstObject(s.value)
        let wind = SolarWind(
            bz: number(magObject?["bz_gsm"]),
            bt: number(magObject?["bt"]),
            speed: number(speedObject?["proton_speed"]),
            date: DateParse.iso(magObject?["time_tag"] as? String)
        )
        return Fetched(value: wind, date: min(m.date, s.date), isStale: m.isStale || s.isStale)
    }

    private static func firstObject(_ data: Data) -> [String: Any]? {
        let json = try? JSONSerialization.jsonObject(with: data)
        if let array = json as? [[String: Any]] { return array.first }
        return json as? [String: Any]
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }
}
