import Foundation

// Community confirmation of the aurora, crossed with the model.
//
// Reports come from Norður users (/api/sightings): "I see it" (naked eye or
// camera, with an intensity) and "I'm looking and there is none", with the sky
// as the observer saw it. A clear-sky negative is evidence of no aurora there;
// a cloudy one says nothing about the aurora and is ignored. Reports are
// weighted by distance and age; the model (OVATION/Kp at this place) and the
// local clouds are reported next to them, never mixed into the same number, so
// a report that disagrees with the model stays visible as such.

struct SightingReport: Decodable, Hashable {
    let t: String
    let lat: Double
    let lon: Double
    let seen: Bool?
    let nakedEye: Bool?
    let camera: Bool?
    let strength: String?
    let sky: String?

    var date: Date? { DateParse.iso(t) }
    var coordinate: Coordinate { Coordinate(lat: lat, lon: lon) }
    var isPositive: Bool { seen != false }
}

struct SightingsFeed: Decodable {
    struct Cell: Decodable { let lat: Double; let lon: Double; let reports: Int; let nakedEye: Int; let camera: Int; let negative: Int?; let latest: String }
    let hours: Int
    let total: Int
    let negative: Int?
    let cells: [Cell]
    let recent: [SightingReport]?
}

struct AuroraConfirmation {
    enum Status: Int, Comparable {
        case noReports, clearNegative, reported, likely, confirmed
        static func < (a: Status, b: Status) -> Bool { a.rawValue < b.rawValue }
    }

    let status: Status
    let positives: Int
    let nakedEye: Int
    let strong: Int
    let clearNegatives: Int
    let nearestKm: Double?
    let latest: Date?
    let score: Double
    let radiusKm: Double
    let windowMinutes: Int
    /// The model's activity factor here (0…1) and the clear-sky fraction, when known.
    let modelActivity: Double?
    let clear: Double?

    /// Reports and model disagree: people see it where the model says little (or the opposite).
    var disagreesWithModel: Bool {
        guard let modelActivity else { return false }
        return (status >= .likely && modelActivity < 0.1) || (status == .clearNegative && modelActivity >= 0.5)
    }

    static func evaluate(_ reports: [SightingReport], at place: Coordinate, now: Date = Date(),
                         radiusKm: Double = 100, windowMinutes: Int = 45,
                         modelActivity: Double? = nil, clear: Double? = nil) -> AuroraConfirmation {
        let window = Double(windowMinutes) * 60
        var score = 0.0, positives = 0, nakedEye = 0, strong = 0, negatives = 0
        var nearest: Double?, latest: Date?
        for r in reports {
            guard let date = r.date, now.timeIntervalSince(date) <= window, date <= now.addingTimeInterval(120) else { continue }
            let km = Geo.distanceKm(place, r.coordinate)
            guard km <= radiusKm else { continue }
            let age = max(0, now.timeIntervalSince(date)) / window
            let weight = (1 - 0.5 * age) * (1 - 0.5 * km / radiusKm)
            if r.isPositive {
                positives += 1
                if r.nakedEye == true { nakedEye += 1 }
                if r.strength == "forte" { strong += 1 }
                score += weight * (r.nakedEye == true ? 1 : 0.6) * (r.strength == "forte" ? 1.2 : 1)
                nearest = min(nearest ?? .infinity, km)
                latest = max(latest ?? date, date)
            } else if r.sky == "sereno" || r.sky == "parziale" {
                negatives += 1
                score -= weight * (r.sky == "sereno" ? 0.5 : 0.25)
            }
        }
        let status: Status
        if positives >= 2 && score >= 1.5 { status = .confirmed }
        else if positives >= 1 && (score >= 0.8 || (modelActivity ?? 0) >= 0.3) { status = .likely }
        else if positives >= 1 { status = .reported }
        else if negatives >= 1 { status = .clearNegative }
        else { status = .noReports }
        return AuroraConfirmation(status: status, positives: positives, nakedEye: nakedEye, strong: strong, clearNegatives: negatives,
                                  nearestKm: nearest, latest: latest, score: score, radiusKm: radiusKm, windowMinutes: windowMinutes,
                                  modelActivity: modelActivity, clear: clear)
    }

    var headline: String {
        switch status {
        case .confirmed: return String(localized: "Aurora confermata dalla community")
        case .likely: return String(localized: "Aurora segnalata vicino a te")
        case .reported: return String(localized: "Una segnalazione da verificare")
        case .clearNegative: return String(localized: "Cielo sereno senza aurora, secondo chi guarda")
        case .noReports: return String(localized: "Nessuna segnalazione recente")
        }
    }

    var detail: String {
        var parts: [String] = []
        if positives > 0 {
            parts.append(String(localized: "\(positives) avvistamenti entro \(Int(radiusKm)) km negli ultimi \(windowMinutes) min (\(nakedEye) a occhio nudo)."))
            if let nearestKm, let latest {
                parts.append(String(localized: "Il più vicino a \(Int(nearestKm.rounded())) km, l'ultimo \(Fmt.relative(latest))."))
            }
        }
        if clearNegatives > 0 {
            parts.append(String(localized: "\(clearNegatives) osservatori con cielo sereno non la vedono."))
        }
        if positives == 0 && clearNegatives == 0 {
            parts.append(String(localized: "L'assenza di segnalazioni non indica assenza di aurora."))
        }
        if let modelActivity {
            parts.append(modelActivity >= 0.5 ? String(localized: "Il modello indica attività forte qui.")
                         : modelActivity >= 0.2 ? String(localized: "Il modello indica attività moderata qui.")
                         : String(localized: "Il modello indica attività debole qui."))
        }
        if disagreesWithModel {
            parts.append(status >= .likely
                         ? String(localized: "Le segnalazioni superano il modello: può essere un'attività locale non prevista.")
                         : String(localized: "Il modello prevede attività ma chi guarda non la vede: può essere ancora debole o coperta dalla luce."))
        }
        if let clear, status >= .reported {
            parts.append(clear < 0.3 ? String(localized: "Qui ora il cielo è in gran parte coperto.")
                         : String(localized: "Qui ora il cielo è sereno al \(Int((clear * 100).rounded()))%."))
        }
        return parts.joined(separator: " ")
    }
}
