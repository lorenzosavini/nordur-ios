import SwiftUI
import MapKit
import UIKit

// MARK: - Raster overlay (coloured weather / aurora field)

final class RasterOverlay: NSObject, MKOverlay {
    let boundingMapRect: MKMapRect
    let coordinate: CLLocationCoordinate2D
    let image: UIImage

    init(south: Double, west: Double, north: Double, east: Double, image: UIImage) {
        let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: north, longitude: west))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(latitude: south, longitude: east))
        boundingMapRect = MKMapRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
        coordinate = CLLocationCoordinate2D(latitude: (north + south) / 2, longitude: (west + east) / 2)
        self.image = image
    }
}

final class RasterRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let raster = overlay as? RasterOverlay else { return }
        let rect = self.rect(for: raster.boundingMapRect)
        context.interpolationQuality = .high
        UIGraphicsPushContext(context)
        raster.image.draw(in: rect)
        UIGraphicsPopContext()
    }
}

enum RasterPainter {
    /// Paints `sample(lat, lon)` through `ramp` into an image in Web-Mercator
    /// space, so it lines up with the map at every latitude.
    static func image(south: Double, west: Double, north: Double, east: Double, width: Int = 360,
                      ramp: [ColorStop], sample: (Double, Double) -> Double?) -> UIImage? {
        let top = MKMapPoint(CLLocationCoordinate2D(latitude: north, longitude: west))
        let bottom = MKMapPoint(CLLocationCoordinate2D(latitude: south, longitude: east))
        let aspect = (bottom.y - top.y) / max(bottom.x - top.x, 1)
        let height = max(8, Int(Double(width) * aspect))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let mapY = top.y + (Double(y) + 0.5) / Double(height) * (bottom.y - top.y)
            let lat = MKMapPoint(x: top.x, y: mapY).coordinate.latitude
            for x in 0..<width {
                let lon = west + (Double(x) + 0.5) / Double(width) * (east - west)
                guard let value = sample(lat, lon), !value.isNaN else { continue }
                let c = ColorStop.color(for: value, in: ramp)
                let i = (y * width + x) * 4
                // Premultiplied RGBA.
                pixels[i] = UInt8(max(0, min(255, c.r * c.a * 255)))
                pixels[i + 1] = UInt8(max(0, min(255, c.g * c.a * 255)))
                pixels[i + 2] = UInt8(max(0, min(255, c.b * c.a * 255)))
                pixels[i + 3] = UInt8(max(0, min(255, c.a * 255)))
            }
        }
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Annotations

final class ArrowAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let degrees: Double
    let speed: Double
    init(coordinate: CLLocationCoordinate2D, degrees: Double, speed: Double) {
        self.coordinate = coordinate
        self.degrees = degrees
        self.speed = speed
    }
}

/// Any point of interest drawn on the map.
final class PoiAnnotation: NSObject, MKAnnotation {
    enum Kind: String { case place, station, webcam, quake, fuel, charger, shop, stop, visit, roadSection, roadHazard, sighting, noSighting }
    let kind: Kind
    let key: String
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?
    let color: UIColor
    let text: String?
    let size: CGFloat

    init(kind: Kind, key: String, coordinate: CLLocationCoordinate2D, title: String?, subtitle: String? = nil,
         color: UIColor, text: String? = nil, size: CGFloat = 22) {
        self.kind = kind; self.key = key; self.coordinate = coordinate; self.title = title
        self.subtitle = subtitle; self.color = color; self.text = text; self.size = size
    }
}

final class TitledPolygon: MKPolygon {
    var fill: UIColor = .clear
    var strokeColor: UIColor = .clear
}

final class TitledPolyline: MKPolyline {
    var strokeColor: UIColor = .systemIndigo
    var width: CGFloat = 3
    var dashed = false
    /// A road section (umferdin.is id): tapping the line selects it.
    var sectionID: String?
}

// MARK: - Map content description (built by SwiftUI, applied by the coordinator)

struct MapContent {
    var raster: RasterOverlay?
    var rasterKey = ""
    var radarTemplate: String?
    var arrows: [ArrowAnnotation] = []
    var arrowsKey = ""
    var pois: [PoiAnnotation] = []
    var poisKey = ""
    var polygons: [TitledPolygon] = []
    var polygonsKey = ""
    var polylines: [TitledPolyline] = []
    var polylinesKey = ""
    /// Animated wind particles (nil = off).
    var windField: WindField?
    var windFieldKey = ""
    /// Gently pulse the raster (aurora "breathing").
    var pulse = false
}

