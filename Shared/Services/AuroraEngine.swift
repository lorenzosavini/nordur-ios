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

/// Terrain horizon: elevation angle (°) of the skyline for 16 azimuths (0°, 22.5°, …),
/// from EU-DEM 25 m via nordur-api (/api/horizon).
struct TerrainHorizon: Codable {
    let angles: [Double]

    /// Skyline angle toward `azimuth`, interpolated between the 16 directions.
    func angle(toward azimuth: Double) -> Double {
        guard angles.count == 16 else { return 0 }
        let x = Astro.normalize(azimuth) / 22.5
        let i = Int(floor(x)) % 16, j = (i + 1) % 16, t = x - floor(x)
        return angles[i] * (1 - t) + angles[j] * t
    }

    static let flat = TerrainHorizon(angles: Array(repeating: 0, count: 16))
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
    /// North geomagnetic (centred-dipole) pole, IGRF-13 at 2020.5.
    static let poleLat = 80.65, poleLon = -72.68

    /// Centred-dipole magnetic latitude (reference only: in Iceland it is ~5° too high).
    static func dipoleLatitude(_ c: Coordinate) -> Double {
        let d = Astro.deg
        let s = sin(c.lat * d) * sin(poleLat * d) + cos(c.lat * d) * cos(poleLat * d) * cos((c.lon - poleLon) * d)
        return asin(max(-1, min(1, s))) / d
    }

    // IGRF-13 degree-1/2 Gauss coefficients at 2020.5 (nT).
    private static let g10 = -29401.95, g11 = -1447.2, h11 = 4639.55
    private static let g20 = -2505.1, g21 = 2978.5, h21 = -3006.7, g22 = 1675.95, h22 = -745.8

    /// Eccentric (offset) dipole, Fraser-Smith (1987): centre offset and axis.
    private static let eccentric: (offset: (Double, Double, Double), axis: (Double, Double, Double)) = {
        let b0sq = g10 * g10 + g11 * g11 + h11 * h11, b0 = b0sq.squareRoot(), s3 = 3.0.squareRoot()
        let l0 = 2 * g10 * g20 + s3 * (g11 * g21 + h11 * h21)
        let l1 = -g11 * g20 + s3 * (g10 * g21 + g11 * g22 + h11 * h22)
        let l2 = -h11 * g20 + s3 * (g10 * h21 - h11 * g22 + g11 * h22)
        let e = (l0 * g10 + l1 * g11 + l2 * h11) / (4 * b0sq)
        let a = 6371.2
        return ((a * (l1 - g11 * e) / (3 * b0sq), a * (l2 - h11 * e) / (3 * b0sq), a * (l0 - g10 * e) / (3 * b0sq)),
                (-g11 / b0, -h11 / b0, -g10 / b0))
    }()

    static func eccentricLatitude(_ c: Coordinate) -> Double {
        let d = Astro.deg, a = 6371.2
        let (o, p) = eccentric
        let x = a * cos(c.lat * d) * cos(c.lon * d) - o.0
        let y = a * cos(c.lat * d) * sin(c.lon * d) - o.1
        let z = a * sin(c.lat * d) - o.2
        let r = (x * x + y * y + z * z).squareRoot()
        return asin((x * p.0 + y * p.1 + z * p.2) / r) / d
    }

    /// Corrected-geomagnetic latitude minus eccentric-dipole latitude at 39
    /// magnetic observatories (ISGI, IGRF-13 2020.5 corrected geomagnetic coordinates).
    static let residuals: [(lat: Double, lon: Double, delta: Double)] = [
        (64.18, -21.7, 0.567), (69.67, 18.95, -0.78), (67.369, 26.627, -1.05), (68.355, 18.819, -0.71),
        (61.162, -45.442, -0.532), (67.83, 20.42, -0.751), (60.138, -1.183, 1.139), (77.0, 15.55, -0.955),
        (74.5, 19.0, -0.967), (54.616, -113.347, -1.91), (58.759, -94.088, -3.54), (64.874, -147.86, 2.366),
        (62.48, -114.482, -1.449), (64.318, -96.012, -3.082), (45.403, -75.552, -3.42), (60.508, 24.655, -0.571),
        (59.903, 17.353, 0.049), (64.612, 18.748, -0.458), (62.073, 9.117, 0.346), (71.323, -156.623, 2.715),
        (69.123, -105.031, -1.947), (74.69, -94.895, -2.072), (77.468, -69.22, -2.142), (69.251, -53.529, -1.676),
        (57.058, -135.327, 1.065), (48.265, -117.123, -1.523), (38.205, -77.373, -3.569), (55.314, -3.206, 2.214),
        (54.604, 18.813, 0.559), (50.096, 4.597, 2.95), (50.995, -4.484, 3.422), (53.743, 9.073, 1.673),
        (55.633, 11.667, 1.091), (65.417, -52.917, -1.525), (36.233, 140.189, 0.139), (43.91, 144.189, 1.03),
        (40.137, -105.237, -3.048), (47.595, -52.677, 0.263), (63.753, -68.518, -2.804),
    ]

