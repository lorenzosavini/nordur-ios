import SwiftUI
import MapKit
import UIKit

/// Interactive weather map: one coloured raster layer (wind, gusts, rain, snow,
/// clouds, temperature, aurora, radar) with a 48-hour time slider, plus
/// switchable overlays (IMO warnings, road stations, webcams, quakes, fuel, trip).
struct MapScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(TripStore.self) private var trip
    @Environment(DriveRecorder.self) private var recorder

    @AppStorage("map.layer") private var layerRaw = WeatherLayer.wind.rawValue
    @AppStorage("map.warnings") private var showWarnings = true
    @AppStorage("map.roads") private var showRoads = true
    @AppStorage("map.webcams") private var showWebcams = false
    @AppStorage("map.quakes") private var showQuakes = false
    @AppStorage("map.fuel") private var showFuel = false
    @AppStorage("map.chargers") private var showChargers = false
    @AppStorage("map.trip") private var showTrip = true
    @AppStorage("map.particles") private var showParticles = true

    @State private var hour: Double = -1
    @State private var radarIndex: Double = -1
    @State private var playing = false
    @State private var raster: RasterOverlay?
    @State private var rasterKey = ""
    @State private var probe: Coordinate?
    @State private var selectedStation: RoadStation?
    @State private var selectedWebcam: WebcamSite?
    @State private var showWindy = false

    private var layer: WeatherLayer { WeatherLayer(rawValue: layerRaw) ?? .wind }
    private var grid: WeatherGrid? { model.weatherGrid?.value }
    private var hourIndex: Int {
        guard let grid, grid.hourCount > 0 else { return 0 }
        return hour < 0 ? grid.currentHourIndex : min(Int(hour), grid.hourCount - 1)
    }
    private var radarFrame: RadarFrame? {
        let frames = model.radarFrames
        guard !frames.isEmpty else { return nil }
        let pastCount = frames.filter { $0.time <= Date() }.count
        let index = radarIndex < 0 ? max(0, pastCount - 1) : min(Int(radarIndex), frames.count - 1)
        return frames[index]
    }

    static let iceland = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 64.95, longitude: -18.8),
                                            span: MKCoordinateSpan(latitudeDelta: 5.2, longitudeDelta: 13))

    var body: some View {
        NavigationStack {
            WeatherMapView(
                content: content,
                initialRegion: Self.iceland,
                onTap: { coordinate in probe = Coordinate(coordinate) },
                onSelect: select
            )
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .top) { layerChips }
            .safeAreaInset(edge: .bottom) { bottomPanel }
            .toolbar(.hidden, for: .navigationBar)
            .task { await model.refreshMapData() }
            .task(id: rasterRequestKey) { await rebuildRaster() }
            .task(id: playing) { await animate() }
            .task(id: layerRaw) { await liveRefresh() }
            .sheet(item: $selectedWebcam) { site in
                NavigationStack { WebcamSiteView(site: site) }.presentationDetents([.medium, .large])
            }
            .sheet(item: $selectedStation) { station in
                NavigationStack {
                    List {
                        if let network = model.roads?.value {
                            StationRow(station: station, network: network)
                        }
                    }
                    .navigationTitle(station.name)
                    .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.fraction(0.35), .medium])
            }
            .sheet(isPresented: $showWindy) {
                WindyView(layer: layer, center: probe ?? model.activePlace.coordinate)
            }
        }
    }

    // MARK: Top chips

    private var layerChips: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(WeatherLayer.allCases) { item in
                        Button {
                            layerRaw = item.rawValue
                            playing = false
                        } label: {
                            Label(item.label, systemImage: item.symbol)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(layer == item ? Color.accentColor : Color(.systemBackground).opacity(0.9), in: Capsule())
                                .foregroundStyle(layer == item ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            HStack {
                Menu {
                    Toggle("Allerte meteo IMO", systemImage: "exclamationmark.triangle", isOn: $showWarnings)
                    Toggle("Stazioni stradali (raffiche)", systemImage: "road.lanes", isOn: $showRoads)
                    Toggle("Webcam", systemImage: "video", isOn: $showWebcams)
                    Toggle("Terremoti 48 h", systemImage: "waveform.path.ecg", isOn: $showQuakes)
                    Toggle("Distributori", systemImage: "fuelpump", isOn: $showFuel)
                    Toggle("Ricarica EV", systemImage: "bolt.car", isOn: $showChargers)
                    Toggle("Viaggio e percorso", systemImage: "point.topleft.down.to.point.bottomright.curvepath", isOn: $showTrip)
                    Toggle("Animazione particelle vento", systemImage: "wind", isOn: $showParticles)
                } label: {
                    Label("Livelli", systemImage: "square.3.layers.3d")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(.regularMaterial, in: Capsule())
                }
                Button { showWindy = true } label: {
                    Label("Animazione Windy", systemImage: "wind.circle")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(.regularMaterial, in: Capsule())
                }
                Spacer()
            }
            .padding(.horizontal)
        }
        .padding(.top, 54)
    }

    // MARK: Bottom panel

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let probe { ProbeCard(coordinate: probe, hour: hourIndex) { self.probe = nil } }
            VStack(alignment: .leading, spacing: 8) {
                legend
                timeControls
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    @ViewBuilder private var legend: some View {
        let ramp = layer.ramp
        if !ramp.isEmpty, let minV = ramp.first?.value, let maxV = ramp.last?.value, maxV > minV {
            VStack(alignment: .leading, spacing: 2) {
                LinearGradient(stops: ramp.map {
                    .init(color: Color(red: $0.r, green: $0.g, blue: $0.b).opacity(max($0.a, 0.35)), location: ($0.value - minV) / (maxV - minV))
                }, startPoint: .leading, endPoint: .trailing)
                .frame(height: 10)
                .clipShape(Capsule())
                GeometryReader { geo in
                    ForEach(layer.legendValues, id: \.self) { value in
                        Text(Fmt.number(value, decimals: value < 1 && value > 0 ? 1 : 0))
                            .font(.caption2)
                            .position(x: geo.size.width * (value - minV) / (maxV - minV), y: 6)
                    }
                }
                .frame(height: 12)
                Text("\(layer.label) (\(layer.unit)) · tocca la mappa per i valori in un punto")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        } else if layer == .radar {
            Text("Radar precipitazioni (RainViewer): ultime 2 ore + previsione a breve. Copertura parziale sull'Islanda.")
                .font(.caption2).foregroundStyle(.secondary)
        } else {
            Text("Nessun livello meteo · tocca la mappa per i valori in un punto").font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var timeControls: some View {
        if layer.isForecast, let grid, grid.hourCount > 1 {
            HStack {
                Button { playing.toggle() } label: { Image(systemName: playing ? "pause.fill" : "play.fill") }
                VStack(alignment: .leading, spacing: 0) {
                    Text(Fmt.dayTime(grid.times[hourIndex], in: .iceland)).font(.caption.weight(.semibold))
                    Slider(value: Binding(get: { Double(hourIndex) }, set: { hour = $0.rounded() }),
                           in: 0...Double(grid.hourCount - 1), step: 1)
                }
                Button("Adesso") { hour = -1; playing = false }.font(.caption)
            }
            if let fetched = model.weatherGrid {
                FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: "Open-Meteo")
            }
        } else if layer.isForecast {
            HStack {
                if model.errors[.grid] == nil { ProgressView() }
                ErrorNote(message: model.errors[.grid] ?? "Carico la griglia meteo…")
                Spacer()
                Button("Riprova") { Task { await model.refreshMapData(force: true) } }.font(.caption)
            }
        } else if layer == .radar, let frame = radarFrame {
            HStack {
                Button { playing.toggle() } label: { Image(systemName: playing ? "pause.fill" : "play.fill") }
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Fmt.dayTime(frame.time))\(frame.time > Date() ? " (previsione)" : "")").font(.caption.weight(.semibold))
                    Slider(value: Binding(get: { Double(model.radarFrames.firstIndex(of: frame) ?? 0) }, set: { radarIndex = $0.rounded() }),
                           in: 0...Double(max(model.radarFrames.count - 1, 1)), step: 1)
                }
            }
        } else if layer == .aurora {
            HStack {
                Text("LIVE").font(.caption2.weight(.heavy)).padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.red, in: Capsule()).foregroundStyle(.white)
                Image(systemName: "sparkles").foregroundStyle(.mint)
                Text("Ovale OVATION previsto per le \(Fmt.time(model.ovation?.value.forecastTime, in: .iceland)) · Kp \(Fmt.number(model.kp.flatMap { AuroraCalc.kp(at: Date(), in: $0.value) }, decimals: 1))")
                    .font(.caption)
                Spacer()
            }
            Text("Probabilità di vedere l'aurora sopra di te. Attiva anche «Nuvole» per capire dove il cielo è sereno.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: Raster

    private var rasterRequestKey: String {
        switch layer {
        case .aurora:
            return "aurora-\(model.ovation?.date.timeIntervalSince1970 ?? 0)"
        case _ where layer.isForecast:
            return "\(layer.rawValue)-\(hourIndex)-\(model.weatherGrid?.date.timeIntervalSince1970 ?? 0)"
        default:
            return "none"
        }
    }

    private func rebuildRaster() async {
        let key = rasterRequestKey
        let currentLayer = layer
        let ramp = currentLayer.ramp
        var built: RasterOverlay?
        if currentLayer == .aurora, let ovation = model.ovation?.value {
            built = await Task.detached(priority: .userInitiated) {
                let (s, w, n, e) = (35.0, -180.0, 84.0, 180.0)
                guard let image = RasterPainter.image(south: s, west: w, north: n, east: e, width: 1024, ramp: ramp,
                                                      sample: { lat, lon in ovation.interpolated(lat: lat, lon: lon) }) else { return nil }
                return RasterOverlay(south: s, west: w, north: n, east: e, image: image)
            }.value
        } else if currentLayer.isForecast, let grid {
            let h = hourIndex
            built = await Task.detached(priority: .userInitiated) {
                let (s, w, n, e) = (grid.lats.first!, grid.lons.first!, grid.lats.last!, grid.lons.last!)
                guard let image = RasterPainter.image(south: s, west: w, north: n, east: e, width: 360, ramp: ramp,
                                                      sample: { lat, lon in grid.value(currentLayer, hour: h, lat: lat, lon: lon) }) else { return nil }
                return RasterOverlay(south: s, west: w, north: n, east: e, image: image)
            }.value
        }
        guard key == rasterRequestKey else { return }
        raster = built
        rasterKey = built == nil ? "none" : key
    }

    /// Keeps "live" layers fresh while they are on screen: aurora oval every 5 min, radar every 5 min.
    private func liveRefresh() async {
        while !Task.isCancelled && (layer == .aurora || layer == .radar) {
            try? await Task.sleep(nanoseconds: 300 * 1_000_000_000)
            guard !Task.isCancelled else { break }
            if layer == .aurora {
                if let fresh = try? await SpaceWeather.ovation() { model.ovation = fresh }
            } else if layer == .radar {
                if let frames = try? await RainViewer.frames() { model.radarFrames = frames; radarIndex = -1 }
            }
        }
    }

    private func animate() async {
        guard playing else { return }
        while playing && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard playing else { break }
            if layer == .radar {
                let count = model.radarFrames.count
                guard count > 0 else { continue }
                let current = radarFrame.flatMap { model.radarFrames.firstIndex(of: $0) } ?? 0
                radarIndex = Double((current + 1) % count)
            } else if let grid, grid.hourCount > 0 {
                hour = Double((hourIndex + 1) % grid.hourCount)
            }
        }
    }

    // MARK: Map content

    private var content: MapContent {
        var c = MapContent()
        c.raster = raster
        c.rasterKey = rasterKey
        c.radarTemplate = layer == .radar ? radarFrame?.urlTemplate : nil

        if layer.showsArrows && showParticles, let grid {
            c.windField = WindField(grid: grid, hour: hourIndex)
            c.windFieldKey = "wf-\(hourIndex)-\(model.weatherGrid?.date.timeIntervalSince1970 ?? 0)"
        }
        c.pulse = layer == .aurora

        if layer.showsArrows && !showParticles, let grid {
            let h = hourIndex
            var arrows: [ArrowAnnotation] = []
            for row in grid.lats.indices where row % 2 == 0 {
                for col in grid.lons.indices where col % 2 == 0 {
                    guard let dir = grid.direction(hour: h, row: row, col: col) else { continue }
                    let speed = grid.value(.wind, hour: h, lat: grid.lats[row], lon: grid.lons[col]) ?? 0
                    arrows.append(ArrowAnnotation(coordinate: CLLocationCoordinate2D(latitude: grid.lats[row], longitude: grid.lons[col]),
                                                  degrees: dir, speed: speed))
                }
            }
            c.arrows = arrows
            c.arrowsKey = "arrows-\(h)-\(model.weatherGrid?.date.timeIntervalSince1970 ?? 0)"
        }

        var pois: [PoiAnnotation] = []
        var poisKey = ""
        if showRoads, let network = model.roads?.value {
            for station in network.stations where !station.isOutdated {
                guard let coord = station.coordinate, station.Vindhvida != nil || station.Vindhradi != nil else { continue }
                let gust = Int((station.Vindhvida ?? station.Vindhradi ?? 0).rounded())
                pois.append(PoiAnnotation(kind: .station, key: "st\(station.id)", coordinate: coord.clCoordinate,
                                          title: station.name, color: UIColor(network.worstRisk(of: station).color), text: "\(gust)"))
            }
            poisKey += "roads\(model.roads?.date.timeIntervalSince1970 ?? 0)"
        }
        if showWebcams {
            for site in model.webcams?.value ?? [] {
                pois.append(PoiAnnotation(kind: .webcam, key: "wc\(site.id)", coordinate: site.coordinate.clCoordinate,
                                          title: site.name, color: .systemIndigo))
            }
            poisKey += "webcams\(model.webcams?.value.count ?? 0)"
        }
        if showQuakes {
            for quake in (model.quakes?.value ?? []) where quake.magnitude >= 1 {
                pois.append(PoiAnnotation(kind: .quake, key: "q\(quake.id)", coordinate: quake.coordinate.clCoordinate,
                                          title: "M\(Fmt.number(quake.magnitude, decimals: 1)) \(quake.region)",
                                          color: UIColor(quake.risk.color).withAlphaComponent(0.8), size: CGFloat(8 + quake.magnitude * 5)))
            }
            poisKey += "quakes\(model.quakes?.date.timeIntervalSince1970 ?? 0)"
        }
        if showFuel || showChargers {
            for station in model.fuel?.value ?? [] where (station.kind == .fuel && showFuel) || (station.kind == .charger && showChargers) {
                pois.append(PoiAnnotation(kind: station.kind == .fuel ? .fuel : .charger, key: "f\(station.id)",
                                          coordinate: station.coordinate.clCoordinate, title: station.name,
                                          color: station.kind == .fuel ? .systemOrange : .systemGreen))
            }
            poisKey += "fuel\(showFuel)\(showChargers)\(model.fuel?.value.count ?? 0)"
        }
        if showTrip {
            for (i, stop) in trip.stops.enumerated() {
                pois.append(PoiAnnotation(kind: .stop, key: "s\(stop.id)", coordinate: stop.place.coordinate.clCoordinate,
                                          title: "\(i + 1). \(stop.place.name)", color: .systemIndigo))
            }
            poisKey += "trip\(trip.stops.map(\.id.uuidString).joined())"
        }
        c.pois = pois
        c.poisKey = poisKey

        if showWarnings {
            var polygons: [TitledPolygon] = []
            for warning in model.warnings?.value ?? [] {
                for ring in warning.polygons {
                    let coords = ring.map(\.clCoordinate)
                    let polygon = TitledPolygon(coordinates: coords, count: coords.count)
                    let color = UIColor(warning.color.color)
                    polygon.fill = color.withAlphaComponent(warning.isActive() ? 0.18 : 0.08)
                    polygon.strokeColor = color
                    polygons.append(polygon)
                }
            }
            c.polygons = polygons
            c.polygonsKey = "w\(model.warnings?.date.timeIntervalSince1970 ?? 0)"
        }

        var lines: [TitledPolyline] = []
        var linesKey = ""
        if showTrip && trip.stops.count >= 2 {
            let coords = trip.stops.map(\.place.coordinate.clCoordinate)
            let line = TitledPolyline(coordinates: coords, count: coords.count)
            line.dashed = true
            lines.append(line)
            linesKey += "trip\(trip.stops.map(\.id.uuidString).joined())"
        }
        if recorder.isRecording {
            let coords = recorder.recentPoints.map(\.coordinate.clCoordinate)
            if coords.count >= 2 {
                let line = TitledPolyline(coordinates: coords, count: coords.count)
                line.strokeColor = .systemRed
                line.width = 4
                lines.append(line)
                linesKey += "rec\(coords.count / 10)"
            }
        }
        c.polylines = lines
        c.polylinesKey = linesKey
        return c
    }

    private func select(_ poi: PoiAnnotation) {
        switch poi.kind {
        case .station:
            let id = Int(poi.key.dropFirst(2)) ?? -1
            selectedStation = model.roads?.value.stations.first { $0.id == id }
        case .webcam:
            let id = Int(poi.key.dropFirst(2)) ?? -1
            selectedWebcam = model.webcams?.value.first { $0.id == id }
        default:
            probe = Coordinate(poi.coordinate)
        }
    }
}

/// Values at a tapped point: forecast for the selected hour, aurora, live road data, warnings.
struct ProbeCard: View {
    @Environment(AppModel.self) private var model
    let coordinate: Coordinate
    let hour: Int
    let close: () -> Void

    private func v(_ layer: WeatherLayer) -> Double? {
        model.weatherGrid?.value.value(layer, hour: hour, lat: coordinate.lat, lon: coordinate.lon)
    }

    var body: some View {
        let grid = model.weatherGrid?.value
        let warnings = (model.warnings?.value ?? []).filter { $0.covers(coordinate) }
        let nearest = model.roads?.value.nearestStations(to: coordinate, count: 1).first
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(format: "%.2f°N %.2f°O", coordinate.lat, -coordinate.lon)).font(.caption.weight(.semibold))
                if let grid, grid.times.indices.contains(hour) {
                    Text("· \(Fmt.dayTime(grid.times[hour], in: .iceland))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            }
            if grid != nil, v(.temperature) != nil {
                HStack {
                    Metric(title: "Temp.", value: Fmt.temp(v(.temperature)))
                    Metric(title: "Vento", value: Fmt.ms(v(.wind)), tint: Risk.wind(mean: v(.wind), gust: nil).color)
                    Metric(title: "Raffiche", value: Fmt.ms(v(.gust)), tint: Risk.wind(mean: nil, gust: v(.gust)).color)
                }
                HStack {
                    Metric(title: "Pioggia", value: Fmt.number(v(.precipitation), decimals: 1, unit: "mm/h"))
                    Metric(title: "Neve", value: Fmt.number(v(.snow), decimals: 1, unit: "cm/h"))
                    Metric(title: "Nuvole", value: Fmt.percent(v(.cloud)))
                }
            } else {
                Text("Fuori dalla griglia meteo dell'Islanda.").font(.caption).foregroundStyle(.secondary)
            }
            if let ovation = model.ovation?.value {
                Text("Aurora adesso: \(Fmt.percent(ovation.interpolated(lat: coordinate.lat, lon: coordinate.lon)))")
                    .font(.caption).foregroundStyle(.mint)
            }
            if let nearest {
                Text("Stazione \(nearest.station.name) (\(Int(nearest.distance)) km): \(Fmt.ms(nearest.station.Vindhradi)) / raff. \(Fmt.ms(nearest.station.Vindhvida)), asfalto \(Fmt.temp(nearest.station.Veghiti))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(warnings.prefix(2)) { warning in
                HStack { WarningBadge(color: warning.color); Text(warning.headline).font(.caption2) }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
