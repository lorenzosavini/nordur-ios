import Foundation

/// "Now", the same everywhere (Today, Weather, the widget): what the nearest
/// vedur.is station measured in the last 75 minutes, else the forecast for now
/// (vedur.is where it has a station, the model elsewhere). Sky, feels-like and
/// cloud always come from the forecast (a station does not report them).
struct NowConditions {
    let temperature: Double?
    let wind: Double?
    let gust: Double?
    /// Degrees.
    let direction: Double?
    let humidity: Double?
    let pressure: Double?
    /// Measured: rain of the last hour (mm). Forecast: rate now (mm/h).
    let precipitation: Double?
    let cloud: Double?
    let code: Int?
    let isDay: Bool
    let apparent: Double?
    /// The measurement used, when there is one.
    let measured: IMOObservation?

    static let maxAge: TimeInterval = 75 * 60

    init?(forecast: Forecast?, observation: IMOObservation?) {
        let c = forecast?.current
        let m = observation.flatMap { $0.age <= Self.maxAge ? $0 : nil }
        guard c != nil || m != nil else { return nil }
        measured = m
        temperature = m?.temperature ?? c?.temperature_2m
        wind = m?.wind ?? c?.wind_speed_10m
        // A measured mean wind without its gust: never show a forecast gust below it.
        gust = m?.gust ?? c?.wind_gusts_10m.map { max($0, m?.wind ?? 0) }
        direction = m?.degrees ?? c?.wind_direction_10m
        humidity = m?.humidity ?? c?.relative_humidity_2m
        pressure = m?.pressure ?? c?.pressure_msl
        precipitation = m != nil ? m?.precipitation : c?.precipitation
        cloud = m?.cloud ?? c?.cloud_cover
        code = c?.weather_code
        isDay = (c?.is_day ?? 1) != 0
        // Feels-like: the forecast's, moved by the difference the measurement makes.
        if let a = c?.apparent_temperature, let t = c?.temperature_2m, let mt = m?.temperature { apparent = a + (mt - t) } else { apparent = c?.apparent_temperature }
    }

    var isMeasured: Bool { measured != nil }
}
