import Foundation

// Forecast pipeline.
//
// Primary: MET Norway Locationforecast 2.0 (api.met.no), the operational
// MEPS/HARMONIE model run with the Icelandic Met Office — the same model behind
// yr.no and the Nordic forecasting centres. Open-Meteo fills what MET does not
// publish for Iceland (gusts, CAPE, visibility) and the days after MET's range,
// and is the fallback if MET is unreachable.
// Cross-check: the official hourly station forecast of Veðurstofa Íslands.

enum WeatherService {
    static func forecast(_ c: Coordinate) async throws -> Fetched<Forecast> {
        async let met = attempt { try await METNorway.forecast(c) }
        async let om = attempt { try await OpenMeteo.forecast(c) }
        let (metResult, omResult) = await (met, om)

        switch (metResult, omResult) {
        case (.success(let m), .success(let o)):
            return Fetched(value: merge(met: m.value, base: o.value, at: c),
                           date: min(m.date, o.date), isStale: m.isStale || o.isStale)
        case (.success(let m), .failure):
            return Fetched(value: metOnly(m.value, at: c), date: m.date, isStale: m.isStale)
        case (.failure, .success(let o)):
            return o
        case (.failure(let e), .failure):
            throw e
        }
    }

    // MARK: Merge

    private static func merge(met: METResponse, base: Forecast, at c: Coordinate) -> Forecast {
        let entries = Dictionary(met.properties.timeseries.map { (Int($0.time.timeIntervalSince1970), $0) }, uniquingKeysWith: { a, _ in a })
        guard let h = base.hourly else { return metOnly(met, at: c) }

        let n = h.time.count
        var temp = h.temperature_2m ?? Array(repeating: nil, count: n)
        var apparent = h.apparent_temperature ?? Array(repeating: nil, count: n)
        var prob = h.precipitation_probability ?? Array(repeating: nil, count: n)
        var precip = h.precipitation ?? Array(repeating: nil, count: n)
        var code = h.weather_code ?? Array(repeating: nil, count: n)
        var cloud = h.cloud_cover ?? Array(repeating: nil, count: n)
        var low = h.cloud_cover_low ?? Array(repeating: nil, count: n)
        var mid = h.cloud_cover_mid ?? Array(repeating: nil, count: n)
        var high = h.cloud_cover_high ?? Array(repeating: nil, count: n)
        var fog: [Double?] = Array(repeating: nil, count: n)
        var wind = h.wind_speed_10m ?? Array(repeating: nil, count: n)
        var dir = h.wind_direction_10m ?? Array(repeating: nil, count: n)
        var gust = h.wind_gusts_10m ?? Array(repeating: nil, count: n)

        var lastMET = 0
        for (i, t) in h.time.enumerated() {
            guard let e = entries[t], let next1 = e.data.next_1_hours else { continue }
            let d = e.data.instant.details
            lastMET = max(lastMET, t)
            temp[i] = d.air_temperature ?? temp[i]
            apparent[i] = d.apparent_air_temperature ?? apparent[i]
            cloud[i] = d.cloud_area_fraction ?? cloud[i]
            low[i] = d.cloud_area_fraction_low ?? low[i]
            mid[i] = d.cloud_area_fraction_medium ?? mid[i]
            high[i] = d.cloud_area_fraction_high ?? high[i]
            fog[i] = d.fog_area_fraction
            wind[i] = d.wind_speed ?? wind[i]
            dir[i] = d.wind_from_direction ?? dir[i]
            if let g = d.wind_speed_of_gust { gust[i] = g }
            // A gust can never be lower than the mean wind.
            if let w = wind[i], let g = gust[i], g < w { gust[i] = w }
            precip[i] = next1.details?.precipitation_amount ?? precip[i]
            prob[i] = next1.details?.probability_of_precipitation ?? prob[i]
            code[i] = METSymbol.code(next1.summary.symbol_code) ?? code[i]
            if let thunder = next1.details?.probability_of_thunder, thunder >= 30 { code[i] = 95 }
        }

        let hourly = Forecast.Hourly(
            time: h.time, temperature_2m: temp, apparent_temperature: apparent, precipitation_probability: prob,
            precipitation: precip, snowfall: h.snowfall, weather_code: code, cloud_cover: cloud, visibility: h.visibility,
            wind_speed_10m: wind, wind_direction_10m: dir, wind_gusts_10m: gust, cape: h.cape, is_day: h.is_day,
            cloud_cover_low: low, cloud_cover_mid: mid, cloud_cover_high: high, fog_area_fraction: fog)

        var current = base.current
        if let first = met.properties.timeseries.first(where: { $0.time.addingTimeInterval(3600) > Date() }) {
            let d = first.data.instant.details
            let o = base.current
            current = Forecast.Current(
                time: Int(first.time.timeIntervalSince1970),
                temperature_2m: d.air_temperature ?? o?.temperature_2m,
                apparent_temperature: d.apparent_air_temperature ?? o?.apparent_temperature,
                relative_humidity_2m: d.relative_humidity ?? o?.relative_humidity_2m,
                precipitation: first.data.next_1_hours?.details?.precipitation_amount ?? o?.precipitation,
                snowfall: o?.snowfall,
                weather_code: METSymbol.code(first.data.next_1_hours?.summary.symbol_code) ?? o?.weather_code,
                cloud_cover: d.cloud_area_fraction ?? o?.cloud_cover,
                pressure_msl: d.air_pressure_at_sea_level ?? o?.pressure_msl,
                wind_speed_10m: d.wind_speed ?? o?.wind_speed_10m,
                wind_direction_10m: d.wind_from_direction ?? o?.wind_direction_10m,
                wind_gusts_10m: max(o?.wind_gusts_10m ?? 0, d.wind_speed ?? 0),
                is_day: o?.is_day ?? (Solar.isDay(Date(), at: c) ? 1 : 0))
        }

        let tenDays = trimmed(hourly, days: base.daily, limitDays: 10)
        var merged = Forecast(latitude: base.latitude, longitude: base.longitude, timezone: base.timezone,
                              utc_offset_seconds: base.utc_offset_seconds, current: current,
                              hourly: tenDays.hourly, daily: nil)
        merged.daily = recomputedDaily(base: tenDays.daily, from: merged)
        merged.sources = lastMET > 0 ? ["MET Norway", "Open-Meteo"] : ["Open-Meteo"]
        merged.primaryUntil = lastMET > 0 ? Date(timeIntervalSince1970: TimeInterval(lastMET)) : nil
        return merged
    }

