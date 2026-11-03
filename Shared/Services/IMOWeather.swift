import Foundation

// Veðurstofa Íslands (IMO), xmlweather.vedur.is: the official station forecasts
// and observations, the PRIMARY source of the app's forecast in Iceland
// (docs/IMO.md). What a station forecast gives, for every step: mean wind F
// (m/s), direction D, temperature T (°C), weather W (text), cloud cover N (%),
// precipitation R (mm over the step) and dew point TD. Steps are hourly for
// about 3 days, then 3-hourly, then 6-hourly, about 9–10 days in all (IMO
// changes the blend of models without notice, so the horizon is read from each
// answer). Gusts, cloud layers, chance of rain, visibility and snow amounts are
// not in it: those come from the models (MET Norway, Open-Meteo), never over an
// IMO value.
//
// Terms (vedur.is › Notkunarskilmálar): free use, also commercial, naming the
// source and when the data was downloaded, and keeping clear what is IMO's and
// what is not. The service asks not to poll too often: answers are kept 20
// minutes (forecasts) and 10 minutes (observations) on the phone.

struct StationForecast {
    struct Station: Decodable, Hashable {
        let id: Int
        let name: String
        let lat: Double
        let lon: Double
        /// Height above the sea (m, terrain model at the station), to match places at a similar height.
        var elev: Double?
        /// The IMO text-forecast region the station belongs to (30–39, 3 for the capital area).
        var area: Int?
        var coordinate: Coordinate { Coordinate(lat: lat, lon: lon) }
    }

    struct Hour: Identifiable {
        var id: Date { date }
        let date: Date
        /// Hours since the previous step (1, 3 or 6): precipitation is the amount over it.
        var stepHours: Double = 1
        let wind: Double?
        let direction: String
        let temperature: Double?
        let text: String
        var cloud: Double?
        var precipitation: Double?
        var dewPoint: Double?
        /// WMO weather code for the IMO description (nil when it has none, e.g. dust).
        var code: Int?
        var degrees: Double? { IMOForecast.degrees(direction) }
    }

    let station: Station
    let distanceKm: Double
    let issued: Date?
    let hours: [Hour]
    var link: String?

    /// Last time covered by this forecast.
    var until: Date? { hours.last?.date }
}

/// Which hours of a forecast come from Veðurstofa Íslands, from which station.
struct OfficialForecast {
    let station: StationForecast.Station
    let distanceKm: Double
    let issued: Date?
    /// Last hour of the IMO forecast: after it, the models.
    let until: Date
    var link: String?
    /// The models' values in the hours IMO replaced (for the comparison table), by epoch second.
    var modelTemperature: [Int: Double] = [:]
    var modelWind: [Int: Double] = [:]
    /// The models' precipitation in those hours: the alerts take the higher of the two.
    var modelPrecipitation: [Int: Double] = [:]

    func covers(_ date: Date) -> Bool { date <= until }
}

/// The latest measurement at an IMO station.
struct IMOObservation: Codable, Equatable {
    let stationID: Int
    let station: String
    let distanceKm: Double
    let time: Date
    let wind: Double?
    /// Strongest gust of the last hour (FG), m/s.
    let gust: Double?
    let direction: String
    let temperature: Double?
    let text: String?
    let humidity: Double?
    let pressure: Double?
    let precipitation: Double?
    var link: String?
    /// Strongest 10-minute mean wind of the last hour (FX), m/s.
    var maxWind: Double? = nil
    var dewPoint: Double? = nil
    /// Visibility (V), km — staffed stations only.
    var visibility: Double? = nil
    /// Cloud cover (N), % — staffed stations only.
    var cloud: Double? = nil
    /// Snow depth (SND), cm, and state of the ground (SNC), staffed stations.
    var snowDepth: Double? = nil
    var snowCover: String? = nil
    /// State of the sea (SED), coastal staffed stations.
    var sea: String? = nil
    /// Measured every 10 minutes (api.vedur.is) rather than hourly (xmlweather).
    var tenMinute: Bool? = nil

