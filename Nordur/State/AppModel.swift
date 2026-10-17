import Foundation
import Observation

/// Holds every data source the app shows and refreshes them.
@MainActor
@Observable
final class AppModel {
    enum Source: String, CaseIterable {
        case forecast = "Previsioni"
        case marine = "Mare"
        case air = "Qualità dell'aria"
        case warnings = "Allerte IMO"
        case quakes = "Terremoti"
        case roads = "Strade"
        case kp = "Indice Kp"
        case ovation = "Ovale aurorale"
        case solarWind = "Vento solare"
        case news = "SafeTravel"
        case webcams = "Webcam"
        case fuel = "Distributori"
        case flights = "Voli KEF"
        case ferry = "Herjólfur"
        case grid = "Mappa meteo"
        case radar = "Radar"
        case aurora = "Aurora (NOAA/GFZ/NASA)"
        case sites = "Località aurora"
    }

    let location = LocationManager()

    private(set) var useCurrentLocation: Bool
    private(set) var chosenPlace: Place

    var forecast: Fetched<Forecast>?
    /// Official IMO forecast for the nearest station (nil when none within 60 km).
    var stationForecast: Fetched<StationForecast>?
    var marine: Fetched<Marine>?
    var air: Fetched<AirQuality>?
    var warnings: Fetched<[WeatherWarning]>?
    var quakes: Fetched<[Quake]>?
    var roads: Fetched<RoadNetwork>?
    var kp: Fetched<[KpPoint]>?
    var ovation: Fetched<OvationGrid>?
    var solarWind: Fetched<SolarWind>?
    /// Validated space-weather state (NOAA SWPC, GFZ, NASA DONKI) from nordur-api.
    var aurora: Fetched<AuroraState>?
    /// MET Norway sky forecast at the reference observing sites.
    var auroraSites: Fetched<AuroraSitesResponse>?
    /// Engine output for the active place, hourly for 72 h (recomputed when inputs change).
    private(set) var auroraSlots: [AuroraSlot] = []
    /// Reference sites ranked by observability in the next 12 h.
    private(set) var siteRanking: [SiteOutlook] = []
    /// Terrain skylines by rounded coordinate (TerrainService.key).
    private(set) var horizons: [String: TerrainHorizon] = [:]
    var news: Fetched<[NewsItem]>?
    var webcams: Fetched<[WebcamSite]>?
    var fuel: Fetched<[FuelStation]>?
    var flights: Fetched<[Flight]>?
    var ferry: Fetched<FerryNotice?>?
    var weatherGrid: Fetched<WeatherGrid>?
    var radarFrames: [RadarFrame] = []

    var errors: [Source: String] = [:]
    var isRefreshing = false
    private var lastGlobalRefresh: Date?

    init() {
        let defaults = UserDefaults.standard
        useCurrentLocation = defaults.object(forKey: Self.useCurrentKey) as? Bool ?? true
        chosenPlace = Self.storedChosenPlace ?? .reykjavik
    }

    func reloadSelection() {
        useCurrentLocation = UserDefaults.standard.object(forKey: Self.useCurrentKey) as? Bool ?? true
        chosenPlace = Self.storedChosenPlace ?? .reykjavik
    }

    // MARK: - Place selection

    var activePlace: Place {
        if useCurrentLocation, let c = location.coordinate {
            return Place(name: location.placeName ?? String(localized: "Posizione attuale"), coordinate: c, subtitle: String(localized: "Posizione attuale"))
        }
        return chosenPlace
    }

    /// Changes whenever the place-dependent data must be reloaded.
    var placeKey: String { activePlace.coordinate.key }

    func select(_ place: Place) {
        chosenPlace = place
        useCurrentLocation = false
        persistSelection()
    }

    func selectCurrentLocation() {
        useCurrentLocation = true
        location.request()
        persistSelection()
    }

    private func persistSelection() {
        UserDefaults.standard.set(useCurrentLocation, forKey: Self.useCurrentKey)
        if let data = try? JSONEncoder().encode(chosenPlace) {
            UserDefaults.standard.set(data, forKey: Self.chosenPlaceKey)
        }
    }

    private nonisolated static let useCurrentKey = "useCurrentLocation"
    private nonisolated static let chosenPlaceKey = "chosenPlace"

