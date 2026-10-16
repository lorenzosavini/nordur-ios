import Foundation

// Engine tests, compiled with the real sources on CI:
//   swiftc Shared/Core/{Geo,Format,Dates}.swift Shared/Services/{Astro,AuroraEngine}.swift Tests/EngineTests/main.swift
// Reference values: NASA/USNO eclipse and lunar phase tables, MET Norway Sunrise 3.0.

var failures = 0
func check(_ condition: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
    if condition { print("ok   \(name)") } else { failures += 1; print("FAIL \(name) \(detail())") }
}
func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

let reykjavik = Coordinate(lat: 64.1466, lon: -21.9426)

// MARK: Astronomy

do {
    // Full Moon 2024-04-23 23:49 UTC, New Moon 2024-04-08 18:21 UTC (total solar eclipse).
    let full = Astro.moon(date("2024-04-23T23:49:00Z"), at: Coordinate(lat: 0, lon: 0)).illuminatedFraction
    let new = Astro.moon(date("2024-04-08T18:21:00Z"), at: Coordinate(lat: 0, lon: 0)).illuminatedFraction
    check(full > 0.99, "moon full", "\(full)")
    check(new < 0.01, "moon new", "\(new)")

    // During totality at Mazatlán the Moon covers the Sun.
    let t = date("2024-04-08T18:18:00Z"), mazatlan = Coordinate(lat: 23.22, lon: -106.42)
    let s = Astro.sun(t)
    let sunH = Astro.horizontal(ra: s.ra, dec: s.dec, date: t, at: mazatlan)
    let moon = Astro.moon(t, at: mazatlan)
    check(abs(sunH.altitude - moon.altitude) < 1 && abs(sunH.azimuth - moon.azimuth) < 1.5, "eclipse alignment",
          "sun \(sunH) moon \(moon.altitude),\(moon.azimuth)")

    // MET Norway: Reykjavík sunset 2026-10-16 18:04 UTC.
    let sunset = Astro.crossings(of: -0.833, from: date("2026-10-16T12:00:00Z"), at: reykjavik).down!
    check(abs(sunset.timeIntervalSince(date("2026-10-16T18:04:00Z"))) < 180, "Reykjavík sunset", "\(sunset)")

    // Midsummer in Reykjavík: the Sun never goes below −18° (no astronomical night).
    check(Astro.hoursBelow(-18, from: date("2026-06-21T12:00:00Z"), at: reykjavik) == 0, "no astronomical night in June")
    check(Astro.Darkness(sunAltitude: -20) == .night && Astro.Darkness(sunAltitude: -3) == .civil, "darkness classes")
}

// MARK: Geomagnetic coordinates and geometry

do {
    let pole = Geomagnetic.latitude(Coordinate(lat: Geomagnetic.poleLat, lon: Geomagnetic.poleLon))
    check(abs(pole - 90) < 0.01, "dipole pole is 90°", "\(pole)")
    let rvk = Geomagnetic.latitude(reykjavik)
    check(rvk > 67 && rvk < 71, "Reykjavík dipole latitude ≈ 69°", "\(rvk)")
    check(Geomagnetic.ovalEdge(kp: 0) == 66.5 && abs(Geomagnetic.ovalEdge(kp: 9) - 48.05) < 0.01, "oval edge fit")

    check(abs(ViewingGeometry.elevation(groundKm: 0, emissionKm: 110) - 90) < 0.01, "emission overhead at 90°")
    // Horizon distance for 110 km: θ = acos(R/(R+h)) ≈ 10.5° ≈ 1 170 km.
    let horizonKm = acos(6371 / 6481.0) * 6371
    check(abs(ViewingGeometry.elevation(groundKm: horizonKm, emissionKm: 110)) < 0.05, "emission on the horizon at the geometric limit")
    check(ViewingGeometry.elevation(groundKm: 500, emissionKm: 110) > ViewingGeometry.elevation(groundKm: 800, emissionKm: 110), "elevation decreases with distance")
    let north = ViewingGeometry.bearing(from: reykjavik, to: Coordinate(lat: 70, lon: -21.9426))
    check(north < 1 || north > 359, "bearing north", "\(north)")
}

// MARK: Field geometry

struct Band: AuroraField {
    let lat: Int; let v: Double
    var validAt: Date? = Date().addingTimeInterval(1800)
    var observedAt: Date? = Date().addingTimeInterval(-1800)
    func value(lat: Int, lon: Int) -> Double? { lat == self.lat ? v : 0 }
}

