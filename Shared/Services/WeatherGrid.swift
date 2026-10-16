import Foundation

/// Raster layers that can be painted on the map.
enum WeatherLayer: String, CaseIterable, Identifiable, Codable {
    case none, wind, gust, precipitation, snow, cloud, temperature, aurora, radar

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return String(localized: "Nessuno")
        case .wind: return String(localized: "Vento")
        case .gust: return String(localized: "Raffiche")
        case .precipitation: return String(localized: "Pioggia")
        case .snow: return String(localized: "Neve")
        case .cloud: return String(localized: "Nuvole")
        case .temperature: return String(localized: "Temperatura")
        case .aurora: return String(localized: "Aurora")
        case .radar: return String(localized: "Radar")
        }
    }

    var symbol: String {
        switch self {
        case .none: return "map"
        case .wind: return "wind"
        case .gust: return "tornado"
        case .precipitation: return "cloud.rain.fill"
        case .snow: return "snowflake"
        case .cloud: return "cloud.fill"
        case .temperature: return "thermometer.medium"
        case .aurora: return "moon.stars.fill"
        case .radar: return "dot.radiowaves.left.and.right"
        }
    }

    var unit: String {
        switch self {
        case .wind, .gust: return "m/s"
        case .precipitation: return "mm/h"
        case .snow: return "cm/h"
        case .cloud, .aurora: return "%"
        case .temperature: return "°C"
        case .none, .radar: return ""
        }
    }

    /// Uses the 48-hour forecast grid (time slider applies).
    var isForecast: Bool {
        switch self {
        case .wind, .gust, .precipitation, .snow, .cloud, .temperature: return true
        default: return false
        }
    }

    var showsArrows: Bool { self == .wind || self == .gust }

    /// Colour ramp: (value, r, g, b, alpha) — values in the layer unit.
    var ramp: [ColorStop] {
        switch self {
        case .wind, .gust:
            return [.init(0, 0.55, 0.75, 1.0, 0.25), .init(5, 0.20, 0.80, 0.85, 0.45), .init(10, 0.25, 0.80, 0.30, 0.55),
                    .init(15, 0.98, 0.85, 0.15, 0.62), .init(20, 1.0, 0.55, 0.10, 0.68), .init(25, 0.92, 0.15, 0.15, 0.72),
                    .init(30, 0.80, 0.10, 0.60, 0.75), .init(40, 0.45, 0.10, 0.65, 0.8)]
        case .precipitation:
            return [.init(0, 0.3, 0.6, 1, 0), .init(0.1, 0.55, 0.80, 1.0, 0.35), .init(0.5, 0.30, 0.60, 1.0, 0.55),
                    .init(1.5, 0.10, 0.35, 0.95, 0.65), .init(4, 0.45, 0.20, 0.85, 0.72), .init(8, 0.85, 0.15, 0.70, 0.78)]
        case .snow:
            return [.init(0, 0.7, 0.85, 1, 0), .init(0.05, 0.70, 0.90, 1.0, 0.40), .init(0.5, 0.40, 0.65, 1.0, 0.60),
                    .init(1.5, 0.60, 0.45, 0.95, 0.70), .init(3, 0.90, 0.40, 0.90, 0.78)]
        case .cloud:
            return [.init(0, 0.4, 0.45, 0.5, 0), .init(30, 0.45, 0.48, 0.52, 0.15), .init(70, 0.40, 0.42, 0.46, 0.45),
                    .init(100, 0.30, 0.32, 0.36, 0.70)]
        case .temperature:
            return [.init(-20, 0.45, 0.15, 0.65, 0.6), .init(-10, 0.25, 0.35, 0.90, 0.6), .init(-2, 0.35, 0.75, 0.95, 0.55),
                    .init(2, 0.40, 0.85, 0.60, 0.5), .init(8, 0.75, 0.88, 0.30, 0.5), .init(14, 0.98, 0.75, 0.20, 0.55),
                    .init(20, 0.95, 0.35, 0.15, 0.6)]
        case .aurora:
            return [.init(0, 0.2, 0.9, 0.4, 0), .init(4, 0.20, 0.90, 0.40, 0.25), .init(15, 0.15, 0.95, 0.35, 0.55),
                    .init(35, 0.95, 0.95, 0.20, 0.65), .init(60, 1.0, 0.55, 0.10, 0.72), .init(85, 0.95, 0.15, 0.20, 0.8)]
        case .none, .radar:
            return []
        }
    }

    /// Values shown in the legend.
    var legendValues: [Double] {
        switch self {
        case .wind, .gust: return [0, 5, 10, 15, 20, 25, 30]
        case .precipitation: return [0.1, 0.5, 1.5, 4, 8]
        case .snow: return [0.05, 0.5, 1.5, 3]
        case .cloud: return [30, 70, 100]
        case .temperature: return [-10, -2, 2, 8, 14, 20]
        case .aurora: return [4, 15, 35, 60, 85]
        default: return []
        }
    }
}