    nonisolated static var storedChosenPlace: Place? {
        guard let data = UserDefaults.standard.data(forKey: chosenPlaceKey) else { return nil }
        return try? JSONDecoder().decode(Place.self, from: data)
    }

    /// Place to monitor from background checks (no live GPS there).
    nonisolated static var monitoredPlace: Place {
        let useCurrent = UserDefaults.standard.object(forKey: useCurrentKey) as? Bool ?? true
        if useCurrent, let last = LocationManager.lastKnown {
            return Place(name: String(localized: "Posizione attuale"), coordinate: last)
        }
        return storedChosenPlace ?? .reykjavik
    }

    // MARK: - Refresh

    func refreshAll() async {
        isRefreshing = true
        async let place: Void = refreshPlace()
        async let global: Void = refreshGlobal(force: true)
        _ = await (place, global)
        isRefreshing = false
    }

    func refreshPlace() async {
        let c = activePlace.coordinate
        async let f = attempt { try await WeatherService.forecast(c) }
        async let m = attempt { try await OpenMeteo.marine(c) }
        async let a = attempt { try await OpenMeteo.airQuality(c) }
        async let s = attempt { try await IMOForecast.forecast(near: c) }
        let (rf, rm, ra, rs) = await (f, m, a, s)
        // The user may have switched place meanwhile.
        guard c == activePlace.coordinate else { return }
        if case .success(let station) = rs { stationForecast = station }
        apply(rf, .forecast) { self.forecast = $0 }
        apply(rm, .marine) { self.marine = $0 }
        apply(ra, .air) { self.air = $0 }
        recomputeAurora()
    }

    /// Country-wide feeds; skipped if refreshed less than 5 minutes ago unless forced.
    func refreshGlobal(force: Bool = false) async {
        if !force, let last = lastGlobalRefresh, Date().timeIntervalSince(last) < 300 { return }
        lastGlobalRefresh = Date()
        async let w = attempt { try await IMO.warnings() }
        async let q = attempt { try await IMO.quakes() }
        async let r = attempt { try await Roads.network() }
        async let k = attempt { try await SpaceWeather.kpForecast() }
        async let o = attempt { try await SpaceWeather.ovation() }
        async let s = attempt { try await SpaceWeather.solarWind() }
        async let n = attempt { try await SafeTravel.news() }
        let (rw, rq, rr, rk, ro, rs, rn) = await (w, q, r, k, o, s, n)
        apply(rw, .warnings) { self.warnings = $0 }
        apply(rq, .quakes) { self.quakes = $0 }
        apply(rr, .roads) { self.roads = $0 }
        apply(rk, .kp) { self.kp = $0 }
        apply(ro, .ovation) { self.ovation = $0 }
        apply(rs, .solarWind) { self.solarWind = $0 }
        apply(rn, .news) { self.news = $0 }
        await refreshAurora()
        await refreshStatic()
    }

    /// Slow-changing data: webcam list (every 6 h) and fuel stations (30-day on-device copy).
    func refreshStatic(force: Bool = false) async {
        let webcamsOld = webcams.map { Date().timeIntervalSince($0.date) > 6 * 3600 || $0.isStale } ?? true
        if webcamsOld || force {
            let result = await attempt { try await Webcams.sites() }
            apply(result, .webcams) { self.webcams = $0 }
        }
        if fuel == nil || force {
            let maxAge: TimeInterval = force ? 0 : 30 * 24 * 3600
            let result = await attempt { try await FuelStations.all(maxAge: maxAge) }
            apply(result, .fuel) { self.fuel = $0 }
        }
    }

    /// Forecast grid for the weather map (refreshed at most hourly) and radar frames.
    func refreshMapData(force: Bool = false) async {
        let gridOld = weatherGrid.map { Date().timeIntervalSince($0.date) > 3600 || $0.isStale } ?? true
        if gridOld || force {
            let result = await attempt { try await WeatherGridService.iceland() }
            apply(result, .grid) { self.weatherGrid = $0 }
        }
        let radar = await attempt { try await RainViewer.frames() }
        apply(radar, .radar) { self.radarFrames = $0 }
        if ovation == nil || force {
            let result = await attempt { try await SpaceWeather.ovation() }
            apply(result, .ovation) { self.ovation = $0 }
        }
    }

