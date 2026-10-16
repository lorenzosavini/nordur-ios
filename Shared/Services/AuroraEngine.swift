import Foundation

// Aurora observing engine. Three outputs, never mixed:
//   1. activity      – what the models/measurements say about the aurora itself
//   2. observability – whether an observer at this place and hour could see it
//   3. reliability   – how far to trust 1 and 2 (lead time, data age, agreement)
//
// The observability index is a HEURISTIC, not a probability: no calibrated
// model of P(sighting | conditions) exists for this app yet. It multiplies
// documented factors and is shown only as one of five classes with its
// reasons. Collected sightings (/api/sightings) are meant to calibrate it later.

// MARK: - Inputs (neutral, testable)

/// Sky conditions for one hour at one place.
struct SkyHour {
    var date: Date
    var cloudTotal: Double?   // %
    var cloudLow: Double?
    var cloudMid: Double?
    var cloudHigh: Double?
    var fog: Double?          // % (MET Norway fog_area_fraction)
    var visibility: Double?   // m
}

/// One 3-hour Kp block.
struct KpBlock {
    let start: Date
    let value: Double
    let isObserved: Bool
    var end: Date { start.addingTimeInterval(3 * 3600) }
}

/// Any OVATION-like field: value 0–100 at integer lat/lon (°).
protocol AuroraField {
    var validAt: Date? { get }
    var observedAt: Date? { get }
    func value(lat: Int, lon: Int) -> Double?
}

// MARK: - Geomagnetic coordinates

enum Geomagnetic {
    /// North geomagnetic (dipole) pole, IGRF-14 epoch 2025 (≈80.8°N, 72.7°W).
    static let poleLat = 80.8, poleLon = -72.7

    /// Centred-dipole magnetic latitude. Differs from corrected geomagnetic
    /// latitude by a few degrees in the North Atlantic (Iceland: dipole ≈ 69°, CGM ≈ 65°).
    static func latitude(_ c: Coordinate) -> Double {
        let d = Astro.deg
        let s = sin(c.lat * d) * sin(poleLat * d) + cos(c.lat * d) * cos(poleLat * d) * cos((c.lon - poleLon) * d)
        return asin(max(-1, min(1, s))) / d
    }

    /// Equatorward edge of the auroral oval (midnight sector) for a Kp value,
    /// geomagnetic latitude in degrees. Linear fit to NOAA SWPC's Kp/latitude
    /// table (Kp 0 → 66.5°, Kp 9 → 48.1°), uncertainty ≈ ±2–3°.
    static func ovalEdge(kp: Double) -> Double { 66.5 - 2.05 * max(0, min(9, kp)) }
}

// MARK: - Viewing geometry

enum ViewingGeometry {
    static let earthRadius = 6371.0
    /// Assumed emission heights (km): lower border of green aurora ~100–110 km;
    /// red/upper rays reach 200–300 km and can be seen from farther away.
    static let lowerEmission = 110.0, upperEmission = 200.0

    /// Elevation (degrees) of an emission at height `h` above a point at ground distance `km`.
    static func elevation(groundKm km: Double, emissionKm h: Double) -> Double {
        let theta = km / earthRadius
        let r = earthRadius / (earthRadius + h)
        return atan2(cos(theta) - r, sin(theta)) / Astro.deg
    }

    static func bearing(from a: Coordinate, to b: Coordinate) -> Double {
        let d = Astro.deg
        let y = sin((b.lon - a.lon) * d) * cos(b.lat * d)
        let x = cos(a.lat * d) * sin(b.lat * d) - sin(a.lat * d) * cos(b.lat * d) * cos((b.lon - a.lon) * d)
        return Astro.normalize(atan2(y, x) / d)
    }

    enum Category: Int, Comparable {
        case none = 0, low, toward, overhead
        static func < (l: Category, r: Category) -> Bool { l.rawValue < r.rawValue }
        var label: String {
            switch self {
            case .overhead: return "Sopra di te o quasi"
            case .toward: return "Visibile verso l'orizzonte"
            case .low: return "Molto bassa sull'orizzonte"
            case .none: return "Non prevista nel cielo visibile"
            }
        }
    }

    struct Result {
        let category: Category
        let value: Double          // strongest model value in the visible sky
        let azimuth: Double?       // where to look
        let elevation: Double?
        let distanceKm: Double?
    }

    /// NOAA's 30-minute map starts colouring at about 10: below that the
    /// model shows no meaningful aurora.
    static let threshold = 10.0

