import Foundation

/// A day of driving between two trip stops, with the forecast along the way
/// (a few points on the line between them, the worst of them hour by hour).
struct TripLegCheck {
    struct Hour {
        let date: Date
        var gust: Double?
        var precipitation: Double?
        var snowfall: Double?
        /// Rain or drizzle with the temperature around zero somewhere on the way.
        var ice = false
    }

    let from: String
    let to: String
    /// The travel day (start of the day, Iceland time).
    let day: Date
    let samples: [Coordinate]
    var hours: [Hour] = []

    var route: String { "\(from) → \(to)" }
    var key: String { "\(from)>\(to)@\(Int(day.timeIntervalSince1970 / 86400))" }

    /// Points every ~50 km on the line between the two stops, ends included.
    static func samples(from a: Coordinate, to b: Coordinate) -> [Coordinate] {
        let n = max(1, min(6, Int((Geo.distanceKm(a, b) / 50).rounded(.up))))
        return (0...n).map { i in
            let f = Double(i) / Double(n)
            return Coordinate(lat: a.lat + (b.lat - a.lat) * f, lon: a.lon + (b.lon - a.lon) * f)
        }
    }

    /// Merges the hourly forecast of one sample into the worst-case hours.
    static func merge(_ hours: inout [Date: Hour], _ forecast: Forecast, from start: Date, to end: Date) {
        guard let h = forecast.hourly else { return }
        for (i, t) in h.time.enumerated() {
            let date = Date(timeIntervalSince1970: TimeInterval(t))
            guard date >= start, date < end else { continue }
            let gust = h.wind_gusts_10m?[safe: i] ?? nil
            let rain = h.precipitation?[safe: i] ?? nil
            let snow = h.snowfall?[safe: i] ?? nil
            let temp = h.temperature_2m?[safe: i] ?? nil
            var hour = hours[date] ?? Hour(date: date)
            hour.gust = max(hour.gust ?? 0, gust ?? 0)
            hour.precipitation = max(hour.precipitation ?? 0, rain ?? 0)
            hour.snowfall = max(hour.snowfall ?? 0, snow ?? 0)
            if let temp, let rain, temp > -3, temp <= 1, rain >= 0.2, (snow ?? 0) < rain * 0.5 { hour.ice = true }
            hours[date] = hour
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

extension AlertEngine {
    /// What the forecast holds for the drives of the next days and for the next
    /// hours where you are: wind, heavy rain, snow, ice; and on today's and
    /// tomorrow's routes, closed or dangerous road sections and strong gusts now.
    static func travelEvents(_ input: AlertInput, settings: AlertSettings) -> [AlertEvent] {
        var events: [AlertEvent] = []
        let now = input.now
        let zone = TimeZone.iceland
        let today = Calendar.iceland.startOfDay(for: now)

        for leg in input.legs {
            let day = Fmt.day(leg.day, in: zone)
            let isToday = leg.day == today
            let upcoming = leg.hours.filter { $0.date > now.addingTimeInterval(-3600) }

            if settings.isOn(.wind), let worst = upcoming.max(by: { ($0.gust ?? 0) < ($1.gust ?? 0) }),
               let gust = worst.gust, gust >= settings.gustThreshold {
                let risk: Risk = gust >= 30 ? .danger : gust >= 25 ? .warning : .caution
                events.append(AlertEvent(
                    id: "lw:\(leg.key):\(Int(gust / 5))", date: now, category: .wind, severity: risk.rawValue,
                    title: String(localized: "Vento sul viaggio \(leg.route), \(day)"),
                    body: String(localized: "Raffiche previste fino a \(Fmt.ms(gust)) verso le \(Fmt.time(worst.date, in: zone)) lungo il percorso. \(Risk.windAdvice(risk))"),
                    expires: leg.day.addingTimeInterval(24 * 3600), group: "lw:\(leg.key)", starts: worst.date))
            }

            if settings.isOn(.weatherWarning), let text = weatherSummary(upcoming, zone: zone) {
                events.append(AlertEvent(
                    id: "lm:\(leg.key):\(text.key)", date: now, category: .weatherWarning, severity: text.risk.rawValue,
                    title: String(localized: "Meteo sul viaggio \(leg.route), \(day): \(text.title)"),
                    body: text.body, expires: leg.day.addingTimeInterval(24 * 3600), group: "lm:\(leg.key)"))
            }

            // Roads as they are now matter for today's and tomorrow's drives.
            guard leg.day <= today.addingTimeInterval(36 * 3600) else { continue }
            if settings.isOn(.road), let info = input.roadInfo {
                var seen = Set<String>()
                for section in info.sections {
                    guard section.isClosed || (section.risk ?? .ok) >= .warning else { continue }
                    let near = leg.samples.contains { sample in
                        if let km = input.roadGeometry?.distanceKm(from: sample, to: section.id) { return km <= 15 }
                        return (section.distanceKm(to: sample) ?? .infinity) <= 3
                    }
                    guard near, seen.insert(section.id).inserted else { continue }
                    let road = section.numbers.isEmpty ? section.name : "\(section.name) (\(section.numbers))"
                    events.append(AlertEvent(
                        id: "lr:\(section.id):\(section.condition?.category ?? "")", date: now, category: .road,
                        severity: (section.isClosed ? Risk.danger : (section.risk ?? .warning)).rawValue,
                        title: String(localized: "\(section.label) sul percorso \(leg.route): \(road)"),
                        body: String(localized: "Viaggio di \(day). Aggiornato \(Fmt.time(section.condition?.updated, in: zone)). Fonte: Vegagerðin (umferdin.is), informazioni 1777."),
                        coordinate: section.center?.coordinate, expires: leg.day.addingTimeInterval(24 * 3600), group: "road:\(section.id)"))
                }
            }
            if isToday, settings.isOn(.wind), let roads = input.roads, leg.samples.count >= 2,
               let a = leg.samples.first, let b = leg.samples.last {
                let strong = roads.corridor(from: a, to: b, corridorKm: 15)
                    .filter { ($0.Vindhvida ?? 0) >= settings.gustThreshold }
                    .max { ($0.Vindhvida ?? 0) < ($1.Vindhvida ?? 0) }
                if let station = strong {
                    let bucket = Int(now.timeIntervalSince1970 / (3 * 3600))
                    events.append(AlertEvent(
                        id: "lg:\(station.id):\(bucket)", date: now, category: .wind, severity: station.windRisk.rawValue,
                        title: String(localized: "Raffiche di \(Fmt.ms(station.Vindhvida)) adesso sul percorso di oggi"),
                        body: String(localized: "Stazione \(station.name), sul viaggio \(leg.route). Vento medio \(Fmt.ms(station.Vindhradi)) \(station.windDirection). \(Risk.windAdvice(station.windRisk))"),
                        coordinate: station.coordinate, expires: now.addingTimeInterval(3 * 3600), group: "g:\(station.id)"))
                }
            }
        }

        // Where you are, the next 6 hours.
        let soon = input.hereHours.filter { $0.date > now && $0.date < now.addingTimeInterval(6 * 3600) }
        let bucket = Int(now.timeIntervalSince1970 / (6 * 3600))
        if settings.isOn(.weatherWarning), let text = weatherSummary(soon, zone: zone) {
            events.append(AlertEvent(
                id: "hm:\(bucket):\(text.key)", date: now, category: .weatherWarning, severity: text.risk.rawValue,
                title: String(localized: "Nelle prossime ore a \(input.herePlace): \(text.title)"),
                body: text.body, expires: now.addingTimeInterval(6 * 3600), group: "hm"))
        }
        if settings.isOn(.wind), let worst = soon.max(by: { ($0.gust ?? 0) < ($1.gust ?? 0) }),
           let gust = worst.gust, gust >= settings.gustThreshold {
            let risk: Risk = gust >= 30 ? .danger : gust >= 25 ? .warning : .caution
            events.append(AlertEvent(
                id: "hw:\(bucket):\(Int(gust / 5))", date: now, category: .wind, severity: risk.rawValue,
                title: String(localized: "Raffiche fino a \(Fmt.ms(gust)) nelle prossime ore a \(input.herePlace)"),
                body: String(localized: "Previste verso le \(Fmt.time(worst.date, in: zone)). \(Risk.windAdvice(risk))"),
                expires: now.addingTimeInterval(6 * 3600), group: "hw", starts: worst.date))
        }
        return events
    }

    /// The evening summary of tomorrow, for whoever is travelling: the drive (or
    /// the stop), its wind, rain, snow or ice, the roads closed on the way, the IMO
    /// warnings, and the aurora tonight. Nil without a trip tomorrow.
    static func eveningSummary(_ input: AlertInput) -> AlertEvent? {
        let now = input.now, zone = TimeZone.iceland
        let tomorrow = Calendar.iceland.startOfDay(for: now).addingTimeInterval(24 * 3600)
        let leg = input.legs.first { $0.day == tomorrow }
        let stop = input.watched.first { !$0.isCurrent && $0.from <= tomorrow.addingTimeInterval(12 * 3600) && $0.to >= tomorrow.addingTimeInterval(12 * 3600) }
        guard leg != nil || stop != nil else { return nil }
        var lines: [String] = []
        var risk = Risk.ok
        if let leg {
            let hours = leg.hours
            if let worst = hours.max(by: { ($0.gust ?? 0) < ($1.gust ?? 0) }), let gust = worst.gust, gust >= 15 {
                lines.append(String(localized: "Raffiche fino a \(Fmt.ms(gust)) verso le \(Fmt.time(worst.date, in: zone))"))
                risk = max(risk, gust >= 30 ? .danger : gust >= 25 ? .warning : .caution)
            } else if !hours.isEmpty {
                lines.append(String(localized: "Vento debole o moderato"))
            }
            if let text = weatherSummary(hours, zone: zone) {
                lines.append(text.title.prefix(1).uppercased() + text.title.dropFirst())
                risk = max(risk, text.risk)
            }
            if let info = input.roadInfo {
                let closed = info.sections.filter { section in
                    guard section.isClosed || (section.risk ?? .ok) >= .danger else { return false }
                    return leg.samples.contains { sample in
                        if let km = input.roadGeometry?.distanceKm(from: sample, to: section.id) { return km <= 15 }
                        return (section.distanceKm(to: sample) ?? .infinity) <= 3
                    }
                }
                if closed.isEmpty {
                    lines.append(String(localized: "Nessuna strada chiusa sul percorso"))
                } else {
                    lines.append(String(localized: "Strade chiuse o pericolose sul percorso: \(closed.prefix(3).map(\.name).joined(separator: ", "))"))
                    risk = max(risk, .danger)
                }
            }
        }
        let points = (leg?.samples ?? []) + (stop.map { [$0.coordinate] } ?? [])
        let dayEnd = tomorrow.addingTimeInterval(24 * 3600)
        let warnings = input.warnings.filter { w in
            w.isRelevant(at: now) && w.overlaps(tomorrow, dayEnd) && points.contains { w.covers($0) }
        }
        if let worst = warnings.max(by: { $0.color < $1.color }) {
            lines.append(String(localized: "\(worst.color.label): \(worst.headline)"))
            risk = max(risk, worst.color.risk)
        }
        if let best = AuroraEngine.best(input.auroraSlots, within: 8, now: now), best.observability >= .moderate {
            lines.append(String(localized: "Stanotte aurora: condizioni \(best.observability.label.lowercased()) verso le \(Fmt.time(best.date, in: input.auroraZone))"))
        }
        let title = leg.map { String(localized: "Domani \($0.route)") } ?? String(localized: "Domani a \(stop!.name)")
        return AlertEvent(id: "summary:\(Int(tomorrow.timeIntervalSince1970 / 86400))", date: now, category: .summary,
                          severity: risk.rawValue, title: title, body: lines.joined(separator: " · "),
                          expires: dayEnd, starts: tomorrow)
    }

    /// "pioggia forte, ghiaccio" with the details, when any of them is expected.
    static func weatherSummary(_ hours: [TripLegCheck.Hour], zone: TimeZone) -> (key: String, title: String, body: String, risk: Risk)? {
        guard !hours.isEmpty else { return nil }
        var parts: [String] = [], details: [String] = [], key = "", risk = Risk.caution
        let rainSum = hours.compactMap(\.precipitation).reduce(0, +)
        if let wettest = hours.max(by: { ($0.precipitation ?? 0) < ($1.precipitation ?? 0) }),
           (wettest.precipitation ?? 0) >= 4 || rainSum >= 15 {
            parts.append(String(localized: "pioggia forte"))
            details.append(String(localized: "Fino a \(Fmt.number(wettest.precipitation ?? 0, decimals: 1)) mm/h verso le \(Fmt.time(wettest.date, in: zone)), \(Int(rainSum.rounded())) mm in tutto."))
            key += "r"
        }
        let snowSum = hours.compactMap(\.snowfall).reduce(0, +)
        if snowSum >= 2 {
            parts.append(String(localized: "neve"))
            details.append(String(localized: "Circa \(Int(snowSum.rounded())) cm di neve fresca."))
            key += "s"
            if snowSum >= 8 { risk = .warning }
        }
        if let first = hours.first(where: \.ice) {
            parts.append(String(localized: "rischio ghiaccio"))
            details.append(String(localized: "Pioggia con temperature intorno a 0 °C dalle \(Fmt.time(first.date, in: zone)): strade e passerelle possono gelare."))
            key += "i"
            risk = .warning
        }
        guard !parts.isEmpty else { return nil }
        return (key, parts.joined(separator: ", "), details.joined(separator: " ") + String(localized: " Previsione lungo il percorso, verifica su vedur.is e umferdin.is."), risk)
    }
}
