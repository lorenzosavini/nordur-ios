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
    let pole = Geomagnetic.dipoleLatitude(Coordinate(lat: Geomagnetic.poleLat, lon: Geomagnetic.poleLon))
    check(abs(pole - 90) < 0.01, "dipole pole is 90°", "\(pole)")
    // ISGI corrected geomagnetic latitudes (IGRF-13 2020.5).
    let lrv = Geomagnetic.latitude(Coordinate(lat: 64.18, lon: -21.7))
    check(abs(lrv - 64.06) < 0.3, "Leirvogur CGM ≈ 64.06°", "\(lrv)")
    check(abs(Geomagnetic.eccentricLatitude(Coordinate(lat: 64.18, lon: -21.7)) - 64.63) < 0.05, "Leirvogur eccentric dipole ≈ 64.63°")
    check(abs(Geomagnetic.dipoleLatitude(Coordinate(lat: 64.18, lon: -21.7)) - 68.74) < 0.2, "Leirvogur centred dipole ≈ 68.74° (ISGI)")
    let tro = Geomagnetic.latitude(Coordinate(lat: 69.67, lon: 18.95))
    check(abs(tro - 66.92) < 0.3, "Tromsø CGM ≈ 66.92°", "\(tro)")
    let rvk = Geomagnetic.latitude(reykjavik)
    check(rvk > 63.5 && rvk < 64.7, "Reykjavík CGM ≈ 64.1°", "\(rvk)")
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

// MARK: Terrain horizon

do {
    let wall = TerrainHorizon(angles: (0..<16).map { $0 == 0 ? 30 : 0 })
    check(abs(wall.angle(toward: 0) - 30) < 1e-9 && abs(wall.angle(toward: 11.25) - 15) < 1e-9 && wall.angle(toward: 180) == 0, "horizon interpolation")
    // A band 3° north (≈17–29° high) is hidden by a 40° skyline all round (a deep valley), visible with a flat horizon.
    let band = Band(lat: 67, v: 40)
    let valley = TerrainHorizon(angles: Array(repeating: 40, count: 16))
    check(ViewingGeometry.evaluate(band, at: reykjavik, horizon: valley).category == .none, "aurora behind a mountain is not visible")
    check(ViewingGeometry.evaluate(band, at: reykjavik).category == .toward, "same aurora with a flat horizon")
    let nw = TerrainHorizon(angles: Array(repeating: 12, count: 16))
    let trondelag = Coordinate(lat: 62.5, lon: 10)
    // CGM ≈ 59.8°: at Kp 1 the oval edge (64.45°) is ≈ 4.7° away, low on the horizon.
    check(ViewingGeometry.fromKp(1, at: trondelag).category == .low, "Kp 1 aurora low on the horizon from 59.8° CGM")
    let kpLow = ViewingGeometry.fromKp(1, at: trondelag, horizon: nw)
    check(kpLow.category == .none, "low aurora hidden by a 12° skyline", "\(kpLow)")
}

// MARK: Light pollution (Black Marble sky-glow grid)

do {
    let city = LightPollution.factor(at: Coordinate(lat: 64.146, lon: -21.94)).value
    let selfoss = LightPollution.factor(at: Coordinate(lat: 63.93, lon: -21.0)).value
    let vik = LightPollution.factor(at: Coordinate(lat: 63.42, lon: -19.0)).value
    let glacier = LightPollution.factor(at: Coordinate(lat: 64.4, lon: -16.5)).value
    check(SkyGlowGrid.values.count == SkyGlowGrid.nLat * SkyGlowGrid.nLon, "sky-glow grid decodes")
    check(city > 0.45 && city < 0.62, "central Reykjavík strongly lit", "\(city)")
    check(selfoss > city && selfoss < 0.85, "Selfoss less lit than Reykjavík", "\(selfoss)")
    check(vik > 0.95 && glacier > 0.99, "Vík and Vatnajökull dark", "\(vik) \(glacier)")
    check(LightPollution.factor(at: Coordinate(lat: 45, lon: 9)).value == 1, "outside Iceland: no data, neutral")
}

// MARK: Next hour (nowcast)