    /// Scans the field within reach of the observer (~1 300 km) and returns the
    /// strongest aurora that rises at least 3° above the horizon (lower emission),
    /// with a 200 km upper-emission check for very low aurora.
    static func evaluate(_ field: AuroraField, at observer: Coordinate) -> Result {
        var best: (score: Double, value: Double, el: Double, az: Double, km: Double, cat: Category)?
        let latRange = Int(floor(observer.lat - 12))...Int(ceil(min(89, observer.lat + 12)))
        for lat in latRange {
            let lonSpan = Int(ceil(13 / max(0.15, cos(Double(lat) * Astro.deg))))
            for dl in -lonSpan...lonSpan {
                let lon = Int(observer.lon.rounded()) + dl
                guard let v = field.value(lat: lat, lon: lon), v >= threshold else { continue }
                let cell = Coordinate(lat: Double(lat), lon: Double(lon))
                let km = Geo.distanceKm(observer, cell)
                let el = elevation(groundKm: km, emissionKm: lowerEmission)
                let elUpper = elevation(groundKm: km, emissionKm: upperEmission)
                let cat: Category
                if el >= 60 { cat = .overhead }
                else if el >= 15 { cat = .toward }
                else if el >= 3 || elUpper >= 5 { cat = .low }
                else { continue }
                // Prefer strong aurora high in the sky: weight by geometry class.
                let score = v * (cat == .overhead ? 1 : cat == .toward ? 0.85 : 0.5)
                if best == nil || score > best!.score {
                    best = (score, v, max(el, 0), bearing(from: observer, to: cell), km, cat)
                }
            }
        }
        guard let b = best else { return Result(category: .none, value: 0, azimuth: nil, elevation: nil, distanceKm: nil) }
        return Result(category: b.cat, value: b.value, azimuth: b.az, elevation: b.el, distanceKm: b.km)
    }

    /// Kp-based geometry for hours beyond OVATION's horizon: where the oval's
    /// equatorward edge sits relative to the observer (Δ = magLat − edge, °).
    static func fromKp(_ kp: Double, at observer: Coordinate) -> (category: Category, delta: Double) {
        let delta = Geomagnetic.latitude(observer) - Geomagnetic.ovalEdge(kp: kp)
        // The edge is uncertain by ±2–3° (model fit + dipole vs corrected coordinates):
        // "overhead" only beyond that margin. 1° ≈ 111 km; lower-border aurora
        // 15° / 3° high lies ≈ 350 / 760 km away.
        let category: Category = delta >= 2 ? .overhead : delta > -2 ? .toward : delta > -6 ? .low : .none
        return (category, delta)
    }
}

// MARK: - Sky

enum SkyModel {
    /// Fraction of sky clear enough to see aurora (0…1), random-overlap
    /// assumption between layers; thin high cloud counts half (aurora often
    /// shows through cirrus). Fog or visibility < 1 km closes the sky.
    static func clearFraction(_ s: SkyHour) -> Double? {
        if let fog = s.fog, fog >= 50 { return 0 }
        if let vis = s.visibility, vis < 1000 { return 0 }
        if let low = s.cloudLow, let mid = s.cloudMid, let high = s.cloudHigh {
            return (1 - low / 100) * (1 - mid / 100) * (1 - 0.5 * high / 100)
        }
        if let total = s.cloudTotal { return 1 - total / 100 }
        return nil
    }
}

// MARK: - Light pollution proxy

enum LightPollution {
    /// No openly licensed sky-brightness API is integrated. Proxy: distance from
    /// Iceland's largest built-up areas (Statistics Iceland). Shown as a proxy.
    static let towns: [(name: String, c: Coordinate, radiusKm: Double)] = [
        ("Area di Reykjavík", Coordinate(lat: 64.12, lon: -21.88), 12),
        ("Reykjanesbær", Coordinate(lat: 63.99, lon: -22.56), 5),
        ("Akureyri", Coordinate(lat: 65.68, lon: -18.10), 5),
        ("Selfoss", Coordinate(lat: 63.93, lon: -21.00), 3),
    ]

    static func factor(at c: Coordinate) -> (value: Double, note: String?) {
        for town in towns {
            let km = Geo.distanceKm(c, town.c)
            if km <= town.radiusKm { return (0.7, "Dentro \(town.name): cielo illuminato") }
            if km <= town.radiusKm + 10 { return (0.88, "Vicino a \(town.name)") }
        }
        return (1, nil)
    }
}

// MARK: - Engine output

