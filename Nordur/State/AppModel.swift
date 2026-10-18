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
        case roadInfo = "Notizie strade (umferdin.is)"
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
        case sightings = "Avvistamenti aurora (community)"
    }

    let location = LocationManager()
    /// A screen asks the root view to switch tab ("map", "weather", "trip"…).
    var requestedTab: String?
    var showSettings = false

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
    var roadInfo: Fetched<RoadInfo>?
    /// Lines of the road sections (static, refreshed weekly).
    var roadGeometry: Fetched<RoadGeometry>?
    /// Aurora reports from Norður users, last 3 hours.
    var sightings: Fetched<SightingsFeed>?
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

    /// The active place is in Iceland: the Icelandic sources apply.
    var inIceland: Bool { Coverage.iceland(activePlace.coordinate) }

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

    private var loadedPlaceKey: String?

    /// The active place changed (picked from the list, or "my position" got a
    /// fix): drop the previous place's data so nothing stale is shown, then reload
    /// everything that depends on the place, without a manual refresh.
    func placeChanged() async {
        let key = placeKey
        if let loaded = loadedPlaceKey, loaded != key {
            forecast = nil
            stationForecast = nil
            marine = nil
            air = nil
            // A place seen before shows its saved forecast at once, while the new one loads.
            live.subtract([.forecast, .marine, .air])
            await HTTP.$cacheOnly.withValue(true) { await refreshPlace() }
        }
        await warmStart()
        isRefreshing = true
        await refreshPlace()
        guard key == placeKey else { return }
        loadedPlaceKey = key
        await refreshAurora()
        isRefreshing = false
    }

    /// The place forecast, if the one shown is older than 15 minutes.
    func refreshPlaceIfOld() async {
        if let f = forecast, !f.isStale, Date().timeIntervalSince(f.date) < 15 * 60 { return }
        await refreshPlace()
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

    /// Country-wide feeds; skipped if refreshed less than 2 minutes ago unless forced.
    /// Each feed is shown as soon as it arrives: the slowest no longer holds back the others.
    func refreshGlobal(force: Bool = false) async {
        if !force, let last = lastGlobalRefresh, Date().timeIntervalSince(last) < 110 { return }
        lastGlobalRefresh = Date()
        async let w: Void = load(.warnings, \.warnings) { try await IMO.warnings() }
        async let q: Void = load(.quakes, \.quakes) { try await IMO.quakes() }
        async let r: Void = load(.roads, \.roads) { try await Roads.network() }
        async let ri: Void = load(.roadInfo, \.roadInfo) { try await RoadInfoService.load() }
        async let k: Void = load(.kp, \.kp) { try await SpaceWeather.kpForecast() }
        async let o: Void = load(.ovation, \.ovation) { try await SpaceWeather.ovation() }
        async let s: Void = load(.solarWind, \.solarWind) { try await SpaceWeather.solarWind() }
        async let n: Void = load(.news, \.news) { try await SafeTravel.news() }
        async let a: Void = refreshAurora()
        _ = await (w, q, r, ri, k, o, s, n, a)
        recomputeAurora()
        await localizeWebText()
        await refreshStatic()
    }

    /// Fetches one source and shows it right away.
    private func load<T>(_ source: Source, _ property: ReferenceWritableKeyPath<AppModel, Fetched<T>?>,
                         _ fetch: @escaping () async throws -> Fetched<T>) async {
        apply(await attempt(fetch), source) { self[keyPath: property] = $0 }
    }

    /// Sources already loaded from the network in this session (a cached copy never replaces them).
    private var live = Set<Source>()
    private var warmed = false

    /// At launch, the last copies saved on the phone are shown at once, while the
    /// network refresh runs: the screens are never empty waiting for the slowest source.
    func warmStart() async {
        guard !warmed else { return }
        warmed = true
        await HTTP.$cacheOnly.withValue(true) {
            let c = activePlace.coordinate
            async let w: Void = load(.warnings, \.warnings) { try await IMO.warnings() }
            async let q: Void = load(.quakes, \.quakes) { try await IMO.quakes() }
            async let r: Void = load(.roads, \.roads) { try await Roads.network() }
            async let ri: Void = load(.roadInfo, \.roadInfo) { try await RoadInfoService.load() }
            async let k: Void = load(.kp, \.kp) { try await SpaceWeather.kpForecast() }
            async let n: Void = load(.news, \.news) { try await SafeTravel.news() }
            async let f: Void = load(.forecast, \.forecast) { try await WeatherService.forecast(c) }
            async let m: Void = load(.marine, \.marine) { try await OpenMeteo.marine(c) }
            async let ai: Void = load(.air, \.air) { try await OpenMeteo.airQuality(c) }
            async let wc: Void = load(.webcams, \.webcams) { try await Webcams.sites() }
            _ = await (w, q, r, ri, k, n, f, m, ai, wc)
        }
        recomputeAurora()
    }

    /// Web text (IMO, SafeTravel, Vegagerðin, Herjólfur, NOAA) in the app language.
    /// The originals are shown first; the translations replace them when ready.
    func localizeWebText() async {
        async let w: Void = localizeWarnings()
        async let n: Void = localizeNews()
        async let r: Void = localizeRoadInfo()
        async let f: Void = localizeFerry()
        async let a: Void = localizeAurora()
        _ = await (w, n, r, f, a)
    }

    private func localizeWarnings() async {
        guard let w = warnings else { return }
        let localized = await Translator.shared.localize(w.value)
        if warnings?.date == w.date { warnings = Fetched(value: localized, date: w.date, isStale: w.isStale) }
    }

    private func localizeNews() async {
        guard let n = news else { return }
        let localized = await Translator.shared.localize(n.value)
        if news?.date == n.date { news = Fetched(value: localized, date: n.date, isStale: n.isStale) }
    }

    private func localizeRoadInfo() async {
        guard let r = roadInfo else { return }
        let localized = await Translator.shared.localize(r.value)
        if roadInfo?.date == r.date { roadInfo = Fetched(value: localized, date: r.date, isStale: r.isStale) }
    }

    private func localizeFerry() async {
        guard let f = ferry, let notice = f.value else { return }
        let localized = await Translator.shared.localize(notice)
        if ferry?.date == f.date { ferry = Fetched(value: localized, date: f.date, isStale: f.isStale) }
    }

    private func localizeAurora() async {
        guard let a = aurora else { return }
        let localized = await Translator.shared.localize(a.value)
        if aurora?.date == a.date { aurora = Fetched(value: localized, date: a.date, isStale: a.isStale) }
    }

    /// Slow-changing data: webcam list (every 6 h) and fuel stations (30-day on-device copy).
    func refreshStatic(force: Bool = false) async {
        let webcamsOld = webcams.map { Date().timeIntervalSince($0.date) > 6 * 3600 || $0.isStale } ?? true
        if webcamsOld || force {
            let result = await attempt { try await Webcams.sites() }
            apply(result, .webcams) { self.webcams = $0 }
        }
        await loadRoadGeometry(force: force)
        if fuel == nil || force {
            let maxAge: TimeInterval = force ? 0 : 30 * 24 * 3600
            let result = await attempt { try await FuelStations.all(maxAge: maxAge) }
            apply(result, .fuel) { self.fuel = $0 }
        }
    }

    /// Lines of the road sections for the map (static, kept a week on the phone).
    func loadRoadGeometry(force: Bool = false) async {
        guard roadGeometry == nil || force else { return }
        if case .success(let geometry) = await attempt({ try await RoadGeometry.load() }) { roadGeometry = geometry }
    }

    /// Forecast grid for the weather map (refreshed at most hourly) and radar frames.
    func refreshMapData(force: Bool = false) async {
        await loadRoadGeometry()
        if roadInfo == nil {
            apply(await attempt { try await RoadInfoService.load() }, .roadInfo) { self.roadInfo = $0 }
        }
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
        await localizeWebText()
    }

    private func apply<T>(_ result: Result<T, Error>, _ source: Source, _ assign: (T) -> Void) {
        if HTTP.cacheOnly {
            // Warm start: a saved copy fills an empty screen, never replaces fresher data, never reports errors.
            if case .success(let value) = result, !live.contains(source) { assign(value) }
            return
        }
        live.insert(source)
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
        if let a = aurora {
            let localized = await Translator.shared.localize(a.value)
            if aurora?.date == a.date { aurora = Fetched(value: localized, date: a.date, isStale: a.isStale) }
        }
        await refreshSightings()
        await loadHorizons()
    }

    func refreshSightings() async {
        apply(await attempt { try await SightingsFeed.loadFetched() }, .sightings) { self.sightings = $0 }
    }

    /// Community reports crossed with the model and the clouds at the active place.
    var auroraConfirmation: AuroraConfirmation {
        let now = auroraNow.flatMap { abs($0.date.timeIntervalSinceNow) < 1800 ? $0 : nil }
        return AuroraConfirmation.evaluate(sightings?.value.recent ?? [], at: activePlace.coordinate,
                                           modelActivity: now?.activityFactor, clear: now?.clear)
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

    /// The next 60 minutes at the active place, from the solar wind already measured at L1.
    var auroraNextHour: [NowcastStep] {
        guard let nowcast = aurora?.value.solarWind?.nowcast else { return [] }
        let inputs = auroraInputs(for: activePlace.coordinate, forecast: forecast?.value)
        return AuroraEngine.nextHour(inputs, steps: nowcast.inputs)
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