do {
    let now = date("2026-01-15T00:00:00Z")
    let inputs = AuroraInputs(place: reykjavik, sky: [SkyHour(date: now.addingTimeInterval(-600), cloudLow: 0, cloudMid: 0, cloudHigh: 0)],
                              kp: [KpBlock(start: now.addingTimeInterval(-3600), value: 3, isObserved: false)], field: nil, now: now)
    let rising = (0...6).map { i in
        NowcastInput(date: now.addingTimeInterval(Double(i) * 600), minutes: i * 10, known: i < 6, bz: i >= 3 ? -8 : 2, speed: 500, newellKp: 2 + Double(i) * 0.3)
    }
    let steps = AuroraEngine.nextHour(inputs, steps: rising)
    check(steps.count == 7 && abs((steps[0].kp ?? 0) - 3) < 1e-9, "next hour starts from the current Kp")
    check(abs((steps[5].kp ?? 0) - 4.5) < 1e-9, "expected Kp follows the Newell change of the arriving wind", "\(steps[5].kp ?? -1)")
    check(steps[6].kp == 3, "beyond the measured wind: current Kp")
    check(steps[5].slot.index >= steps[0].slot.index, "rising activity does not lower observability")
    check(AuroraEngine.nextHourSummary(steps)?.contains("Bz") == true, "summary names the southward Bz", AuroraEngine.nextHourSummary(steps) ?? "nil")
}

// MARK: Community confirmation

do {
    let now = date("2026-01-15T22:00:00Z")
    func report(_ minutesAgo: Double, _ dLat: Double, seen: Bool = true, nakedEye: Bool = true, sky: String? = nil) -> SightingReport {
        SightingReport(t: ISO8601DateFormatter().string(from: now.addingTimeInterval(-minutesAgo * 60)),
                       lat: reykjavik.lat + dLat, lon: reykjavik.lon, seen: seen, nakedEye: nakedEye, camera: false, strength: "moderata", sky: sky)
    }
    let none = AuroraConfirmation.evaluate([], at: reykjavik, now: now)
    check(none.status == .noReports, "no reports, no confirmation")
    let two = AuroraConfirmation.evaluate([report(5, 0.05), report(12, 0.2)], at: reykjavik, now: now, modelActivity: 0.4)
    check(two.status == .confirmed && two.positives == 2, "two recent naked-eye reports nearby confirm", "\(two.status) \(two.score)")
    let old = AuroraConfirmation.evaluate([report(90, 0.05), report(10, 3)], at: reykjavik, now: now)
    check(old.status == .noReports, "old or far reports are ignored")
    let photo = AuroraConfirmation.evaluate([report(30, 0.6, nakedEye: false)], at: reykjavik, now: now, modelActivity: 0.05)
    check(photo.status == .reported, "one distant camera-only report stays a report", "\(photo.status) \(photo.score)")
    let cloudyNo = AuroraConfirmation.evaluate([report(5, 0, seen: false, sky: "coperto")], at: reykjavik, now: now)
    check(cloudyNo.status == .noReports, "a cloudy negative says nothing")
    let clearNo = AuroraConfirmation.evaluate([report(5, 0, seen: false, sky: "sereno")], at: reykjavik, now: now, modelActivity: 0.6)
    check(clearNo.status == .clearNegative && clearNo.disagreesWithModel, "a clear-sky negative against a strong model is flagged")
    let lone = AuroraConfirmation.evaluate([report(5, 0.05)], at: reykjavik, now: now, modelActivity: 0.02)
    check(lone.status == .likely && lone.disagreesWithModel, "a report the model does not explain is shown as a disagreement")
}

// MARK: GPX import (Garmin Connect export)

