import UIKit
import MapKit

/// Wind vectors on the forecast grid for one hour (u = towards east, v = towards north, m/s).
struct WindField {
    let lats: [Double]
    let lons: [Double]
    let u: [Double]
    let v: [Double]

    init?(grid: WeatherGrid, hour: Int) {
        guard let speeds = grid.fields[.wind], speeds.indices.contains(hour), grid.windDirection.indices.contains(hour) else { return nil }
        lats = grid.lats
        lons = grid.lons
        var u: [Double] = [], v: [Double] = []
        u.reserveCapacity(speeds[hour].count)
        v.reserveCapacity(speeds[hour].count)
        for (speed, from) in zip(speeds[hour], grid.windDirection[hour]) {
            if speed.isNaN || from.isNaN { u.append(.nan); v.append(.nan); continue }
            // Meteorological direction is where the wind comes FROM.
            let rad = from * .pi / 180
            u.append(-speed * sin(rad))
            v.append(-speed * cos(rad))
        }
        self.u = u
        self.v = v
    }

    var bounds: (south: Double, west: Double, north: Double, east: Double) {
        (lats.first ?? 0, lons.first ?? 0, lats.last ?? 0, lons.last ?? 0)
    }

    func sample(lat: Double, lon: Double) -> (u: Double, v: Double)? {
        guard let uu = WeatherGrid.bilinear(u, lats: lats, lons: lons, lat: lat, lon: lon),
              let vv = WeatherGrid.bilinear(v, lats: lats, lons: lons, lat: lat, lon: lon) else { return nil }
        return (uu, vv)
    }
}

/// Animated wind particles drawn over the map (like Windy's flow), driven by a CADisplayLink.
final class WindParticleView: UIView {
    weak var mapView: MKMapView?
    var field: WindField? {
        didSet { resetParticles() }
    }

    private var displayLink: CADisplayLink?
    private var lats: [Double] = []
    private var lons: [Double] = []
    private var ages: [Int] = []
    private var maxAges: [Int] = []
    private var context: CGContext?
    private var lastMapRect = MKMapRect.null
    private var lastTimestamp: CFTimeInterval = 0
    #if targetEnvironment(simulator)
    private let pixelScale: CGFloat = 1.0
    #else
    private let pixelScale: CGFloat = 1.5
    #endif
    /// Particle budget, lowered when frames cost too much main-thread time so
    /// touches stay responsive on slow devices and in the simulator.
    #if targetEnvironment(simulator)
    private var budget = 500
    #else
    private var budget = 2200
    #endif
    private var slowFrames = 0
    private static let buckets: [(limit: Double, color: CGColor)] = {
        WeatherLayer.wind.legendValues.map { value in
            let c = ColorStop.color(for: value + 2.5, in: WeatherLayer.wind.ramp)
            return (value + 5, UIColor(red: c.r, green: c.g, blue: c.b, alpha: 0.95).cgColor)
        }
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.contentsScale = pixelScale
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(step(_:)))
            #if targetEnvironment(simulator)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 20, preferred: 15)
            #else
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
            #endif
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else if window == nil {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        context = nil
    }

    private var particleCount: Int {
        Int(min(Double(budget), max(Double(min(budget, 600)), bounds.width * bounds.height / 220)))
    }