enum ObservabilityClass: Int, Comparable, CaseIterable {
    case veryPoor = 0, poor, moderate, good, excellent
    static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }

    init(index: Double) {
        switch index {
        case ..<0.08: self = .veryPoor
        case ..<0.2: self = .poor
        case ..<0.35: self = .moderate
        case ..<0.55: self = .good
        default: self = .excellent
        }
    }

    var label: String {
        switch self {
        case .veryPoor: return "Molto sfavorevole"
        case .poor: return "Sfavorevole"
        case .moderate: return "Moderatamente favorevole"
        case .good: return "Favorevole"
        case .excellent: return "Molto favorevole"
        }
    }
}

enum Reliability: Int, Comparable {
    case low = 0, medium, high
    static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }
    var label: String { self == .high ? "Alta" : self == .medium ? "Media" : "Bassa" }
    func lowered() -> Reliability { Reliability(rawValue: max(0, rawValue - 1)) ?? .low }
}

struct AuroraSlot: Identifiable {
    var id: Date { date }
    let date: Date
    // 1 · activity
    let activitySource: String          // "OVATION" or "Kp → ovale"
    let kp: Double?
    let geometry: ViewingGeometry.Category
    let ovationValue: Double?
    let lookAzimuth: Double?
    let lookElevation: Double?
    let activityFactor: Double
    // 2 · observability
    let sunAltitude: Double
    let darkness: Astro.Darkness
    let clear: Double?
    let moonAltitude: Double
    let moonFraction: Double
    let index: Double
    let observability: ObservabilityClass
    let reasons: [String]
    // 3 · reliability
    let reliability: Reliability
    let reliabilityNotes: [String]
}

struct AuroraInputs {
    var place: Coordinate
    var sky: [SkyHour]                 // hourly
    var kp: [KpBlock]
    var field: AuroraField?            // OVATION, used only around its validity time
    var now = Date()
    var solarWindFresh = true
    var kpSourceFresh = true
    var secondSky: [SkyHour] = []      // another weather model, for agreement checks
}

enum AuroraEngine {
    /// OVATION is used from its observation time to 45 min past its forecast time.
    static func fieldIsUsable(_ f: AuroraField, at date: Date, now: Date) -> Bool {
        guard let valid = f.validAt else { return false }
        let start = f.observedAt ?? valid.addingTimeInterval(-90 * 60)
        return date >= start.addingTimeInterval(-10 * 60) && date <= valid.addingTimeInterval(45 * 60) && now.timeIntervalSince(start) < 40 * 60
    }

    static func kp(at date: Date, in blocks: [KpBlock]) -> KpBlock? {
        blocks.first { $0.start <= date && date < $0.end }
    }

    /// Activity factor 0…1 for a Kp value: not a probability, a ranking aid.
    static func kpActivity(_ kp: Double) -> Double {
        min(1, 0.15 + 0.12 * max(0, kp))
    }