    /// Flight board and ferry notices; loaded on demand (the flight page is ~1.5 MB).
    func refreshTransport() async {
        async let fl = attempt { try await TransportService.kefFlights() }
        async let fe = attempt { try await TransportService.herjolfur() }
        let (rfl, rfe) = await (fl, fe)
        apply(rfl, .flights) { self.flights = $0 }
        apply(rfe, .ferry) { self.ferry = $0 }
    }

    private func apply<T>(_ result: Result<T, Error>, _ source: Source, _ assign: (T) -> Void) {
        switch result {
        case .success(let value):
            assign(value)
            errors[source] = nil
        case .failure(let error):
            errors[source] = error.localizedDescription
        }
    }

    // MARK: - Derived data

    /// Warnings in force now or later that cover the active place.
    var warningsHere: [WeatherWarning] {
        let point = activePlace.coordinate
        return (warnings?.value ?? []).filter { $0.covers(point) }
    }

    func warnings(at point: Coordinate, from start: Date, to end: Date) -> [WeatherWarning] {
        (warnings?.value ?? []).filter { $0.covers(point) && $0.overlaps(start, end) }
    }

    // MARK: - Aurora

    /// Space-weather state every call (the backend caches for 60 s); sites every 30 min.
    func refreshAurora() async {
        let sitesOld = auroraSites.map { Date().timeIntervalSince($0.date) > 1800 || $0.isStale } ?? true
        async let state = attempt { try await AuroraStateService.load() }
        async let sites = attempt { sitesOld ? try await AuroraSitesService.load() : nil }
        let (rs, rt) = await (state, sites)
        apply(rs, .aurora) { self.aurora = $0 }
        apply(rt, .sites) { if let fresh = $0 { self.auroraSites = fresh } }
        // NOAA unreachable from this network (or only a cached copy): use the backend's OVATION run.
        if let state = aurora, let backendOvation = state.value.ovation, ovation == nil || ovation?.isStale == true {
            ovation = Fetched(value: OvationGrid(backend: backendOvation), date: state.date, isStale: state.isStale)
            if !state.isStale { errors[.ovation] = nil }
        }
        recomputeAurora()
        await loadHorizons()
    }

    func auroraInputs(for place: Coordinate, forecast: Forecast?) -> AuroraInputs {
        AuroraInputs.make(place: place, forecast: forecast, state: aurora?.value, kp: kp?.value ?? [], ovation: ovation?.value,
                          horizon: horizons[TerrainService.key(place)])
    }

    /// Skylines for the active place and the reference sites, one request at a
    /// time (the terrain service allows one call per second); kept for good.
    private func loadHorizons() async {
        let wanted = [activePlace.coordinate] + (auroraSites?.value.sites.map(\.coordinate) ?? [])
        var changed = false
        for c in wanted where horizons[TerrainService.key(c)] == nil {
            if let h = await TerrainService.horizon(c) { horizons[TerrainService.key(c)] = h; changed = true }
        }
        if changed { recomputeAurora() }
    }

    func recomputeAurora() {
        let place = activePlace.coordinate
        let inputs = auroraInputs(for: place, forecast: forecast?.value)
        auroraSlots = AuroraEngine.forecast(inputs)
        if let sites = auroraSites?.value {
            siteRanking = AuroraSitesService.rank(sites, base: inputs, from: useCurrentLocation ? location.coordinate : nil, horizons: horizons)
        }
    }

    var auroraNow: AuroraSlot? { auroraSlots.first { abs($0.date.timeIntervalSinceNow) < 1800 } ?? auroraSlots.first }
    var auroraBestTonight: AuroraSlot? { AuroraEngine.best(auroraSlots, within: 24) }

    var recentQuakes24h: [Quake] {
        let since = Date().addingTimeInterval(-24 * 3600)
        return (quakes?.value ?? []).filter { $0.date >= since }
    }

    /// Worst wind/ice risk over the next 12 hours at the active place.
    var drivingRiskNext12h: (risk: Risk, maxGust: Double?, minTemp: Double?, snow: Double) {
        let hours = forecast?.value.upcomingHours(12) ?? []
        let risk = hours.map { max($0.windRisk, $0.iceRisk) }.max() ?? .ok
        let gust = hours.compactMap(\.gust).max()
        let minTemp = hours.compactMap(\.temperature).min()
        let snow = hours.compactMap(\.snowfall).reduce(0, +)
        return (risk, gust, minTemp, snow)
    }
}
