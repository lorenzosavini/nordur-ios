import Foundation

// Everything else Veðurstofa Íslands publishes for the traveller, besides the
// station forecasts (IMOWeather.swift), the warnings and the quakes (IMO.swift):
//
// - the forecasters' written forecasts (xmlweather.vedur.is, type=txt): the
//   country, the capital area, each of the ten forecast regions, the next days,
//   the general synopsis and the sea areas;
// - the 10-minute measurements of the automatic stations (api.vedur.is/weather);
// - the state of the volcanoes (api.vedur.is/volcanoes): aviation colour code
//   (VONA), alert level (VALS) and the weekly report.
//
// Parsing only (no network), so the engine tests compile it. docs/IMO.md lists
// what is used and what is not.

// MARK: - Written forecasts

struct IMOText: Codable, Identifiable, Equatable {
    let id: Int
    let title: String
    let created: Date?
    let validFrom: Date?
    let validTo: Date?
    var content: String
}

enum IMOTexts {
    /// The ten forecast regions (Miðhálendið, Suðurland … Suðausturland).
    static let regions = Array(30...39)
    /// The sea areas around Iceland (Suðvesturmið … Suðausturmið).
    static let seaAreas = Array(51...59)
    /// Country (2), capital area (3), next days (5, with its summary 6), synopsis (9),
    /// IMO's own English versions (7, 27, 42), the regions and the sea areas: one request.
    static let ids = [2, 3, 5, 6, 7, 9, 27, 42] + regions + seaAreas
    /// IMO writes these in English too: the English one is shown instead of translating.
    static let english: [Int: Int] = [2: 7, 5: 27, 9: 42]
    static let capitalArea = 3

    static func parse(_ xml: String) -> [IMOText] {
        var out: [IMOText] = []
        var rest = Substring(xml)
        while let open = rest.range(of: "<text id=\"") {
            let after = rest[open.upperBound...]
            guard let quote = after.firstIndex(of: "\""), let id = Int(after[..<quote]),
                  let close = after.range(of: "</text>") else { break }
            let body = after[quote..<close.lowerBound]
            rest = after[close.upperBound...]
            let content = clean(IMOForecast.tag("content", in: body) ?? "")
            guard !content.isEmpty else { continue }
            out.append(IMOText(id: id, title: clean(IMOForecast.tag("title", in: body) ?? ""),
                               created: IMOForecast.date(IMOForecast.tag("creation", in: body)),
                               validFrom: IMOForecast.date(IMOForecast.tag("valid_from", in: body)),
                               validTo: IMOForecast.date(IMOForecast.tag("valid_to", in: body)),
                               content: content))
        }
        return out
    }

    /// `<br/>` to line breaks, other tags dropped, entities decoded, spaces tidied.
    static func clean(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, char) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&nbsp;": " "] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        let lines = s.components(separatedBy: "\n").map {
            $0.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        }
        // At most one empty line in a row.
        var out: [String] = []
        for line in lines where !(line.isEmpty && (out.last?.isEmpty ?? true)) { out.append(line) }
        while out.last?.isEmpty == true { out.removeLast() }
        return out.joined(separator: "\n")
    }

    /// The forecast region of a place: that of the nearest IMO station (within 60 km).
    static func region(near c: Coordinate, stations: [StationForecast.Station]) -> Int? {
        stations.filter { $0.area != nil }
            .map { ($0, Geo.distanceKm(c, $0.coordinate)) }
            .filter { $0.1 <= 60 }
            .min { $0.1 < $1.1 }?.0.area
    }
}

// MARK: - 10-minute measurements (api.vedur.is/weather/observations/aws/10min/latest)

enum IMOAutomatic {
    struct Reading: Decodable {
        let station: Int
        let name: String?
        let time: String
        let t: Double?
        let f: Double?
        let fg: Double?
        let d: Double?
        let d_txt: String?
        let rh: Double?
        let td: Double?
        let p: Double?
        let r: Double?
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    static func parse(_ data: Data, distances: [Int: Double]) -> [IMOObservation] {
        guard let readings = try? JSONDecoder().decode([Reading].self, from: data) else { return [] }
        return readings.compactMap { r in
            guard let time = formatter.date(from: String(r.time.prefix(19))) else { return nil }
            return IMOObservation(stationID: r.station, station: r.name ?? "", distanceKm: distances[r.station] ?? 0, time: time,
                                  wind: r.f, gust: r.fg, direction: r.d_txt ?? "", temperature: r.t, text: nil,
                                  humidity: r.rh, pressure: r.p, precipitation: r.r, link: nil,
                                  dewPoint: r.td, tenMinute: true)
        }
    }