    /// Keeps the first `limitDays` days: past that, no model is useful for planning.
    private static func trimmed(_ h: Forecast.Hourly, days: Forecast.Daily?, limitDays: Int) -> (hourly: Forecast.Hourly, daily: Forecast.Daily?) {
        let cutoff = Int(Date().addingTimeInterval(TimeInterval(limitDays) * 86400).timeIntervalSince1970)
        let n = h.time.firstIndex { $0 > cutoff } ?? h.time.count
        func cut<T>(_ a: [T?]?) -> [T?]? { a.map { Array($0.prefix(n)) } }
        let hourly = Forecast.Hourly(
            time: Array(h.time.prefix(n)), temperature_2m: cut(h.temperature_2m), apparent_temperature: cut(h.apparent_temperature),
            precipitation_probability: cut(h.precipitation_probability), precipitation: cut(h.precipitation), snowfall: cut(h.snowfall),
            weather_code: cut(h.weather_code), cloud_cover: cut(h.cloud_cover), visibility: cut(h.visibility),
            wind_speed_10m: cut(h.wind_speed_10m), wind_direction_10m: cut(h.wind_direction_10m), wind_gusts_10m: cut(h.wind_gusts_10m),
            cape: cut(h.cape), is_day: cut(h.is_day),
            cloud_cover_low: cut(h.cloud_cover_low), cloud_cover_mid: cut(h.cloud_cover_mid),
            cloud_cover_high: cut(h.cloud_cover_high), fog_area_fraction: cut(h.fog_area_fraction))
        guard let d = days else { return (hourly, nil) }
        let m = min(limitDays, d.time.count)
        func cutD<T>(_ a: [T?]?) -> [T?]? { a.map { Array($0.prefix(m)) } }
        let daily = Forecast.Daily(
            time: Array(d.time.prefix(m)), weather_code: cutD(d.weather_code), temperature_2m_max: cutD(d.temperature_2m_max),
            temperature_2m_min: cutD(d.temperature_2m_min), precipitation_sum: cutD(d.precipitation_sum), snowfall_sum: cutD(d.snowfall_sum),
            precipitation_probability_max: cutD(d.precipitation_probability_max), wind_speed_10m_max: cutD(d.wind_speed_10m_max),
            wind_gusts_10m_max: cutD(d.wind_gusts_10m_max), wind_direction_10m_dominant: cutD(d.wind_direction_10m_dominant),
            sunrise: cutD(d.sunrise), sunset: cutD(d.sunset), daylight_duration: cutD(d.daylight_duration))
        return (hourly, daily)
    }