struct ColorStop {
    let value: Double
    let r: Double, g: Double, b: Double, a: Double
    init(_ value: Double, _ r: Double, _ g: Double, _ b: Double, _ a: Double) {
        self.value = value; self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// Linear interpolation along a ramp.
    static func color(for value: Double, in ramp: [ColorStop]) -> (r: Double, g: Double, b: Double, a: Double) {
        guard let first = ramp.first, let last = ramp.last else { return (0, 0, 0, 0) }
        if value <= first.value { return (first.r, first.g, first.b, first.a) }
        if value >= last.value { return (last.r, last.g, last.b, last.a) }
        for i in 1..<ramp.count where value <= ramp[i].value {
            let lo = ramp[i - 1], hi = ramp[i]
            let t = (value - lo.value) / max(hi.value - lo.value, 1e-9)
            return (lo.r + (hi.r - lo.r) * t, lo.g + (hi.g - lo.g) * t, lo.b + (hi.b - lo.b) * t, lo.a + (hi.a - lo.a) * t)
        }
        return (last.r, last.g, last.b, last.a)
    }
}

/// Hourly forecast on a regular lat/lon grid covering Iceland.
struct WeatherGrid {
    let lats: [Double]           // ascending
    let lons: [Double]           // ascending
    let times: [Date]
    /// fields[layer][hour][row * lons.count + col]
    let fields: [WeatherLayer: [[Double]]]
    let windDirection: [[Double]]

    static let south = 63.1, north = 66.8, west = -24.7, east = -13.3

    var hourCount: Int { times.count }

    /// Index of the hour closest to now.
    var currentHourIndex: Int {
        let now = Date()
        return times.indices.min { abs(times[$0].timeIntervalSince(now)) < abs(times[$1].timeIntervalSince(now)) } ?? 0
    }

    func contains(_ c: Coordinate) -> Bool {
        c.lat >= lats.first! && c.lat <= lats.last! && c.lon >= lons.first! && c.lon <= lons.last!
    }

    /// Bilinear interpolation; nil outside the grid.
    func value(_ layer: WeatherLayer, hour: Int, lat: Double, lon: Double) -> Double? {
        guard let field = fields[layer], field.indices.contains(hour) else { return nil }
        return Self.bilinear(field[hour], lats: lats, lons: lons, lat: lat, lon: lon)
    }

    func direction(hour: Int, row: Int, col: Int) -> Double? {
        guard windDirection.indices.contains(hour) else { return nil }
        let v = windDirection[hour][row * lons.count + col]
        return v.isNaN ? nil : v
    }

    static func bilinear(_ values: [Double], lats: [Double], lons: [Double], lat: Double, lon: Double) -> Double? {
        guard lats.count >= 2, lons.count >= 2,
              lat >= lats[0], lat <= lats[lats.count - 1], lon >= lons[0], lon <= lons[lons.count - 1] else { return nil }
        let dLat = lats[1] - lats[0], dLon = lons[1] - lons[0]
        let fy = (lat - lats[0]) / dLat, fx = (lon - lons[0]) / dLon
        let y0 = min(Int(fy), lats.count - 2), x0 = min(Int(fx), lons.count - 2)
        let ty = fy - Double(y0), tx = fx - Double(x0)
        let w = lons.count
        let v00 = values[y0 * w + x0], v01 = values[y0 * w + x0 + 1]
        let v10 = values[(y0 + 1) * w + x0], v11 = values[(y0 + 1) * w + x0 + 1]
        let corners = [v00, v01, v10, v11]
        if corners.contains(where: { $0.isNaN }) {
            let valid = corners.filter { !$0.isNaN }
            return valid.isEmpty ? nil : valid.reduce(0, +) / Double(valid.count)
        }
        let top = v00 + (v01 - v00) * tx
        let bottom = v10 + (v11 - v10) * tx
        return top + (bottom - top) * ty
    }
}

enum WeatherGridService {
    static let latStep = 0.3, lonStep = 0.6

