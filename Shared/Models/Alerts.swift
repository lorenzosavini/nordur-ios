import Foundation

enum AlertCategory: String, Codable, CaseIterable, Identifiable {
    case weatherWarning, wind, arrival, road, quake, safeTravel, aurora, flight, ferry, speed, toll, notice, summary

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weatherWarning: return String(localized: "Allerte meteo vedur.is")
        case .wind: return String(localized: "Raffiche forti vicino a te")
        case .arrival: return String(localized: "In arrivo a una tappa")
        case .road: return String(localized: "Strade chiuse o impraticabili")
        case .quake: return String(localized: "Terremoti")
        case .safeTravel: return String(localized: "Avvisi SafeTravel")
        case .aurora: return String(localized: "Aurora boreale")
        case .flight: return String(localized: "Voli seguiti (KEF)")
        case .ferry: return String(localized: "Traghetto Herjólfur")
        case .speed: return String(localized: "Limite di velocità (in guida)")
        case .toll: return String(localized: "Pedaggi e parcheggi a pagamento")
        case .notice: return String(localized: "Avvisi di Norður")
        case .summary: return String(localized: "Riepilogo serale del viaggio")
        }
    }

    /// Compact name for filter chips.
    var shortLabel: String {
        switch self {
        case .weatherWarning: return String(localized: "Meteo vedur.is")
        case .wind: return String(localized: "Raffiche")
        case .arrival: return String(localized: "Arrivo")
        case .road: return String(localized: "Strade")
        case .quake: return String(localized: "Terremoti")
        case .safeTravel: return String(localized: "SafeTravel")
        case .aurora: return String(localized: "Aurora")
        case .flight: return String(localized: "Voli")
        case .ferry: return String(localized: "Traghetto")
        case .speed: return String(localized: "Velocità")
        case .toll: return String(localized: "Pedaggi")
        case .notice: return "Norður"
        case .summary: return String(localized: "Riepilogo")
        }
    }

    var symbol: String {
        switch self {
        case .weatherWarning: return "exclamationmark.triangle.fill"
        case .wind: return "wind"
        case .arrival: return "flag.checkered"
        case .road: return "road.lanes"
        case .quake: return "waveform.path.ecg"
        case .safeTravel: return "megaphone.fill"
        case .aurora: return "moon.stars.fill"
        case .flight: return "airplane"
        case .ferry: return "ferry.fill"
        case .speed: return "gauge.with.dots.needle.67percent"
        case .toll: return "eurosign.circle"
        case .notice: return "megaphone"
        case .summary: return "calendar.badge.clock"
        }
    }
}

struct AlertEvent: Codable, Identifiable, Hashable {
    /// Deduplication key: the same key never fires twice.
    let id: String
    let date: Date
    let category: AlertCategory
    let severity: Int            // Risk raw value
    let title: String
    let body: String
    var coordinate: Coordinate?
    var read: Bool = false
    /// After this time the condition no longer applies (aurora windows, space-weather alerts).
    var expires: Date?
    /// The same alert across its updates (an IMO warning for a region, a road
    /// section, a station): a new version notifies only when it is worse.
    var group: String?
    /// When the condition begins, when it is still to come (a warning from tomorrow 9:00).
    var starts: Date?

    var risk: Risk { Risk(rawValue: severity) ?? .caution }
    var lifecycleGroup: String { group ?? id }
}

enum AuroraWatchMode: String, CaseIterable, Identifiable {
    case off, night, always
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return String(localized: "Spenta")
        case .night: return String(localized: "Di notte")
        case .always: return String(localized: "Sempre")
        }
    }
}