do {
    let gpx = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx creator="Garmin Connect" version="1.1" xmlns="http://www.topografix.com/GPX/1/1" xmlns:ns3="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
      <metadata><name>Ignored</name><time>2026-07-01T10:00:00.000Z</time></metadata>
      <trk><name>Reykjavík Corsa</name><type>running</type><trkseg>
        <trkpt lat="64.14660" lon="-21.94260"><ele>10.2</ele><time>2026-07-01T10:00:00.000Z</time><extensions><ns3:TrackPointExtension><ns3:hr>120</ns3:hr></ns3:TrackPointExtension></extensions></trkpt>
        <trkpt lat="64.14750" lon="-21.94260"><ele>14.4</ele><time>2026-07-01T10:00:30.000Z</time></trkpt>
        <trkpt lat="64.14840" lon="-21.94260"><ele>18.6</ele><time>2026-07-01T10:01:00.000Z</time></trkpt>
        <trkpt lat="64.14930" lon="-21.94260"><ele>22.8</ele><time>2026-07-01T10:01:30Z</time></trkpt>
      </trkseg></trk>
    </gpx>
    """
    let read = GPXReader.read(Data(gpx.utf8))
    check(read?.points.count == 4, "gpx points", "\(read?.points.count ?? -1)")
    check(read?.name == "Reykjavík Corsa", "gpx track name wins", read?.name ?? "nil")
    let session = DriveMath.imported(name: read?.name ?? "", points: read?.points ?? [])
    check(abs(session.stats.km - 0.30) < 0.02, "gpx distance", "\(session.stats.km)")
    check(abs(session.durationSeconds() - 90) < 1, "gpx duration", "\(session.durationSeconds())")
    check(session.stats.elevationGain > 10, "gpx climb", "\(session.stats.elevationGain)")
    check(GPXReader.read(Data("<gpx></gpx>".utf8)) == nil, "empty gpx is refused")
    let route = GPXReader.read(Data("<gpx><rte><name>Piano</name><rtept lat=\"64\" lon=\"-21\"/><rtept lat=\"64.01\" lon=\"-21\"/></rte></gpx>".utf8))
    check(route?.points.count == 2 && route?.name == "Piano", "gpx route without times", "\(route?.points.count ?? -1)")
}

// MARK: Shop opening hours (OpenStreetMap)

do {
    let utc = ISO8601DateFormatter()
    func at(_ s: String) -> Date { utc.date(from: s)! }
    // 2026-10-19 is a Monday; Iceland is UTC all year.
    let h = OpeningHours("Mo-Fr 10:00-19:00; Sa 11:00-18:00; Su off")
    check(h != nil, "hours parse")
    check(h?.isOpen(at: at("2026-10-19T12:00:00Z")) == true, "open monday noon")
    check(h?.isOpen(at: at("2026-10-19T19:30:00Z")) == false, "closed monday evening")
    check(h?.nextChange(after: at("2026-10-19T12:00:00Z")) == at("2026-10-19T19:00:00Z"), "closes at 19")
    check(h?.nextChange(after: at("2026-10-25T09:00:00Z")) == at("2026-10-26T10:00:00Z"), "sunday closed, opens monday 10")
    let late = OpeningHours("Mo-Su 18:00-02:00")
    check(late?.isOpen(at: at("2026-10-20T01:00:00Z")) == true, "open after midnight")
    check(OpeningHours("24/7")?.isOpen(at: at("2026-10-21T03:00:00Z")) == true, "24/7")
    check(OpeningHours("24/7")?.nextChange(after: at("2026-10-21T03:00:00Z")) == nil, "24/7 never closes")
    check(OpeningHours("Mo-Fr 09:00-18:00; PH off")?.isOpen(at: at("2026-10-20T10:00:00Z")) == true, "PH rule ignored")
    check(OpeningHours("by appointment") == nil, "unreadable hours")
    // Forms found in the Icelandic OpenStreetMap data.
    let comma = OpeningHours("Mo-Fr 09:00-21:00, Sa-Su 11:00-21:00")
    check(comma?.isOpen(at: at("2026-10-24T10:00:00Z")) == false && comma?.isOpen(at: at("2026-10-24T12:00:00Z")) == true, "comma before days")
    check(OpeningHours("Mo-Fr 08:00-22:00; Sa,Su 10:00-22:00")?.isOpen(at: at("2026-10-25T11:00:00Z")) == true, "day list with comma")
    let dated = OpeningHours("Mo-Fr 10:00-19:00; Sa 10:00-18:00; Su 12:00-17:00; May 01,easter +39 days 12:00-17:00; easter +49 days off")
    check(dated?.isOpen(at: at("2026-10-25T13:00:00Z")) == true, "dated rules skipped")
    check(OpeningHours("Mo-Su 07:30-24:00")?.nextChange(after: at("2026-10-19T20:00:00Z")) == at("2026-10-20T00:00:00Z"), "closes at midnight")
}

// MARK: Trip files (GPX waypoints, KML from Google My Maps)

do {
    let gpx = """
    <?xml version="1.0"?><gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
      <wpt lat="64.1466" lon="-21.9426"><name>Reykjavík</name><time>2026-11-06T15:00:00Z</time><type>Tappa</type><desc>2 notti</desc></wpt>
      <wpt lat="64.3271" lon="-20.1199"><name>Gullfoss</name><type>Attrazione</type></wpt>
      <wpt lat="63.4186" lon="-19.0060"><name>Vík</name><time>2026-11-08T17:00:00Z</time><sym>Lodging</sym></wpt>
      <rte><rtept lat="64.1466" lon="-21.9426"><name>Reykjavík</name></rtept><rtept lat="63.4186" lon="-19.0060"/></rte>
    </gpx>
    """
    let items = TripFileReader.read(Data(gpx.utf8)) ?? []
    check(items.count == 3, "trip gpx places", "\(items.count)")
    check(items.map(\.isStop) == [true, false, true], "trip gpx stops and attractions", "\(items.map(\.isStop))")
    check(items.first?.nights == 2, "trip gpx nights from description", "\(String(describing: items.first?.nights))")
    check(items.first?.date != nil, "trip gpx dates")

    let kml = """
    <?xml version="1.0" encoding="UTF-8"?><kml xmlns="http://www.opengis.net/kml/2.2"><Document><name>Islanda</name>
      <Folder><name>Hotel</name>
        <Placemark><name>Höfn Guesthouse</name><Point><coordinates>-15.2069,64.2539,0</coordinates></Point></Placemark>
      </Folder>
      <Folder><name>Da vedere</name>
        <Placemark><name>Jökulsárlón</name><description><![CDATA[Laguna<br>al tramonto]]></description><Point><coordinates>-16.1792,64.0784,0</coordinates></Point></Placemark>
        <Placemark><name>Stokksnes</name><Point><coordinates>-14.9670,64.2470,0</coordinates></Point></Placemark>
      </Folder>
    </Document></kml>
    """
    let k = TripFileReader.read(Data(kml.utf8)) ?? []
    check(k.count == 3 && k[0].isStop && !k[1].isStop && !k[2].isStop, "kml folders", "\(k.map { "\($0.name) \($0.isStop)" })")
    check(abs((k.first?.lat ?? 0) - 64.2539) < 1e-6 && abs((k.first?.lon ?? 0) + 15.2069) < 1e-6, "kml lon,lat order")
    check(k[1].notes == "Laguna al tramonto", "kml description", k[1].notes ?? "nil")
    let plain = TripFileReader.read(Data("<kml><Placemark><name>A</name><Point><coordinates>-21,64</coordinates></Point></Placemark><Placemark><name>B</name><Point><coordinates>-19,63.4</coordinates></Point></Placemark></kml>".utf8)) ?? []
    check(plain.count == 2 && plain.allSatisfy(\.isStop), "short unmarked list = stops")
}

// MARK: Alert lifecycle

do {
    let now = date("2026-10-25T12:00:00Z")
    let seen = ["w:Suðurland": AlertLifecycle.Seen(severity: 2, starts: date("2026-10-26T09:00:00Z"), at: now.addingTimeInterval(-3600))]
    func decide(_ id: String, _ group: String, _ severity: Int, _ starts: Date? = nil) -> AlertLifecycle.Decision {
        AlertLifecycle.decide(id: id, group: group, severity: severity, starts: starts, fired: ["w:old": now], seen: seen, now: now)
    }
    check(decide("w:old", "w:Suðurland", 3) == .skip, "same key never twice")
    check(decide("w:new", "w:Vestfirðir", 2) == .notify, "new alert notifies")
    check(decide("w:upd", "w:Suðurland", 2, date("2026-10-26T09:00:00Z")) == .quiet, "same alert reworded stays quiet")
    check(decide("w:upd", "w:Suðurland", 1) == .quiet, "better is quiet")
    check(decide("w:upd", "w:Suðurland", 3) == .notify, "worse notifies")
    check(decide("w:upd", "w:Suðurland", 2, date("2026-10-26T06:00:00Z")) == .notify, "earlier start notifies")
    let later = AlertLifecycle.decide(id: "w:upd", group: "w:Suðurland", severity: 2, starts: nil, fired: [:], seen: seen, now: now.addingTimeInterval(40 * 3600))
    check(later == .notify, "back after a day and a half is new")

    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
    let night = date("2026-10-25T23:30:00Z"), day = date("2026-10-25T14:00:00Z")
    check(AlertLifecycle.delivery(risk: 3, at: night, quietNights: true, calendar: cal) == .init(sound: true, urgent: true, passive: false), "danger rings at night")
    check(AlertLifecycle.delivery(risk: 2, at: night, quietNights: true, calendar: cal) == .init(sound: false, urgent: false, passive: false), "orange silent at night")
    check(AlertLifecycle.delivery(risk: 1, at: night, quietNights: true, calendar: cal).passive, "yellow quiet at night")
    check(AlertLifecycle.delivery(risk: 2, at: day, quietNights: true, calendar: cal) == .init(sound: true, urgent: true, passive: false), "orange rings by day")
    check(AlertLifecycle.delivery(risk: 1, at: night, quietNights: false, calendar: cal).sound, "quiet nights off")

    check(AlertLifecycle.phase(starts: nil, expires: now.addingTimeInterval(3600), noticed: now, now: now) == .now, "in progress")
    check(AlertLifecycle.phase(starts: now.addingTimeInterval(7200), expires: now.addingTimeInterval(9000), noticed: now, now: now) == .upcoming, "upcoming")
    check(AlertLifecycle.phase(starts: nil, expires: now.addingTimeInterval(-1), noticed: now, now: now) == .ended, "past its end")
    check(AlertLifecycle.phase(starts: nil, expires: nil, noticed: now.addingTimeInterval(-25 * 3600), now: now) == .ended, "a day old without end")
}

print(failures == 0 ? "ALL ENGINE TESTS PASSED" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)