    static func iceland() async throws -> Fetched<WeatherGrid> {
        let lats = Array(stride(from: WeatherGrid.south, through: WeatherGrid.north + 0.001, by: latStep))
        let lons = Array(stride(from: WeatherGrid.west, through: WeatherGrid.east + 0.001, by: lonStep))
        var points: [Coordinate] = []
        for lat in lats { for lon in lons { points.append(Coordinate(lat: lat, lon: lon)) } }

        var forecasts: [Forecast?] = Array(repeating: nil, count: points.count)
        var newestDate = Date.distantPast
        var stale = false
        for start in stride(from: 0, to: points.count, by: 100) {
            let chunk = Array(points[start..<min(start + 100, points.count)])
            let url = try HTTP.url("https://api.open-meteo.com/v1/forecast", [
                "latitude": chunk.map { String(format: "%.2f", $0.lat) }.joined(separator: ","),
                "longitude": chunk.map { String(format: "%.2f", $0.lon) }.joined(separator: ","),
                "hourly": "temperature_2m,precipitation,snowfall,cloud_cover,wind_speed_10m,wind_direction_10m,wind_gusts_10m",
                "wind_speed_unit": "ms",
                "forecast_hours": "48",
                "timeformat": "unixtime",
                "timezone": "GMT",
            ])
            let fetched = try await HTTP.get(url, cacheKey: "grid_iceland_\(start)")
            newestDate = max(newestDate, fetched.date)
            stale = stale || fetched.isStale
            let decoded = try RouteWeather.decodeMany(fetched.value)
            for (i, forecast) in decoded.enumerated() where start + i < forecasts.count {
                forecasts[start + i] = forecast
            }
        }
        let grid = build(lats: lats, lons: lons, forecasts: forecasts)
        return Fetched(value: grid, date: newestDate, isStale: stale)
    }

    static func build(lats: [Double], lons: [Double], forecasts: [Forecast?]) -> WeatherGrid {
        let reference = forecasts.compactMap { $0?.hourly?.time }.max { $0.count < $1.count } ?? []
        let times = reference.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let cells = lats.count * lons.count
        func field(_ pick: (Forecast.Hourly) -> [Double?]?) -> [[Double]] {
            (0..<times.count).map { h in
                (0..<cells).map { idx in
                    guard idx < forecasts.count, let hourly = forecasts[idx]?.hourly,
                          let array = pick(hourly), array.indices.contains(h), let v = array[h] else { return .nan }
                    return v
                }
            }
        }
        let fields: [WeatherLayer: [[Double]]] = [
            .temperature: field { $0.temperature_2m },
            .precipitation: field { $0.precipitation },
            .snow: field { $0.snowfall },
            .cloud: field { $0.cloud_cover },
            .wind: field { $0.wind_speed_10m },
            .gust: field { $0.wind_gusts_10m },
        ]
        return WeatherGrid(lats: lats, lons: lons, times: times, fields: fields, windDirection: field { $0.wind_direction_10m })
    }
}

/// RainViewer: free global radar mosaic, past 2 hours in 10-minute frames.
struct RadarFrame: Identifiable, Hashable {
    let time: Date
    let urlTemplate: String
    var id: Date { time }
}

enum RainViewer {
    static func frames() async throws -> [RadarFrame] {
        guard let url = URL(string: "https://api.rainviewer.com/public/weather-maps.json") else { throw HTTPError.invalidURL }
        struct Maps: Decodable {
            struct Radar: Decodable { let past: [Frame]; let nowcast: [Frame]? }
            struct Frame: Decodable { let time: Int; let path: String }
            let host: String
            let radar: Radar
        }
        let maps = try await HTTP.json(Maps.self, from: url, cacheKey: "rainviewer").value
        return (maps.radar.past + (maps.radar.nowcast ?? [])).map {
            RadarFrame(time: Date(timeIntervalSince1970: TimeInterval($0.time)),
                       urlTemplate: "\(maps.host)\($0.path)/256/{z}/{x}/{y}/2/1_1.png")
        }
    }
}
