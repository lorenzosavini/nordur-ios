import SwiftUI
import MapKit
import AVFoundation

/// A recorded route as a picture or a short video to post (Instagram stories and
/// posts, like Strava): the route drawn on a 3D satellite view of the terrain,
/// looking along the way, with distance, time, climb and speed.
enum RouteCard {
    enum Format: String, CaseIterable, Identifiable {
        case story, post
        var id: String { rawValue }
        var label: String { self == .story ? String(localized: "Storia 9:16") : String(localized: "Post 4:5") }
        /// Pixels.
        var size: CGSize { self == .story ? CGSize(width: 1080, height: 1920) : CGSize(width: 1080, height: 1350) }
    }

    struct Stats {
        let title: String
        let date: String
        let figures: [(label: String, value: String)]
    }

    static func stats(_ s: DriveSession) -> Stats {
        let hours = s.durationSeconds() / 3600
        var figures: [(label: String, value: String)] = [
            (String(localized: "DISTANZA"), "\(Fmt.number(s.stats.km, decimals: s.stats.km < 100 ? 1 : 0)) km"),
            (String(localized: "TEMPO"), Fmt.duration(s.durationSeconds())),
            (String(localized: "DISLIVELLO"), "\(Int(s.stats.elevationGain.rounded())) m"),
        ]
        if s.isDrive || hours <= 0 {
            figures.append((String(localized: "MEDIA"), hours > 0 ? "\(Int((s.stats.km / hours).rounded())) km/h" : "–"))
        } else {
            let pace = s.durationSeconds() / 60 / max(s.stats.km, 0.01)
            figures.append((String(localized: "PASSO"), String(format: "%d:%02d /km", Int(pace), Int((pace - floor(pace)) * 60))))
        }
        return Stats(title: s.name, date: Fmt.day(s.start, in: .iceland), figures: figures)
    }

    // MARK: Map

