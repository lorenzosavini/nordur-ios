import SwiftUI
import MapKit
import UIKit

/// Live aurora: the OVATION oval painted on the map, plus NOAA's polar
/// animation of the last hours.
struct AuroraLiveView: View {
    @Environment(AppModel.self) private var model
    @State private var raster: RasterOverlay?
    @State private var rasterKey = ""
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
                    WeatherMapView(content: mapContent, initialRegion: Self.region, onTap: { _ in }, onSelect: { _ in })
                        .frame(height: 380)
                        .clipShape(Rectangle())
                    legend
                    Text("Di giorno l'ovale si trova sul lato notturno della Terra.")
                        .font(.app(.caption2)).foregroundStyle(.secondary)
                    if let ovation = model.ovation {
                        Text("Previsione OVATION per le \(Fmt.time(ovation.value.forecastTime, in: .iceland)) (30–90 minuti avanti). Kp attuale \(Fmt.number(model.kp.flatMap { AuroraCalc.kp(at: Date(), in: $0.value) }, decimals: 1)).")
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

    private var mapContent: MapContent {
        var c = MapContent()
        c.raster = raster
        c.rasterKey = rasterKey
        c.pulse = true
        return c
    }

    @ViewBuilder private var legend: some View {
        let ramp = WeatherLayer.aurora.ramp
        HStack(spacing: 6) {
            Text("0%").font(.app(.caption2))
            LinearGradient(stops: ramp.map { .init(color: Color(red: $0.r, green: $0.g, blue: $0.b).opacity(max($0.a, 0.35)), location: $0.value / 85) },
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 8)
                .clipShape(Rectangle())
            Text("85%+").font(.app(.caption2))
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
