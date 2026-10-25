import SwiftUI
import MapKit
import SceneKit
import AVFoundation

/// The route flight rendered by a real 3D engine (SceneKit), like Strava's, and
/// the same flight as the landing's share section (nordur.info, landing/scenes.js):
/// - the terrain is a mesh built from elevation data (Terrain Tiles, open data
///   from Mapzen and others on AWS, no key), slightly exaggerated so the relief
///   reads on a phone, with the surroundings four times wider around it;
/// - the colours are Apple Maps' satellite picture of the same area, laid on it;
/// - a low sun shades the slopes and a haze fades the distance;
/// - the route is a ribbon lying on the ground, so it climbs and drops with it,
///   never hidden by the relief;
/// - stops are pins standing on the terrain with their place and minutes;
/// - the camera flies smoothly at 30 fps; the altitude profile uses the
///   terrain's heights.
/// When the elevation can't be loaded the MapKit flight (RouteFlyover) is used.
enum RouteTerrain3D {
    private static let exaggeration: Float = 1.35

    // MARK: Terrain

    struct Terrain {
        let zoom: Int
        let minPx: Double, minPy: Double, maxPx: Double, maxPy: Double   // world pixels at `zoom`
        let metersPerPixel: Double
        let width: Int, height: Int                                       // elevation samples
        let heights: [Float]                                               // metres, row-major from north-west
        let texture: UIImage

        var sizeMeters: Double { max(maxPx - minPx, maxPy - minPy) * metersPerPixel }

        /// Scene coordinates (metres; x east, z south, y up) of a place.
        func scene(_ c: Coordinate, lift: Float = 0) -> SCNVector3 {
            let (px, py) = RouteTerrain3D.worldPixel(c, zoom)
            return SCNVector3(Float((px - (minPx + maxPx) / 2) * metersPerPixel), height(px: px, py: py) * exaggeration + lift,
                              Float((py - (minPy + maxPy) / 2) * metersPerPixel))
        }

        /// Ground height (metres, not exaggerated) under a world pixel, bilinear.
        func height(px: Double, py: Double) -> Float {
            let fx = (px - minPx) / (maxPx - minPx) * Double(width - 1), fy = (py - minPy) / (maxPy - minPy) * Double(height - 1)
            let x0 = max(0, min(width - 2, Int(fx))), y0 = max(0, min(height - 2, Int(fy)))
            let tx = Float(max(0, min(1, fx - Double(x0)))), ty = Float(max(0, min(1, fy - Double(y0))))
            let h00 = heights[y0 * width + x0], h10 = heights[y0 * width + x0 + 1]
            let h01 = heights[(y0 + 1) * width + x0], h11 = heights[(y0 + 1) * width + x0 + 1]
            return (h00 * (1 - tx) + h10 * tx) * (1 - ty) + (h01 * (1 - tx) + h11 * tx) * ty
        }

        func height(at c: Coordinate) -> Double {
            let (px, py) = RouteTerrain3D.worldPixel(c, zoom)
            return Double(height(px: px, py: py))
        }
    }

    static func worldPixel(_ c: Coordinate, _ z: Int) -> (Double, Double) {
        let n = pow(2.0, Double(z)) * 256
        let lat = max(-85, min(85, c.lat)) * .pi / 180
        return ((c.lon + 180) / 360 * n, (1 - log(tan(lat) + 1 / cos(lat)) / .pi) / 2 * n)
    }

    static func coordinate(px: Double, py: Double, _ z: Int) -> Coordinate {
        let n = pow(2.0, Double(z)) * 256
        let lon = px / n * 360 - 180
        let lat = atan(sinh(.pi * (1 - 2 * py / n))) * 180 / .pi
        return Coordinate(lat: lat, lon: lon)
    }