struct AlertSettings: Codable, Equatable {
    var enabled: Set<AlertCategory> = [.weatherWarning, .wind, .arrival, .road, .quake, .safeTravel, .aurora, .flight, .speed]
    var includeYellow = false
    var gustThreshold = 25.0          // m/s
    var gustRadiusKm = 25.0
    var roadRadiusKm = 40.0
    var quakeMagnitude = 3.0
    var quakeRadiusKm = 80.0
    var auroraScore = 50              // legacy (score removed), kept so stored settings still decode
    /// Minimum observability class for aurora notifications (ObservabilityClass raw value).
    var auroraMinClass: Int?
    /// NOAA K-index alerts and NASA CMEs notify from this Kp.
    var auroraKpAlert: Double?
    /// "off", "night" (default) or "always": the aurora checked every few minutes with the app closed.
    var auroraWatchMode: String?
    /// Norður's own sound for each kind of alert (nil = on); off: the iPhone's standard sound.
    var customSoundsOff: Bool?
    var customSounds: Bool { customSoundsOff != true }
    var spoken = true
    /// Also notify for the place chosen by hand (off: only where you really are and the trip stops).
    var followChosenPlace: Bool?
    /// Places followed without being in the trip (the bell next to the place): their
    /// IMO warnings, closed roads and quakes are notified, at most `followLimit`.
    var followedPlaces: [Place]?
    static let followLimit = 5
    var followed: [Place] { followedPlaces ?? [] }
    func follows(_ place: Place) -> Bool { followed.contains { $0.coordinate.key == place.coordinate.key } }
    /// The evening summary of tomorrow's travel (nil = on).
    var eveningSummaryOff: Bool?
    /// At night only danger rings; orange is silent, the rest quiet (nil = on).
    var quietNightsOff: Bool?
    var followsChosenPlace: Bool { followChosenPlace == true }
    var eveningSummary: Bool { eveningSummaryOff != true }
    var quietNights: Bool { quietNightsOff != true }
    var backgroundLocation = true     // position-based checks with the app closed (needs "Always")
    /// Tolls and paid parking near you while driving (nil = on), and from how far (km, nil = 10).
    var tollsOff: Bool?
    var tollRadius: Double?
    var tolls: Bool { tollsOff != true }
    var tollRadiusKm: Double { tollRadius ?? 10 }
    var followedFlights: [String] = []

    private static let key = "alertSettings"

    static func load() -> AlertSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              var settings = try? JSONDecoder().decode(AlertSettings.self, from: data) else { return AlertSettings() }
        // v2: position-based background alerts are on by default, also for existing installs.
        if !UserDefaults.standard.bool(forKey: "alertSettings.v2") {
            settings.backgroundLocation = true
            UserDefaults.standard.set(true, forKey: "alertSettings.v2")
            settings.save()
        }
        // v3: the arrival at a trip stop (conditions measured there by vedur.is) is on by default.
        if !UserDefaults.standard.bool(forKey: "alertSettings.v3") {
            settings.enabled.insert(.arrival)
            UserDefaults.standard.set(true, forKey: "alertSettings.v3")
            settings.save()
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    func isOn(_ category: AlertCategory) -> Bool { enabled.contains(category) }

    var auroraClass: ObservabilityClass { ObservabilityClass(rawValue: auroraMinClass ?? ObservabilityClass.good.rawValue) ?? .good }
    var auroraKp: Double { auroraKpAlert ?? 4 }
    var auroraWatch: AuroraWatchMode { AuroraWatchMode(rawValue: auroraWatchMode ?? "") ?? .night }
}

/// Everything the engine looks at in one pass.
struct AlertInput {
    struct Watched {
        let name: String
        let coordinate: Coordinate
        let from: Date
        let to: Date
        /// The device's current position (wind/road/quake checks use it).
        let isCurrent: Bool
    }