    /// Approximate corrected geomagnetic (CGM) latitude: eccentric dipole plus
    /// the observatory residuals interpolated with a Gaussian kernel (600 km)
    /// and a weak prior towards zero far from any observatory.
    /// Leave-one-out error vs ISGI: 0.3° rms in Iceland/Scandinavia/Greenland,
    /// 0.6° rms over all 39 observatories (centred dipole: 2.8°, 4.8° in Iceland).
    static func latitude(_ c: Coordinate) -> Double {
        var num = 0.0, den = 0.0
        for r in residuals {
            let km = Geo.distanceKm(c, Coordinate(lat: r.lat, lon: r.lon))
            let w = exp(-(km / 600) * (km / 600))
            num += w * r.delta
            den += w
        }
        return eccentricLatitude(c) - num / (den + 0.02)
    }

    /// Equatorward edge of the auroral oval (midnight sector) for a Kp value,
    /// corrected geomagnetic latitude in degrees. Linear fit to NOAA SWPC's Kp/latitude
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
            case .overhead: return String(localized: "Sopra di te o quasi")
            case .toward: return String(localized: "Visibile verso l'orizzonte")
            case .low: return String(localized: "Molto bassa sull'orizzonte")
            case .none: return String(localized: "Non prevista nel cielo visibile")
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
    static func evaluate(_ field: AuroraField, at observer: Coordinate, horizon: TerrainHorizon = .flat) -> Result {
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
                // Hidden behind the local skyline (1° margin): not visible from here.
                let az = bearing(from: observer, to: cell)
                let skyline = horizon.angle(toward: az)
                if max(el, elUpper) < skyline + 1 { continue }
                let cat: Category
                if el >= 60 { cat = .overhead }
                else if el >= 15 { cat = .toward }
                else if el >= 3 || elUpper >= 5 { cat = .low }
                else { continue }
                // Prefer strong aurora high in the sky: weight by geometry class.
                let score = v * (cat == .overhead ? 1 : cat == .toward ? 0.85 : 0.5)
                if best == nil || score > best!.score {
                    best = (score, v, max(el, 0), az, km, cat)
                }
            }
        }
        guard let b = best else { return Result(category: .none, value: 0, azimuth: nil, elevation: nil, distanceKm: nil) }
        return Result(category: b.cat, value: b.value, azimuth: b.az, elevation: b.el, distanceKm: b.km)
    }

    /// Kp-based geometry for hours beyond OVATION's horizon: where the oval's
    /// equatorward edge sits relative to the observer (Δ = magLat − edge, °).
    static func fromKp(_ kp: Double, at observer: Coordinate, horizon: TerrainHorizon = .flat) -> (category: Category, delta: Double) {
        let delta = Geomagnetic.latitude(observer) - Geomagnetic.ovalEdge(kp: kp)
        // The edge is uncertain by ±2–3° (model fit + dipole vs corrected coordinates):
        // "overhead" only beyond that margin. 1° ≈ 111 km; lower-border aurora
        // 15° / 3° high lies ≈ 350 / 760 km away.
        var category: Category = delta >= 2 ? .overhead : delta > -2 ? .toward : delta > -6 ? .low : .none
        // The skyline toward the magnetic pole hides low aurora (typical heights: low ~5°, toward ~15°).
        let skyline = horizon.angle(toward: bearing(from: observer, to: Coordinate(lat: Geomagnetic.poleLat, lon: Geomagnetic.poleLon)))
        if category == .low && skyline >= 5 { category = .none }
        if category == .toward && skyline >= 15 { category = .low }
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
    /// Artificial sky glow from NASA Black Marble night lights (SkyGlowGrid):
    /// 1 far from lights, about 0.5 in central Reykjavík. Night lights measure
    /// light emitted upwards, not sky brightness at the observer: an indicator.
    /// Sky brightness at the observer from artificial light, as a multiple of a
    /// natural dark sky (1 far from lights, about 16 in central Reykjavík).
    static func skyRatio(at c: Coordinate) -> Double {
        guard let s = SkyGlowGrid.index(at: c) else { return 1 }
        return 1 + s / 3
    }

    static func factor(at c: Coordinate) -> (value: Double, note: String?) {
        guard let s = SkyGlowGrid.index(at: c) else { return (1, nil) }
        let value = pow(1 + s / 3, -0.25)
        if value < 0.65 { return (value, String(localized: "Cielo molto illuminato dalle luci della città")) }
        if value < 0.8 { return (value, String(localized: "Cielo illuminato dalle luci vicine")) }
        if value < 0.93 { return (value, String(localized: "Lieve inquinamento luminoso")) }
        return (value, nil)
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
        case .veryPoor: return String(localized: "Molto sfavorevole")
        case .poor: return String(localized: "Sfavorevole")
        case .moderate: return String(localized: "Moderatamente favorevole")
        case .good: return String(localized: "Favorevole")
        case .excellent: return String(localized: "Molto favorevole")
        }
    }
}

