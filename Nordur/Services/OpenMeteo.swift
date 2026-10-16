import Foundation

// Open-Meteo (open-meteo.com): free global forecasts blending the best national
// models (incl. the Icelandic/Nordic HARMONIE and ECMWF), plus marine and air
// quality (CAMS) APIs. No API key needed.

struct Forecast: Decodable {
    let latitude: Double
    let longitude: Double
    let timezone: String
    let utc_offset_seconds: Int
    let current: Current?
    let hourly: Hourly?
    let daily: Daily?

    struct Current: Decodable {
        let time: Int
        let temperature_2m: Double?
        let apparent_temperature: Double?
        let relative_humidity_2m: Double?
        let precipitation: Double?
        let snowfall: Double?
        let weather_code: Int?
        let cloud_cover: Double?
        let pressure_msl: Double?
        let wind_speed_10m: Double?
        let wind_direction_10m: Double?
        let wind_gusts_10m: Double?
        let is_day: Int?
    }

    struct Hourly: Decodable {
        let time: [Int]
        let temperature_2m: [Double?]?
        let apparent_temperature: [Double?]?
        let precipitation_probability: [Double?]?
        let precipitation: [Double?]?
        let snowfall: [Double?]?
        let weather_code: [Int?]?
        let cloud_cover: [Double?]?
        let visibility: [Double?]?
        let wind_speed_10m: [Double?]?
        let wind_direction_10m: [Double?]?
        let wind_gusts_10m: [Double?]?
        let cape: [Double?]?
        let is_day: [Int?]?
    }

    struct Daily: Decodable {
        let time: [Int]
        let weather_code: [Int?]?
        let temperature_2m_max: [Double?]?
        let temperature_2m_min: [Double?]?
        let precipitation_sum: [Double?]?
        let snowfall_sum: [Double?]?
        let precipitation_probability_max: [Double?]?
        let wind_speed_10m_max: [Double?]?
        let wind_gusts_10m_max: [Double?]?
        let wind_direction_10m_dominant: [Double?]?
        let sunrise: [Int?]?
        let sunset: [Int?]?
        let daylight_duration: [Double?]?
    }

    var timeZone: TimeZone { TimeZone(identifier: timezone) ?? TimeZone(secondsFromGMT: utc_offset_seconds) ?? .current }

    var hours: [HourPoint] {
        guard let h = hourly else { return [] }
        return h.time.indices.map { i in
            HourPoint(
                date: Date(timeIntervalSince1970: TimeInterval(h.time[i])),
                temperature: h.temperature_2m.value(i),
                apparent: h.apparent_temperature.value(i),
                precipitationProbability: h.precipitation_probability.value(i),
                precipitation: h.precipitation.value(i),
                snowfall: h.snowfall.value(i),
                code: h.weather_code.value(i),
                cloudCover: h.cloud_cover.value(i),
                visibility: h.visibility.value(i),
                wind: h.wind_speed_10m.value(i),
                windDirection: h.wind_direction_10m.value(i),
                gust: h.wind_gusts_10m.value(i),
                cape: h.cape.value(i),
                isDay: (h.is_day.value(i) ?? 1) == 1
            )
        }
    }

    var days: [DayPoint] {
        guard let d = daily else { return [] }
        return d.time.indices.map { i in
            DayPoint(
                date: Date(timeIntervalSince1970: TimeInterval(d.time[i])),
                code: d.weather_code.value(i),
                maxTemp: d.temperature_2m_max.value(i),
                minTemp: d.temperature_2m_min.value(i),
                precipitation: d.precipitation_sum.value(i),
                snowfall: d.snowfall_sum.value(i),
                precipitationProbability: d.precipitation_probability_max.value(i),
                maxWind: d.wind_speed_10m_max.value(i),
                maxGust: d.wind_gusts_10m_max.value(i),
                windDirection: d.wind_direction_10m_dominant.value(i),
                sunrise: d.sunrise.value(i).map { Date(timeIntervalSince1970: TimeInterval($0)) },
                sunset: d.sunset.value(i).map { Date(timeIntervalSince1970: TimeInterval($0)) },
                daylight: d.daylight_duration.value(i)
            )
        }
    }

    /// Hours from the current one onwards.
    func upcomingHours(_ count: Int, from now: Date = Date()) -> [HourPoint] {
        let all = hours
        let start = all.firstIndex { $0.date.addingTimeInterval(3600) > now } ?? 0
        return Array(all[start..<min(all.count, start + count)])
    }

    /// The daily row for the calendar day containing `date` in the place's time zone.
    func day(for date: Date) -> DayPoint? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }
}

private extension Optional {
    func value<T>(_ index: Int) -> T? where Wrapped == [T?] {
        guard let array = self, array.indices.contains(index) else { return nil }
        return array[index]
    }
}

struct HourPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let temperature: Double?
    let apparent: Double?
    let precipitationProbability: Double?
    let precipitation: Double?
    let snowfall: Double?
    let code: Int?
    let cloudCover: Double?
    let visibility: Double?
    let wind: Double?
    let windDirection: Double?
    let gust: Double?
    let cape: Double?
    let isDay: Bool

    var windRisk: Risk { Risk.wind(mean: wind, gust: gust) }
    var iceRisk: Risk { Risk.ice(temperature: temperature, precipitation: precipitation, snowfall: snowfall) }
    var lightningRisk: Risk {
        if WeatherCode.isThunderstorm(code) { return .warning }
        if let cape, cape >= 1000 { return .caution }
        return .ok
    }
}