    /// One 3D picture of the terrain under the route, with the camera behind its start looking along it.
    static func snapshot(_ points: [TrackPoint], format: Format) async throws -> MKMapSnapshotter.Snapshot {
        let coords = points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        let spanKm = max(Geo.distanceKm(Coordinate(lat: lats.min()!, lon: lons.min()!), Coordinate(lat: lats.max()!, lon: lons.max()!)), 0.6)
        let first = points.first!.coordinate, last = points.last!.coordinate
        let heading = Geo.distanceKm(first, last) > 0.3 ? bearing(first, last) : 0
        let options = MKMapSnapshotter.Options()
        options.size = CGSize(width: format.size.width / 3, height: format.size.height / 3)
        options.traitCollection = UITraitCollection(traitsFrom: [UITraitCollection(displayScale: 3), UITraitCollection(userInterfaceStyle: .dark)])
        options.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .realistic)
        options.camera = MKMapCamera(lookingAtCenter: center, fromDistance: spanKm * 1000 * (format == .story ? 2.4 : 1.9), pitch: 58, heading: heading)
        return try await MKMapSnapshotter(options: options).start()
    }

    private static func bearing(_ a: Coordinate, _ b: Coordinate) -> CLLocationDirection {
        let φ1 = a.lat * .pi / 180, φ2 = b.lat * .pi / 180, Δλ = (b.lon - a.lon) * .pi / 180
        let y = sin(Δλ) * cos(φ2), x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    // MARK: Drawing

    /// One frame: the map (zoomed by `zoom` around the centre), the route up to
    /// `progress` (0…1), the stats (counting up with `progress`) and the mark.
    static func draw(_ ctx: CGContext, snapshot: MKMapSnapshotter.Snapshot, route: [CGPoint], size: CGSize,
                     stats: Stats, progress: Double, zoom: CGFloat) {
        UIGraphicsPushContext(ctx)
        defer { UIGraphicsPopContext() }
        let scale = size.width / snapshot.image.size.width
        let transform = CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
            .scaledBy(x: zoom, y: zoom).translatedBy(x: -size.width / 2, y: -size.height / 2)
        ctx.saveGState()
        ctx.concatenate(transform)
        snapshot.image.draw(in: CGRect(origin: .zero, size: size))
        // The route: a soft glow, then the line, up to the progress.
        let count = max(2, Int(Double(route.count) * progress))
        let pts = route.prefix(count).map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
        if pts.count > 1 {
            let path = CGMutablePath()
            path.addLines(between: pts)
            ctx.setLineCap(.round); ctx.setLineJoin(.round)
            ctx.addPath(path); ctx.setStrokeColor(UIColor(red: 1, green: 0.35, blue: 0.1, alpha: 0.35).cgColor); ctx.setLineWidth(26); ctx.strokePath()
            ctx.addPath(path); ctx.setStrokeColor(UIColor(red: 1, green: 0.42, blue: 0.12, alpha: 1).cgColor); ctx.setLineWidth(11); ctx.strokePath()
            ctx.addPath(path); ctx.setStrokeColor(UIColor(white: 1, alpha: 0.85).cgColor); ctx.setLineWidth(3); ctx.strokePath()
            dot(ctx, pts.first!, color: UIColor(red: 0.2, green: 0.9, blue: 0.6, alpha: 1))
            dot(ctx, pts.last!, color: .white, ring: progress < 1)
        }
        ctx.restoreGState()

        // Shades for the text.
        let colors = [UIColor.black.withAlphaComponent(0.75).cgColor, UIColor.black.withAlphaComponent(0).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height * 0.22), options: [])
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: 0, y: size.height * 0.62), options: [])
        }

        let margin: CGFloat = 72
        // The app's mark and name, so a shared picture says where it comes from.
        logo(ctx, at: CGPoint(x: margin, y: 64), side: 104)
        text("NORÐUR", at: CGPoint(x: margin + 128, y: 66), font: condensed(58), color: .white, kern: 10)
        text(stats.date.uppercased(), at: CGPoint(x: margin + 130, y: 134), font: mono(30), color: UIColor(white: 1, alpha: 0.8), kern: 2)
        let credit = String(localized: "Creato con Norður")
        let creditFont = mono(26)
        let creditWidth = (credit as NSString).size(withAttributes: [.font: creditFont, .kern: 2]).width
        text(credit, at: CGPoint(x: size.width - margin - creditWidth, y: size.height - 62), font: creditFont,
             color: UIColor(white: 1, alpha: 0.75), kern: 2)
        // Stats at the bottom, two by two.
        let bottom = size.height - 90
        let colWidth = (size.width - margin * 2) / 2
        for (i, f) in stats.figures.enumerated() {
            let col = CGFloat(i % 2), row = CGFloat(i / 2)
            let rows = CGFloat((stats.figures.count + 1) / 2)
            let y = bottom - (rows - row) * 150
            text(f.label, at: CGPoint(x: margin + col * colWidth, y: y), font: mono(28), color: UIColor(white: 1, alpha: 0.7), kern: 3)
            text(counting(f.value, progress), at: CGPoint(x: margin + col * colWidth, y: y + 34), font: condensed(92), color: .white)
        }
        let titleY = bottom - CGFloat((stats.figures.count + 1) / 2) * 150 - 110
        text(stats.title, at: CGPoint(x: margin, y: titleY), font: condensed(70), color: .white, width: size.width - margin * 2)
    }

    /// "123.4 km" shown growing with the animation.
    private static func counting(_ value: String, _ progress: Double) -> String {
        guard progress < 1, let range = value.range(of: #"^\d+([.,]\d+)?"#, options: .regularExpression) else { return value }
        let number = String(value[range])
        let comma = number.contains(",")
        guard let n = Double(number.replacingOccurrences(of: ",", with: ".")) else { return value }
        let shown = n * min(1, progress * 1.1)
        var digits = String(format: "%.\(number.contains(",") || number.contains(".") ? 1 : 0)f", shown)
        if comma { digits = digits.replacingOccurrences(of: ".", with: ",") }
        return digits + value[range.upperBound...]
    }

    /// The app icon's mark: the white Ð with its orange bar on the night blue tile.
    private static func logo(_ ctx: CGContext, at origin: CGPoint, side: CGFloat) {
        let tile = UIBezierPath(roundedRect: CGRect(origin: origin, size: CGSize(width: side, height: side)), cornerRadius: side * 0.22)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 10, color: UIColor.black.withAlphaComponent(0.5).cgColor)
        UIColor(red: 0.05, green: 0.08, blue: 0.16, alpha: 1).setFill()
        tile.fill()
        ctx.restoreGState()
        // A band of aurora across the top of the tile.
        ctx.saveGState()
        tile.addClip()
        let aurora = [UIColor(red: 0.2, green: 0.85, blue: 0.6, alpha: 0.85).cgColor, UIColor(red: 0.2, green: 0.85, blue: 0.6, alpha: 0).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: aurora, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: origin.x, y: origin.y + side * 0.18), end: CGPoint(x: origin.x, y: origin.y + side * 0.5), options: [])
        }
        ctx.restoreGState()
        // The D: a stem and a bowl, white.
        let w = side * 0.42, h = side * 0.56
        let x = origin.x + side * 0.36, y = origin.y + side * 0.24
        let d = UIBezierPath()
        d.move(to: CGPoint(x: x, y: y))
        d.addLine(to: CGPoint(x: x + w * 0.45, y: y))
        d.addArc(withCenter: CGPoint(x: x + w * 0.45, y: y + h / 2), radius: h / 2, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: true)
        d.addLine(to: CGPoint(x: x, y: y + h))
        d.close()
        let inner = UIBezierPath()
        let t = side * 0.1
        inner.move(to: CGPoint(x: x + t, y: y + t))
        inner.addLine(to: CGPoint(x: x + w * 0.45, y: y + t))
        inner.addArc(withCenter: CGPoint(x: x + w * 0.45, y: y + h / 2), radius: h / 2 - t, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: true)
        inner.addLine(to: CGPoint(x: x + t, y: y + h - t))
        inner.close()
        d.append(inner.reversing())
        UIColor(white: 0.97, alpha: 1).setFill()
        d.fill()
        // The bar of the Ð.
        UIColor(red: 0.94, green: 0.29, blue: 0, alpha: 1).setFill()
        UIBezierPath(rect: CGRect(x: origin.x + side * 0.24, y: y + h * 0.47, width: side * 0.27, height: side * 0.075)).fill()
    }

    private static func dot(_ ctx: CGContext, _ p: CGPoint, color: UIColor, ring: Bool = false) {
        let r: CGFloat = ring ? 18 : 14
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.35).cgColor)
        ctx.fillEllipse(in: CGRect(x: p.x - r - 4, y: p.y - r - 4, width: (r + 4) * 2, height: (r + 4) * 2))
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        ctx.setStrokeColor(UIColor.white.cgColor); ctx.setLineWidth(4)
        ctx.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }

    private static func condensed(_ size: CGFloat) -> UIFont { UIFont(name: AppFontName.condensed(.bold), size: size) ?? .boldSystemFont(ofSize: size) }
    private static func mono(_ size: CGFloat) -> UIFont { UIFont(name: AppFontName.mono(.semibold), size: size) ?? .monospacedSystemFont(ofSize: size, weight: .semibold) }

    private static func text(_ s: String, at p: CGPoint, font: UIFont, color: UIColor, kern: CGFloat = 0, width: CGFloat = 2000) {
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = 8
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern, .shadow: shadow]
        NSAttributedString(string: s, attributes: attrs)
            .draw(with: CGRect(x: p.x, y: p.y, width: width, height: font.lineHeight * 2.2), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }

    /// The route in snapshot points (fewer than 600, enough for a smooth line).
    static func route(_ points: [TrackPoint], in snapshot: MKMapSnapshotter.Snapshot) -> [CGPoint] {
        let step = max(1, points.count / 600)
        return stride(from: 0, to: points.count, by: step).map { snapshot.point(for: CLLocationCoordinate2D(latitude: points[$0].lat, longitude: points[$0].lon)) }
            + [snapshot.point(for: CLLocationCoordinate2D(latitude: points.last!.lat, longitude: points.last!.lon))]
    }

    // MARK: Picture and video

    static func image(_ session: DriveSession, format: Format) async throws -> URL {
        let snap = try await snapshot(session.points, format: format)
        let route = route(session.points, in: snap)
        let stats = stats(session)
        let renderer = UIGraphicsImageRenderer(size: format.size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        let image = renderer.image { r in draw(r.cgContext, snapshot: snap, route: route, size: format.size, stats: stats, progress: 1, zoom: 1) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Nordur-\(format.rawValue).jpg")
        try image.jpegData(compressionQuality: 0.92)?.write(to: url, options: .atomic)
        return url
    }

    /// 8 seconds at 30 fps: the route draws itself on the 3D terrain while the
    /// camera moves in slowly, then holds on the whole route.
    static func video(_ session: DriveSession, format: Format, progress report: @escaping (Double) -> Void) async throws -> URL {
        let snap = try await snapshot(session.points, format: format)
        let route = route(session.points, in: snap)
        let stats = stats(session)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Nordur-\(format.rawValue).mp4")
        try? FileManager.default.removeItem(at: url)
        let size = format.size
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 10_000_000],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let fps = 30, frames = 8 * fps
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 5_000_000) }
            let t = Double(frame) / Double(frames - 1)
            // Draw over the first 5.5 s (eased), hold the rest.
            let drawT = min(1, t / 0.69)
            let eased = drawT < 0.5 ? 2 * drawT * drawT : 1 - pow(-2 * drawT + 2, 2) / 2
            let zoom = 1.12 - 0.12 * CGFloat(eased)
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                // UIKit drawing is top-down.
                ctx.translateBy(x: 0, y: size.height)
                ctx.scaleBy(x: 1, y: -1)
                draw(ctx, snapshot: snap, route: route, size: size, stats: stats, progress: eased, zoom: zoom)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
            if frame % 10 == 0 { report(Double(frame) / Double(frames)) }
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? NSError(domain: "Nordur", code: 2) }
        report(1)
        return url
    }
}