    var degrees: Double? { IMOForecast.degrees(direction) }
    var age: TimeInterval { Date().timeIntervalSince(time) }
    /// Itself when measured within `seconds`, else nil.
    func flatMapRecent(_ seconds: TimeInterval) -> IMOObservation? { age <= seconds ? self : nil }
}

enum IMOForecast {
    static let attribution = "vedur.is"
    static let sourceName = "vedur.is"

    static func station(_ id: Int) -> StationForecast.Station? { stations.first { $0.id == id } }

    static let stations: [StationForecast.Station] = {
        guard let url = Bundle.main.url(forResource: "imo-stations", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([StationForecast.Station].self, from: data)) ?? []
    }()

    static func nearest(to c: Coordinate) -> (StationForecast.Station, Double)? {
        stations.map { ($0, Geo.distanceKm(c, $0.coordinate)) }.min { $0.1 < $1.1 }
    }

    // MARK: Which station speaks for a place

    /// Stations that may stand for a place, best first. A station is used only
    /// near the place and at a similar height: within 25 km and 200 m of height,
    /// or up to 35 km when the height is within 100 m. Without the place's height
    /// only the distance counts (25 km). Coast and inland differ mostly in height
    /// in Iceland (fjords, valleys, highland plateaus), and the station network is
    /// dense where people travel: past these limits the models are better.
    static func candidates(near c: Coordinate, elevation: Double?, in list: [StationForecast.Station] = stations) -> [(StationForecast.Station, Double)] {
        list.compactMap { s -> (StationForecast.Station, Double, Double)? in
            let km = Geo.distanceKm(c, s.coordinate)
            guard km <= 35 else { return nil }
            if let elevation, let height = s.elev {
                let dh = abs(elevation - height)
                guard (km <= 25 && dh <= 200) || dh <= 100 else { return nil }
                return (s, km, km + dh / 20)
            }
            return km <= 25 ? (s, km, km) : nil
        }
        .sorted { $0.2 < $1.2 }
        .map { ($0.0, $0.1) }
    }

    /// Among fetched station forecasts, the one that may stand for the place.
    static func choose(_ forecasts: [StationForecast], near c: Coordinate, elevation: Double?) -> StationForecast? {
        let order = candidates(near: c, elevation: elevation, in: forecasts.map(\.station))
        for (station, _) in order {
            if let f = forecasts.first(where: { $0.station.id == station.id }), f.hours.count >= 2 { return f }
        }
        return nil
    }

    // MARK: Parsing (xmlweather.vedur.is, view=xml)

    struct RawForecast {
        let id: Int
        let name: String
        let issued: Date?
        let link: String?
        let hours: [StationForecast.Hour]
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Atlantic/Reykjavik")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func date(_ text: String?) -> Date? { text.flatMap { formatter.date(from: $0) } }

