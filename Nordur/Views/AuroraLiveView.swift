import SwiftUI
import MapKit
import UIKit

/// Live aurora: the OVATION oval painted on the map, plus NOAA's polar
/// animation of the last hours.
struct AuroraLiveView: View {
    @Environment(AppModel.self) private var model
    @Environment(TripStore.self) private var trip
    @State private var raster: RasterOverlay?
    @State private var rasterKey = ""
    @State private var cloudRaster: RasterOverlay?
    @State private var cloudKey = ""
    /// One quantity at a time, each with its own legend: OVATION or cloud cover.
    @State private var layer: Layer = .oval

    enum Layer: String, CaseIterable { case oval = "OVALE OVATION", clouds = "NUVOLE ORA" }
    @State private var frames: [OvationFrame] = []
    @State private var images: [Date: UIImage] = [:]
    @State private var index = 0
    @State private var playing = true
    @State private var error: String?

    private static let region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 66, longitude: -18),
                                                   span: MKCoordinateSpan(latitudeDelta: 24, longitudeDelta: 60))

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Card(title: "Ovale aurorale sulla mappa", systemImage: "moon.stars.fill", tint: .mint) {
                    HStack(spacing: 0) {
                        ForEach(Layer.allCases, id: \.self) { l in
                            Button { layer = l; Task { await buildClouds() } } label: {
                                Text(l.rawValue).font(.mono(10.5, .semibold))
                                    .foregroundStyle(layer == l ? Theme.bg : Theme.text)
                                    .frame(maxWidth: .infinity).frame(height: 34)
                                    .background(layer == l ? Theme.text : .clear)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: 1))
                    WeatherMapView(content: mapContent, initialRegion: layer == .clouds ? Self.iceland : Self.region, onTap: { _ in }, onSelect: { _ in })
                        .id(layer)
                        .frame(height: 380)
                        .clipShape(Rectangle())
                    if layer == .oval { legend } else { cloudLegend }
                    siteLegend
                    Text("Di giorno l'ovale si trova sul lato notturno della Terra.")
                        .font(.app(.caption2)).foregroundStyle(.secondary)
                    if let ovation = model.ovation {
                        Text("Previsione OVATION valida per le \(Fmt.time(ovation.value.forecastTime, in: .iceland)) (circa 30–90 minuti dopo la misura del vento solare a L1): non vale per le ore e i giorni successivi. La scala mostra il valore del modello OVATION, non nuvolosità né probabilità di osservazione. Kp previsto per il blocco attuale \(Fmt.number(model.kp.flatMap { KpLookup.kp(at: Date(), in: $0.value) }, decimals: 1)).")
                            .font(.app(.caption2)).foregroundStyle(.secondary)
                        FreshnessLabel(date: ovation.date, isStale: ovation.isStale, source: "NOAA SWPC")
                    }
                    ErrorNote(message: model.errors[.ovation])
                }

                Card(title: "Vista polare NOAA, ultime 3 ore", systemImage: "globe.europe.africa.fill", tint: .green) {
                    if frames.isEmpty {
                        if let error { ErrorNote(message: error) } else { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
                    } else {
                        let frame = frames[min(index, frames.count - 1)]
                        ZStack {
                            Color.black
                            if let image = images[frame.time] {
                                Image(uiImage: image).resizable().scaledToFit()
                            } else {
                                ProgressView().tint(.white)
                            }
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(Rectangle())
                        HStack {
                            Button { playing.toggle() } label: { Image(systemName: playing ? "pause.fill" : "play.fill") }
                            Slider(value: Binding(get: { Double(index) }, set: { index = Int($0.rounded()); playing = false }),
                                   in: 0...Double(max(frames.count - 1, 1)), step: 1)
                            Text(Fmt.time(frame.time, in: .iceland)).font(.app(.caption).monospacedDigit())
                        }
                    }
                }

            }
            .padding()
        }
        .background(Theme.bg.ignoresSafeArea())
        .themedList()
        .navigationTitle("Aurora live")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .task { if model.siteRanking.isEmpty { await model.refreshAurora() } }
        .task(id: playing) { await animate() }
        .refreshable { await load(force: true) }
        .task {
            // Live: NOAA refreshes the oval every ~5 minutes.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300 * 1_000_000_000)
                guard !Task.isCancelled else { break }
                await load(force: true)
            }
        }
    }

    private static let iceland = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 64.9, longitude: -19),
                                                    span: MKCoordinateSpan(latitudeDelta: 4.6, longitudeDelta: 12))

    private var mapContent: MapContent {
        var c = MapContent()
        c.raster = layer == .oval ? raster : cloudRaster
        c.rasterKey = layer == .oval ? rasterKey : cloudKey
        c.pulse = layer == .oval
        // Reference sites coloured by their best observability class in the next 12 h.
        var pois = model.siteRanking.map { s -> PoiAnnotation in
            let cls = s.best?.observability ?? .veryPoor
            return PoiAnnotation(kind: .stop, key: "site-\(s.id)", coordinate: s.site.coordinate.clCoordinate,
                                 title: s.site.name, subtitle: cls.label, color: Self.classColor(cls), text: "\(cls.rawValue)", size: 20)
        }
        // Saved places: the trip's stops.
        pois += trip.stops.map { stop in
            PoiAnnotation(kind: .stop, key: "trip-\(stop.id)", coordinate: stop.place.coordinate.clCoordinate,
                          title: stop.place.name, subtitle: "Tappa del viaggio", color: UIColor(white: 0.5, alpha: 1), size: 16)
        }
        c.pois = pois
        c.poisKey = "sites-\(model.siteRanking.map { "\($0.id)\($0.best?.observability.rawValue ?? -1)" }.joined())-\(trip.stops.count)"
        return c
    }

    static func classColor(_ c: ObservabilityClass) -> UIColor {
        switch c {
        case .excellent: return UIColor(red: 0, green: 0.7, blue: 0.48, alpha: 1)
        case .good: return UIColor(red: 0.24, green: 0.82, blue: 0.6, alpha: 1)
        case .moderate: return UIColor(red: 0.95, green: 0.72, blue: 0.03, alpha: 1)
        case .poor: return UIColor(white: 0.55, alpha: 1)
        case .veryPoor: return UIColor(white: 0.35, alpha: 1)
        }
    }

    private var siteLegend: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PUNTI: LOCALITÀ DI RIFERIMENTO, COLORATE PER OSSERVABILITÀ MIGLIORE NELLE PROSSIME 12 H (STIMA EURISTICA, NON PROBABILITÀ). GRIGI PICCOLI: TAPPE DEL VIAGGIO.")
                .font(.mono(8.5)).foregroundStyle(Theme.faint)
            HStack(spacing: 10) {
                ForEach(ObservabilityClass.allCases.reversed(), id: \.rawValue) { c in
                    HStack(spacing: 4) {
                        Circle().fill(Color(Self.classColor(c))).frame(width: 8, height: 8)
                        Text("\(c.rawValue)").font(.mono(9)).foregroundStyle(Theme.dim)
                    }
                }
                Text("4 = MOLTO FAVOREVOLE").font(.mono(8.5)).foregroundStyle(Theme.faint)
            }
        }
    }

    @ViewBuilder private var cloudLegend: some View {
        let ramp = WeatherLayer.cloud.ramp
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("0%").font(.mono(9))
                LinearGradient(stops: ramp.map { .init(color: Color(red: $0.r, green: $0.g, blue: $0.b).opacity(max($0.a, 0.35)), location: $0.value / 100) },
                               startPoint: .leading, endPoint: .trailing)
                    .frame(height: 8)
                Text("100%").font(.mono(9))
            }
            Text(model.weatherGrid.map { "COPERTURA NUVOLOSA TOTALE, ORA \(Fmt.time($0.value.times[$0.value.currentHourIndex], in: .iceland)) · OPEN-METEO" } ?? "NUVOLOSITÀ IN CARICAMENTO")
                .font(.mono(8.5)).foregroundStyle(Theme.faint)
        }
    }

    private func buildClouds() async {
        guard layer == .clouds else { return }
        if model.weatherGrid == nil { await model.refreshMapData() }
        guard let grid = model.weatherGrid?.value else { return }
        let h = grid.currentHourIndex, ramp = WeatherLayer.cloud.ramp
        let built = await Task.detached(priority: .userInitiated) { () -> RasterOverlay? in
            let (s, w, n, e) = (grid.lats.first!, grid.lons.first!, grid.lats.last!, grid.lons.last!)
            guard let image = RasterPainter.image(south: s, west: w, north: n, east: e, width: 360, ramp: ramp,
                                                  sample: { lat, lon in grid.value(.cloud, hour: h, lat: lat, lon: lon) }) else { return nil }
            return RasterOverlay(south: s, west: w, north: n, east: e, image: image)
        }.value
        cloudRaster = built
        cloudKey = "cloud-\(h)-\(model.weatherGrid?.date.timeIntervalSince1970 ?? 0)"
    }

    @ViewBuilder private var legend: some View {
        let ramp = WeatherLayer.aurora.ramp
        HStack(spacing: 6) {
            Text("0").font(.mono(9))
            LinearGradient(stops: ramp.map { .init(color: Color(red: $0.r, green: $0.g, blue: $0.b).opacity(max($0.a, 0.35)), location: $0.value / 85) },
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 8)
                .clipShape(Rectangle())
            Text("85+ · VALORE OVATION").font(.mono(9))
        }
    }

    private func load(force: Bool = false) async {
        if model.ovation == nil || force {
            await model.refreshMapData(force: force)
        }
        if let ovation = model.ovation?.value {
            let ramp = WeatherLayer.aurora.ramp
            let built = await Task.detached(priority: .userInitiated) { () -> RasterOverlay? in
                let (s, w, n, e) = (35.0, -180.0, 84.0, 180.0)
                guard let image = RasterPainter.image(south: s, west: w, north: n, east: e, width: 1024, ramp: ramp,
                                                      sample: { lat, lon in ovation.interpolated(lat: lat, lon: lon) }) else { return nil }
                return RasterOverlay(south: s, west: w, north: n, east: e, image: image)
            }.value
            raster = built
            rasterKey = "aurora-\(model.ovation?.date.timeIntervalSince1970 ?? 0)"
        }
        do {
            frames = try await SpaceWeather.ovationAnimation(lastHours: 3, step: 2)
            index = max(0, frames.count - 1)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        for frame in frames.reversed() where images[frame.time] == nil {
            if let data = try? await HTTP.get(frame.url, cacheKey: "ovimg_\(Int(frame.time.timeIntervalSince1970))").value,
               let image = UIImage(data: data) {
                images[frame.time] = image
            }
        }
    }

    private func animate() async {
        while playing && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard playing, !frames.isEmpty else { continue }
            index = (index + 1) % frames.count
        }
    }
}