enum Reliability: Int, Comparable {
    case low = 0, medium, high
    static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }
    var label: String { self == .high ? String(localized: "Alta") : self == .medium ? String(localized: "Media") : String(localized: "Bassa") }
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
    var horizon: TerrainHorizon?       // local skyline; nil = assumed flat
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

        // 1 · activity (and the electron energy flux behind it, erg cm⁻² s⁻¹)
        var flux = 0.0
        let block = kp(at: date, in: inputs.kp)
        let kpValue = block?.value
        var source = "Kp → ovale"
        var geometry = ViewingGeometry.Category.none
        var ovationValue: Double?, azimuth: Double?, elevation: Double?
        var activity = 0.0
        if let field = inputs.field, fieldIsUsable(field, at: date, now: now) {
            let g = ViewingGeometry.evaluate(field, at: place, horizon: inputs.horizon ?? .flat)
            source = "OVATION"
            geometry = g.category; ovationValue = g.value; azimuth = g.azimuth; elevation = g.elevation
            let geo = g.category == .overhead ? 1 : g.category == .toward ? 0.85 : g.category == .low ? 0.45 : 0
            activity = min(1, g.value / 40) * geo
            // SWPC's "probability of visible aurora" is P = 10 + 8·Σj of the energy flux
            // Σj (Case, MacDonald & Viereck 2016, Space Weather): invert it. An aurora
            // seen on the horizon rather than overhead counts less.
            flux = max(0, (g.value - 10) / 8) * (g.category == .overhead ? 1 : g.category == .toward ? 0.8 : g.category == .low ? 0.45 : 0)
            if g.category == .none { reasons.append((1, String(localized: "OVATION non prevede aurora nel tuo cielo"))) }
        } else if let kpValue {
            let g = ViewingGeometry.fromKp(kpValue, at: place, horizon: inputs.horizon ?? .flat)
            geometry = g.category
            azimuth = g.category == .overhead ? nil : ViewingGeometry.bearing(from: place, to: Coordinate(lat: Geomagnetic.poleLat, lon: Geomagnetic.poleLon))
            let geo = g.category == .overhead ? 1 : g.category == .toward ? 0.6 : g.category == .low ? 0.3 : 0
            activity = kpActivity(kpValue) * geo
            // Without OVATION, a rough flux from Kp (about doubling per Kp step, 2 erg at
            // Kp 4 under the oval); the slot's reliability already says it is coarser.
            flux = 0.5 * pow(2, kpValue - 2) * geo
            if g.category == .none { reasons.append((1, String(localized: "Con Kp \(Fmt.number(kpValue, decimals: 1)) l'ovale resta lontano"))) }
        } else {
            notes.append(String(localized: "Nessuna previsione geomagnetica per quest'ora"))
        }
        if activity > 0 && activity < 0.45 {
            reasons.append((1 - activity, kpValue.map { String(localized: "Attività prevista debole (Kp \(Fmt.number($0, decimals: 1)))") } ?? String(localized: "Attività prevista debole")))
        }

        // 2 · observability
        let sunAlt = Astro.sunAltitude(date, at: place)
        let darkness = Astro.Darkness(sunAltitude: sunAlt)
        if darkness <= .civil { reasons.append((1, darkness == .day ? String(localized: "È giorno") : String(localized: "Cielo ancora chiaro (crepuscolo civile)"))) }
        else if darkness == .nautical { reasons.append((0.5, String(localized: "Crepuscolo nautico: solo aurore intense"))) }

        let clear = SkyModel.clearFraction(sky)
        let clearFactor = clear ?? 0.5
        if clear == nil { notes.append(String(localized: "Nuvolosità non disponibile")) }
        if let c = clear, c < 0.6 { reasons.append((1 - c, c < 0.15 ? String(localized: "Cielo coperto") : String(localized: "Nuvolosità \(Int(((1 - c) * 100).rounded()))% (stima per strati)"))) }

        let moon = Astro.moon(date, at: place)
        let moonUp = moon.altitude > 0 ? min(1, (moon.altitude + 5) / 30) : 0
        let moonFactor = 1 - 0.35 * moon.illuminatedFraction * moonUp   // for the reason only
        if moonFactor < 0.85 { reasons.append((1 - moonFactor, String(localized: "Luna illuminata al \(Int((moon.illuminatedFraction * 100).rounded()))% sopra l'orizzonte"))) }

        if let h = inputs.horizon {
            let towardPole = h.angle(toward: ViewingGeometry.bearing(from: place, to: Coordinate(lat: Geomagnetic.poleLat, lon: Geomagnetic.poleLon)))
            if towardPole >= 5 { reasons.append((min(1, towardPole / 20), String(localized: "Rilievi verso nord-ovest: orizzonte a \(Int(towardPole.rounded()))°"))) }
        } else {
            notes.append(String(localized: "Orizzonte del terreno non disponibile: considerato libero"))
        }

        let light = LightPollution.factor(at: place)
        if let note = light.note { reasons.append((1 - light.value, note)) }

        // Can the eye see it from here? Under a dark sky the aurora is visible from
        // about 1 erg cm⁻² s⁻¹ (Machol et al. 2012, the 18 % of SWPC's scale). A brighter
        // sky (twilight, Moon, city lights; as a multiple of a natural night sky) raises
        // the threshold with its square root, as night vision does (de Vries–Rose law).
        // The margin over the threshold gives 0…1 (1× → moderate, 2× → good, 4× → excellent),
        // then the clouds take their share.
        let background = twilightSky(sunAlt) + 30 * pow(moon.illuminatedFraction, 2.5) * moonUp + (LightPollution.skyRatio(at: place) - 1)
        let margin = flux / sqrt(background)
        let visibility = darkness == .day ? 0 : 1 - exp(-0.29 * margin)
        let index = visibility * clearFactor
        let cls = ObservabilityClass(index: index)
        if reasons.isEmpty && cls >= .good {
            reasons.append((0, String(localized: "Buio, cielo in gran parte sereno e attività sufficiente")))
        }

        // 3 · reliability
        let lead = date.timeIntervalSince(now) / 3600
        var reliability: Reliability = source == "OVATION" ? .high : lead < 24 ? .medium : .low
        if source == "OVATION" && !inputs.solarWindFresh { reliability = .medium; notes.append(String(localized: "Vento solare non aggiornato")) }
        if !inputs.kpSourceFresh { reliability = reliability.lowered(); notes.append(String(localized: "Previsione Kp non aggiornata")) }
        if clear == nil { reliability = reliability.lowered() }
        if let other = inputs.secondSky.first(where: { abs($0.date.timeIntervalSince(date)) < 1800 }),
           let a = clear, let b = SkyModel.clearFraction(other), abs(a - b) > 0.4 {
            reliability = reliability.lowered()
            notes.append(String(localized: "I modelli meteo non concordano sulle nuvole"))
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

    /// Twilight sky brightness at the zenith as a multiple of the night sky, from the
    /// measured twilight curve (about 21.8 mag/arcsec² at night, 19 at −12°, 15 at −6°).
    static func twilightSky(_ sunAltitude: Double) -> Double {
        let points: [(alt: Double, mag: Double)] = [(-18, 0), (-15, 1.2), (-12, 2.8), (-9, 5), (-6, 7), (-0.833, 11)]
        guard sunAltitude > -18 else { return 1 }
        guard sunAltitude < -0.833 else { return pow(10, 0.4 * 11) }
        for (a, b) in zip(points, points.dropFirst()) where sunAltitude <= b.alt {
            let f = (sunAltitude - a.alt) / (b.alt - a.alt)
            return pow(10, 0.4 * (a.mag + f * (b.mag - a.mag)))
        }
        return 1
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
        let names = [String(localized: "N"), String(localized: "NNE"), String(localized: "NE"), String(localized: "ENE"), String(localized: "E"), String(localized: "ESE"), String(localized: "SE"), String(localized: "SSE"), String(localized: "S"), String(localized: "SSO"), String(localized: "SO"), String(localized: "OSO"), String(localized: "O"), String(localized: "ONO"), String(localized: "NO"), String(localized: "NNO")]
        return names[Int((azimuth / 22.5).rounded()) % 16]
    }
}