    /// More than ~8 ms per frame for a few frames: fewer particles (down to 150),
    /// then fewer frames per second (down to 8), so the main thread stays free for touches.
    private func adapt(_ cost: CFTimeInterval) {
        slowFrames = cost > 0.008 ? slowFrames + 1 : max(0, slowFrames - 1)
        guard slowFrames >= 5 else { return }
        slowFrames = 0
        if budget > 150 {
            budget = max(150, budget * 2 / 3)
        } else if let link = displayLink, link.preferredFrameRateRange.preferred ?? 30 > 8 {
            let fps = max(8, (link.preferredFrameRateRange.preferred ?? 30) / 2)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 6, maximum: fps, preferred: fps)
        }
    }

    private func resetParticles() {
        lats = []; lons = []; ages = []; maxAges = []
        clear()
        layer.contents = nil
    }

    private func clear() {
        guard let ctx = context else { return }
        ctx.clear(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
    }

    private func makeContext() -> CGContext? {
        let w = Int(bounds.width * pixelScale), h = Int(bounds.height * pixelScale)
        guard w > 0, h > 0 else { return nil }
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        // Flip to UIKit coordinates.
        ctx?.translateBy(x: 0, y: CGFloat(h))
        ctx?.scaleBy(x: pixelScale, y: -pixelScale)
        ctx?.setLineCap(.round)
        return ctx
    }

    /// Random spawn point inside both the visible map and the wind grid.
    private func spawn(_ i: Int, visible: MKCoordinateRegion, field: WindField) {
        let b = field.bounds
        let south = max(b.south, visible.center.latitude - visible.span.latitudeDelta / 2)
        let north = min(b.north, visible.center.latitude + visible.span.latitudeDelta / 2)
        let west = max(b.west, visible.center.longitude - visible.span.longitudeDelta / 2)
        let east = min(b.east, visible.center.longitude + visible.span.longitudeDelta / 2)
        guard north > south, east > west else { lats[i] = .nan; return }
        lats[i] = Double.random(in: south...north)
        lons[i] = Double.random(in: west...east)
        ages[i] = 0
        maxAges[i] = Int.random(in: 40...110)
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let map = mapView, let field, !isHidden, bounds.width > 0 else {
            if layer.contents != nil { layer.contents = nil }
            return
        }
        if context == nil { context = makeContext(); lastMapRect = .null }
        guard let ctx = context else { return }
        let started = CACurrentMediaTime()
        defer { adapt(CACurrentMediaTime() - started) }

        let rect = map.visibleMapRect
        let region = map.region
        let dt = lastTimestamp == 0 ? 1.0 / 30 : min(0.1, link.timestamp - lastTimestamp)
        lastTimestamp = link.timestamp

        // The map moved: drop the trails so they don't smear.
        if !MKMapRectEqualToRect(rect, lastMapRect) {
            clear()
            lastMapRect = rect
        }

        let count = particleCount
        if lats.count != count {
            lats = Array(repeating: .nan, count: count)
            lons = Array(repeating: .nan, count: count)
            ages = Array(repeating: 0, count: count)
            maxAges = Array(repeating: 60, count: count)
            for i in 0..<count { spawn(i, visible: region, field: field) }
        }

        // Fade existing trails.
        ctx.saveGState()
        ctx.setBlendMode(.destinationIn)
        ctx.setFillColor(UIColor(white: 0, alpha: 0.90).cgColor)
        ctx.fill(CGRect(origin: .zero, size: bounds.size))
        ctx.restoreGState()

        let w = bounds.width, h = bounds.height
        func screen(_ lat: Double, _ lon: Double) -> CGPoint {
            let p = MKMapPoint(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            return CGPoint(x: (p.x - rect.minX) / rect.width * w, y: (p.y - rect.minY) / rect.height * h)
        }

        // Degrees moved per second per m/s, scaled to the zoom so motion looks the same at any zoom.
        let k = region.span.latitudeDelta * 0.0045
        let paths = Self.buckets.map { _ in CGMutablePath() }

        for i in 0..<count {
            if lats[i].isNaN { spawn(i, visible: region, field: field); continue }
            guard let wind = field.sample(lat: lats[i], lon: lons[i]) else { spawn(i, visible: region, field: field); continue }
            let speed = hypot(wind.u, wind.v)
            let newLat = lats[i] + wind.v * k * dt
            let newLon = lons[i] + wind.u * k * dt / max(cos(lats[i] * .pi / 180), 0.2)
            let a = screen(lats[i], lons[i]), b = screen(newLat, newLon)
            let bucket = Self.buckets.firstIndex { speed < $0.limit } ?? Self.buckets.count - 1
            paths[bucket].move(to: a)
            paths[bucket].addLine(to: b)
            lats[i] = newLat
            lons[i] = newLon
            ages[i] += 1
            if ages[i] > maxAges[i] || b.x < -20 || b.y < -20 || b.x > w + 20 || b.y > h + 20 {
                spawn(i, visible: region, field: field)
            }
        }

        ctx.setLineWidth(1.6)
        for (i, path) in paths.enumerated() where !path.isEmpty {
            ctx.setStrokeColor(Self.buckets[i].color)
            ctx.addPath(path)
            ctx.strokePath()
        }
        layer.contents = ctx.makeImage()
    }
}
