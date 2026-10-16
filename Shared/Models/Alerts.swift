import Foundation

enum AlertCategory: String, Codable, CaseIterable, Identifiable {
    case weatherWarning, wind, road, quake, safeTravel, aurora, flight, ferry, speed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weatherWarning: return "Allerte meteo IMO"
        case .wind: return "Raffiche forti vicino a te"
        case .road: return "Strade chiuse o impraticabili"
        case .quake: return "Terremoti"
        case .safeTravel: return "Avvisi SafeTravel"
        case .aurora: return "Aurora boreale"
        case .flight: return "Voli seguiti (KEF)"
        case .ferry: return "Traghetto Herjólfur"
        case .speed: return "Limite di velocità (in guida)"
        }
    }

    var symbol: String {
        switch self {
        case .weatherWarning: return "exclamationmark.triangle.fill"
        case .wind: return "wind"
        case .road: return "road.lanes"
        case .quake: return "waveform.path.ecg"
        case .safeTravel: return "megaphone.fill"
        case .aurora: return "sparkles"
        case .flight: return "airplane"
        case .ferry: return "ferry.fill"
        case .speed: return "gauge.with.dots.needle.67percent"
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

    var risk: Risk { Risk(rawValue: severity) ?? .caution }
}

struct AlertSettings: Codable, Equatable {
    var enabled: Set<AlertCategory> = [.weatherWarning, .wind, .road, .quake, .safeTravel, .aurora, .flight, .speed]
    var includeYellow = false
    var gustThreshold = 25.0          // m/s
    var gustRadiusKm = 25.0
    var roadRadiusKm = 40.0
    var quakeMagnitude = 3.0
    var quakeRadiusKm = 80.0
    var auroraScore = 50
    var spoken = true
    var backgroundLocation = false    // significant-change monitoring (needs "Always")
    var followedFlights: [String] = []

    private static let key = "alertSettings"

    static func load() -> AlertSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(AlertSettings.self, from: data) else { return AlertSettings() }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    func isOn(_ category: AlertCategory) -> Bool { enabled.contains(category) }
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
    var quakes: [Quake] = []
    var news: [NewsItem] = []
    var aurora: AuroraOutlook?
    var auroraZone: TimeZone = .iceland
    var flights: [Flight] = []
    var ferry: FerryNotice?
    var now = Date()
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
                let when = warning.isActive(at: now) ? "in corso" : "dalle \(Fmt.dayTime(warning.onset, in: .iceland))"
                events.append(AlertEvent(
                    id: "w:\(warning.identifier)", date: now, category: .weatherWarning, severity: warning.color.risk.rawValue,
                    title: "\(warning.color.label): \(warning.headline)",
                    body: "\(place.name) · \(warning.region) · \(when) fino alle \(Fmt.time(warning.expires, in: .iceland))",
                    coordinate: place.coordinate))
            }
        }

        if let roads = input.roads, let current {
            if settings.isOn(.wind) {
                let nearby = roads.stations.compactMap { station -> (RoadStation, Double)? in
                    guard let c = station.coordinate, !station.isOutdated, let gust = station.Vindhvida, gust >= settings.gustThreshold else { return nil }
                    let km = Geo.distanceKm(c, current.coordinate)
                    return km <= settings.gustRadiusKm ? (station, km) : nil
                }.sorted { ($0.0.Vindhvida ?? 0) > ($1.0.Vindhvida ?? 0) }
                if let first = nearby.first {
                    let (station, km) = first
                    // Re-arms every 3 hours while the condition persists.
                    let bucket = Int(now.timeIntervalSince1970 / (3 * 3600))
                    events.append(AlertEvent(
                        id: "g:\(station.id):\(bucket)", date: now, category: .wind, severity: station.windRisk.rawValue,
                        title: "Raffiche di \(Fmt.ms(station.Vindhvida)) a \(station.name)",
                        body: "A \(Int(km)) km da te. Vento medio \(Fmt.ms(station.Vindhradi)) \(station.windDirection). \(Risk.windAdvice(station.windRisk))",
                        coordinate: station.coordinate))
                }
            }
            if settings.isOn(.road) {
                var seen = Set<Int>()
                for station in roads.stations {
                    guard let c = station.coordinate, Geo.distanceKm(c, current.coordinate) <= settings.roadRadiusKm else { continue }
                    for segment in roads.segments(for: station) where segment.risk == .danger && seen.insert(segment.id).inserted {
                        events.append(AlertEvent(
                            id: "r:\(segment.id):\(segment.AstandYfirbord ?? "")", date: now, category: .road, severity: Risk.danger.rawValue,
                            title: "\(segment.conditionItalian): \(segment.name)",
                            body: "Tratto vicino a \(station.name), a \(Int(Geo.distanceKm(c, current.coordinate))) km da te. Verifica su umferdin.is o chiama il 1777.",
                            coordinate: c))
                    }
                }
            }
        }

        if settings.isOn(.quake) {
            for quake in input.quakes where now.timeIntervalSince(quake.date) <= 3 * 3600 {
                let near = input.watched.map { (Geo.distanceKm($0.coordinate, quake.coordinate), $0) }.min { $0.0 < $1.0 }
                let isNear = (near?.0 ?? .infinity) <= settings.quakeRadiusKm && quake.magnitude >= settings.quakeMagnitude
                guard isNear || quake.magnitude >= 4.5 else { continue }
                let distance = near.map { " · \(Int($0.0)) km da \($0.1.name)" } ?? ""
                events.append(AlertEvent(
                    id: "q:\(quake.id)", date: now, category: .quake, severity: quake.risk.rawValue,
                    title: "Terremoto M\(Fmt.number(quake.magnitude, decimals: 1)) – \(quake.region)",
                    body: "\(Fmt.time(quake.date, in: .iceland)), profondità \(Fmt.number(quake.depth, decimals: 1, unit: "km"))\(distance)",
                    coordinate: quake.coordinate))
            }
        }

        if settings.isOn(.safeTravel) {
            for item in input.news where item.risk >= .warning {
                guard let date = item.date, now.timeIntervalSince(date) <= 3 * 24 * 3600 else { continue }
                events.append(AlertEvent(
                    id: "s:\(item.id)", date: now, category: .safeTravel, severity: item.risk.rawValue,
                    title: "SafeTravel: \(item.title)", body: String(item.summary.prefix(220))))
            }
        }

        if settings.isOn(.aurora), let aurora = input.aurora, let best = aurora.best,
           best.score >= settings.auroraScore, best.date.timeIntervalSince(now) <= 6 * 3600 {
            let night = Fmt.day(now.addingTimeInterval(-12 * 3600), in: input.auroraZone)
            events.append(AlertEvent(
                id: "a:\(night)", date: now, category: .aurora, severity: Risk.ok.rawValue,
                title: "Aurora probabile stanotte 🌌",
                body: "Punteggio \(best.score)/100 verso le \(Fmt.time(best.date, in: input.auroraZone)), nuvole \(Fmt.percent(best.cloudCover)), Kp \(Fmt.number(best.kp, decimals: 1))."))
        }

        if settings.isOn(.flight) {
            let followed = Set(settings.followedFlights.map { $0.uppercased() })
            for flight in input.flights where followed.contains(flight.flightNumber.uppercased()) {
                let info = flight.statusInfo
                let key = "f:\(flight.flightNumber):\(flight.status ?? ""):\(flight.updatedTime ?? ""):\(flight.gate ?? "")"
                events.append(AlertEvent(
                    id: key, date: now, category: .flight, severity: info.risk.rawValue,
                    title: "\(flight.flightNumber) \(flight.arrival ? "da" : "per") \(flight.destination ?? "") – \(info.text)",
                    body: "Orario \(flight.time ?? "–")\(flight.gate.map { $0.isEmpty ? "" : " · gate \($0)" } ?? "")"))
            }
        }

        if settings.isOn(.ferry), let ferry = input.ferry {
            events.append(AlertEvent(
                id: "h:\(stableHash(ferry.text))", date: now, category: .ferry, severity: Risk.caution.rawValue,
                title: "Herjólfur – nuovo avviso", body: String(ferry.text.prefix(240))))
        }

        return events
    }
}