    var watched: [Watched] = []
    var warnings: [WeatherWarning] = []
    var roads: RoadNetwork?
    /// umferdin.is: road sections with positions, hazards and roadworks.
    var roadInfo: RoadInfo?
    /// Section lines, for exact distances (bounding boxes otherwise).
    var roadGeometry: RoadGeometry?
    var quakes: [Quake] = []
    var news: [NewsItem] = []
    /// Aurora engine output at the current position, and the space-weather state behind it.
    var auroraSlots: [AuroraSlot] = []
    var auroraState: AuroraState?
    var auroraZone: TimeZone = .iceland
    /// Aurora reports from Norður users (last hours), crossed with the slots above.
    var sightings: [SightingReport] = []
    var flights: [Flight] = []
    var ferry: FerryNotice?
    /// The drives between trip stops in the next days, with their forecast.
    var legs: [TripLegCheck] = []
    /// The forecast where you are (or at the place chosen), next hours.
    var hereHours: [TripLegCheck.Hour] = []
    var herePlace = ""
    /// vedur.is 10-minute measurements around where you are (last 30 minutes).
    var measured: [IMOObservation] = []
    /// Trip stops you are approaching now, with what vedur.is measures and forecasts there.
    var arrivals: [ArrivalCheck] = []
    var now = Date()
}

/// A trip stop of today you are getting close to (2–30 km): the latest vedur.is
/// measurement near it, its forecast for the next hours and the warnings there.
struct ArrivalCheck {
    let stopID: String
    let name: String
    let coordinate: Coordinate
    let distanceKm: Double
    var measured: IMOObservation?
    /// Strongest gust and mean wind forecast for the next 3 hours, and their source.
    var maxGust: Double?
    var maxWind: Double?
    var official: Bool = false
}

enum AlertEngine {
    /// Pure function: returns candidate events; the caller drops already-fired keys.
    static func evaluate(_ input: AlertInput, settings: AlertSettings) -> [AlertEvent] {
        var events: [AlertEvent] = []
        let now = input.now
        let current = input.watched.first { $0.isCurrent }

        if settings.isOn(.weatherWarning) {
            let minimum: WarningColor = settings.includeYellow ? .yellow : .orange
            for warning in input.warnings where warning.color >= minimum && warning.isRelevant(at: now) {
                guard let place = input.watched.first(where: { warning.covers($0.coordinate) && warning.overlaps($0.from, $0.to) }) else { continue }
                let when = warning.isActive(at: now) ? String(localized: "in corso") : String(localized: "dalle \(Fmt.dayTime(warning.onset, in: .iceland))")
                events.append(AlertEvent(
                    id: "w:\(warning.identifier)", date: now, category: .weatherWarning, severity: warning.color.risk.rawValue,
                    title: "\(warning.color.label): \(warning.headline)",
                    body: String(localized: "\(place.name) · \(warning.region) · \(when) fino alle \(Fmt.time(warning.expires, in: .iceland))"),
                    coordinate: place.coordinate, expires: warning.expires, group: "w:\(warning.region)", starts: warning.onset))
            }
        }

        if let current, settings.isOn(.wind) {
            // Measured gusts near you: Vegagerðin road stations and vedur.is weather stations;
            // the strongest one over the threshold makes the alert.
            struct Gust { let id: String; let name: String; let gust: Double; let mean: Double?; let direction: String; let km: Double; let coordinate: Coordinate?; let source: String; let time: Date? }
            var gusts: [Gust] = []
            for station in input.roads?.stations ?? [] {
                guard let c = station.coordinate, !station.isOutdated, let gust = station.Vindhvida, gust >= settings.gustThreshold else { continue }
                let km = Geo.distanceKm(c, current.coordinate)
                if km <= settings.gustRadiusKm {
                    gusts.append(Gust(id: "g:\(station.id)", name: station.name, gust: gust, mean: station.Vindhradi, direction: station.windDirection,
                                      km: km, coordinate: c, source: "Vegagerðin", time: nil))
                }
            }
            for o in input.measured {
                guard let gust = o.gust, gust >= settings.gustThreshold, now.timeIntervalSince(o.time) <= 30 * 60 else { continue }
                let c = IMOForecast.station(o.stationID)?.coordinate
                let km = c.map { Geo.distanceKm($0, current.coordinate) } ?? o.distanceKm
                if km <= settings.gustRadiusKm {
                    gusts.append(Gust(id: "gv:\(o.stationID)", name: o.station, gust: gust, mean: o.wind, direction: Fmt.compass(o.degrees),
                                      km: km, coordinate: c, source: "vedur.is", time: o.time))
                }
            }
            if let first = gusts.max(by: { $0.gust < $1.gust }) {
                let risk = Risk.wind(mean: first.mean, gust: first.gust)
                // Re-arms every 3 hours while the condition persists.
                let bucket = Int(now.timeIntervalSince1970 / (3 * 3600))
                let measuredAt = first.time.map { String(localized: " Misurata da vedur.is alle \(Fmt.time($0, in: .iceland)).") } ?? String(localized: " Stazione stradale Vegagerðin.")
                events.append(AlertEvent(
                    id: "\(first.id):\(bucket)", date: now, category: .wind, severity: risk.rawValue,
                    title: String(localized: "Raffiche di \(Fmt.ms(first.gust)) a \(first.name)"),
                    body: String(localized: "A \(Int(first.km)) km da te. Vento medio \(Fmt.ms(first.mean)) \(first.direction). \(Risk.windAdvice(risk))") + measuredAt,
                    coordinate: first.coordinate, expires: now.addingTimeInterval(3 * 3600), group: first.id))
            }
        }

        if settings.isOn(.arrival) {
            for a in input.arrivals {
                var parts: [String] = []
                var risk = Risk.ok
                if let o = a.measured {
                    parts.append(String(localized: "Adesso a \(o.station): vento \(Fmt.ms(o.wind)), raffica \(Fmt.ms(o.gust)), \(Fmt.temp(o.temperature)) (vedur.is, \(Fmt.time(o.time, in: .iceland)))."))
                    risk = max(risk, Risk.wind(mean: o.wind, gust: o.gust))
                }
                if let g = a.maxGust {
                    parts.append(a.official
                        ? String(localized: "Prossime 3 ore: vento fino a \(Fmt.ms(a.maxWind)), raffiche fino a \(Fmt.ms(g)) (previsione vedur.is).")
                        : String(localized: "Prossime 3 ore: vento fino a \(Fmt.ms(a.maxWind)), raffiche fino a \(Fmt.ms(g)) (modello)."))
                    risk = max(risk, Risk.wind(mean: a.maxWind, gust: g))
                }
                let warnings = input.warnings.filter { $0.covers(a.coordinate) && $0.isRelevant(at: now) }
                if let w = warnings.max(by: { $0.color < $1.color }) {
                    parts.append("\(w.color.label): \(w.headline).")
                    risk = max(risk, w.color.risk)
                }
                // Always told you are arriving: without any data, where to look.
                if parts.isEmpty {
                    parts.append(String(localized: "Nessun dato meteo disponibile: controlla su vedur.is e umferdin.is."))
                }
                let day = Int(Calendar.iceland.startOfDay(for: now).timeIntervalSince1970)
                events.append(AlertEvent(
                    id: "arr:\(a.stopID):\(day)", date: now, category: .arrival, severity: risk.rawValue,
                    title: String(localized: "In arrivo a \(a.name) (\(Int(a.distanceKm.rounded())) km)"),
                    body: parts.joined(separator: " "),
                    coordinate: a.coordinate, expires: now.addingTimeInterval(3 * 3600), group: "arr:\(a.stopID)"))
            }
        }

        if let roads = input.roads, let current {
            if settings.isOn(.road), input.roadInfo == nil {
                // Fallback when umferdin.is is unavailable: segments found through nearby road stations.
                var seen = Set<Int>()
                for station in roads.stations {
                    guard let c = station.coordinate, Geo.distanceKm(c, current.coordinate) <= settings.roadRadiusKm else { continue }
                    for segment in roads.segments(for: station) where segment.risk == .danger && seen.insert(segment.id).inserted {
                        events.append(AlertEvent(
                            id: "r:\(segment.id):\(segment.AstandYfirbord ?? "")", date: now, category: .road, severity: Risk.danger.rawValue,
                            title: "\(segment.conditionItalian): \(segment.name)",
                            body: String(localized: "Tratto vicino a \(station.name), a \(Int(Geo.distanceKm(c, current.coordinate))) km da te. Verifica su umferdin.is o chiama il 1777."),
                            coordinate: c, group: "r:\(segment.id)"))
                    }
                }
            }
        }

        if settings.isOn(.road), let info = input.roadInfo {
            events += roadEvents(info, input: input, settings: settings)
        }

        if settings.isOn(.quake) {
            for quake in input.quakes where now.timeIntervalSince(quake.date) <= 3 * 3600 {
                let near = input.watched.map { (Geo.distanceKm($0.coordinate, quake.coordinate), $0) }.min { $0.0 < $1.0 }
                let isNear = (near?.0 ?? .infinity) <= settings.quakeRadiusKm && quake.magnitude >= settings.quakeMagnitude
                guard isNear || quake.magnitude >= 4.5 else { continue }
                let distance = near.map { String(localized: " · \(Int($0.0)) km da \($0.1.name)") } ?? ""
                events.append(AlertEvent(
                    id: "q:\(quake.id)", date: now, category: .quake, severity: quake.risk.rawValue,
                    title: String(localized: "Terremoto M\(Fmt.number(quake.magnitude, decimals: 1)) – \(quake.region)"),
                    body: String(localized: "\(Fmt.time(quake.date, in: .iceland)), profondità \(Fmt.number(quake.depth, decimals: 1, unit: "km"))\(distance)"),
                    coordinate: quake.coordinate))
            }
        }

        if settings.isOn(.safeTravel) {
            for item in input.news where item.risk >= .warning {
                guard let date = item.date, now.timeIntervalSince(date) <= 3 * 24 * 3600 else { continue }
                events.append(AlertEvent(
                    id: "s:\(item.id)", date: now, category: .safeTravel, severity: item.risk.rawValue,
                    title: String(localized: "SafeTravel: \(item.title)"), body: String(item.summary.prefix(220))))
            }
        }

        events += travelEvents(input, settings: settings)

        if settings.isOn(.aurora) {
            events += auroraEvents(input, settings: settings)
        }

        if settings.isOn(.flight) {
            let followed = Set(settings.followedFlights.map { $0.uppercased() })
            for flight in input.flights where followed.contains(flight.flightNumber.uppercased()) {
                let info = flight.statusInfo
                let key = "f:\(flight.flightNumber):\(flight.status ?? ""):\(flight.updatedTime ?? ""):\(flight.gate ?? "")"
                events.append(AlertEvent(
                    id: key, date: now, category: .flight, severity: info.risk.rawValue,
                    title: "\(flight.flightNumber) \(flight.arrival ? "da" : "per") \(flight.destination ?? "") – \(info.text)",
                    body: String(localized: "Orario \(flight.time ?? "–")\(flight.gate.map { $0.isEmpty ? "" : String(localized: " · gate \($0)") } ?? "")")))
            }
        }

        if settings.isOn(.ferry), let ferry = input.ferry {
            events.append(AlertEvent(
                id: "h:\(stableHash(ferry.text))", date: now, category: .ferry, severity: Risk.caution.rawValue,
                title: String(localized: "Herjólfur – nuovo avviso"), body: String(ferry.text.prefix(240))))
        }

        return events
    }
}

extension AlertEngine {
    /// Aurora notifications. They report conditions verified in the data and
    /// never promise a visible aurora. Keys are bucketed by time (cooldown) and
    /// each event carries an expiry.
    static func auroraEvents(_ input: AlertInput, settings: AlertSettings) -> [AlertEvent] {
        var events: [AlertEvent] = []
        let now = input.now, zone = input.auroraZone
        let bucket3h = Int(now.timeIntervalSince1970 / 10800)
        let minClass = settings.auroraClass

        // People are seeing it near you (community reports, after dark only).
        if let here = input.watched.first(where: \.isCurrent) {
            let slot = input.auroraSlots.first { abs($0.date.timeIntervalSince(now)) < 1800 }
            let confirmation = AuroraConfirmation.evaluate(input.sightings, at: here.coordinate, now: now,
                                                           modelActivity: slot?.activityFactor, clear: slot?.clear)
            if confirmation.status >= .likely, (slot?.darkness ?? .night) >= .nautical {
                let confirmed = confirmation.status == .confirmed
                events.append(AlertEvent(
                    id: "\(confirmed ? "seen-confirmed" : "seen"):\(Int(now.timeIntervalSince1970 / 7200))", date: now, category: .aurora,
                    severity: (confirmed ? Risk.warning : Risk.caution).rawValue,
                    title: confirmed ? String(localized: "Aurora in corso: confermata da \(confirmation.positives) persone vicino a te")
                                     : String(localized: "Aurora segnalata a \(Int((confirmation.nearestKm ?? 0).rounded())) km da te"),
                    body: confirmation.detail,
                    coordinate: here.coordinate,
                    expires: now.addingTimeInterval(60 * 60)))
            }
        }

        // Observing conditions here, now (OVATION-based when valid).
        if let slot = input.auroraSlots.first(where: { abs($0.date.timeIntervalSince(now)) < 1800 }),
           slot.observability >= minClass, slot.darkness >= .nautical, slot.reliability >= .medium {
            let activity = slot.activitySource == "OVATION"
                ? String(localized: "OVATION \(Int(slot.ovationValue ?? 0)) nel tuo cielo")
                : "Kp \(Fmt.number(slot.kp, decimals: 1))"
            let look = slot.lookAzimuth.map { String(localized: " Guarda verso \(AuroraEngine.compass($0)).") } ?? ""
            events.append(AlertEvent(
                id: "aurora-now:\(bucket3h)", date: now, category: .aurora, severity: Risk.caution.rawValue,
                title: String(localized: "Condizioni \(slot.observability.label.lowercased()) per l'aurora, adesso"),
                body: String(localized: "Stima euristica: \(activity), cielo sereno al \(Int(((slot.clear ?? 0) * 100).rounded()))%.\(look) Non è garanzia di aurora visibile."),
                expires: now.addingTimeInterval(90 * 60)))
        } else if let best = AuroraEngine.best(input.auroraSlots, within: 6, now: now), best.date > now.addingTimeInterval(1800),
                  best.observability >= minClass {
            // A favourable window later tonight.
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let night = calendar.startOfDay(for: best.date.addingTimeInterval(-12 * 3600))
            events.append(AlertEvent(
                id: "aurora-window:\(Int(night.timeIntervalSince1970))", date: now, category: .aurora, severity: Risk.ok.rawValue,
                title: String(localized: "Finestra \(best.observability.label.lowercased()) per l'aurora verso le \(Fmt.time(best.date, in: zone))"),
                body: String(localized: "\(best.reasons.first ?? String(localized: "Buio e cielo in gran parte sereno")). Affidabilità \(best.reliability.label.lowercased()): ricontrolla più tardi."),
                expires: best.date.addingTimeInterval(3600)))
        }

        // Ahead of time: the solar wind on its way will reach a dark, clear sky here.
        let verdict = AuroraVerdict.make(slots: input.auroraSlots, state: input.auroraState, zone: zone, now: now)
        if verdict.level == .soon, minClass <= .good {
            events.append(AlertEvent(
                id: "aurora-soon:\(Int(now.timeIntervalSince1970 / 7200))", date: now, category: .aurora, severity: Risk.caution.rawValue,
                title: verdict.title, body: verdict.detail, expires: verdict.at?.addingTimeInterval(3600)))
        }
        guard let state = input.auroraState else { return events }

        // Persistent southward IMF (measured, fresh data only).
        if state.source("solarWind")?.isOK == true, let sw = state.solarWind,
           sw.bzSouth.continuousMinutes >= 30, let bz = sw.average(30)?.bz, bz <= -8 {
            let lead = sw.propagation.map { String(localized: " Arriva a terra tra ~\(Int($0.minutes)) min.") } ?? ""
            events.append(AlertEvent(
                id: "bz:\(bucket3h)", date: now, category: .aurora, severity: Risk.caution.rawValue,
                title: String(localized: "Bz negativo persistente: \(Fmt.number(bz, decimals: 0)) nT da \(sw.bzSouth.continuousMinutes) min"),
                body: String(localized: "Il campo interplanetario è orientato a sud: favorisce l'attività geomagnetica.\(lead) Non garantisce un'aurora visibile."),
                expires: now.addingTimeInterval(3 * 3600)))
        }
        if state.source("solarWind")?.isOK == true, let shock = state.solarWind?.shocks.last, now.timeIntervalSince(shock.date) < 3600 {
            events.append(AlertEvent(
                id: "shock:\(Int(shock.t))", date: now, category: .aurora, severity: Risk.caution.rawValue,
                title: String(localized: "Possibile shock nel vento solare"),
                body: String(localized: "A L1 alle \(Fmt.time(shock.date, in: zone)): velocità +\(Int(shock.dv)) km/s, densità ×\(Fmt.number(shock.densityRatio, decimals: 1)). Rilevamento automatico: l'attività potrebbe aumentare nella prossima ora."),
                expires: now.addingTimeInterval(3 * 3600)))
        }
        // NOAA K-index warnings/alerts in force.
        for alert in state.alerts ?? [] where alert.active == true {
            guard let k = alert.kp, Double(k) >= settings.auroraKp else { continue }
            events.append(AlertEvent(
                id: "swpc:\(alert.id)", date: now, category: .aurora, severity: (k >= 7 ? Risk.warning : Risk.caution).rawValue,
                title: String(localized: "NOAA: attività geomagnetica Kp \(k)"),
                body: [alert.italian + ".",
                       alert.issuedDate.map { String(localized: "Emesso \(Fmt.dayTime($0, in: zone))") },
                       alert.validTo.flatMap { DateParse.iso($0) }.map { String(localized: "valido fino a \(Fmt.dayTime($0, in: zone))") },
                       zone == .iceland ? String(localized: "(ora islandese)") : nil]
                    .compactMap { $0 }.joined(separator: " "),
                expires: alert.validTo.flatMap { DateParse.iso($0) }))
        }
        // NASA DONKI CME expected at Earth within 36 h.
        for cme in state.donki?.upcoming ?? [] {
            guard let arrival = cme.arrivalDate, let kp = cme.expectedKp, kp >= settings.auroraKp,
                  arrival > now.addingTimeInterval(-6 * 3600), arrival < now.addingTimeInterval(36 * 3600) else { continue }
            let range = cme.kp.map { "Kp \(Fmt.number($0.min))–\(Fmt.number($0.max))" } ?? ""
            events.append(AlertEvent(
                id: "cme:\(cme.id)", date: now, category: .aurora, severity: (kp >= 7 ? Risk.warning : Risk.caution).rawValue,
                title: cme.glancing ? String(localized: "CME di striscio in arrivo") : String(localized: "Espulsione di massa coronale in arrivo"),
                body: String(localized: "NASA (WSA-ENLIL) prevede l'arrivo verso \(Fmt.dayTime(arrival, in: zone)) ±7 h, \(range). L'effetto dipende dal Bz all'arrivo."),
                expires: arrival.addingTimeInterval((cme.durationHours ?? 18) * 3600)))
        }
        // NOAA ENLIL: CME material predicted at Earth within 36 h.
        for arrival in state.enlil?.cmeArrivals ?? [] {
            guard let t = arrival.date, t > now, t < now.addingTimeInterval(36 * 3600) else { continue }
            events.append(AlertEvent(
                id: "enlil:\(Int(t.timeIntervalSince1970 / 3600))", date: now, category: .aurora, severity: Risk.ok.rawValue,
                title: String(localized: "Possibile arrivo di una CME verso \(Fmt.dayTime(t, in: zone))"),
                body: String(localized: "Il modello WSA-ENLIL di NOAA prevede l'arrivo di materiale di CME sulla Terra (picco ~\(Int(arrival.peakSpeed)) km/s). Intensità non prevedibile prima dell'arrivo."),
                expires: t.addingTimeInterval(24 * 3600)))
        }
        return events
    }
}

// MARK: - Roads (umferdin.is)

extension AlertEngine {
    /// Road alerts from umferdin.is: closures and dangerous surfaces near where you
    /// are, closures near the trip stops, and roadworks or hazards within 10 km of
    /// your position (each fires once; hazards expire with their end date).
    static func roadEvents(_ info: RoadInfo, input: AlertInput, settings: AlertSettings) -> [AlertEvent] {
        let now = input.now
        var events: [AlertEvent] = []
        var seen = Set<String>()
        for place in input.watched {
            for section in info.sections {
                guard let risk = section.risk, risk >= .warning || section.isClosed,
                      let km = input.roadGeometry?.distanceKm(from: place.coordinate, to: section.id) ?? section.distanceKm(to: place.coordinate) else { continue }
                if !place.isCurrent && !section.isClosed { continue }
                // Closures and dangerous surfaces within the road radius; slippery or snowy ones close by.
                let radius = section.isClosed || risk == .danger ? settings.roadRadiusKm : min(settings.roadRadiusKm, 15)
                guard km <= (place.isCurrent ? radius : min(radius, 25)), seen.insert(section.id).inserted else { continue }
                let road = section.numbers.isEmpty ? section.name : "\(section.name) (\(section.numbers))"
                let whereText = place.isCurrent
                    ? String(localized: "a \(Int(km.rounded())) km da te")
                    : String(localized: "vicino a \(place.name)")
                events.append(AlertEvent(
                    id: "ri:\(section.id):\(section.condition?.category ?? "")", date: now, category: .road,
                    severity: (section.isClosed ? Risk.danger : risk).rawValue,
                    title: "\(section.label): \(road)",
                    body: String(localized: "Tratto \(whereText). Aggiornato \(Fmt.time(section.condition?.updated, in: .iceland)). Fonte: Vegagerðin (umferdin.is), informazioni 1777."),
                    coordinate: section.center?.coordinate, group: "road:\(section.id)"))
            }
        }
        if let here = input.watched.first(where: \.isCurrent)?.coordinate {
            for section in info.sections {
                for hazard in section.hazards {
                    guard let at = hazard.at?.coordinate, hazard.start.map({ $0 <= now }) ?? true else { continue }
                    let km = Geo.distanceKm(at, here)
                    guard km <= 10 else { continue }
                    let kind = RoadCode.hazard(hazard.code)
                    let end = hazard.end.map { String(localized: "Fino al \(Fmt.dayTime($0, in: .iceland)).") }
                    let parts = [hazard.text, end].compactMap { text -> String? in
                        guard let text, !text.isEmpty else { return nil }
                        return text
                    }
                    events.append(AlertEvent(
                        id: "rh:\(hazard.id)", date: now, category: .road, severity: Risk.caution.rawValue,
                        title: String(localized: "\(kind.label) a \(Int(km.rounded())) km: \(section.name)"),
                        body: parts.isEmpty ? section.numbers : parts.joined(separator: " "),
                        coordinate: at, expires: hazard.end))
                }
            }
        }
        return events
    }
}

extension AlertEvent {
    /// The sound file (Nordur/Sounds) for this alert: the aurora its own, the rest by kind.
    var soundName: String {
        let prefix = id.split(separator: ":").first.map(String.init) ?? ""
        switch category {
        case .aurora: return prefix == "aurora-now" || prefix.hasPrefix("seen") ? "aurora_now" : "aurora_soon"
        case .weatherWarning: return risk >= .warning ? "warning_urgent" : "warning"
        case .wind: return "wind"
        case .arrival: return risk >= .warning ? "warning" : "info"
        case .road: return "road"
        case .quake: return "quake"
        case .safeTravel: return "info"
        case .flight: return "flight"
        case .ferry: return "ferry"
        case .speed: return "speed"
        case .toll: return "road"
        case .notice, .summary: return "info"
        }
    }
}