    /// Daily rows rebuilt from the merged hourly series, so the days agree with the hours.
    private static func recomputedDaily(base: Forecast.Daily?, from f: Forecast) -> Forecast.Daily? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = f.timeZone
        let hours = f.hours
        let groups = Dictionary(grouping: hours) { calendar.startOfDay(for: $0.date) }
        let dayStarts: [Date]
        if let base { dayStarts = base.time.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
        else { dayStarts = groups.keys.sorted() }

        var maxT: [Double?] = [], minT: [Double?] = [], sum: [Double?] = [], maxW: [Double?] = [], maxG: [Double?] = []
        var codes: [Int?] = [], probs: [Double?] = [], rises: [Int?] = [], sets: [Int?] = [], light: [Double?] = [], dirs: [Double?] = []
        for (i, start) in dayStarts.enumerated() {
            let day = groups[calendar.startOfDay(for: start)] ?? []
            let full = day.count >= 20
            func pick<T>(_ computed: T?, _ fallback: [T?]?) -> T? { full ? (computed ?? fallback.at(i)) : (fallback.at(i) ?? computed) }
            maxT.append(pick(day.compactMap(\.temperature).max(), base?.temperature_2m_max))
            minT.append(pick(day.compactMap(\.temperature).min(), base?.temperature_2m_min))
            sum.append(pick(day.isEmpty ? nil : day.compactMap(\.precipitation).reduce(0, +), base?.precipitation_sum))
            maxW.append(pick(day.compactMap(\.wind).max(), base?.wind_speed_10m_max))
            maxG.append(pick(day.compactMap(\.gust).max(), base?.wind_gusts_10m_max))
            probs.append(pick(day.compactMap(\.precipitationProbability).max(), base?.precipitation_probability_max))
            codes.append(pick(dominantCode(day), base?.weather_code))
            dirs.append((base?.wind_direction_10m_dominant).at(i) ?? day.compactMap(\.windDirection).first)
            let sun = Solar.sunriseSunset(on: start, at: Coordinate(lat: f.latitude, lon: f.longitude), calendar: calendar)
            rises.append((base?.sunrise).at(i) ?? sun.rise.map { Int($0.timeIntervalSince1970) })
            sets.append((base?.sunset).at(i) ?? sun.set.map { Int($0.timeIntervalSince1970) })
            light.append((base?.daylight_duration).at(i) ?? {
                guard let r = sun.rise, let s = sun.set else { return nil }
                return s.timeIntervalSince(r)
            }())
        }
        return Forecast.Daily(
            time: dayStarts.map { Int($0.timeIntervalSince1970) }, weather_code: codes, temperature_2m_max: maxT, temperature_2m_min: minT,
            precipitation_sum: sum, snowfall_sum: base?.snowfall_sum, precipitation_probability_max: probs, wind_speed_10m_max: maxW,
            wind_gusts_10m_max: maxG, wind_direction_10m_dominant: dirs, sunrise: rises, sunset: sets, daylight_duration: light)
    }

    /// The most significant weather of the daytime hours.
    private static func dominantCode(_ hours: [HourPoint]) -> Int? {
        let daytime = hours.filter { (8...20).contains(Calendar.current.component(.hour, from: $0.date)) }
        let codes = (daytime.isEmpty ? hours : daytime).compactMap(\.code)
        guard !codes.isEmpty else { return nil }
        if let storm = codes.first(where: { $0 >= 95 }) { return storm }
        let wet = codes.filter { $0 >= 51 }
        if wet.count >= 3 { return Dictionary(grouping: wet, by: { $0 }).max { $0.value.count < $1.value.count }?.key }
        return Dictionary(grouping: codes, by: { $0 }).max { $0.value.count < $1.value.count }?.key
    }

