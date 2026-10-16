import Foundation

// Weather you will meet along a drive: the route is sampled every ~25 km and
// each sample gets the forecast for the hour you are expected to pass there.

struct RouteSample: Identifiable {
    let index: Int
    let coordinate: Coordinate
    let kmFromStart: Double
    let eta: Date
    var id: Int { index }
}

struct RouteWaypointWeather: Identifiable {
    let sample: RouteSample
    let hour: HourPoint?
    var id: Int { sample.index }

    var risk: Risk {
        guard let hour else { return .ok }
        return max(hour.windRisk, hour.iceRisk, hour.lightningRisk)
    }
}

enum RouteWeather {
    /// Evenly spaced points along a polyline, with ETA proportional to distance.
    static func sample(_ polyline: [Coordinate], every stepKm: Double = 25, departure: Date, travelTime: TimeInterval) -> [RouteSample] {
        guard polyline.count >= 2 else { return [] }
        var cumulative: [Double] = [0]
        for i in 1..<polyline.count {
            cumulative.append(cumulative[i - 1] + Geo.distanceKm(polyline[i - 1], polyline[i]))
        }
        let total = cumulative.last ?? 0
        guard total > 0 else { return [] }
        var targets = Array(stride(from: 0.0, to: total, by: stepKm))
        if total - (targets.last ?? 0) > stepKm * 0.3 || targets.count == 1 { targets.append(total) }

        var samples: [RouteSample] = []
        var segment = 1
        for (n, target) in targets.enumerated() {
            while segment < cumulative.count - 1 && cumulative[segment] < target { segment += 1 }
            let a = polyline[segment - 1], b = polyline[segment]
            let length = cumulative[segment] - cumulative[segment - 1]
            let t = length > 0 ? (target - cumulative[segment - 1]) / length : 0
            let point = Coordinate(lat: a.lat + (b.lat - a.lat) * t, lon: a.lon + (b.lon - a.lon) * t)
            let eta = departure.addingTimeInterval(travelTime * target / total)
            samples.append(RouteSample(index: n, coordinate: point, kmFromStart: target, eta: eta))
        }
        return samples
    }

    /// One Open-Meteo request for every sample (the API accepts lists of coordinates).
    static func forecast(for samples: [RouteSample]) async throws -> [RouteWaypointWeather] {
        guard !samples.isEmpty else { return [] }
        var results: [RouteWaypointWeather] = []
        for chunk in stride(from: 0, to: samples.count, by: 50).map({ Array(samples[$0..<min($0 + 50, samples.count)]) }) {
            let url = try HTTP.url("https://api.open-meteo.com/v1/forecast", [
                "latitude": chunk.map { String(format: "%.4f", $0.coordinate.lat) }.joined(separator: ","),
                "longitude": chunk.map { String(format: "%.4f", $0.coordinate.lon) }.joined(separator: ","),
                "hourly": "temperature_2m,apparent_temperature,precipitation_probability,precipitation,snowfall,weather_code,cloud_cover,visibility,wind_speed_10m,wind_direction_10m,wind_gusts_10m,cape,is_day",
                "wind_speed_unit": "ms",
                "timezone": "auto",
                "timeformat": "unixtime",
                "forecast_days": "16",
            ])
            let key = "route_" + stableHash(chunk.map { $0.coordinate.key }.joined())
            let fetched = try await HTTP.get(url, cacheKey: key)
            let forecasts = try decodeMany(fetched.value)
            for (sample, forecast) in zip(chunk, forecasts) {
                let hour = forecast.hours.min { abs($0.date.timeIntervalSince(sample.eta)) < abs($1.date.timeIntervalSince(sample.eta)) }
                let usable = hour.flatMap { abs($0.date.timeIntervalSince(sample.eta)) <= 2 * 3600 ? $0 : nil }
                results.append(RouteWaypointWeather(sample: sample, hour: usable))
            }
        }
        return results
    }

    /// Open-Meteo returns an object for one location and an array for several.
    static func decodeMany(_ data: Data) throws -> [Forecast] {
        if let many = try? JSONDecoder().decode([Forecast].self, from: data) { return many }
        return [try JSONDecoder().decode(Forecast.self, from: data)]
    }
}
