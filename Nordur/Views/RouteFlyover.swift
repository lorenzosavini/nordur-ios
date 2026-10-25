import SwiftUI
import MapKit
import AVFoundation

/// The route video as a flight over the 3D terrain (like Strava's): the camera
/// starts high over the whole route, comes down behind the start and follows
/// the line as it draws itself, low and pitched so mountains and valleys stand
/// out, the stops appear where they were made (place and minutes), and at the
/// end it rises again over the whole route with every stop numbered.
///
/// Each frame is a real MapKit snapshot of the satellite with realistic
/// elevation, taken from the moving camera: 12 different views a second,
/// written at 24 fps, a few at a time so memory stays low.
enum RouteFlyover {
    struct Stop {
        let coordinate: Coordinate
        let start: Date
        let minutes: Int
        let index: Int          // point where it happened
        var name: String?
    }

    // MARK: Stops

    /// Where the recording stood still for at least 2 minutes (speed under ~5 km/h
    /// within 150 m, or a gap in the fixes without moving), skipping the start and end.
    static func stops(_ points: [TrackPoint]) -> [Stop] {
        guard points.count > 2 else { return [] }
        var found: [Stop] = []
        var i = 0
        while i < points.count - 1 {
            let a = points[i]
            var j = i
            while j + 1 < points.count,
                  Geo.distanceKm(a.coordinate, points[j + 1].coordinate) < 0.15,
                  points[j + 1].speed < DriveMath.movingThreshold || points[j + 1].t.timeIntervalSince(points[j].t) > 60 {
                j += 1
            }
            let seconds = points[j].t.timeIntervalSince(a.t)
            if seconds >= DriveMath.stopSeconds, i > 0, j < points.count - 1 {
                let mid = points[(i + j) / 2]
                found.append(Stop(coordinate: mid.coordinate, start: a.t, minutes: Int((seconds / 60).rounded()), index: (i + j) / 2))
                i = j + 1
            } else {
                i += 1
            }
        }
        // Several stops a few hundred metres apart are one.
        var merged: [Stop] = []
        for s in found {
            if let last = merged.last, Geo.distanceKm(last.coordinate, s.coordinate) < 0.4 {
                merged[merged.count - 1] = Stop(coordinate: last.coordinate, start: last.start, minutes: last.minutes + s.minutes, index: last.index)
            } else {
                merged.append(s)
            }
        }
        return Array(merged.prefix(12))
    }