    static func tag(_ name: String, in text: Substring) -> String? {
        guard let open = text.range(of: "<\(name)>"), let close = text.range(of: "</\(name)>", range: open.upperBound..<text.endIndex) else { return nil }
        var value = String(text[open.upperBound..<close.lowerBound])
        if value.hasPrefix("<![CDATA["), value.hasSuffix("]]>") { value = String(value.dropFirst(9).dropLast(3)) }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// IMO writes decimals with a comma in some answers ("11,3").
    static func number(_ text: String?) -> Double? {
        guard let text, !text.isEmpty else { return nil }
        return Double(text.replacingOccurrences(of: ",", with: "."))
    }

    static func stationBlocks(_ xml: String) -> [(id: Int, valid: Bool, body: Substring)] {
        var out: [(id: Int, valid: Bool, body: Substring)] = []
        var rest = Substring(xml)
        while let open = rest.range(of: "<station ") {
            guard let headEnd = rest.range(of: ">", range: open.upperBound..<rest.endIndex),
                  let close = rest.range(of: "</station>", range: headEnd.upperBound..<rest.endIndex) else { break }
            let head = rest[open.upperBound..<headEnd.lowerBound]
            let id = head.range(of: "id=\"").flatMap { r in
                head[r.upperBound...].split(separator: "\"").first.flatMap { Int($0) }
            }
            let valid = !head.contains("valid=\"0\"")
            if let id { out.append((id: id, valid: valid, body: rest[headEnd.upperBound..<close.lowerBound])) }
            rest = rest[close.upperBound...]
        }
        return out
    }

    static func parseForecasts(_ xml: String) -> [RawForecast] {
        stationBlocks(xml).filter { $0.valid }.map { block -> RawForecast in
            var hours: [StationForecast.Hour] = []
            var previous: Date?
            for part in block.body.components(separatedBy: "<forecast>").dropFirst() {
                let body = Substring(part)
                guard let time = date(tag("ftime", in: body)) else { continue }
                let step = previous.map { max(1, time.timeIntervalSince($0) / 3600) } ?? 1
                previous = time
                let english = tag("W", in: body) ?? ""
                hours.append(StationForecast.Hour(
                    date: time, stepHours: step, wind: number(tag("F", in: body)), direction: tag("D", in: body) ?? "",
                    temperature: number(tag("T", in: body)), text: translate(english),
                    cloud: number(tag("N", in: body)), precipitation: number(tag("R", in: body)),
                    dewPoint: number(tag("TD", in: body)), code: code(english)))
            }
            return RawForecast(id: block.id, name: tag("name", in: block.body) ?? "", issued: date(tag("atime", in: block.body)),
                               link: tag("link", in: block.body), hours: hours)
        }
    }

    static func parseObservations(_ xml: String, distances: [Int: Double]) -> [IMOObservation] {
        stationBlocks(xml).filter { $0.valid }.compactMap { block -> IMOObservation? in
            guard let time = date(tag("time", in: block.body)) else { return nil }
            let english = tag("W", in: block.body)
            return IMOObservation(
                stationID: block.id, station: tag("name", in: block.body) ?? "", distanceKm: distances[block.id] ?? 0, time: time,
                wind: number(tag("F", in: block.body)), gust: number(tag("FG", in: block.body)), direction: tag("D", in: block.body) ?? "",
                temperature: number(tag("T", in: block.body)), text: english.flatMap { $0.isEmpty ? nil : translate($0) },
                humidity: number(tag("RH", in: block.body)), pressure: number(tag("P", in: block.body)),
                precipitation: number(tag("R", in: block.body)), link: tag("link", in: block.body),
                maxWind: number(tag("FX", in: block.body)), dewPoint: number(tag("TD", in: block.body)),
                visibility: number(tag("V", in: block.body)), cloud: number(tag("N", in: block.body)),
                snowDepth: number(tag("SND", in: block.body)), snowCover: nonEmpty(tag("SNC", in: block.body)),
                sea: nonEmpty(tag("SED", in: block.body)))
        }
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    // MARK: Words

    /// Compass point (English or Icelandic abbreviation) to degrees; nil for calm or unknown.
    static func degrees(_ text: String) -> Double? {
        let points = ["N": 0, "NNE": 22.5, "ENE": 67.5, "NE": 45, "E": 90, "ESE": 112.5, "SE": 135, "SSE": 157.5,
                      "S": 180, "SSW": 202.5, "SW": 225, "WSW": 247.5, "W": 270, "WNW": 292.5, "NW": 315, "NNW": 337.5,
                      "NNA": 22.5, "NA": 45, "ANA": 67.5, "A": 90, "ASA": 112.5, "SA": 135, "SSA": 157.5,
                      "SSV": 202.5, "SV": 225, "VSV": 247.5, "V": 270, "VNV": 292.5, "NV": 315, "NNV": 337.5]
        return points[text.trimmingCharacters(in: .whitespaces).uppercased()]
    }

    /// The IMO weather description (English) as a WMO code used across the app.
    static func code(_ english: String) -> Int? {
        switch english.trimmingCharacters(in: .whitespaces).lowercased() {
        case "clear sky": return 0
        case "partly cloudy": return 1
        case "cloudy": return 2
        case "overcast": return 3
        case "fog": return 45
        case "light drizzle": return 51
        case "drizzle": return 53
        case "freezing drizzle": return 56
        case "light rain": return 61
        case "rain": return 63
        case "heavy rain": return 65
        case "freezing rain": return 66
        case "light sleet", "sleet": return 68
        case "light snow": return 71
        case "snow": return 73
        case "heavy snow": return 75
        case "rain showers", "light rain showers": return 80
        case "sleet showers": return 83
        case "snow showers", "light snow showers": return 85
        case "light thunder", "thunder": return 95
        default: return nil   // dust, blowing snow, hail: the models' code stays
        }
    }

    static func translate(_ text: String) -> String {
        let table: [String: String] = [
            "clear sky": String(localized: "Sereno"), "partly cloudy": String(localized: "Poco nuvoloso"), "cloudy": String(localized: "Nuvoloso"), "overcast": String(localized: "Coperto"),
            "light rain": String(localized: "Pioggia debole"), "rain": String(localized: "Pioggia"), "heavy rain": String(localized: "Pioggia forte"), "drizzle": String(localized: "Pioviggine"),
            "light sleet": String(localized: "Nevischio debole"), "sleet": String(localized: "Nevischio"), "light snow": String(localized: "Neve debole"), "snow": String(localized: "Neve"),
            "heavy snow": String(localized: "Neve forte"), "rain showers": String(localized: "Rovesci"), "light rain showers": String(localized: "Rovesci deboli"),
            "sleet showers": String(localized: "Rovesci di nevischio"), "snow showers": String(localized: "Rovesci di neve"), "light snow showers": String(localized: "Rovesci di neve deboli"),
            "fog": String(localized: "Nebbia"), "dust": String(localized: "Polvere"), "thunder": String(localized: "Temporale"), "freezing rain": String(localized: "Pioggia gelata"),
            "light drizzle": String(localized: "Pioviggine debole"), "freezing drizzle": String(localized: "Pioviggine gelata"),
            "dust devil": String(localized: "Mulinelli di polvere"), "dust storm": String(localized: "Tempesta di polvere"),
            "blowing snow": String(localized: "Neve sollevata dal vento"), "hail": String(localized: "Grandine"), "light thunder": String(localized: "Temporale debole"),
        ]
        return table[text.lowercased()] ?? text
    }
}

/// IMO station steps laid on the hourly grid of the forecast: temperature, wind
/// and cloud interpolated between steps, direction from the nearer step, the
/// weather of the step the hour belongs to, and its precipitation spread over
/// its hours.
enum IMOBlend {
    struct Value: Equatable {
        var temperature: Double?
        var wind: Double?
        var direction: Double?
        var code: Int?
        var cloud: Double?
        /// mm in this hour.
        var precipitation: Double?
    }

    static func values(at times: [Int], steps unsorted: [StationForecast.Hour]) -> [Int: Value] {
        let steps = unsorted.sorted { $0.date < $1.date }
        guard let first = steps.first?.date, let last = steps.last?.date else { return [:] }
        var out: [Int: Value] = [:]
        var j = 0
        for t in times {
            let date = Date(timeIntervalSince1970: TimeInterval(t))
            // The hour before the first step takes its values; nothing past the last.
            guard date >= first.addingTimeInterval(-3600), date <= last else { continue }
            while j + 1 < steps.count, steps[j + 1].date <= date { j += 1 }
            let a = steps[j]
            let b = (a.date < date && j + 1 < steps.count) ? steps[j + 1] : a
            let span = b.date.timeIntervalSince(a.date)
            let x = span > 0 ? date.timeIntervalSince(a.date) / span : 0
            func lerp(_ p: Double?, _ q: Double?) -> Double? {
                guard let p, let q else { return p ?? q }
                return p + (q - p) * x
            }
            let nearer = x < 0.5 ? a : b
            out[t] = Value(temperature: lerp(a.temperature, b.temperature), wind: lerp(a.wind, b.wind),
                           direction: nearer.degrees ?? a.degrees ?? b.degrees, code: b.code,
                           cloud: lerp(a.cloud, b.cloud), precipitation: b.precipitation.map { $0 / max(1, b.stepHours) })
        }
        return out
    }
}
