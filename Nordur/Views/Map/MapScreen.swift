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
    @AppStorage("map.roads.v2") private var showRoads = false
    @AppStorage("map.roadInfo") private var showRoadInfo = true
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
    @State private var selectedSection: RoadInfo.Section?

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

    /// Road-section lines, rebuilt only when the conditions or the geometry change.
    private static let roadLines = RoadLines()

    static let iceland = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 64.95, longitude: -18.8),
                                            span: MKCoordinateSpan(latitudeDelta: 5.2, longitudeDelta: 13))

    var body: some View {
        NavigationStack {
            WeatherMapView(
                content: content,
                initialRegion: Self.iceland,
                onTap: { coordinate in probe = Coordinate(coordinate) },
                onSelect: select,
                onSelectSection: showRoadInfo ? { id in selectedSection = model.roadInfo?.value.sections.first { $0.id == id } } : nil
            )
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .top) { layerChips }
            .safeAreaInset(edge: .bottom) { bottomPanel }
            .toolbar(.hidden, for: .navigationBar)
            .task { await model.refreshMapData() }
            .task(id: rasterRequestKey) { await rebuildRaster() }
            .task(id: playing) { await animate() }
            .task(id: layerRaw) { await liveRefresh() }
            .sheet(item: $selectedSection) { section in
                NavigationStack { RoadSectionView(section: section) }.presentationDetents([.medium, .large])
            }
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
                    .themedList()
                    .navigationTitle(station.name)
                    .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.fraction(0.35), .medium])
            }
        }
    }

    // MARK: Top chips

    private var layerChips: some View {
        VStack(spacing: 8) {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(WeatherLayer.allCases) { item in
                    Button {
                        if layerRaw != item.rawValue { Haptics.select() }
                        layerRaw = item.rawValue
                        playing = false
                    } label: {
                        Label(item.label.loc.uppercased(), systemImage: item.symbol)
                            .labelStyle(.titleAndIcon)
                            .font(.mono(10, .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(layer == item ? Theme.accent : Theme.bg.opacity(0.94))
                            .foregroundStyle(layer == item ? Theme.onAccent : Theme.text)
                            .overlay(Rectangle().strokeBorder(Theme.hairline))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("layer.\(item.rawValue)")
                    .accessibilityAddTraits(layer == item ? .isSelected : [])
                }
            }
            .padding(.horizontal)
            HStack {
                Menu {
                    Toggle("Allerte meteo IMO", systemImage: "exclamationmark.triangle", isOn: $showWarnings)
                    Toggle("Strade: chiusure, lavori e pericoli", systemImage: "exclamationmark.triangle", isOn: $showRoadInfo)
                    Toggle("Stazioni stradali (raffiche)", systemImage: "road.lanes", isOn: $showRoads)
                    Toggle("Webcam", systemImage: "video", isOn: $showWebcams)
                    Toggle("Terremoti 48 h", systemImage: "waveform.path.ecg", isOn: $showQuakes)
                    Toggle("Distributori", systemImage: "fuelpump", isOn: $showFuel)
                    Toggle("Ricarica EV", systemImage: "bolt.car", isOn: $showChargers)
                    Toggle("Viaggio e percorso", systemImage: "point.topleft.down.to.point.bottomright.curvepath", isOn: $showTrip)
                    Toggle("Animazione particelle vento", systemImage: "wind", isOn: $showParticles)
                } label: {
                    Text("LIVELLI +")
                        .font(.mono(10.5, .semibold)).foregroundStyle(Theme.text)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Theme.bg.opacity(0.94)).overlay(Rectangle().strokeBorder(Theme.hairline))
                }
                .accessibilityIdentifier("layers.menu")
                Spacer()
            }
            .padding(.horizontal)
            if !model.inIceland {
                Label("Fuori copertura: la mappa meteo e le strade coprono solo l'Islanda", systemImage: "globe.europe.africa.fill")
                    .font(.app(.caption, .medium)).foregroundStyle(Theme.text)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.bg.opacity(0.94)).overlay(alignment: .leading) { Theme.caution.frame(width: 3) }
                    .padding(.horizontal)
            }
        }
        .padding(.top, 54)
    }

    // MARK: Bottom panel

    @AppStorage("map.legendOpen") private var legendOpen = true
    @State private var detailsHeight: CGFloat = 120

    /// Probe card and legends scroll inside a capped height; the time slider
    /// always stays visible at the bottom, above the tab bar.
    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            if probe != nil || legendOpen {
                ScrollView {
                    panelDetails
                        .background(GeometryReader { g in
                            Color.clear.preference(key: PanelHeightKey.self, value: g.size.height)
                        })
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(max(detailsHeight, 1), 300))
                .onPreferenceChange(PanelHeightKey.self) { detailsHeight = $0 }
            }
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) { timeControls }
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    withAnimation(.snappy) { legendOpen.toggle() }
                } label: {
                    Image(systemName: legendOpen ? "chevron.down" : "list.bullet.below.rectangle")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.text)
                .accessibilityLabel(legendOpen ? String(localized: "Nascondi legenda") : String(localized: "Mostra legenda"))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.bg.opacity(0.94)).overlay(Rectangle().strokeBorder(Theme.hairline))
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    @ViewBuilder private var panelDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let probe { ProbeCard(coordinate: probe, hour: hourIndex) { self.probe = nil } }
            if legendOpen {
                VStack(alignment: .leading, spacing: 8) {
                    legend
                    if showRoadInfo && model.roadGeometry != nil && model.roadInfo != nil { roadLegend }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bg.opacity(0.94)).overlay(Rectangle().strokeBorder(Theme.hairline))
            }
        }
    }

    @ViewBuilder private var legend: some View {
        let ramp = layer.ramp
        if !ramp.isEmpty, let minV = ramp.first?.value, let maxV = ramp.last?.value, maxV > minV {
            VStack(alignment: .leading, spacing: 2) {
                LinearGradient(stops: ramp.map {
                    .init(color: Color(red: $0.r, green: $0.g, blue: $0.b).opacity(max($0.a, 0.35)), location: ($0.value - minV) / (maxV - minV))
                }, startPoint: .leading, endPoint: .trailing)
                .frame(height: 10)
                .clipShape(Rectangle())
                GeometryReader { geo in
                    ForEach(layer.legendValues, id: \.self) { value in
                        Text(layer.showsArrows ? Fmt.wind(value) : Fmt.number(value, decimals: value < 1 && value > 0 ? 1 : 0))
                            .font(.app(.caption2))
                            .position(x: geo.size.width * (value - minV) / (maxV - minV), y: 6)
                    }
                }
                .frame(height: 12)
                Text("\(layer.label), \(layer.showsArrows ? Fmt.windUnit : layer.unit)")
                    .font(.app(.caption2)).foregroundStyle(.secondary)
            }
        } else if layer == .radar {
            Text("Radar RainViewer, ultime 2 ore. Copertura parziale.")
                .font(.app(.caption2)).foregroundStyle(.secondary)
        } else {
            Text("Tocca la mappa per i valori in un punto").font(.app(.caption2)).foregroundStyle(.secondary)
        }
    }

    /// Colours of the road lines (umferdin.is surface conditions).
    private var roadLegend: some View {
        let items: [(String, UIColor, Bool)] = [
            (String(localized: "Percorribile"), RoadLines.style(for: .ok), false),
            (String(localized: "Ghiaccio a tratti"), RoadLines.style(for: .caution), false),
            (String(localized: "Scivolosa / neve"), RoadLines.style(for: .warning), false),
            (String(localized: "Difficile"), RoadLines.style(for: .danger), false),
            (String(localized: "Chiusa"), RoadLines.closedColor, true),
            (String(localized: "Nessun servizio"), RoadLines.style(for: nil), false),
        ]
        return VStack(alignment: .leading, spacing: 4) {
            FlowLayout(spacing: 10, lineSpacing: 4) {
                ForEach(items, id: \.0) { item in
                    HStack(spacing: 4) {
                        Capsule().fill(Color(item.1)).frame(width: 14, height: item.2 ? 4 : 3)
                        Text(item.0).font(.app(.caption2)).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Strade: condizioni Vegagerðin. Tocca una strada per i dettagli.").font(.app(.caption2)).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder private var timeControls: some View {
        if layer.isForecast, let grid, grid.hourCount > 1 {
            HStack {
                Button { playing.toggle() } label: { Image(systemName: playing ? "pause.fill" : "play.fill") }
                VStack(alignment: .leading, spacing: 0) {
                    Text(Fmt.dayTime(grid.times[hourIndex], in: .iceland)).font(.app(.caption, .semibold))
                    Slider(value: Binding(get: { Double(hourIndex) }, set: { hour = $0.rounded() }),
                           in: 0...Double(grid.hourCount - 1), step: 1)
                }
                Button("Adesso") { hour = -1; playing = false }.font(.app(.caption))
            }
            if let fetched = model.weatherGrid {
                FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: String(localized: "Open-Meteo"))
            }
        } else if layer.isForecast {
            HStack {
                if model.errors[.grid] == nil { ProgressView() }
                ErrorNote(message: model.errors[.grid] ?? String(localized: "Carico la griglia meteo…"))
                Spacer()
                Button("Riprova") { Task { await model.refreshMapData(force: true) } }.font(.app(.caption))
            }
        } else if layer == .radar, let frame = radarFrame {
            HStack {
                Button { playing.toggle() } label: { Image(systemName: playing ? "pause.fill" : "play.fill") }
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Fmt.dayTime(frame.time))\(frame.time > Date() ? String(localized: " (previsione)") : "")").font(.app(.caption, .semibold))
                    Slider(value: Binding(get: { Double(model.radarFrames.firstIndex(of: frame) ?? 0) }, set: { radarIndex = $0.rounded() }),
                           in: 0...Double(max(model.radarFrames.count - 1, 1)), step: 1)
                }
            }
        } else if layer == .aurora {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "moon.stars.fill").foregroundStyle(.secondary)
                    Text("Ovale OVATION previsto per le \(Fmt.time(model.ovation?.value.forecastTime, in: .iceland)) · Kp \(Fmt.number(model.kp.flatMap { KpLookup.kp(at: Date(), in: $0.value) }, decimals: 1))")
                        .font(.app(.caption))
                    Spacer()
                }
                if let peak = icelandAuroraPeak {
                    Text(peak < 4
                         ? String(localized: "Sull'Islanda adesso il valore massimo è \(Int(peak.rounded())): troppo basso per essere colorato (la scala parte da 4). Il colore compare quando l'ovale si allarga verso sud.")
                         : String(localized: "Valore massimo sull'Islanda adesso: \(Int(peak.rounded()))."))
                        .font(.app(.caption2)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Highest OVATION value over Iceland right now (1° grid).
    private var icelandAuroraPeak: Double? {
        guard let ovation = model.ovation?.value else { return nil }
        var peak = 0.0
        for lat in stride(from: 63.0, through: 67.0, by: 0.5) {
            for lon in stride(from: -25.0, through: -13.0, by: 0.5) { peak = max(peak, ovation.interpolated(lat: lat, lon: lon)) }
        }
        return peak
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
        if showRoadInfo, let info = model.roadInfo?.value {
            for section in info.sections {
                // Lines show every section; closures also get a marker, visible at any zoom.
                if section.isClosed, let risk = section.risk, let center = section.center {
                    pois.append(PoiAnnotation(kind: .roadSection, key: "rs\(section.id)", coordinate: center.coordinate.clCoordinate,
                                              title: "\(section.label): \(section.name)", color: UIColor(risk.color)))
                }
                for hazard in section.hazards {
                    guard let at = hazard.at else { continue }
                    pois.append(PoiAnnotation(kind: .roadHazard, key: "rh\(section.id)|\(hazard.id)", coordinate: at.coordinate.clCoordinate,
                                              title: RoadCode.hazard(hazard.code).label, color: .systemOrange))
                }
            }
            poisKey += "roadinfo\(model.roadInfo?.date.timeIntervalSince1970 ?? 0)"
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
        // The place set in the app (the GPS position already has its blue dot).
        if !model.useCurrentLocation || model.location.coordinate == nil {
            let place = model.activePlace
            pois.append(PoiAnnotation(kind: .place, key: "place", coordinate: place.coordinate.clCoordinate,
                                      title: place.name, subtitle: String(localized: "Posizione impostata"), color: .systemRed))
            poisKey += "place\(place.name)\(model.placeKey)"
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
        if showRoadInfo, let info = model.roadInfo, let geometry = model.roadGeometry {
            // Over a weather layer the roads step back (thinner, translucent) so the colours read.
            let dimmed = layer != .none
            let key = "roads\(info.date.timeIntervalSince1970)-\(geometry.date.timeIntervalSince1970)-\(dimmed)"
            lines = Self.roadLines.lines(key: key, info: info.value, geometry: geometry.value, dimmed: dimmed) + lines
            linesKey = key + linesKey
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
        case .roadSection, .roadHazard:
            let id = String(poi.key.dropFirst(2).split(separator: "|").first ?? "")
            selectedSection = model.roadInfo?.value.sections.first { $0.id == id }
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
                Text(String(format: "%.2f°N %.2f°O", coordinate.lat, -coordinate.lon)).font(.app(.caption, .semibold))
                if let grid, grid.times.indices.contains(hour) {
                    Text("· \(Fmt.dayTime(grid.times[hour], in: .iceland))").font(.app(.caption)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            }
            if grid != nil, v(.temperature) != nil {
                HStack {
                    Metric(title: String(localized: "Temp."), value: Fmt.temp(v(.temperature)))
                    Metric(title: String(localized: "Vento"), value: Fmt.ms(v(.wind)), tint: Risk.wind(mean: v(.wind), gust: nil).color)
                    Metric(title: String(localized: "Raffiche"), value: Fmt.ms(v(.gust)), tint: Risk.wind(mean: nil, gust: v(.gust)).color)
                }
                HStack {
                    Metric(title: String(localized: "Pioggia"), value: Fmt.number(v(.precipitation), decimals: 1, unit: "mm/h"))
                    Metric(title: String(localized: "Neve"), value: Fmt.number(v(.snow), decimals: 1, unit: "cm/h"))
                    Metric(title: String(localized: "Nuvole"), value: Fmt.percent(v(.cloud)))
                }
            } else {
                Text("Fuori dalla griglia meteo dell'Islanda.").font(.app(.caption)).foregroundStyle(.secondary)
            }
            if let ovation = model.ovation?.value {
                Text("Aurora adesso: \(Fmt.percent(ovation.interpolated(lat: coordinate.lat, lon: coordinate.lon)))")
                    .font(.app(.caption)).foregroundStyle(.secondary)
            }
            if let nearest {
                Text("Stazione \(nearest.station.name) (\(Int(nearest.distance)) km): \(Fmt.ms(nearest.station.Vindhradi)) / raff. \(Fmt.ms(nearest.station.Vindhvida)), asfalto \(Fmt.temp(nearest.station.Veghiti))")
                    .font(.app(.caption2)).foregroundStyle(.secondary)
            }
            ForEach(warnings.prefix(2)) { warning in
                HStack { WarningBadge(color: warning.color); Text(warning.headline).font(.app(.caption2)) }
            }
        }
        .padding(12)
        .background(Theme.bg.opacity(0.94)).overlay(Rectangle().strokeBorder(Theme.hairline))
    }
}

/// Every road section as a line coloured by its surface condition (umferdin.is
/// categories): green passable, yellow icy patches or wet snow, orange slippery
/// or snowy, red difficult or extremely slippery, dark red dashed closed, grey
/// no winter service or unknown.
final class RoadLines {
    private var key = ""
    private var cached: [TitledPolyline] = []

    func lines(key: String, info: RoadInfo, geometry: RoadGeometry, dimmed: Bool) -> [TitledPolyline] {
        if key == self.key { return cached }
        var out: [TitledPolyline] = []
        // Worst on top: grey, green, then rising risk, closures last.
        let ordered = info.sections.sorted { Self.rank($0) < Self.rank($1) }
        for section in ordered {
            guard let parts = geometry.lines[section.id] else { continue }
            let style = Self.style(section)
            for part in parts where part.count >= 2 {
                let coords = part.map(\.clCoordinate)
                let line = TitledPolyline(coordinates: coords, count: coords.count)
                // Dimmed: good roads almost vanish, problems stay visible.
                let problem = section.isClosed || (section.risk ?? .ok) >= .caution
                line.strokeColor = dimmed ? style.color.withAlphaComponent(problem ? 0.85 : 0.35) : style.color
                line.width = dimmed ? (problem ? style.width * 0.8 : 1.2) : style.width
                line.dashed = section.isClosed
                line.sectionID = section.id
                out.append(line)
            }
        }
        self.key = key
        cached = out
        return out
    }

    static func rank(_ s: RoadInfo.Section) -> Int {
        if s.isClosed { return 5 }
        return (s.risk?.rawValue).map { $0 + 1 } ?? 0
    }

    static let closedColor = UIColor(red: 0.55, green: 0, blue: 0.08, alpha: 1)
    static func style(for risk: Risk?) -> UIColor {
        switch risk {
        case .ok: return UIColor(red: 0.13, green: 0.66, blue: 0.33, alpha: 0.9)
        case .caution: return UIColor(red: 0.98, green: 0.80, blue: 0.10, alpha: 1)
        case .warning: return UIColor(red: 0.98, green: 0.50, blue: 0.05, alpha: 1)
        case .danger: return UIColor(red: 0.90, green: 0.12, blue: 0.10, alpha: 1)
        case nil: return UIColor(white: 0.55, alpha: 0.8)
        }
    }

    static func style(_ s: RoadInfo.Section) -> (color: UIColor, width: CGFloat) {
        if s.isClosed { return (closedColor, 4) }
        switch s.risk {
        case .ok: return (style(for: .ok), 2.5)
        case .caution: return (style(for: .caution), 3)
        case .warning: return (style(for: .warning), 3.5)
        case .danger: return (style(for: .danger), 4)
        case nil: return (style(for: nil), 1.5)
        }
    }
}

/// Height of the map's bottom panel content (scrolls past 300 pt).
private struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