    /// The terrain around the route, as on the landing: a detailed square (the
    /// route plus a border, at least 8 km) and its surroundings four times wider.
    static func terrain(for points: [TrackPoint]) async throws -> (detail: Terrain, wide: Terrain) {
        let lats = points.map(\.lat), lons = points.map(\.lon)
        let centerLat = (lats.min()! + lats.max()!) / 2
        // Pick the finest zoom that keeps the area within 6 × 6 tiles.
        var zoom = 13
        var bounds = (0.0, 0.0, 0.0, 0.0)
        while zoom >= 7 {
            var (x0, y0) = worldPixel(Coordinate(lat: lats.max()!, lon: lons.min()!), zoom)
            var (x1, y1) = worldPixel(Coordinate(lat: lats.min()!, lon: lons.max()!), zoom)
            let mpp = 156_543.03 * cos(centerLat * .pi / 180) / pow(2, Double(zoom))
            let minSide = 8000 / mpp
            let side = max(x1 - x0, y1 - y0, minSide) * 1.35
            let cx = (x0 + x1) / 2, cy = (y0 + y1) / 2
            x0 = cx - side / 2; x1 = cx + side / 2; y0 = cy - side / 2; y1 = cy + side / 2
            bounds = (x0, y0, x1, y1)
            if (floor(x1 / 256) - floor(x0 / 256) + 1) <= 6 && (floor(y1 / 256) - floor(y0 / 256) + 1) <= 6 { break }
            zoom -= 1
        }
        let (x0, y0, x1, y1) = bounds
        // The same centre two zooms out, four times the side: about as many tiles.
        let cx = (x0 + x1) / 8, cy = (y0 + y1) / 8, half = (x1 - x0) / 2
        async let detail = grid(x0, y0, x1, y1, zoom: zoom, samples: 384, centerLat: centerLat)
        async let wide = grid(cx - half, cy - half, cx + half, cy + half, zoom: zoom - 2, samples: 161, centerLat: centerLat)
        return try await (detail, wide)
    }