    static func slot(for sky: SkyHour, inputs: AuroraInputs) -> AuroraSlot {
        let date = sky.date, place = inputs.place, now = inputs.now
        var reasons: [(weight: Double, text: String)] = []
        var notes: [String] = []

        // 1 · activity
        let block = kp(at: date, in: inputs.kp)
        let kpValue = block?.value
        var source = "Kp → ovale"
        var geometry = ViewingGeometry.Category.none
        var ovationValue: Double?, azimuth: Double?, elevation: Double?
        var activity = 0.0
        if let field = inputs.field, fieldIsUsable(field, at: date, now: now) {
            let g = ViewingGeometry.evaluate(field, at: place)
            source = "OVATION"
            geometry = g.category; ovationValue = g.value; azimuth = g.azimuth; elevation = g.elevation
            let geo = g.category == .overhead ? 1 : g.category == .toward ? 0.85 : g.category == .low ? 0.45 : 0
            activity = min(1, g.value / 40) * geo
            if g.category == .none { reasons.append((1, "OVATION non prevede aurora nel tuo cielo")) }
        } else if let kpValue {
            let g = ViewingGeometry.fromKp(kpValue, at: place)
            geometry = g.category
            azimuth = g.category == .overhead ? nil : ViewingGeometry.bearing(from: place, to: Coordinate(lat: Geomagnetic.poleLat, lon: Geomagnetic.poleLon))
            let geo = g.category == .overhead ? 1 : g.category == .toward ? 0.6 : g.category == .low ? 0.3 : 0
            activity = kpActivity(kpValue) * geo
            if g.category == .none { reasons.append((1, "Con Kp \(Fmt.number(kpValue, decimals: 1)) l'ovale resta lontano")) }
        } else {
            notes.append("Nessuna previsione geomagnetica per quest'ora")
        }
        if activity > 0 && activity < 0.45 {
            reasons.append((1 - activity, kpValue.map { "Attività prevista debole (Kp \(Fmt.number($0, decimals: 1)))" } ?? "Attività prevista debole"))
        }

        // 2 · observability
        let sunAlt = Astro.sunAltitude(date, at: place)
        let darkness = Astro.Darkness(sunAltitude: sunAlt)
        let darkFactor: Double = [.day: 0, .civil: 0.05, .nautical: 0.5, .astronomical: 0.85, .night: 1][darkness] ?? 0
        if darkness <= .civil { reasons.append((1, darkness == .day ? "È giorno" : "Cielo ancora chiaro (crepuscolo civile)")) }
        else if darkness == .nautical { reasons.append((0.5, "Crepuscolo nautico: solo aurore intense")) }

        let clear = SkyModel.clearFraction(sky)
        let clearFactor = clear ?? 0.5
        if clear == nil { notes.append("Nuvolosità non disponibile") }
        if let c = clear, c < 0.6 { reasons.append((1 - c, c < 0.15 ? "Cielo coperto" : "Nuvolosità \(Int(((1 - c) * 100).rounded()))% (stima per strati)")) }

        let moon = Astro.moon(date, at: place)
        let moonUp = moon.altitude > 0 ? min(1, (moon.altitude + 5) / 30) : 0
        let moonFactor = 1 - 0.35 * moon.illuminatedFraction * moonUp
        if moonFactor < 0.85 { reasons.append((1 - moonFactor, "Luna illuminata al \(Int((moon.illuminatedFraction * 100).rounded()))% sopra l'orizzonte")) }

        let light = LightPollution.factor(at: place)
        if let note = light.note { reasons.append((1 - light.value, note)) }

        let index = activity * clearFactor * darkFactor * moonFactor * light.value
        let cls = ObservabilityClass(index: index)
        if reasons.isEmpty && cls >= .good {
            reasons.append((0, "Buio, cielo in gran parte sereno e attività adeguata"))
        }

        // 3 · reliability
        let lead = date.timeIntervalSince(now) / 3600
        var reliability: Reliability = source == "OVATION" ? .high : lead < 24 ? .medium : .low
        if source == "OVATION" && !inputs.solarWindFresh { reliability = .medium; notes.append("Vento solare non aggiornato") }
        if !inputs.kpSourceFresh { reliability = reliability.lowered(); notes.append("Previsione Kp non aggiornata") }
        if clear == nil { reliability = reliability.lowered() }
        if let other = inputs.secondSky.first(where: { abs($0.date.timeIntervalSince(date)) < 1800 }),
           let a = clear, let b = SkyModel.clearFraction(other), abs(a - b) > 0.4 {
            reliability = reliability.lowered()
            notes.append("I modelli meteo non concordano sulle nuvole")
        }
        if lead > 72 { reliability = .low }

        return AuroraSlot(
            date: date, activitySource: source, kp: kpValue, geometry: geometry, ovationValue: ovationValue,
            lookAzimuth: azimuth, lookElevation: elevation, activityFactor: activity,
            sunAltitude: sunAlt, darkness: darkness, clear: clear, moonAltitude: moon.altitude, moonFraction: moon.illuminatedFraction,
            index: index, observability: cls,
            reasons: reasons.sorted { $0.weight > $1.weight }.map(\.text),
            reliability: reliability, reliabilityNotes: notes)
    }

    static func forecast(_ inputs: AuroraInputs, hours: Int = 72) -> [AuroraSlot] {
        let start = inputs.now.addingTimeInterval(-3600)
        return inputs.sky
            .filter { $0.date >= start }
            .prefix(hours)
            .map { slot(for: $0, inputs: inputs) }
    }

    /// The best dark hour in the next `hours`.
    static func best(_ slots: [AuroraSlot], within hours: Double, now: Date = Date()) -> AuroraSlot? {
        slots.filter { $0.date.addingTimeInterval(3600) > now && $0.date < now.addingTimeInterval(hours * 3600) && $0.darkness >= .nautical }
            .max { $0.index < $1.index }
    }

    static func compass(_ azimuth: Double?) -> String {
        guard let azimuth else { return "–" }
        let names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSO", "SO", "OSO", "O", "ONO", "NO", "NNO"]
        return names[Int((azimuth / 22.5).rounded()) % 16]
    }
}
