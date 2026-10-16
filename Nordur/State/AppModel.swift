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
    }

    let location = LocationManager()

    private(set) var useCurrentLocation: Bool
    private(set) var chosenPlace: Place

    var forecast: Fetched<Forecast>?
    var marine: Fetched<Marine>?
    var air: Fetched<AirQuality>?
    var warnings: Fetched<[WeatherWarning]>?
    var quakes: Fetched<[Quake]>?
    var roads: Fetched<RoadNetwork>?
    var kp: Fetched<[KpPoint]>?
    var ovation: Fetched<OvationGrid>?
    var solarWind: Fetched<SolarWind>?
    var news: Fetched<[NewsItem]>?
    var webcams: Fetched<[WebcamSite]>?
    var fuel: Fetched<[FuelStation]>?
    var flights: Fetched<[Flight]>?
    var ferry: Fetched<FerryNotice?>?

    var errors: [Source: String] = [:]
    var isRefreshing = false
    private var lastGlobalRefresh: Date?

    init() {
        let defaults = UserDefaults.standard
        useCurrentLocation = defaults.object(forKey: Self.useCurrentKey) as? Bool ?? true
        chosenPlace = Self.storedChosenPlace ?? .reykjavik
    }

    // MARK: - Place selection

    var activePlace: Place {
        if useCurrentLocation, let c = location.coordinate {
            return Place(name: location.placeName ?? "Posizione attuale", coordinate: c, subtitle: "Posizione attuale")
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
            return Place(name: "Posizione attuale", coordinate: last)
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
        async let f = attempt { try await OpenMeteo.forecast(c) }
        async let m = attempt { try await OpenMeteo.marine(c) }
        async let a = attempt { try await OpenMeteo.airQuality(c) }
        let (rf, rm, ra) = await (f, m, a)
        // The user may have switched place meanwhile.
        guard c == activePlace.coordinate else { return }
        apply(rf, .forecast) { self.forecast = $0 }
        apply(rm, .marine) { self.marine = $0 }
        apply(ra, .air) { self.air = $0 }
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

    var auroraOutlook: AuroraOutlook? {
        guard let forecast = forecast?.value else { return nil }
        return AuroraCalc.outlook(forecast: forecast, kp: kp?.value ?? [], ovation: ovation?.value)
    }

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