    // MARK: MET only (Open-Meteo unreachable)

    private static func metOnly(_ met: METResponse, at c: Coordinate) -> Forecast {
        let series = met.properties.timeseries
        let time = series.map { Int($0.time.timeIntervalSince1970) }
        func instant(_ k: KeyPath<METResponse.Details, Double?>) -> [Double?] { series.map { $0.data.instant.details[keyPath: k] } }
        let block: (METResponse.Entry) -> METResponse.Period? = { $0.data.next_1_hours ?? $0.data.next_6_hours }
        let hourly = Forecast.Hourly(
            time: time, temperature_2m: instant(\.air_temperature), apparent_temperature: instant(\.apparent_air_temperature),
            precipitation_probability: series.map { block($0)?.details?.probability_of_precipitation },
            precipitation: series.map { e in
                if let one = e.data.next_1_hours?.details?.precipitation_amount { return one }
                return e.data.next_6_hours?.details?.precipitation_amount.map { $0 / 6 }
            },
            snowfall: nil, weather_code: series.map { METSymbol.code(block($0)?.summary.symbol_code) },
            cloud_cover: instant(\.cloud_area_fraction), visibility: nil, wind_speed_10m: instant(\.wind_speed),
            wind_direction_10m: instant(\.wind_from_direction), wind_gusts_10m: instant(\.wind_speed_of_gust), cape: nil,
            is_day: series.map { Solar.isDay($0.time, at: c) ? 1 : 0 },
            cloud_cover_low: instant(\.cloud_area_fraction_low), cloud_cover_mid: instant(\.cloud_area_fraction_medium),
            cloud_cover_high: instant(\.cloud_area_fraction_high), fog_area_fraction: instant(\.fog_area_fraction))
        let first = series.first { $0.time.addingTimeInterval(3600) > Date() } ?? series.first
        let d = first?.data.instant.details
        let current = first.map { f in
            Forecast.Current(
                time: Int(f.time.timeIntervalSince1970), temperature_2m: d?.air_temperature, apparent_temperature: d?.apparent_air_temperature,
                relative_humidity_2m: d?.relative_humidity, precipitation: f.data.next_1_hours?.details?.precipitation_amount, snowfall: nil,
                weather_code: METSymbol.code(f.data.next_1_hours?.summary.symbol_code), cloud_cover: d?.cloud_area_fraction,
                pressure_msl: d?.air_pressure_at_sea_level, wind_speed_10m: d?.wind_speed, wind_direction_10m: d?.wind_from_direction,
                wind_gusts_10m: d?.wind_speed_of_gust, is_day: Solar.isDay(Date(), at: c) ? 1 : 0)
        }
        let zone = TimeZone(identifier: "Atlantic/Reykjavik") ?? .gmt
        var f = Forecast(latitude: c.lat, longitude: c.lon, timezone: zone.identifier, utc_offset_seconds: zone.secondsFromGMT(),
                         current: current, hourly: hourly, daily: nil)
        f.daily = recomputedDaily(base: nil, from: f)
        f.sources = ["MET Norway"]
        f.primaryUntil = series.last?.time
        return f
    }
}

private extension Optional {
    func at<T>(_ i: Int) -> T? where Wrapped == [T?] {
        guard let a = self, a.indices.contains(i) else { return nil }
        return a[i]
    }
}

// MARK: - MET Norway

struct METResponse: Decodable {
    let properties: Properties

    struct Properties: Decodable {
        let meta: Meta
        let timeseries: [Entry]
    }

    struct Meta: Decodable { let updated_at: Date }

    struct Entry: Decodable {
        let time: Date
        let data: Payload
    }

    struct Payload: Decodable {
        let instant: Instant
        let next_1_hours: Period?
        let next_6_hours: Period?
    }

    struct Instant: Decodable { let details: Details }