/// The share sheet of a route: preview, format, picture and video.
struct RouteShareSheet: View {
    let session: DriveSession
    @Environment(\.dismiss) private var dismiss
    @State private var format: RouteCard.Format = .story
    @State private var imageURL: URL?
    @State private var videoURL: URL?
    @State private var making = false
    @State private var progress = 0.0
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Formato", selection: $format) {
                        ForEach(RouteCard.Format.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    ZStack {
                        RoundedRectangle(cornerRadius: 14).fill(Theme.surface)
                        if let imageURL, let image = UIImage(contentsOfFile: imageURL.path) {
                            Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 14))
                        } else {
                            VStack(spacing: 8) { ProgressView(); Text("Preparo la mappa 3D…").font(.app(.caption)).foregroundStyle(Theme.dim) }
                        }
                    }
                    .frame(height: format == .story ? 460 : 360)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                Section {
                    if let imageURL {
                        ShareLink(item: imageURL, preview: SharePreview(session.name, image: Image(systemName: "photo"))) {
                            Label("Condividi l'immagine", systemImage: "photo.on.rectangle.angled").font(.app(.headline))
                        }
                    }
                    if let videoURL {
                        ShareLink(item: videoURL, preview: SharePreview(session.name, image: Image(systemName: "film"))) {
                            Label("Condividi il video 3D", systemImage: "film.stack").font(.app(.headline))
                        }
                    } else {
                        Button { Task { await makeVideo() } } label: {
                            HStack {
                                Label(making ? String(localized: "Creo il video…") : String(localized: "Crea il video 3D (8 s)"), systemImage: "video.badge.plus")
                                    .font(.app(.headline))
                                if making { Spacer(); ProgressView(value: progress).frame(width: 90) }
                            }
                        }
                        .disabled(making)
                    }
                    if let error { Text(error).font(.app(.caption)).foregroundStyle(Theme.danger) }
                } footer: {
                    Text("Dal menu di condivisione: Instagram (storia o post), WhatsApp, oppure «Salva immagine/video» nelle Foto. Il terreno in 3D e il satellite sono di Apple Mappe.")
                }
            }
            .themedList()
            .navigationTitle("Condividi il percorso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
            .task(id: format) {
                imageURL = nil
                videoURL = nil
                do { imageURL = try await RouteCard.image(session, format: format) } catch { self.error = error.localizedDescription }
            }
        }
    }

    private func makeVideo() async {
        making = true
        progress = 0
        defer { making = false }
        do {
            videoURL = try await RouteCard.video(session, format: format) { p in Task { @MainActor in progress = p } }
            Haptics.result(true)
        } catch {
            self.error = error.localizedDescription
            Haptics.result(false)
        }
    }
}