    /// One station's hourly report (xmlweather: rain, visibility, cloud, snow, sea…)
    /// and its latest 10-minute measurement: the newer wind, gust, temperature,
    /// humidity, dew point and pressure, the rest from the hourly report.
    static func merge(hourly: IMOObservation?, tenMinute: IMOObservation?) -> IMOObservation? {
        guard let ten = tenMinute, ten.wind != nil || ten.temperature != nil else { return hourly }
        guard let h = hourly else { return ten }
        guard ten.time > h.time else { return h }
        var out = IMOObservation(stationID: h.stationID, station: h.station.isEmpty ? ten.station : h.station, distanceKm: h.distanceKm,
                                 time: ten.time, wind: ten.wind ?? h.wind, gust: ten.gust ?? h.gust,
                                 direction: ten.direction.isEmpty ? h.direction : ten.direction,
                                 temperature: ten.temperature ?? h.temperature, text: h.text,
                                 humidity: ten.humidity ?? h.humidity, pressure: ten.pressure ?? h.pressure,
                                 precipitation: h.precipitation, link: h.link)
        out.maxWind = h.maxWind
        out.dewPoint = ten.dewPoint ?? h.dewPoint
        out.visibility = h.visibility
        out.cloud = h.cloud
        out.snowDepth = h.snowDepth
        out.snowCover = h.snowCover
        out.sea = h.sea
        out.tenMinute = true
        return out
    }

    /// Relative humidity (%) from temperature and dew point (Magnus formula).
    static func humidity(temperature t: Double, dewPoint td: Double) -> Double {
        let a = 17.625, b = 243.04
        return min(100, max(0, 100 * exp(a * td / (b + td)) / exp(a * t / (b + t))))
    }
}

// MARK: - Volcanoes (api.vedur.is/volcanoes)

struct Volcano: Codable, Identifiable, Equatable {
    var id: String { code }
    let code: String
    let name: String
    let lat: Double
    let lon: Double
    let height: Double?
    let zone: String?
    /// Aviation colour code (VONA): GREEN, YELLOW, ORANGE, RED.
    let aviation: String?
    let aviationSince: Date?
    var aviationText: String?
    /// IMO alert level (VALS): 0 green, 1 yellow, 2 orange, 3 red.
    let level: Int?
    let levelSince: Date?
    var levelText: String?
    /// The volcano's line in the latest weekly report, when it has one.
    var report: String?

    var coordinate: Coordinate { Coordinate(lat: lat, lon: lon) }

    /// 0 green … 3 red: the higher of the two codes.
    var severity: Int {
        let colour = ["GREEN": 0, "YELLOW": 1, "ORANGE": 2, "RED": 3][aviation?.uppercased() ?? ""] ?? 0
        return max(colour, level ?? 0)
    }
}

struct VolcanoStatus: Codable {
    var volcanoes: [Volcano]
    /// The latest weekly report on Iceland's volcanoes.
    var reportDate: Date?
    var reportNotes: String?
    var updated: Date?

    /// Volcanoes above green first, then by name.
    var sorted: [Volcano] {
        volcanoes.sorted { $0.severity != $1.severity ? $0.severity > $1.severity : $0.name < $1.name }
    }
}

enum VolcanoParse {
    private struct Raw: Decodable {
        struct Country: Decodable { let iso_code: String? }
        struct Zone: Decodable { let name_en: String? }
        struct Point: Decodable { let coordinates: [Double] }
        struct Colour: Decodable { let code: String?; let description_en: String? }
        struct Level: Decodable { let level: Int?; let description_en: String? }
        struct Vona: Decodable { let published_at: String?; let aviation_color: Colour? }
        struct Vals: Decodable { let published_at: String?; let alert_level_info: Level? }
        struct Current<T: Decodable>: Decodable { let current: T? }
        let code: String
        let name: String
        let country: Country?
        let zone: Zone?
        let height: Double?
        let geom_point: Point?
        let vona: Current<Vona>?
        let vals: Current<Vals>?
    }

    private struct Weekly: Decodable {
        struct Entry: Decodable { let volcano_code: String; let status_text: String? }
        let id: Int
        let published_at: String?
        let entries: [Entry]?
        let additional_notes: String?
    }

    /// The `/volcanoes` list of api.vedur.is: Iceland's volcanoes with their current codes.
    static func volcanoes(_ data: Data) -> [Volcano] {
        guard let raw = try? JSONDecoder().decode([Raw].self, from: data) else { return [] }
        return raw.compactMap { v in
            guard v.country?.iso_code == "IS", let c = v.geom_point?.coordinates, c.count >= 2 else { return nil }
            let vona = v.vona?.current, vals = v.vals?.current
            return Volcano(code: v.code, name: v.name, lat: c[1], lon: c[0], height: v.height, zone: v.zone?.name_en,
                           aviation: vona?.aviation_color?.code, aviationSince: DateParse.iso(vona?.published_at),
                           aviationText: vona?.aviation_color?.description_en,
                           level: vals?.alert_level_info?.level, levelSince: DateParse.iso(vals?.published_at),
                           levelText: vals?.alert_level_info?.description_en, report: nil)
        }
    }

    /// The latest weekly report (`/vwr`): its date, notes and one line per volcano.
    static func weekly(_ data: Data) -> (date: Date?, notes: String?, lines: [String: String])? {
        guard let all = try? JSONDecoder().decode([Weekly].self, from: data), let last = all.max(by: { $0.id < $1.id }) else { return nil }
        var lines: [String: String] = [:]
        for e in last.entries ?? [] {
            if let t = e.status_text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { lines[e.volcano_code] = t }
        }
        let notes = last.additional_notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (DateParse.iso(last.published_at), notes?.isEmpty == false ? notes : nil, lines)
    }
}
