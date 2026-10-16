import Foundation

// Astronomy for aurora observing: Sun and Moon positions, twilight, lunar phase.
// Low-precision analytic series, adequate for observing decisions:
//   Sun  – NOAA / Astronomical Almanac approximation, ≈0.01° in declination,
//          ≈1 min in event times at mid latitudes (worse near polar day/night).
//   Moon – Astronomical Almanac low-precision series (main periodic terms),
//          ≈0.3° in position, ≈1 % in illuminated fraction; topocentric
//          parallax applied to the altitude.
// All computations are in UTC; time zones are only for display.

enum Astro {
    static let deg = Double.pi / 180

    static func julianDay(_ date: Date) -> Double { date.timeIntervalSince1970 / 86400 + 2440587.5 }

    /// Greenwich mean sidereal time, degrees.
    static func gmst(_ jd: Double) -> Double {
        let d = jd - 2451545.0
        return normalize(280.46061837 + 360.98564736629 * d)
    }

    static func normalize(_ degrees: Double) -> Double {
        let r = degrees.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    /// Altitude and azimuth (degrees, azimuth from north through east) of an object at RA/Dec (degrees).
    static func horizontal(ra: Double, dec: Double, date: Date, at c: Coordinate) -> (altitude: Double, azimuth: Double) {
        let lst = gmst(julianDay(date)) + c.lon
        let h = (lst - ra) * deg, phi = c.lat * deg, delta = dec * deg
        let sinAlt = sin(phi) * sin(delta) + cos(phi) * cos(delta) * cos(h)
        let alt = asin(max(-1, min(1, sinAlt)))
        let az = atan2(-sin(h) * cos(delta), cos(phi) * sin(delta) - sin(phi) * cos(delta) * cos(h))
        return (alt / deg, normalize(az / deg))
    }

    // MARK: Sun

    struct SunPosition {
        let eclipticLongitude: Double  // degrees
        let ra: Double
        let dec: Double
    }

    static func sun(_ date: Date) -> SunPosition {
        let n = julianDay(date) - 2451545.0
        let L = normalize(280.460 + 0.9856474 * n)
        let g = normalize(357.528 + 0.9856003 * n) * deg
        let lambda = normalize(L + 1.915 * sin(g) + 0.020 * sin(2 * g))
        let epsilon = (23.439 - 0.0000004 * n) * deg
        let ra = normalize(atan2(cos(epsilon) * sin(lambda * deg), cos(lambda * deg)) / deg)
        let dec = asin(sin(epsilon) * sin(lambda * deg)) / deg
        return SunPosition(eclipticLongitude: lambda, ra: ra, dec: dec)
    }

    /// Solar altitude in degrees (geometric, centre of the disc).
    static func sunAltitude(_ date: Date, at c: Coordinate) -> Double {
        let s = sun(date)
        return horizontal(ra: s.ra, dec: s.dec, date: date, at: c).altitude
    }

    // MARK: Moon

    struct MoonPosition {
        let altitude: Double            // topocentric, degrees
        let azimuth: Double
        let illuminatedFraction: Double // 0…1
        let waxing: Bool
        let eclipticLongitude: Double
    }

    static func moon(_ date: Date, at c: Coordinate) -> MoonPosition {
        let T = (julianDay(date) - 2451545.0) / 36525
        func s(_ a: Double, _ b: Double) -> Double { sin((a + b * T) * deg) }
        func co(_ a: Double, _ b: Double) -> Double { cos((a + b * T) * deg) }
        let lambda = normalize(218.32 + 481267.881 * T
            + 6.29 * s(135.0, 477198.87) - 1.27 * s(259.3, -413335.36) + 0.66 * s(235.7, 890534.22)
            + 0.21 * s(269.9, 954397.74) - 0.19 * s(357.5, 35999.05) - 0.11 * s(186.5, 966404.03))
        let beta = 5.13 * s(93.3, 483202.02) + 0.28 * s(228.2, 960400.89) - 0.28 * s(318.3, 6003.15) - 0.17 * s(217.6, -407332.21)
        let parallax = 0.9508 + 0.0518 * co(135.0, 477198.87) + 0.0095 * co(259.3, -413335.36)
            + 0.0078 * co(235.7, 890534.22) + 0.0028 * co(269.9, 954397.74)

        let l = cos(beta * deg) * cos(lambda * deg)
        let m = 0.9175 * cos(beta * deg) * sin(lambda * deg) - 0.3978 * sin(beta * deg)
        let n = 0.3978 * cos(beta * deg) * sin(lambda * deg) + 0.9175 * sin(beta * deg)
        let ra = normalize(atan2(m, l) / deg)
        let dec = asin(max(-1, min(1, n))) / deg
        let geo = horizontal(ra: ra, dec: dec, date: date, at: c)
        let topoAltitude = geo.altitude - parallax * cos(geo.altitude * deg)

        let sunLambda = sun(date).eclipticLongitude
        let elongation = acos(max(-1, min(1, cos(beta * deg) * cos((lambda - sunLambda) * deg)))) / deg
        // Phase angle ≈ 180° − elongation (the Sun–Moon distance ratio correction is < 0.2°).
        let phaseAngle = 180 - elongation
        let fraction = (1 + cos(phaseAngle * deg)) / 2
        return MoonPosition(altitude: topoAltitude, azimuth: geo.azimuth, illuminatedFraction: fraction,
                            waxing: normalize(lambda - sunLambda) < 180, eclipticLongitude: lambda)
    }

    static func moonPhaseName(_ m: MoonPosition) -> String {
        switch m.illuminatedFraction {
        case ..<0.03: return String(localized: "Luna nuova")
        case ..<0.35: return m.waxing ? String(localized: "Falce crescente") : String(localized: "Falce calante")
        case ..<0.65: return m.waxing ? String(localized: "Primo quarto") : String(localized: "Ultimo quarto")
        case ..<0.97: return m.waxing ? String(localized: "Gibbosa crescente") : String(localized: "Gibbosa calante")
        default: return String(localized: "Luna piena")
        }
    }

    // MARK: Twilight

    enum Darkness: Int, Comparable {
        case day = 0, civil, nautical, astronomical, night

        init(sunAltitude a: Double) {
            switch a {
            case (-0.833)...: self = .day
            case (-6)...: self = .civil
            case (-12)...: self = .nautical
            case (-18)...: self = .astronomical
            default: self = .night
            }
        }

        static func < (l: Darkness, r: Darkness) -> Bool { l.rawValue < r.rawValue }

        var label: String {
            switch self {
            case .day: return String(localized: "Giorno")
            case .civil: return String(localized: "Crepuscolo civile")
            case .nautical: return String(localized: "Crepuscolo nautico")
            case .astronomical: return String(localized: "Crepuscolo astronomico")
            case .night: return String(localized: "Notte astronomica")
            }
        }
    }

    /// Times the Sun crosses `altitude` going down and up within the 24 h after `start`.
    /// Nil when it never crosses (polar day/night for that threshold).
    static func crossings(of altitude: Double, from start: Date, at c: Coordinate) -> (down: Date?, up: Date?) {
        var down: Date?, up: Date?
        var previous = sunAltitude(start, at: c) - altitude
        for minute in stride(from: 5, through: 1440, by: 5) {
            let t = start.addingTimeInterval(Double(minute) * 60)
            let value = sunAltitude(t, at: c) - altitude
            let crossing = t.addingTimeInterval(-300 * value / (value - previous))
            if previous > 0, value <= 0, down == nil { down = crossing }
            if previous <= 0, value > 0, up == nil, down != nil || minute > 5 { up = crossing }
            previous = value
        }
        return (down, up)
    }

    /// Hours in the 24 h after `start` with the Sun below `altitude` (sampled every 10 min).
    static func hoursBelow(_ altitude: Double, from start: Date, at c: Coordinate) -> Double {
        var count = 0
        for minute in stride(from: 0, to: 1440, by: 10) where sunAltitude(start.addingTimeInterval(Double(minute) * 60), at: c) < altitude {
            count += 1
        }
        return Double(count) / 6
    }
}