    struct Details: Decodable {
        let air_temperature: Double?
        let apparent_air_temperature: Double?
        let air_pressure_at_sea_level: Double?
        let cloud_area_fraction: Double?
        let cloud_area_fraction_low: Double?
        let cloud_area_fraction_medium: Double?
        let cloud_area_fraction_high: Double?
        let relative_humidity: Double?
        let wind_from_direction: Double?
        let wind_speed: Double?
        let wind_speed_of_gust: Double?
        let fog_area_fraction: Double?
    }

    struct Period: Decodable {
        let summary: Summary
        let details: PeriodDetails?
    }

    struct Summary: Decodable { let symbol_code: String }

    struct PeriodDetails: Decodable {
        let precipitation_amount: Double?
        let probability_of_precipitation: Double?
        let probability_of_thunder: Double?
        let air_temperature_max: Double?
        let air_temperature_min: Double?
    }
}

enum METNorway {
    static func forecast(_ c: Coordinate) async throws -> Fetched<METResponse> {
        // MET asks for at most 4 decimals so responses can be cached.
        let url = try HTTP.url("https://api.met.no/weatherapi/locationforecast/2.0/complete", [
            "lat": String(format: "%.4f", c.lat),
            "lon": String(format: "%.4f", c.lon),
        ])
        let fetched = try await HTTP.get(url, cacheKey: "met_\(c.key)")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try fetched.map { try decoder.decode(METResponse.self, from: $0) }
    }
}

/// MET Norway symbol codes → WMO weather codes used across the app.
enum METSymbol {
    static func code(_ symbol: String?) -> Int? {
        guard let symbol else { return nil }
        let base = symbol.replacingOccurrences(of: "_day", with: "")
            .replacingOccurrences(of: "_night", with: "")
            .replacingOccurrences(of: "_polartwilight", with: "")
        if base.contains("thunder") { return 95 }
        switch base {
        case "clearsky": return 0
        case "fair": return 1
        case "partlycloudy": return 2
        case "cloudy": return 3
        case "fog": return 45
        case "lightrain": return 61
        case "rain": return 63
        case "heavyrain": return 65
        case "lightrainshowers", "rainshowers": return 80
        case "heavyrainshowers": return 82
        case "lightsleet", "sleet", "heavysleet": return 68
        case "lightsleetshowers", "sleetshowers", "heavysleetshowers": return 83
        case "lightsnow": return 71
        case "snow": return 73
        case "heavysnow": return 75
        case "lightsnowshowers", "snowshowers": return 85
        case "heavysnowshowers": return 86
        default: return nil
        }
    }
}

// MARK: - Sun position (NOAA approximation)

enum Solar {
    /// Solar elevation in degrees.
    static func elevation(_ date: Date, at c: Coordinate) -> Double {
        let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
        let n = jd - 2451545.0
        let L = (280.460 + 0.9856474 * n).truncatingRemainder(dividingBy: 360)
        let g = (357.528 + 0.9856003 * n).truncatingRemainder(dividingBy: 360) * .pi / 180
        let lambda = (L + 1.915 * sin(g) + 0.020 * sin(2 * g)) * .pi / 180
        let epsilon = (23.439 - 0.0000004 * n) * .pi / 180
        let decl = asin(sin(epsilon) * sin(lambda))
        let ra = atan2(cos(epsilon) * sin(lambda), cos(lambda))
        let gmst = (18.697374558 + 24.06570982441908 * n).truncatingRemainder(dividingBy: 24)
        let hourAngle = (gmst * 15 + c.lon) * .pi / 180 - ra
        let lat = c.lat * .pi / 180
        return asin(sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(hourAngle)) * 180 / .pi
    }

    static func isDay(_ date: Date, at c: Coordinate) -> Bool { elevation(date, at: c) > -0.833 }

    /// Sunrise and sunset on the local day starting at `day`; nil during polar day or night.
    static func sunriseSunset(on day: Date, at c: Coordinate, calendar: Calendar) -> (rise: Date?, set: Date?) {
        let start = calendar.startOfDay(for: day)
        var rise: Date?, set: Date?
        var previous = elevation(start, at: c) + 0.833
        for minute in stride(from: 10, through: 1440, by: 10) {
            let t = start.addingTimeInterval(TimeInterval(minute) * 60)
            let value = elevation(t, at: c) + 0.833
            if previous <= 0, value > 0, rise == nil { rise = t.addingTimeInterval(-600 * value / (value - previous)) }
            if previous > 0, value <= 0, set == nil { set = t.addingTimeInterval(-600 * value / (value - previous)) }
            previous = value
        }
        return (rise, set)
    }
}