do {
    let overhead = ViewingGeometry.evaluate(Band(lat: 64, v: 40), at: reykjavik)
    check(overhead.category == .overhead && overhead.value == 40, "band overhead", "\(overhead)")
    let poleward = ViewingGeometry.evaluate(Band(lat: 67, v: 40), at: reykjavik)
    check(poleward.category == .toward, "band 3° north is toward the horizon", "\(poleward.category)")
    check((poleward.azimuth ?? 180) < 30 || (poleward.azimuth ?? 0) > 330, "look north", "\(String(describing: poleward.azimuth))")
    let far = ViewingGeometry.evaluate(Band(lat: 76, v: 40), at: reykjavik)
    check(far.category == .low || far.category == .none, "distant band low or invisible", "\(far.category)")
    let weak = ViewingGeometry.evaluate(Band(lat: 64, v: 5), at: reykjavik)
    check(weak.category == .none, "below NOAA display threshold ignored")
}

// MARK: Sky and observability

do {
    check(SkyModel.clearFraction(SkyHour(date: Date(), cloudLow: 0, cloudMid: 0, cloudHigh: 0)) == 1, "clear sky")
    check(SkyModel.clearFraction(SkyHour(date: Date(), cloudLow: 100, cloudMid: 0, cloudHigh: 0)) == 0, "low overcast closes the sky")
    let cirrus = SkyModel.clearFraction(SkyHour(date: Date(), cloudLow: 0, cloudMid: 0, cloudHigh: 100))!
    check(abs(cirrus - 0.5) < 1e-9, "thin high cloud counts half")
    check(SkyModel.clearFraction(SkyHour(date: Date(), cloudLow: 0, cloudMid: 0, cloudHigh: 0, fog: 80)) == 0, "fog closes the sky")

    // A clear dark night with moderate Kp vs the same night overcast vs daytime.
    let night = date("2026-01-15T00:00:00Z") // Reykjavík: deep night, check the Moon separately
    let blocks = [KpBlock(start: date("2026-01-14T21:00:00Z"), value: 4, isObserved: false)]
    func slot(_ low: Double, at d: Date) -> AuroraSlot {
        let inputs = AuroraInputs(place: reykjavik, sky: [SkyHour(date: d, cloudLow: low, cloudMid: 0, cloudHigh: 0)], kp: [KpBlock(start: d.addingTimeInterval(-3600), value: 4, isObserved: false)] + blocks, field: nil, now: d)
        return AuroraEngine.slot(for: inputs.sky[0], inputs: inputs)
    }
    let clear = slot(0, at: night), cloudy = slot(95, at: night)
    check(clear.index > cloudy.index, "cloud lowers observability", "\(clear.index) vs \(cloudy.index)")
    check(cloudy.observability <= .poor, "overcast is unfavourable", cloudy.observability.label)
    check(cloudy.reasons.contains { $0.contains("Cielo coperto") || $0.contains("Nuvolosità") }, "reason names the clouds", "\(cloudy.reasons)")
    let noon = slot(0, at: date("2026-01-15T13:30:00Z"))
    check(noon.observability == .veryPoor && noon.index == 0, "daytime is never favourable")
    check(clear.activitySource == "Kp → ovale" && clear.reliability == .medium, "Kp-based slot has medium reliability within 24 h")
    let later = AuroraInputs(place: reykjavik, sky: [], kp: blocks, field: nil, now: night.addingTimeInterval(-40 * 3600))
    check(AuroraEngine.slot(for: SkyHour(date: night, cloudLow: 0, cloudMid: 0, cloudHigh: 0), inputs: later).reliability == .low, "lead > 24 h lowers reliability")

    // OVATION only within its validity window.
    let field = Band(lat: 64, v: 50, validAt: night.addingTimeInterval(1800), observedAt: night.addingTimeInterval(-1800))
    check(AuroraEngine.fieldIsUsable(field, at: night, now: night), "OVATION usable at its time")
    check(!AuroraEngine.fieldIsUsable(field, at: night.addingTimeInterval(6 * 3600), now: night), "OVATION not used 6 h later")
    check(!AuroraEngine.fieldIsUsable(field, at: night, now: night.addingTimeInterval(3 * 3600)), "old OVATION run not used")
}

print(failures == 0 ? "ALL ENGINE TESTS PASSED" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