struct WeatherMapView: UIViewRepresentable {
    var content: MapContent
    var initialRegion: MKCoordinateRegion
    var onTap: (CLLocationCoordinate2D) -> Void
    var onSelect: (PoiAnnotation) -> Void
    /// Tap on a road-section line (within ~22 pt).
    var onSelectSection: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = true
        map.showsScale = true
        map.pointOfInterestFilter = .excludingAll
        // Particle projection assumes a north-up map.
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.setRegion(initialRegion, animated: false)
        let particles = WindParticleView(frame: map.bounds)
        particles.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        particles.mapView = map
        map.addSubview(particles)
        context.coordinator.particles = particles
        map.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "arrow")
        map.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "dot")
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "marker")
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)
        let tracking = MKUserTrackingButton(mapView: map)
        tracking.translatesAutoresizingMaskIntoConstraints = false
        tracking.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.85)
        tracking.layer.cornerRadius = 8
        map.addSubview(tracking)
        NSLayoutConstraint.activate([
            tracking.trailingAnchor.constraint(equalTo: map.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            tracking.topAnchor.constraint(equalTo: map.safeAreaLayoutGuide.topAnchor, constant: 150),
        ])
        context.coordinator.mapView = map
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(content, to: map)
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: WeatherMapView
        weak var mapView: MKMapView?
        private var applied = MapContent()
        private var rasterOverlay: RasterOverlay?
        private var radarOverlay: MKTileOverlay?
        private var radarTemplate: String?
        var particles: WindParticleView?
        private weak var rasterRenderer: RasterRenderer?
        private var pulseLink: CADisplayLink?
        private var pulseStart = CACurrentMediaTime()

        init(_ parent: WeatherMapView) { self.parent = parent }

        deinit { pulseLink?.invalidate() }

        private func setPulse(_ on: Bool) {
            if on, pulseLink == nil {
                let link = CADisplayLink(target: self, selector: #selector(pulseStep))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 20, preferred: 15)
                link.add(to: .main, forMode: .common)
                pulseLink = link
            } else if !on {
                pulseLink?.invalidate()
                pulseLink = nil
                rasterRenderer?.alpha = 1
            }
        }

        @objc private func pulseStep() {
            let t = CACurrentMediaTime() - pulseStart
            rasterRenderer?.alpha = CGFloat(0.72 + 0.28 * sin(t * 2.2))
        }

        func apply(_ content: MapContent, to map: MKMapView) {
            if content.windFieldKey != applied.windFieldKey {
                particles?.field = content.windField
                particles?.isHidden = content.windField == nil
                applied.windFieldKey = content.windFieldKey
            }
            setPulse(content.pulse)
            if content.rasterKey != applied.rasterKey {
                if let old = rasterOverlay { map.removeOverlay(old) }
                rasterOverlay = content.raster
                if let raster = content.raster { map.addOverlay(raster, level: .aboveRoads) }
                applied.rasterKey = content.rasterKey
            }
            if content.radarTemplate != radarTemplate {
                if let old = radarOverlay { map.removeOverlay(old) }
                radarOverlay = nil
                if let template = content.radarTemplate {
                    let tiles = MKTileOverlay(urlTemplate: template)
                    tiles.maximumZ = 7
                    tiles.canReplaceMapContent = false
                    map.addOverlay(tiles, level: .aboveRoads)
                    radarOverlay = tiles
                }
                radarTemplate = content.radarTemplate
            }
            if content.polygonsKey != applied.polygonsKey {
                map.removeOverlays(applied.polygons)
                map.addOverlays(content.polygons, level: .aboveRoads)
                applied.polygons = content.polygons
                applied.polygonsKey = content.polygonsKey
            }
            if content.polylinesKey != applied.polylinesKey {
                map.removeOverlays(applied.polylines)
                map.addOverlays(content.polylines, level: .aboveLabels)
                applied.polylines = content.polylines
                applied.polylinesKey = content.polylinesKey
            }
            if content.arrowsKey != applied.arrowsKey {
                map.removeAnnotations(applied.arrows)
                map.addAnnotations(content.arrows)
                applied.arrows = content.arrows
                applied.arrowsKey = content.arrowsKey
            }
            if content.poisKey != applied.poisKey {
                map.removeAnnotations(applied.pois)
                map.addAnnotations(content.pois)
                applied.pois = content.pois
                applied.poisKey = content.poisKey
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let map = mapView, gesture.state == .ended else { return }
            let point = gesture.location(in: map)
            // Ignore taps on annotations (they have their own selection).
            if let hit = map.hitTest(point, with: nil), hit is MKAnnotationView || hit.superview is MKAnnotationView { return }
            if let select = parent.onSelectSection, let id = nearestSection(to: point, in: map, within: 22) {
                select(id)
                return
            }
            parent.onTap(map.convert(point, toCoordinateFrom: map))
        }

        /// The road-section line closest to a screen point, if within `tolerance` points.
        private func nearestSection(to point: CGPoint, in map: MKMapView, within tolerance: CGFloat) -> String? {
            let visible = map.visibleMapRect
            var best: (id: String, d: CGFloat)?
            for case let line as TitledPolyline in map.overlays {
                guard let id = line.sectionID, line.boundingMapRect.intersects(visible) else { continue }
                let pts = line.points()
                var previous: CGPoint?
                for i in 0..<line.pointCount {
                    let p = map.convert(pts[i].coordinate, toPointTo: map)
                    if let a = previous {
                        let dx = p.x - a.x, dy = p.y - a.y, len2 = dx * dx + dy * dy
                        let t = len2 > 0 ? max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / len2)) : 0
                        let d = hypot(a.x + t * dx - point.x, a.y + t * dy - point.y)
                        if d <= tolerance, d < best?.d ?? .infinity { best = (id, d) }
                    }
                    previous = p
                }
            }
            return best?.id
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let raster = overlay as? RasterOverlay {
                let renderer = RasterRenderer(overlay: raster)
                rasterRenderer = renderer
                return renderer
            }
            if let tiles = overlay as? MKTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tiles)
                renderer.alpha = 0.75
                return renderer
            }
            if let polygon = overlay as? TitledPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.fillColor = polygon.fill
                renderer.strokeColor = polygon.strokeColor
                renderer.lineWidth = 1.5
                return renderer
            }
            if let line = overlay as? TitledPolyline {
                let renderer = MKPolylineRenderer(polyline: line)
                renderer.strokeColor = line.strokeColor
                renderer.lineWidth = line.width
                if line.dashed { renderer.lineDashPattern = [6, 4] }
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if let arrow = annotation as? ArrowAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "arrow", for: arrow)
                view.image = Self.arrowImage
                view.transform = CGAffineTransform(rotationAngle: CGFloat((arrow.degrees + 180) * .pi / 180))
                view.alpha = 0.85
                view.canShowCallout = false
                view.isUserInteractionEnabled = false
                view.displayPriority = .defaultLow
                view.zPriority = .min
                return view
            }
            guard let poi = annotation as? PoiAnnotation else { return nil }
            switch poi.kind {
            case .station, .quake:
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "dot", for: poi)
                view.image = Self.dot(color: poi.color, text: poi.text, size: poi.size)
                view.canShowCallout = false
                view.displayPriority = poi.kind == .station ? .defaultHigh : .required
                return view
            default:
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "marker", for: poi) as! MKMarkerAnnotationView
                view.markerTintColor = poi.color
                view.glyphImage = UIImage(systemName: Self.glyph(poi.kind))
                let pinned = poi.kind == .stop || poi.kind == .place || poi.kind == .visit
                view.titleVisibility = pinned ? .visible : .hidden
                view.subtitleVisibility = poi.kind == .place ? .visible : .hidden
                view.canShowCallout = false
                view.displayPriority = pinned ? .required : .defaultLow
                view.zPriority = poi.kind == .place ? .max : .defaultUnselected
                view.clusteringIdentifier = pinned ? nil : poi.kind.rawValue
                return view
            }
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let poi = annotation as? PoiAnnotation { parent.onSelect(poi) }
            if let cluster = annotation as? MKClusterAnnotation {
                mapView.showAnnotations(cluster.memberAnnotations, animated: true)
            }
            mapView.deselectAnnotation(annotation, animated: false)
        }

        private static func glyph(_ kind: PoiAnnotation.Kind) -> String {
            switch kind {
            case .place: return "mappin"
            case .webcam: return "video.fill"
            case .fuel: return "fuelpump.fill"
            case .charger: return "bolt.car.fill"
            case .shop: return "cart.fill"
            case .stop: return "flag.fill"
            case .visit: return "binoculars.fill"
            case .station: return "road.lanes"
            case .quake: return "waveform.path.ecg"
            case .roadSection: return "exclamationmark.triangle.fill"
            case .roadHazard: return "cone.fill"
            case .sighting: return "eye.fill"
            case .noSighting: return "eye.slash"
            }
        }

        static let arrowImage: UIImage = {
            let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
            return UIImage(systemName: "location.north.fill", withConfiguration: config)?
                .withTintColor(.black.withAlphaComponent(0.75), renderingMode: .alwaysOriginal) ?? UIImage()
        }()

        private static var dotCache: [String: UIImage] = [:]

        static func dot(color: UIColor, text: String?, size: CGFloat) -> UIImage {
            let key = "\(color.description)|\(text ?? "")|\(size)"
            if let cached = dotCache[key] { return cached }
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            let image = renderer.image { _ in
                let rect = CGRect(x: 1, y: 1, width: size - 2, height: size - 2)
                color.setFill()
                UIBezierPath(ovalIn: rect).fill()
                UIColor.white.withAlphaComponent(0.9).setStroke()
                let border = UIBezierPath(ovalIn: rect)
                border.lineWidth = 1.5
                border.stroke()
                if let text {
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: size * 0.45, weight: .bold),
                        .foregroundColor: UIColor.black,
                    ]
                    let s = text as NSString
                    let textSize = s.size(withAttributes: attributes)
                    s.draw(at: CGPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2), withAttributes: attributes)
                }
            }
            dotCache[key] = image
            return image
        }
    }
}