    /// Heights (samples × samples) and the satellite picture of a square in world pixels.
    private static func grid(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, zoom: Int, samples: Int, centerLat: Double) async throws -> Terrain {
        let tx0 = Int(floor(x0 / 256)), tx1 = Int(floor(x1 / 256)), ty0 = Int(floor(y0 / 256)), ty1 = Int(floor(y1 / 256))
        let cols = tx1 - tx0 + 1, rows = ty1 - ty0 + 1
        let tiles = Int(pow(2.0, Double(zoom)))
        // Elevation of the tiles, decoded (Terrarium: R·256 + G + B/256 − 32768).
        var mosaic = [Float](repeating: 0, count: cols * 256 * rows * 256)
        try await withThrowingTaskGroup(of: (Int, Int, [Float]).self) { group in
            for ty in ty0...ty1 where ty >= 0 && ty < tiles { for tx in tx0...tx1 {
                group.addTask {
                    let wrapped = (tx % tiles + tiles) % tiles
                    let url = URL(string: "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/\(zoom)/\(wrapped)/\(ty).png")!
                    let fetched = try await HTTP.get(url, cacheKey: "terrarium_\(zoom)_\(wrapped)_\(ty)")
                    guard let image = UIImage(data: fetched.value)?.cgImage else { throw NSError(domain: "Nordur", code: 4) }
                    return (tx - tx0, ty - ty0, decode(image))
                }
            } }
            for try await (cx, cy, h) in group {
                for row in 0..<256 {
                    let dst = (cy * 256 + row) * cols * 256 + cx * 256
                    for col in 0..<256 { mosaic[dst + col] = h[row * 256 + col] }
                }
            }
        }
        // Resampled to the area, sea and holes at 0.
        let width = samples, height = samples
        var heights = [Float](repeating: 0, count: width * height)
        let mw = cols * 256, mh = rows * 256
        for j in 0..<height {
            for i in 0..<width {
                let px = x0 + (x1 - x0) * Double(i) / Double(width - 1) - Double(tx0 * 256)
                let py = y0 + (y1 - y0) * Double(j) / Double(height - 1) - Double(ty0 * 256)
                let ix = max(0, min(mw - 2, Int(px))), iy = max(0, min(mh - 2, Int(py)))
                let fx = Float(max(0, min(1, px - Double(ix)))), fy = Float(max(0, min(1, py - Double(iy))))
                let a = mosaic[iy * mw + ix], b = mosaic[iy * mw + ix + 1], c = mosaic[(iy + 1) * mw + ix], d = mosaic[(iy + 1) * mw + ix + 1]
                heights[j * width + i] = max(0, (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy)
            }
        }
        let mpp = 156_543.03 * cos(centerLat * .pi / 180) / pow(2, Double(zoom))
        // The satellite picture of exactly that square, from Apple Maps, without labels.
        let nw = coordinate(px: x0, py: y0, zoom), se = coordinate(px: x1, py: y1, zoom)
        let a = MKMapPoint(CLLocationCoordinate2D(latitude: nw.lat, longitude: nw.lon)), b = MKMapPoint(CLLocationCoordinate2D(latitude: se.lat, longitude: se.lon))
        let options = MKMapSnapshotter.Options()
        options.mapRect = MKMapRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
        options.size = CGSize(width: 2048, height: 2048)
        options.traitCollection = UITraitCollection(displayScale: 2)
        options.preferredConfiguration = MKImageryMapConfiguration()
        let snap = try await MKMapSnapshotter(options: options).start()
        return Terrain(zoom: zoom, minPx: x0, minPy: y0, maxPx: x1, maxPy: y1, metersPerPixel: mpp, width: width, height: height, heights: heights, texture: snap.image)
    }

    private static func decode(_ image: CGImage) -> [Float] {
        var bytes = [UInt8](repeating: 0, count: 256 * 256 * 4)
        bytes.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 256 * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            // Exact values: no colour management, no smoothing.
            ctx?.interpolationQuality = .none
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: 256, height: 256))
        }
        return (0..<(256 * 256)).map { i in Float(bytes[i * 4]) * 256 + Float(bytes[i * 4 + 1]) + Float(bytes[i * 4 + 2]) / 256 - 32768 }
    }

    // MARK: Scene

    final class World {
        let scene = SCNScene()
        let camera = SCNNode()
        let terrain: Terrain
        let wide: Terrain
        let routeNode = SCNNode()
        let head = SCNNode()
        var pins: [(SCNNode, Int)] = []
        let route: [SCNVector3]          // the route on the ground, in scene metres
        let cum: [Double]
        /// Line width and marker sizes follow the camera distance, so they look the same on screen.
        var ribbon: Float = 40
        let start = SCNNode()

        init(terrain: Terrain, wide: Terrain, points: [TrackPoint], stops: [RouteFlyover.Stop], cum: [Double]) {
            self.terrain = terrain
            self.wide = wide
            self.cum = cum
            let size = Float(terrain.sizeMeters)
            // The line sits 15 m over the ground, and is never hidden by the relief:
            // along the south coast the road runs under the cliffs.
            route = points.map { terrain.scene($0.coordinate, lift: 15) }
            // Ground: the surroundings a little lower under the detail, the satellite on both,
            // shaded by a sun from the south-west as on the landing.
            let around = RouteTerrain3D.ground(wide)
            around.position.y = -40
            scene.rootNode.addChildNode(around)
            scene.rootNode.addChildNode(RouteTerrain3D.ground(terrain))
            // Sky and haze.
            scene.background.contents = RouteTerrain3D.sky()
            scene.fogColor = UIColor(red: 0.62, green: 0.70, blue: 0.78, alpha: 1)
            scene.fogStartDistance = CGFloat(size * 0.55)
            scene.fogEndDistance = CGFloat(size * 2.4)
            scene.fogDensityExponent = 1.4
            camera.camera = SCNCamera()
            camera.camera!.fieldOfView = 48
            camera.camera!.zNear = 5
            camera.camera!.zFar = Double(size) * 4 + wide.sizeMeters * 2
            camera.camera!.wantsHDR = false
            scene.rootNode.addChildNode(camera)
            scene.rootNode.addChildNode(routeNode)
            // Start, head and stops.
            start.geometry = SCNSphere(radius: 1)
            start.geometry!.firstMaterial = RouteTerrain3D.flat(UIColor(red: 0.2, green: 0.9, blue: 0.6, alpha: 1))
            scene.rootNode.addChildNode(start)
            head.geometry = SCNSphere(radius: 1)
            head.geometry!.firstMaterial = RouteTerrain3D.flat(.white)
            scene.rootNode.addChildNode(head)
            for (n, stop) in stops.enumerated() {
                let pin = RouteTerrain3D.pin(number: n + 1, label: [stop.name, "\(stop.minutes) min"].compactMap { $0 }.joined(separator: " · "))
                pin.position = terrain.scene(stop.coordinate)
                pin.opacity = 0
                scene.rootNode.addChildNode(pin)
                pins.append((pin, stop.index))
            }
        }

        /// The ribbon up to `progress` (orange, with a light core), the rest faint.
        func show(progress: Double, distance: Float) {
            ribbon = max(10, distance * 0.0058)
            let marker = ribbon * 1.1
            start.scale = SCNVector3(marker, marker, marker)
            head.scale = SCNVector3(marker, marker, marker)
            start.position = RouteTerrain3D.lifted(route.first!, ribbon)
            // Pins are built 1:1 for a camera 6 km away.
            let pinScale = distance / 6000
            for (pin, _) in pins { pin.scale = SCNVector3(pinScale, pinScale, pinScale) }
            routeNode.childNodes.forEach { $0.removeFromParentNode() }
            let drawn = progress * cum.last!
            let headIndex = cum.firstIndex { $0 > drawn } ?? route.count
            if headIndex >= 2 {
                var done = Array(route.prefix(headIndex))
                if headIndex < route.count, headIndex > 0 {
                    let f = Float((drawn - cum[headIndex - 1]) / max(cum[headIndex] - cum[headIndex - 1], 0.001))
                    let a = route[headIndex - 1], b = route[headIndex]
                    done.append(SCNVector3(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f, a.z + (b.z - a.z) * f))
                }
                routeNode.addChildNode(RouteTerrain3D.ribbonNode(done, width: ribbon * 3.2, lift: ribbon * 0.5, color: UIColor(red: 1, green: 0.35, blue: 0.1, alpha: 0.35)))
                routeNode.addChildNode(RouteTerrain3D.ribbonNode(done, width: ribbon, lift: ribbon * 0.6, color: UIColor(red: 1, green: 0.45, blue: 0.14, alpha: 1)))
                routeNode.addChildNode(RouteTerrain3D.ribbonNode(done, width: ribbon * 0.3, lift: ribbon * 0.7, color: UIColor(white: 1, alpha: 0.9)))
                head.position = RouteTerrain3D.lifted(done.last!, ribbon * 1.4)
            } else {
                head.position = RouteTerrain3D.lifted(route.first!, ribbon * 1.4)
            }
            head.opacity = progress > 0 && progress < 1 ? 1 : 0
            if headIndex < route.count - 1 {
                routeNode.addChildNode(RouteTerrain3D.ribbonNode(Array(route.suffix(from: max(0, headIndex - 1))), width: ribbon * 0.45, lift: ribbon * 0.5,
                                                                 color: UIColor(white: 1, alpha: 0.45)))
            }
            // Stops stand up as the line nears them, and stay.
            for (pin, index) in pins { pin.opacity = CGFloat(max(0, min(1, (drawn + 2500 - cum[min(index, cum.count - 1)]) / 900))) }
        }
    }

    static func lifted(_ v: SCNVector3, _ by: Float) -> SCNVector3 { SCNVector3(v.x, v.y + by, v.z) }

    static func flat(_ color: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        m.isDoubleSided = true
        m.transparency = color.cgColor.alpha
        m.blendMode = color.cgColor.alpha < 1 ? .alpha : .replace
        // Line, markers and stops are drawn over the relief, never hidden by it.
        m.readsFromDepthBuffer = false
        m.writesToDepthBuffer = false
        return m
    }

    private static func ground(_ t: Terrain) -> SCNNode {
        var vertices: [SCNVector3] = [], uvs: [CGPoint] = [], normals: [SCNVector3] = []
        vertices.reserveCapacity(t.width * t.height)
        let spanX = Float((t.maxPx - t.minPx) * t.metersPerPixel), spanZ = Float((t.maxPy - t.minPy) * t.metersPerPixel)
        let dx = spanX / Float(t.width - 1), dz = spanZ / Float(t.height - 1)
        func h(_ i: Int, _ j: Int) -> Float { t.heights[max(0, min(t.height - 1, j)) * t.width + max(0, min(t.width - 1, i))] * exaggeration }
        for j in 0..<t.height {
            for i in 0..<t.width {
                vertices.append(SCNVector3(-spanX / 2 + Float(i) * dx, h(i, j), -spanZ / 2 + Float(j) * dz))
                uvs.append(CGPoint(x: Double(i) / Double(t.width - 1), y: Double(j) / Double(t.height - 1)))
                let nx = h(i - 1, j) - h(i + 1, j), nz = h(i, j - 1) - h(i, j + 1), ny = 2 * dx
                let l = sqrt(nx * nx + ny * ny + nz * nz)
                normals.append(SCNVector3(nx / l, ny / l, nz / l))
            }
        }
        var indices: [UInt32] = []
        indices.reserveCapacity((t.width - 1) * (t.height - 1) * 6)
        for j in 0..<(t.height - 1) {
            for i in 0..<(t.width - 1) {
                let a = UInt32(j * t.width + i), b = a + 1, c = a + UInt32(t.width), d = c + 1
                indices += [a, c, b, b, c, d]
            }
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals), SCNGeometrySource(textureCoordinates: uvs)],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let m = SCNMaterial()
        m.diffuse.contents = t.texture
        m.diffuse.mipFilter = .linear
        m.diffuse.maxAnisotropy = 8
        m.lightingModel = .constant
        m.isDoubleSided = true
        // The landing's light: 0.74 + 0.42 · n·l, the sun from the south-west
        // (x east, y up, z south), and a little lift in the mid-tones.
        m.shaderModifiers = [.surface: """
            float3 sunDir = normalize((scn_frame.viewTransform * float4(-0.62, 0.48, 0.62, 0.0)).xyz);
            float shade = 0.74 + 0.42 * max(dot(normalize(_surface.normal), sunDir), 0.0);
            _surface.diffuse.rgb = pow(max(_surface.diffuse.rgb, float3(0.0)), float3(0.82)) * shade * 1.06;
            """]
        geometry.firstMaterial = m
        return SCNNode(geometry: geometry)
    }

    /// A flat band along points, facing up, `lift` above them.
    static func ribbonNode(_ pts: [SCNVector3], width: Float, lift: Float, color: UIColor) -> SCNNode {
        guard pts.count > 1 else { return SCNNode() }
        var v: [SCNVector3] = [], idx: [UInt32] = []
        for k in pts.indices {
            let a = pts[max(0, k - 1)], b = pts[min(pts.count - 1, k + 1)]
            var dx = b.x - a.x, dz = b.z - a.z
            let l = max(sqrt(dx * dx + dz * dz), 0.001); dx /= l; dz /= l
            let p = pts[k]
            v.append(SCNVector3(p.x - dz * width / 2, p.y + lift, p.z + dx * width / 2))
            v.append(SCNVector3(p.x + dz * width / 2, p.y + lift, p.z - dx * width / 2))
            if k > 0 {
                let i = UInt32(k * 2)
                idx += [i - 2, i - 1, i, i - 1, i + 1, i]
            }
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: v)], elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        g.firstMaterial = flat(color)
        let node = SCNNode(geometry: g)
        node.renderingOrder = 10
        return node
    }

    /// Height of a pin's stem, built 1:1 for a camera 6 km away; the tag is 0.6 of it, 1.2 up.
    static let pinTall: Float = 260

    /// A stop: a stem and a numbered tag facing the camera.
    private static func pin(number: Int, label: String) -> SCNNode {
        let node = SCNNode()
        let tall = pinTall
        let stem = SCNNode(geometry: SCNCylinder(radius: CGFloat(tall * 0.025), height: CGFloat(tall)))
        stem.geometry!.firstMaterial = flat(.white)
        stem.renderingOrder = 19
        stem.position = SCNVector3(0, tall / 2, 0)
        node.addChildNode(stem)
        let image = tagImage(number: number, label: label)
        let w = tall * 0.6 * Float(image.size.width / image.size.height)
        let plane = SCNPlane(width: CGFloat(w), height: CGFloat(tall * 0.6))
        plane.firstMaterial = flat(.white)
        plane.firstMaterial!.diffuse.contents = image
        plane.firstMaterial!.blendMode = .alpha
        plane.firstMaterial!.readsFromDepthBuffer = false
        let tag = SCNNode(geometry: plane)
        tag.position = SCNVector3(0, tall * 1.2, 0)
        tag.name = "tag"
        tag.constraints = [SCNBillboardConstraint()]
        tag.renderingOrder = 20
        node.addChildNode(tag)
        return node
    }

    private static func tagImage(number: Int, label: String) -> UIImage {
        let font = RouteCard.mono(34), numFont = RouteCard.condensed(46)
        let text = label.uppercased() as NSString
        let tw = text.size(withAttributes: [.font: font, .kern: 1.5]).width
        let size = CGSize(width: 70 + 20 + min(tw, 700) + 24, height: 70)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(red: 0.2, green: 0.88, blue: 0.66, alpha: 1).setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 70, height: 70))
            let num = "\(number)" as NSString
            let ns = num.size(withAttributes: [.font: numFont])
            num.draw(at: CGPoint(x: 35 - ns.width / 2, y: 35 - ns.height / 2), withAttributes: [.font: numFont, .foregroundColor: UIColor.black])
            UIColor.black.withAlphaComponent(0.78).setFill()
            UIRectFill(CGRect(x: 70, y: 0, width: size.width - 70, height: 70))
            text.draw(with: CGRect(x: 90, y: 35 - font.lineHeight / 2, width: min(tw, 700) + 4, height: font.lineHeight),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: [.font: font, .foregroundColor: UIColor.white, .kern: 1.5], context: nil)
        }
    }

    private static func sky() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 512)).image { r in
            let colors = [UIColor(red: 0.25, green: 0.42, blue: 0.62, alpha: 1).cgColor, UIColor(red: 0.62, green: 0.70, blue: 0.78, alpha: 1).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                r.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 512), options: [])
            }
        }
    }

    // MARK: Camera

    struct View { let focus: SCNVector3; let distance: Float; let pitch: Float; let heading: Float }

    static func place(_ camera: SCNNode, _ v: View, size: CGSize) {
        let h = v.heading * .pi / 180, p = v.pitch * .pi / 180
        let forward = SCNVector3(sin(h), 0, -cos(h))
        camera.position = SCNVector3(v.focus.x - forward.x * v.distance * cos(p), v.focus.y + v.distance * sin(p), v.focus.z - forward.z * v.distance * cos(p))
        camera.look(at: v.focus, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        // In the 4:5 post the card's text takes the lower half: the focus sits higher.
        if size.height / size.width < 1.5 {
            let tilt: Float = -atan(0.24 * tan(24 * Float.pi / 180))
            camera.simdLocalRotate(by: simd_quatf(angle: tilt, axis: SIMD3<Float>(1, 0, 0)))
        }
        camera.camera?.zNear = Double(max(5, v.distance * 0.02))
    }

    /// A point in the picture (UIKit coordinates) and its depth, nil behind the camera.
    static func project(_ camera: SCNNode, _ p: SCNVector3, size: CGSize) -> (CGPoint, Float)? {
        let c = camera.convertPosition(p, from: nil)
        let depth = -c.z
        guard depth > 1 else { return nil }
        let f = 1 / tan(24 * Float.pi / 180), aspect = Float(size.width / size.height)
        let x: Float = (1 + c.x / depth * f / aspect) * Float(size.width) / 2
        let y: Float = (1 - c.y / depth * f) * Float(size.height) / 2
        return (CGPoint(x: CGFloat(x), y: CGFloat(y)), depth)
    }

    /// The cameras of the video, 30 a second: over the whole route, down behind
    /// the start, along the line (a little to the side, swinging), up again, hold.
    static func views(_ world: World, perSecond: Int) -> [(View, Double)] {
        let cum = world.cum, route = world.route, length = cum.last!
        let size = Float(world.terrain.sizeMeters)
        let center = world.terrain.scene(RouteTerrain3D.coordinate(px: (world.terrain.minPx + world.terrain.maxPx) / 2,
                                                                   py: (world.terrain.minPy + world.terrain.maxPy) / 2, world.terrain.zoom))
        func at(_ m: Double) -> SCNVector3 {
            let mm = min(max(0, m), length)
            let j = max(1, cum.firstIndex { $0 >= mm } ?? route.count - 1)
            let f = Float((mm - cum[j - 1]) / max(cum[j] - cum[j - 1], 0.001))
            let a = route[j - 1], b = route[j]
            return SCNVector3(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f, a.z + (b.z - a.z) * f)
        }
        let look = max(400, length * 0.05)
        func heading(_ m: Double) -> Float {
            let a = at(m - look), b = at(m + look)
            let dx = b.x - a.x, dz = b.z - a.z
            return dx * dx + dz * dz > 1 ? (atan2(dx, -dz) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360) : 0
        }
        let s0 = route.first!, s1 = route.last!
        let overHeading = (atan2(s1.x - s0.x, -(s1.z - s0.z)) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let over = View(focus: center, distance: size * 0.95, pitch: 48, heading: overHeading)
        // Further back, so the valley and the coast stay in view (as on the landing).
        let followDistance = Float(min(16_000, max(5_000, length * 0.22))), followPitch: Float = 38
        let seconds = (intro: 1.6, dive: 1.8, follow: 14.0, rise: 2.2, hold: 1.6)
        // Slower around the stops (about a second each), so their names can be read.
        let n = 400, stopM = world.pins.map { cum[min($0.1, cum.count - 1)] }
        var table = [0.0]
        for i in 1...n {
            let m = (Double(i) - 0.5) / Double(n) * length
            let near = stopM.map { exp(-pow(($0 - m) / 1800, 2)) }.max() ?? 0
            table.append(table[i - 1] + 1 / (1 - 0.8 * near))
        }
        func warp(_ p: Double) -> Double {
            let want = p * table[n]
            var i = 1
            while i < n && table[i] < want { i += 1 }
            return min(1, max(0, (Double(i - 1) + (want - table[i - 1]) / (table[i] - table[i - 1])) / Double(n)))
        }
        let total = seconds.intro + seconds.dive + seconds.follow + seconds.rise + seconds.hold
        func ease(_ t: Double) -> Float { Float(t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2) }
        func mix(_ a: SCNVector3, _ b: SCNVector3, _ k: Float) -> SCNVector3 { SCNVector3(a.x + (b.x - a.x) * k, a.y + (b.y - a.y) * k, a.z + (b.z - a.z) * k) }
        func angle(_ a: Float, _ b: Float, _ k: Float) -> Float {
            var d = (b - a).truncatingRemainder(dividingBy: 360); if d > 180 { d -= 360 }; if d < -180 { d += 360 }
            return a + d * k
        }
        var smoothed = heading(0)
        var out: [(View, Double)] = []
        for f in 0..<Int(total * Double(perSecond)) {
            let t = Double(f) / Double(perSecond)
            if t < seconds.intro {
                let k = Float(t / seconds.intro)
                out.append((View(focus: over.focus, distance: over.distance * (1 - 0.05 * k), pitch: 48, heading: over.heading - 10 + 10 * k), 0))
            } else if t < seconds.intro + seconds.dive {
                let k = ease((t - seconds.intro) / seconds.dive)
                out.append((View(focus: mix(over.focus, at(0), k), distance: exp(log(over.distance) + (log(followDistance) - log(over.distance)) * k),
                                 pitch: 48 + (followPitch - 48) * k, heading: angle(over.heading, smoothed, k)), 0))
            } else if t < seconds.intro + seconds.dive + seconds.follow {
                let k = (t - seconds.intro - seconds.dive) / seconds.follow
                let p = k < 0.1 ? 5 * k * k : k > 0.9 ? 1 - 5 * (1 - k) * (1 - k) : (k - 0.05) / 0.9
                let progress = warp(min(1, max(0, p)))
                let m = progress * length
                smoothed = angle(smoothed, heading(m), 0.06)
                out.append((View(focus: at(m), distance: followDistance, pitch: followPitch, heading: smoothed + 30 * Float(sin(k * .pi * 1.5))), progress))
            } else if t < total - seconds.hold {
                let k = ease((t - seconds.intro - seconds.dive - seconds.follow) / seconds.rise)
                out.append((View(focus: mix(at(length), over.focus, k), distance: exp(log(followDistance) + (log(over.distance) - log(followDistance)) * k),
                                 pitch: followPitch + (46 - followPitch) * k, heading: angle(smoothed, over.heading, k)), 1))
            } else {
                let k = Float((t - total + seconds.hold) / seconds.hold)
                out.append((View(focus: over.focus, distance: over.distance * (1 + 0.03 * k), pitch: 46, heading: over.heading + 5 * k), 1))
            }
        }
        return out
    }

    // MARK: Render

    @MainActor
    static func prepare(_ session: DriveSession) async throws -> (World, [TrackPoint], [RouteFlyover.Stop], RouteCard.Stats) {
        let points = DriveMath.downsample(session.points, maxPoints: 1500)
        guard points.count > 1 else { throw NSError(domain: "Nordur", code: 3) }
        async let terrainTask = terrain(for: points)
        let stops = await RouteFlyover.named(RouteFlyover.stops(session.points))
        let (terrain, wide) = try await terrainTask
        var cum = [0.0]
        for i in 1..<points.count { cum.append(cum[i - 1] + Geo.distanceKm(points[i - 1].coordinate, points[i].coordinate) * 1000) }
        // Stops indexed on the downsampled route.
        let mapped = stops.map { s -> RouteFlyover.Stop in
            let i = points.indices.min { Geo.distanceKm(points[$0].coordinate, s.coordinate) < Geo.distanceKm(points[$1].coordinate, s.coordinate) } ?? 0
            return RouteFlyover.Stop(coordinate: s.coordinate, start: s.start, minutes: s.minutes, index: i, name: s.name)
        }
        return (World(terrain: terrain, wide: wide, points: points, stops: mapped, cum: cum), points, mapped, RouteCard.stats(session))
    }

    /// Ground heights under the route, for the profile.
    static func groundProfile(_ world: World, _ points: [TrackPoint]) -> [TrackPoint] {
        points.map { TrackPoint(t: $0.t, lat: $0.lat, lon: $0.lon, alt: world.terrain.height(at: $0.coordinate), speed: $0.speed, course: $0.course, accuracy: $0.accuracy) }
    }

    @MainActor
    static func frame(_ renderer: SCNRenderer, _ world: World, _ view: View, progress: Double, size: CGSize) -> UIImage {
        world.show(progress: progress, distance: view.distance)
        place(world.camera, view, size: size)
        // Never a stop over the card's name and date, its profile or its figures.
        let u = size.width / 1080
        for (pin, _) in world.pins where pin.opacity > 0 {
            guard let tag = pin.childNode(withName: "tag", recursively: false),
                  let hit = project(world.camera, tag.worldPosition, size: size) else { pin.opacity = 0; continue }
            let (p, depth) = hit
            let tagHeight: Float = pinTall * 0.6 * pin.scale.y
            let half = CGFloat(tagHeight / depth / tan(24 * Float.pi / 180)) * size.height / 4
            if p.y - half < 190 * u || p.y + half > size.height - 790 * u { pin.opacity = 0 }
        }
        return renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    }

    @MainActor
    static func image(_ session: DriveSession, format: RouteCard.Format) async throws -> URL {
        let (world, points, _, stats) = try await prepare(session)
        guard let device = MTLCreateSystemDefaultDevice() else { throw NSError(domain: "Nordur", code: 5) }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = world.scene
        renderer.pointOfView = world.camera
        let v = views(world, perSecond: 30).last!.0
        let picture = frame(renderer, world, v, progress: 1, size: format.size)
        let profilePoints = groundProfile(world, points)
        let image = UIGraphicsImageRenderer(size: format.size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { r in
            picture.draw(in: CGRect(origin: .zero, size: format.size))
            RouteCard.overlay(r.cgContext, size: format.size, stats: stats, progress: 1)
            RouteFlyover.profile(r.cgContext, points: profilePoints, cum: world.cum, progress: 1, size: format.size, figures: stats.figures.count)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Nordur-\(format.rawValue).jpg")
        try image.jpegData(compressionQuality: 0.92)?.write(to: url, options: .atomic)
        return url
    }

    @MainActor
    static func video(_ session: DriveSession, format: RouteCard.Format, progress report: @escaping (Double) -> Void) async throws -> URL {
        let (world, points, _, stats) = try await prepare(session)
        report(0.08)
        guard let device = MTLCreateSystemDefaultDevice() else { throw NSError(domain: "Nordur", code: 5) }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = world.scene
        renderer.pointOfView = world.camera
        let fps = 30
        let views = views(world, perSecond: fps)
        let profilePoints = groundProfile(world, points)
        let size = format.size
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Nordur-\(format.rawValue)-3d.mp4")
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 16_000_000],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for (i, (view, progress)) in views.enumerated() {
            let picture = frame(renderer, world, view, progress: progress, size: size)
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                ctx.translateBy(x: 0, y: size.height)
                ctx.scaleBy(x: 1, y: -1)
                UIGraphicsPushContext(ctx)
                picture.draw(in: CGRect(origin: .zero, size: size))
                RouteCard.overlay(ctx, size: size, stats: stats, progress: max(progress, 0.001))
                RouteFlyover.profile(ctx, points: profilePoints, cum: world.cum, progress: progress, size: size, figures: stats.figures.count)
                UIGraphicsPopContext()
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 3_000_000) }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
            if i % 6 == 0 {
                report(0.08 + 0.9 * Double(i) / Double(views.count))
                await Task.yield()
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? NSError(domain: "Nordur", code: 2) }
        report(1)
        return url
    }
}