    /// The name of the place of each stop (town or landmark), from Apple's geocoder.
    static func named(_ stops: [Stop]) async -> [Stop] {
        var out: [Stop] = []
        for s in stops {
            var named = s
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: s.coordinate.lat, longitude: s.coordinate.lon)).first
            named.name = placemark?.areasOfInterest?.first ?? placemark?.locality ?? placemark?.subLocality ?? placemark?.name
            out.append(named)
        }
        return out
    }

    // MARK: Camera path

    struct Shot {
        let camera: MKMapCamera
        /// How much of the route is drawn, 0…1 (by distance).
        let progress: Double
        /// Where the camera looks: the head of the line while following.
        let focus: Coordinate
        let following: Bool
    }

    /// Distance along the route of every point, in metres.
    private static func cumulative(_ points: [TrackPoint]) -> [Double] {
        var out = [0.0]
        for i in 1..<points.count { out.append(out[i - 1] + Geo.distanceKm(points[i - 1].coordinate, points[i].coordinate) * 1000) }
        return out
    }

    /// The point at `metres` along the route.
    private static func position(_ points: [TrackPoint], _ cum: [Double], _ metres: Double) -> Coordinate {
        let m = min(max(0, metres), cum.last!)
        var lo = 0, hi = cum.count - 1
        while hi - lo > 1 { let mid = (lo + hi) / 2; if cum[mid] < m { lo = mid } else { hi = mid } }
        let span = cum[hi] - cum[lo]
        let f = span > 0 ? (m - cum[lo]) / span : 0
        return Coordinate(lat: points[lo].lat + (points[hi].lat - points[lo].lat) * f, lon: points[lo].lon + (points[hi].lon - points[lo].lon) * f)
    }

    private static func ease(_ t: Double) -> Double { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    private static func lerpAngle(_ a: Double, _ b: Double, _ t: Double) -> Double {
        var d = (b - a).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return (a + d * t + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The overview: the whole route in view, seen from the south-ish side of its direction.
    static func overview(_ points: [TrackPoint], format: RouteCard.Format, pitch: Double = 52) -> (center: Coordinate, distance: Double, heading: Double) {
        let lats = points.map(\.lat), lons = points.map(\.lon)
        let center = Coordinate(lat: (lats.min()! + lats.max()!) / 2, lon: (lons.min()! + lons.max()!) / 2)
        let spanKm = max(Geo.distanceKm(Coordinate(lat: lats.min()!, lon: lons.min()!), Coordinate(lat: lats.max()!, lon: lons.max()!)), 0.6)
        let first = points.first!.coordinate, last = points.last!.coordinate
        let heading = Geo.distanceKm(first, last) > 0.3 ? RouteCard.bearing(first, last) : 0
        return (center, spanKm * 1000 * (format == .story ? 2.3 : 1.8), heading)
    }

    /// Every camera of the video: 1.5 s over the whole route, a dive behind the
    /// start, the follow along the line, the rise back to the whole route and a hold.
    static func shots(_ points: [TrackPoint], format: RouteCard.Format, perSecond: Int) -> [Shot] {
        let cum = cumulative(points)
        let length = cum.last!
        let over = overview(points, format: format)
        // Low and close while following: the relief reads from 2–6 km away.
        let followDistance = min(7000, max(2200, length * 0.12))
        let followPitch = 66.0
        let look = max(300, length * 0.04)
        let heading = { (m: Double) -> Double in
            let a = position(points, cum, m - look), b = position(points, cum, m + look)
            return Geo.distanceKm(a, b) > 0.05 ? RouteCard.bearing(a, b) : over.heading
        }
        let seconds = (intro: 1.5, dive: 1.5, follow: max(6.0, min(10.0, length / 1000 / 12 + 6)), rise: 2.0, hold: 1.8)
        let total = seconds.intro + seconds.dive + seconds.follow + seconds.rise + seconds.hold
        let count = Int(total * Double(perSecond))
        var smoothed = heading(0)
        var shots: [Shot] = []
        for f in 0..<count {
            let t = Double(f) / Double(perSecond)
            let camera: MKMapCamera
            var progress = 0.0, following = false
            var focus = over.center
            func cam(_ c: Coordinate, _ d: Double, _ p: Double, _ h: Double) -> MKMapCamera {
                MKMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon), fromDistance: d, pitch: p, heading: h)
            }
            if t < seconds.intro {
                // Overview, drifting slowly round.
                camera = cam(over.center, over.distance * (1 - 0.06 * t / seconds.intro), 50, over.heading - 8 + 8 * t / seconds.intro)
            } else if t < seconds.intro + seconds.dive {
                let k = ease((t - seconds.intro) / seconds.dive)
                let start = position(points, cum, 0)
                smoothed = heading(0)
                focus = Coordinate(lat: lerp(over.center.lat, start.lat, k), lon: lerp(over.center.lon, start.lon, k))
                camera = cam(focus, exp(lerp(log(over.distance), log(followDistance), k)), lerp(50, followPitch, k), lerpAngle(over.heading, smoothed, k))
            } else if t < seconds.intro + seconds.dive + seconds.follow {
                let k = (t - seconds.intro - seconds.dive) / seconds.follow
                // Slow in and out at the ends, steady in between.
                let s = k < 0.1 ? 5 * k * k : k > 0.9 ? 1 - 5 * (1 - k) * (1 - k) : (k - 0.05) / 0.9 + 0.0
                progress = min(1, max(0, s))
                let m = progress * length
                focus = position(points, cum, m)
                smoothed = lerpAngle(smoothed, heading(m), 0.12)
                camera = cam(focus, followDistance, followPitch, smoothed)
                following = true
            } else if t < seconds.intro + seconds.dive + seconds.follow + seconds.rise {
                let k = ease((t - seconds.intro - seconds.dive - seconds.follow) / seconds.rise)
                progress = 1
                let end = position(points, cum, length)
                focus = Coordinate(lat: lerp(end.lat, over.center.lat, k), lon: lerp(end.lon, over.center.lon, k))
                camera = cam(focus, exp(lerp(log(followDistance), log(over.distance), k)), lerp(followPitch, 48, k), lerpAngle(smoothed, over.heading, k))
            } else {
                progress = 1
                let k = (t - total + seconds.hold) / seconds.hold
                camera = cam(over.center, over.distance * (1 + 0.03 * k), 48, over.heading + 4 * k)
            }
            shots.append(Shot(camera: camera, progress: progress, focus: focus, following: following))
        }
        return shots
    }

    // MARK: Frames

    static func snapshot(_ shot: Shot, format: RouteCard.Format) async throws -> MKMapSnapshotter.Snapshot {
        let options = MKMapSnapshotter.Options()
        options.size = CGSize(width: format.size.width / 2, height: format.size.height / 2)
        options.traitCollection = UITraitCollection(traitsFrom: [UITraitCollection(displayScale: 2), UITraitCollection(userInterfaceStyle: .dark)])
        options.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .realistic)
        options.pointOfInterestFilter = .excludingAll
        options.camera = shot.camera
        return try await MKMapSnapshotter(options: options).start()
    }

    /// One frame: the snapshot, the line so far (only the part in front of the
    /// camera: a pitched view can't place what is behind it), the stops reached,
    /// the head of the line, then the stats.
    static func draw(_ ctx: CGContext, snapshot: MKMapSnapshotter.Snapshot, shot: Shot, points: [TrackPoint], stops: [Stop],
                     size: CGSize, stats: RouteCard.Stats) {
        UIGraphicsPushContext(ctx)
        defer { UIGraphicsPopContext() }
        snapshot.image.draw(in: CGRect(origin: .zero, size: size))
        let scale = size.width / snapshot.image.size.width
        let heading = shot.camera.heading * .pi / 180
        // Behind the camera's ground point nothing is drawn.
        let behind = shot.following ? shot.camera.centerCoordinateDistance * sin(shot.camera.pitch * .pi / 180) * 0.75 : .infinity
        let lat0 = shot.focus.lat, lon0 = shot.focus.lon, kx = cos(lat0 * .pi / 180) * 111_320.0
        func visible(_ p: Coordinate) -> Bool {
            guard behind.isFinite else { return true }
            let x = (p.lon - lon0) * kx, y = (p.lat - lat0) * 110_540
            return x * sin(heading) + y * cos(heading) > -behind
        }
        func screen(_ p: Coordinate) -> CGPoint {
            let s = snapshot.point(for: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon))
            return CGPoint(x: s.x * scale, y: s.y * scale)
        }
        let cum = cumulative(points)
        let drawnTo = shot.progress * cum.last!
        let step = max(1, points.count / 900)
        var done: [[CGPoint]] = [[]], ahead: [[CGPoint]] = [[]]
        for i in stride(from: 0, to: points.count, by: step) {
            let p = points[i].coordinate
            let inFront = visible(p)
            if cum[i] <= drawnTo {
                if inFront { done[done.count - 1].append(screen(p)) } else if !done[done.count - 1].isEmpty { done.append([]) }
            } else if inFront {
                ahead[ahead.count - 1].append(screen(p))
            } else if !ahead[ahead.count - 1].isEmpty { ahead.append([]) }
        }
        let head = position(points, cum, drawnTo)
        if shot.progress > 0, visible(head) { done[done.count - 1].append(screen(head)) }
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        // Still to go: a faint dashed line.
        for seg in ahead where seg.count > 1 {
            let path = CGMutablePath(); path.addLines(between: seg)
            ctx.saveGState()
            ctx.addPath(path); ctx.setStrokeColor(UIColor(white: 1, alpha: 0.45).cgColor); ctx.setLineWidth(5); ctx.setLineDash(phase: 0, lengths: [14, 12]); ctx.strokePath()
            ctx.restoreGState()
        }
        // Done: glow, orange line, white core.
        for seg in done where seg.count > 1 {
            let path = CGMutablePath(); path.addLines(between: seg)
            ctx.addPath(path); ctx.setStrokeColor(UIColor(red: 1, green: 0.35, blue: 0.1, alpha: 0.35).cgColor); ctx.setLineWidth(30); ctx.strokePath()
            ctx.addPath(path); ctx.setStrokeColor(UIColor(red: 1, green: 0.42, blue: 0.12, alpha: 1).cgColor); ctx.setLineWidth(12); ctx.strokePath()
            ctx.addPath(path); ctx.setStrokeColor(UIColor(white: 1, alpha: 0.85).cgColor); ctx.setLineWidth(3.5); ctx.strokePath()
        }
        if let first = points.first?.coordinate, visible(first) { RouteCard.dot(ctx, screen(first), color: UIColor(red: 0.2, green: 0.9, blue: 0.6, alpha: 1)) }
        // Stops reached so far: a numbered pin with the place and the minutes.
        for (n, stop) in stops.enumerated() where cum[min(stop.index, cum.count - 1)] <= drawnTo + 1 && visible(stop.coordinate) {
            pin(ctx, at: screen(stop.coordinate), number: n + 1,
                label: [stop.name, "\(stop.minutes) min"].compactMap { $0 }.joined(separator: " · "), compact: !shot.following && stops.count > 5)
        }
        if shot.progress >= 1, let last = points.last?.coordinate, visible(last) {
            RouteCard.dot(ctx, screen(last), color: UIColor(red: 1, green: 0.42, blue: 0.12, alpha: 1))
        } else if shot.progress > 0, visible(head) {
            RouteCard.dot(ctx, screen(head), color: .white, ring: true)
        }
        RouteCard.overlay(ctx, size: size, stats: stats, progress: max(shot.progress, 0.001))
    }

    /// A stop: a numbered square on a stem, its label in a dark tag.
    private static func pin(_ ctx: CGContext, at p: CGPoint, number: Int, label: String, compact: Bool) {
        let side: CGFloat = 46, stem: CGFloat = 40
        let top = CGPoint(x: p.x, y: p.y - stem)
        ctx.setStrokeColor(UIColor.white.cgColor); ctx.setLineWidth(3)
        ctx.move(to: p); ctx.addLine(to: top); ctx.strokePath()
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
        let box = CGRect(x: top.x - side / 2, y: top.y - side, width: side, height: side)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 10, color: UIColor.black.withAlphaComponent(0.6).cgColor)
        ctx.setFillColor(UIColor(red: 0.2, green: 0.88, blue: 0.66, alpha: 1).cgColor)
        ctx.fill(box)
        ctx.restoreGState()
        let num = "\(number)" as NSString
        let font = RouteCard.condensed(36)
        let ns = num.size(withAttributes: [.font: font])
        num.draw(at: CGPoint(x: box.midX - ns.width / 2, y: box.midY - ns.height / 2), withAttributes: [.font: font, .foregroundColor: UIColor.black])
        guard !compact, !label.isEmpty else { return }
        let lfont = RouteCard.mono(26)
        let text = label.uppercased() as NSString
        let ls = text.size(withAttributes: [.font: lfont, .kern: 1.5])
        let tag = CGRect(x: box.maxX + 8, y: box.midY - ls.height / 2 - 8, width: min(ls.width + 24, 520), height: ls.height + 16)
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.72).cgColor)
        ctx.fill(tag)
        text.draw(with: tag.insetBy(dx: 12, dy: 8), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                  attributes: [.font: lfont, .foregroundColor: UIColor.white, .kern: 1.5], context: nil)
    }

    // MARK: Video

    /// Renders the flight. Snapshots are taken three at a time, in order, and
    /// written as soon as they are ready.
    static func video(_ session: DriveSession, format: RouteCard.Format, progress report: @escaping (Double) -> Void) async throws -> URL {
        let points = DriveMath.downsample(session.points, maxPoints: 2500)
        guard points.count > 1 else { throw NSError(domain: "Nordur", code: 3) }
        let stops = await named(stops(session.points))
        let stats = RouteCard.stats(session)
        let perSecond = 12, outFPS = 24
        let shots = shots(points, format: format, perSecond: perSecond)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Nordur-\(format.rawValue)-3d.mp4")
        try? FileManager.default.removeItem(at: url)
        let size = format.size
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 14_000_000],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        var frame: Int64 = 0
        func write(_ snap: MKMapSnapshotter.Snapshot, _ shot: Shot) async throws {
            guard let pool = adaptor.pixelBufferPool else { return }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { return }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                ctx.translateBy(x: 0, y: size.height)
                ctx.scaleBy(x: 1, y: -1)
                draw(ctx, snapshot: snap, shot: shot, points: points, stops: stops, size: size, stats: stats)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            // Each view is shown for outFPS / perSecond frames.
            for _ in 0..<(outFPS / perSecond) {
                while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 5_000_000) }
                adaptor.append(buffer, withPresentationTime: CMTime(value: frame, timescale: CMTimeScale(outFPS)))
                frame += 1
            }
        }

        let window = 3
        var next = 0
        try await withThrowingTaskGroup(of: (Int, MKMapSnapshotter.Snapshot).self) { group in
            var ready: [Int: MKMapSnapshotter.Snapshot] = [:]
            var launched = 0
            while launched < min(window, shots.count) {
                let i = launched
                group.addTask { (i, try await snapshot(shots[i], format: format)) }
                launched += 1
            }
            while let (i, snap) = try await group.next() {
                ready[i] = snap
                while let s = ready.removeValue(forKey: next) {
                    try await write(s, shots[next])
                    next += 1
                    report(Double(next) / Double(shots.count) * 0.98)
                }
                if launched < shots.count {
                    let j = launched
                    group.addTask { (j, try await snapshot(shots[j], format: format)) }
                    launched += 1
                }
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? NSError(domain: "Nordur", code: 2) }
        report(1)
        return url
    }
}