// MARK: - Next hour (nowcast)

/// One step of the solar wind reaching Earth, as measured at L1 and shifted by its travel time.
struct NowcastInput {
    let date: Date
    let minutes: Int
    let known: Bool
    let bz: Double?
    let speed: Double?
    let newellKp: Double?
}

struct NowcastStep {
    let date: Date
    let minutes: Int
    let known: Bool
    let bz: Double?
    let speed: Double?
    let kp: Double?
    let slot: AuroraSlot
}

extension AuroraEngine {
    /// The next hour at the observer. The plasma arriving at Earth in the next ~50
    /// minutes has already been measured at L1. Expected Kp = current combined Kp
    /// moved by the change of the Newell-coupling Kp of the arriving plasma (Newell
    /// alone runs high in quiet conditions). OVATION, when valid, still drives the
    /// geometry; clouds come from the hour containing each step.
    static func nextHour(_ inputs: AuroraInputs, steps: [NowcastInput]) -> [NowcastStep] {
        let base = kp(at: inputs.now, in: inputs.kp)?.value
        let reference = steps.first { $0.known && $0.newellKp != nil }?.newellKp
        return steps.map { step in
            var expected = base
            if step.known, let b = base, let r = reference, let n = step.newellKp {
                expected = min(9, max(0, b + n - r))
            }
            var local = inputs
            if let k = expected {
                local.kp = [KpBlock(start: step.date.addingTimeInterval(-3600), value: k, isObserved: false)]
            }
            var sky = inputs.sky.last { $0.date <= step.date } ?? inputs.sky.first ?? SkyHour(date: step.date)
            sky.date = step.date
            return NowcastStep(date: step.date, minutes: step.minutes, known: step.known, bz: step.bz, speed: step.speed,
                               kp: expected, slot: slot(for: sky, inputs: local))
        }
    }

    /// One-line reading of the next hour.
    static func nextHourSummary(_ steps: [NowcastStep]) -> String? {
        let known = steps.filter(\.known)
        guard let first = known.first, let last = known.last else { return nil }
        if let south = known.first(where: { ($0.bz ?? 0) <= -5 }) {
            return String(localized: "Bz verso sud in arrivo intorno alle \(Fmt.time(south.date, in: .iceland)): l'attività può aumentare")
        }
        let change = (last.kp ?? 0) - (first.kp ?? 0)
        if change >= 0.5 { return String(localized: "Attività in aumento nella prossima ora") }
        if change <= -0.5 { return String(localized: "Attività in calo nella prossima ora") }
        if known.allSatisfy({ ($0.bz ?? 0) > 0 }) { return String(localized: "Bz verso nord: attività stabile e debole nella prossima ora") }
        return String(localized: "Attività stabile nella prossima ora")
    }
}
