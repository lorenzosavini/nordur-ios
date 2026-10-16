import Foundation

// Reference observing sites: MET Norway sky forecast fetched once for all users
// by nordur-api (/api/sites), ranked here with the aurora engine.

struct AuroraSitesResponse: Decodable {
    struct Hour: Decodable {
        let t: String
        let step: Int
        let total: Double?
        let low: Double?
        let mid: Double?
        let high: Double?
        let fog: Double?
    }
    struct Site: Decodable, Identifiable {
        let id: String
        let name: String
        let lat: Double
        let lon: Double
        let modelUpdated: String?
        let hours: [Hour]
        var coordinate: Coordinate { Coordinate(lat: lat, lon: lon) }

        /// Hourly sky; 6-hourly MET steps are repeated over their 6 hours (marked coarser by the caller).
        var sky: [SkyHour] {
            hours.flatMap { h -> [SkyHour] in
                guard let date = DateParse.iso(h.t) else { return [] }
                return (0..<max(1, h.step)).map { k in
                    SkyHour(date: date.addingTimeInterval(Double(k) * 3600), cloudTotal: h.total, cloudLow: h.low,
                            cloudMid: h.mid, cloudHigh: h.high, fog: h.fog, visibility: nil)
                }
            }
        }
    }
    let generated: String?
    let provider: String?
    let sites: [Site]
}

struct SiteOutlook: Identifiable {
    let site: AuroraSitesResponse.Site
    let now: AuroraSlot?
    let best: AuroraSlot?
    let distanceKm: Double?
    var id: String { site.id }
}

enum AuroraSitesService {
    static let endpoint = URL(string: "https://nordur-api.vercel.app/api/sites")!

    static func load() async throws -> Fetched<AuroraSitesResponse> {
        try await HTTP.json(AuroraSitesResponse.self, from: endpoint, cacheKey: "nordur_aurora_sites")
    }

    /// Ranks sites by their best observability in the next `hours`.
    static func rank(_ response: AuroraSitesResponse, base: AuroraInputs, from user: Coordinate?, horizons: [String: TerrainHorizon] = [:], hours: Double = 12) -> [SiteOutlook] {
        response.sites.map { site -> SiteOutlook in
            var inputs = base
            inputs.place = site.coordinate
            inputs.sky = site.sky
            inputs.secondSky = []
            inputs.horizon = horizons[TerrainService.key(site.coordinate)]
            let slots = AuroraEngine.forecast(inputs, hours: Int(hours) + 2)
            let now = slots.first { abs($0.date.timeIntervalSince(base.now)) < 1800 } ?? slots.first
            return SiteOutlook(site: site, now: now, best: AuroraEngine.best(slots, within: hours, now: base.now),
                               distanceKm: user.map { Geo.distanceKm($0, site.coordinate) })
        }
        .sorted { ($0.best?.index ?? -1, -($0.distanceKm ?? 0)) > ($1.best?.index ?? -1, -($1.distanceKm ?? 0)) }
    }
}

/// Local skyline from the terrain model (nordur-api /api/horizon, EU-DEM 25 m).
/// Terrain does not change: once downloaded it is kept on the device for good.
enum TerrainService {
    struct Response: Decodable {
        struct Point: Decodable { let azimuth: Double; let angle: Double }
        let elevation: Double?
        let profile: [Point]
    }

    static func key(_ c: Coordinate) -> String { String(format: "%.2f_%.2f", c.lat, c.lon) }

    static func horizon(_ c: Coordinate) async -> TerrainHorizon? {
        let cacheKey = "horizon_\(key(c))"
        func make(_ data: Data) -> TerrainHorizon? {
            guard let r = try? JSONDecoder().decode(Response.self, from: data), r.profile.count == 16 else { return nil }
            return TerrainHorizon(angles: r.profile.sorted { $0.azimuth < $1.azimuth }.map(\.angle))
        }
        if let cached = DiskCache.read(cacheKey), let h = make(cached.data) { return h }
        guard let url = URL(string: String(format: "https://nordur-api.vercel.app/api/horizon?lat=%.2f&lon=%.2f", c.lat, c.lon)),
              let fetched = try? await HTTP.get(url, cacheKey: cacheKey) else { return nil }
        return make(fetched.value)
    }
}

extension SkyHour {
    init(_ h: HourPoint) {
        self.init(date: h.date, cloudTotal: h.cloudCover, cloudLow: h.cloudLow, cloudMid: h.cloudMid,
                  cloudHigh: h.cloudHigh, fog: h.fog, visibility: h.visibility)
    }
}

extension AuroraInputs {
    /// Builds the engine inputs from what the app has: the backend state when
    /// available, otherwise the NOAA Kp forecast and OVATION fetched directly.
    static func make(place: Coordinate, forecast: Forecast?, state: AuroraState?, kp: [KpPoint], ovation: OvationGrid?,
                     horizon: TerrainHorizon? = nil, now: Date = Date()) -> AuroraInputs {
        let blocks: [KpBlock] = state.map(\.kpBlocks).flatMap { $0.isEmpty ? nil : $0 }
            ?? kp.map { KpBlock(start: $0.date, value: $0.kp, isObserved: !$0.isForecast) }
        let field: AuroraField? = state?.ovation ?? ovation
        return AuroraInputs(
            place: place,
            sky: (forecast?.hours ?? []).map(SkyHour.init),
            kp: blocks,
            field: field,
            now: now,
            solarWindFresh: state?.source("solarWind")?.isOK ?? false,
            kpSourceFresh: state?.source("kpForecast")?.isOK ?? !kp.isEmpty,
            horizon: horizon)
    }
}