struct DayPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let code: Int?
    let maxTemp: Double?
    let minTemp: Double?
    let precipitation: Double?
    let snowfall: Double?
    let precipitationProbability: Double?
    let maxWind: Double?
    let maxGust: Double?
    let windDirection: Double?
    let sunrise: Date?
    let sunset: Date?
    let daylight: Double?

    var windRisk: Risk { Risk.wind(mean: maxWind, gust: maxGust) }
    var iceRisk: Risk { Risk.ice(temperature: minTemp, precipitation: precipitation, snowfall: snowfall) }
    var overallRisk: Risk { max(windRisk, iceRisk) }
}

struct Marine: Decodable {
    let current: Current?
    let hourly: Hourly?

    struct Current: Decodable {
        let time: Int
        let wave_height: Double?
        let wave_direction: Double?
        let wave_period: Double?
        let swell_wave_height: Double?
        let swell_wave_period: Double?
        let sea_surface_temperature: Double?
    }

    struct Hourly: Decodable {
        let time: [Int]
        let wave_height: [Double?]?
        let wave_period: [Double?]?
        let swell_wave_height: [Double?]?
    }

    var hasData: Bool { current?.wave_height != nil }

    /// Max wave height over the next `hours`.
    func maxWaveHeight(next hours: Int, from now: Date = Date()) -> Double? {
        guard let h = hourly, let heights = h.wave_height else { return nil }
        let limit = now.addingTimeInterval(TimeInterval(hours) * 3600)
        var best: Double?
        for (i, t) in h.time.enumerated() {
            let date = Date(timeIntervalSince1970: TimeInterval(t))
            guard date >= now.addingTimeInterval(-3600), date <= limit, heights.indices.contains(i), let value = heights[i] else { continue }
            best = max(best ?? value, value)
        }
        return best
    }

    /// Sneaker-wave hazard on the south coast beaches (Reynisfjara, Kirkjufjara…):
    /// long-period swell is what makes waves run unexpectedly far up the sand.
    var beachRisk: Risk {
        guard let c = current, let height = c.wave_height else { return .ok }
        let period = c.wave_period ?? 0
        if height >= 4 || (height >= 2.5 && period >= 12) { return .danger }
        if height >= 2.5 || (height >= 1.5 && period >= 12) { return .warning }
        if height >= 1.5 { return .caution }
        return .ok
    }

    /// Rough comfort scale for ferries and boat trips.
    var seaRisk: Risk {
        guard let height = current?.wave_height else { return .ok }
        if height >= 5 { return .danger }
        if height >= 3.5 { return .warning }
        if height >= 2 { return .caution }
        return .ok
    }
}

struct AirQuality: Decodable {
    let current: Current?

    struct Current: Decodable {
        let european_aqi: Double?
        let pm10: Double?
        let pm2_5: Double?
        let sulphur_dioxide: Double?
        let nitrogen_dioxide: Double?
    }

    /// Volcanic gas (SO₂, µg/m³) thresholds from the Icelandic Environment Agency.
    var so2Risk: Risk {
        guard let so2 = current?.sulphur_dioxide else { return .ok }
        if so2 >= 2600 { return .danger }
        if so2 >= 600 { return .warning }
        if so2 >= 350 { return .caution }
        return .ok
    }

    var aqiRisk: Risk {
        guard let aqi = current?.european_aqi else { return .ok }
        if aqi > 100 { return .danger }
        if aqi > 80 { return .warning }
        if aqi > 60 { return .caution }
        return .ok
    }
}

enum OpenMeteo {
    static func forecast(_ c: Coordinate) async throws -> Fetched<Forecast> {
        let url = try HTTP.url("https://api.open-meteo.com/v1/forecast", [
            "latitude": String(c.lat),
            "longitude": String(c.lon),
            "current": "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,snowfall,weather_code,cloud_cover,pressure_msl,wind_speed_10m,wind_direction_10m,wind_gusts_10m,is_day",
            "hourly": "temperature_2m,apparent_temperature,precipitation_probability,precipitation,snowfall,weather_code,cloud_cover,visibility,wind_speed_10m,wind_direction_10m,wind_gusts_10m,cape,is_day",
            "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,snowfall_sum,precipitation_probability_max,wind_speed_10m_max,wind_gusts_10m_max,wind_direction_10m_dominant,sunrise,sunset,daylight_duration",
            "wind_speed_unit": "ms",
            "timezone": "auto",
            "timeformat": "unixtime",
            "forecast_days": "16",
        ])
        return try await HTTP.json(Forecast.self, from: url, cacheKey: "forecast_\(c.key)")
    }

    static func marine(_ c: Coordinate) async throws -> Fetched<Marine> {
        let url = try HTTP.url("https://marine-api.open-meteo.com/v1/marine", [
            "latitude": String(c.lat),
            "longitude": String(c.lon),
            "current": "wave_height,wave_direction,wave_period,swell_wave_height,swell_wave_period,sea_surface_temperature",
            "hourly": "wave_height,wave_period,swell_wave_height",
            "timeformat": "unixtime",
            "forecast_days": "7",
        ])
        return try await HTTP.json(Marine.self, from: url, cacheKey: "marine_\(c.key)")
    }

    static func airQuality(_ c: Coordinate) async throws -> Fetched<AirQuality> {
        let url = try HTTP.url("https://air-quality-api.open-meteo.com/v1/air-quality", [
            "latitude": String(c.lat),
            "longitude": String(c.lon),
            "current": "european_aqi,pm10,pm2_5,sulphur_dioxide,nitrogen_dioxide",
            "timeformat": "unixtime",
        ])
        return try await HTTP.json(AirQuality.self, from: url, cacheKey: "air_\(c.key)")
    }
}