// MARK: - Official IMO station forecast

struct StationForecast {
    struct Station: Decodable, Hashable {
        let id: Int
        let name: String
        let lat: Double
        let lon: Double
        var coordinate: Coordinate { Coordinate(lat: lat, lon: lon) }
    }

    struct Hour: Identifiable {
        var id: Date { date }
        let date: Date
        let wind: Double?
        let direction: String
        let temperature: Double?
        let text: String
    }

    let station: Station
    let distanceKm: Double
    let issued: Date?
    let hours: [Hour]
}

enum IMOForecast {
    static let stations: [StationForecast.Station] = {
        guard let url = Bundle.main.url(forResource: "imo-stations", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([StationForecast.Station].self, from: data)) ?? []
    }()

    static func nearest(to c: Coordinate) -> (StationForecast.Station, Double)? {
        stations.map { ($0, Geo.distanceKm(c, $0.coordinate)) }.min { $0.1 < $1.1 }
    }

    static func forecast(near c: Coordinate) async throws -> Fetched<StationForecast>? {
        guard let (station, km) = nearest(to: c), km <= 60 else { return nil }
        let url = try HTTP.url("https://xmlweather.vedur.is/", [
            "op_w": "xml", "type": "forec", "lang": "en", "view": "xml", "ids": String(station.id),
        ])
        let fetched = try await HTTP.get(url, cacheKey: "imo_forec_\(station.id)")
        return fetched.map { parse(String(decoding: $0, as: UTF8.self), station: station, km: km) }
    }

    static func parse(_ xml: String, station: StationForecast.Station, km: Double) -> StationForecast {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Atlantic/Reykjavik")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        func tag(_ name: String, in text: Substring) -> String? {
            guard let open = text.range(of: "<\(name)>"), let close = text.range(of: "</\(name)>", range: open.upperBound..<text.endIndex) else { return nil }
            return String(text[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        var hours: [StationForecast.Hour] = []
        for block in xml.components(separatedBy: "<forecast>").dropFirst() {
            let body = Substring(block)
            guard let time = tag("ftime", in: body).flatMap(formatter.date(from:)) else { continue }
            hours.append(.init(date: time, wind: tag("F", in: body).flatMap(Double.init), direction: tag("D", in: body) ?? "",
                               temperature: tag("T", in: body).flatMap(Double.init), text: translate(tag("W", in: body) ?? "")))
        }
        let issued = tag("atime", in: Substring(xml)).flatMap(formatter.date(from:))
        return StationForecast(station: station, distanceKm: km, issued: issued, hours: hours)
    }

    static func translate(_ text: String) -> String {
        let table: [String: String] = [
            "clear sky": String(localized: "Sereno"), "partly cloudy": String(localized: "Poco nuvoloso"), "cloudy": String(localized: "Nuvoloso"), "overcast": String(localized: "Coperto"),
            "light rain": String(localized: "Pioggia debole"), "rain": String(localized: "Pioggia"), "heavy rain": String(localized: "Pioggia forte"), "drizzle": String(localized: "Pioviggine"),
            "light sleet": String(localized: "Nevischio debole"), "sleet": String(localized: "Nevischio"), "light snow": String(localized: "Neve debole"), "snow": String(localized: "Neve"),
            "heavy snow": String(localized: "Neve forte"), "rain showers": String(localized: "Rovesci"), "light rain showers": String(localized: "Rovesci deboli"),
            "sleet showers": String(localized: "Rovesci di nevischio"), "snow showers": String(localized: "Rovesci di neve"), "light snow showers": String(localized: "Deboli rovesci di neve"),
            "fog": String(localized: "Nebbia"), "dust": String(localized: "Polvere"), "thunder": String(localized: "Temporale"), "freezing rain": String(localized: "Pioggia gelata"),
            "light drizzle": String(localized: "Pioviggine debole"), "freezing drizzle": String(localized: "Pioviggine gelata"),
        ]
        return table[text.lowercased()] ?? text
    }
}
