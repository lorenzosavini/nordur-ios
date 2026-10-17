import SwiftUI
import MapKit
import Charts

/// GPS trip recorder: live panel, mileage settings and history of recorded drives.
struct DriveView: View {
    @Environment(AppModel.self) private var model
    @Environment(DriveRecorder.self) private var recorder
    @Environment(DriveStore.self) private var store
    @Environment(AlertCenter.self) private var alerts
    @State private var confirmStop = false
    @State private var lastFinished: DriveSession?
    @State private var planning = false

    var body: some View {
        @Bindable var recorder = recorder
        NavigationStack {
            List {
                Section {
                    ScreenHeader(title: String(localized: "Guida"), subtitle: recorder.isRecording ? String(localized: "Registrazione in corso") : String(localized: "Percorsi e strade"), index: "04") {
                        if recorder.isRecording {
                            Button { confirmStop = true } label: {
                                Text("■ STOP").font(.mono(11, .semibold)).tracking(0.8).foregroundStyle(.white)
                                    .padding(.horizontal, 12).frame(height: 34)
                                    .background(Theme.danger, in: Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            AppearanceButton()
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))

                if let recovered = recorder.recoverable {
                    Section {
                        Label("Una registrazione del \(Fmt.dayTime(recovered.start)) si è interrotta (\(Fmt.number(recovered.stats.km, decimals: 1, unit: "km"))).", systemImage: "exclamationmark.arrow.circlepath")
                        HStack {
                            Button("Riprendi") { recorder.resumeRecovered() }.buttonStyle(.borderedProminent)
                            Button("Salva") { recorder.saveRecovered() }.buttonStyle(.bordered)
                            Button("Scarta", role: .destructive) { recorder.discardRecovered() }.buttonStyle(.bordered)
                        }
                    }
                }

                // CI screenshots show the road watch first (it is below the fold otherwise).
                if UserDefaults.standard.bool(forKey: "ciAutoDrive") { RoadAheadSection() }

                Section {
                    if recorder.isRecording {
                        LiveDrivePanel()
                    } else {
                        startPanel
                    }
                }

                if !UserDefaults.standard.bool(forKey: "ciAutoDrive") { RoadAheadSection() }

                Section {
                    Button {
                        planning = true
                    } label: {
                        Label("Meteo e strade lungo un percorso", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
                    }
                }

                Section {
                    HStack {
                        Text("Contachilometri auto")
                        Spacer()
                        TextField("km", value: $recorder.settings.odometer, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                    }
                    Stepper("Consumo \(Fmt.number(recorder.settings.consumption, decimals: 1)) l/100 km",
                            value: $recorder.settings.consumption, in: 2...25, step: 0.5)
                    HStack {
                        Text("Prezzo carburante (ISK/l)")
                        Spacer()
                        TextField("ISK", value: $recorder.settings.fuelPrice, format: .number.precision(.fractionLength(0)))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                    Stepper("Limite velocità \(Int(recorder.settings.speedLimit)) km/h", value: $recorder.settings.speedLimit, in: 50...130, step: 10)
                    Toggle("Avviso se superi il limite", isOn: $recorder.settings.speedAlerts)
                    Toggle("Avvisi vocali", isOn: $recorder.settings.spokenAlerts)
                } header: {
                    Text("Auto e chilometraggio").eyebrow().pinnedHeader()
                } footer: {
                    Text("Inserisci i km al ritiro dell'auto: si aggiornano a ogni percorso. Limiti: 90 km/h asfalto, 80 sterrato, 50 centri abitati.")
                }
                .onChange(of: recorder.settings) { _, _ in recorder.saveSettings() }

                historySection
            }
            .themedList()
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("Terminare la registrazione?", isPresented: $confirmStop, titleVisibility: .visible) {
                Button("Termina e salva") { lastFinished = recorder.stop() }
                Button("Scarta percorso", role: .destructive) { recorder.discard() }
                Button("Continua", role: .cancel) {}
            }
            .sheet(item: $lastFinished) { finished in
                NavigationStack { DriveDetailView(drive: finished) }
            }
            .sheet(isPresented: $planning) {
                NavigationStack { RoutePlannerSheet() }
            }
        }
    }

    private var startPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("REGISTRA IL PERCORSO").font(.display(26, .bold))
            Text("GPS, km, tempi, velocità, dislivello e consumi. Continua a schermo bloccato.")
                .font(.app(.caption)).foregroundStyle(.secondary)
            Button {
                recorder.start()
            } label: {
                HStack(spacing: 10) {
                    Circle().fill(.white).frame(width: 10, height: 10)
                    Text("AVVIA REGISTRAZIONE").font(.mono(13, .semibold)).tracking(1)
                    Spacer()
                    Text("→").font(.mono(15, .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Theme.accent)
            }
            .buttonStyle(.plain)
            if recorder.authorization == .denied || recorder.authorization == .restricted {
                Label("Accesso alla posizione negato: attivalo in Impostazioni › Norður.", systemImage: "location.slash").font(.app(.caption)).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var historySection: some View {
        Section {
            if store.drives.isEmpty {
                Text("Nessun percorso registrato.").foregroundStyle(.secondary)
            } else {
                HStack {
                    Metric(title: String(localized: "Totale"), value: Fmt.number(store.totalKm, decimals: 1, unit: "km"), systemImage: "road.lanes")
                    Metric(title: String(localized: "Alla guida"), value: Fmt.duration(store.totalSeconds), systemImage: "clock")
                    Metric(title: String(localized: "Percorsi"), value: "\(store.drives.count)", systemImage: "list.number")
                }
                let perDay = DriveMath.kmPerDay(store.drives)
                if perDay.count > 1 {
                    Chart(perDay) { item in
                        BarMark(x: .value(String(localized: "Giorno"), item.day, unit: .day), y: .value("km", item.km))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(height: 120)
                }
            }
            ForEach(store.drives) { drive in
                NavigationLink {
                    DriveDetailView(drive: drive)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(drive.name).font(.app(.subheadline, .semibold))
                        Text("\(Fmt.dayTime(drive.start)) · \(Fmt.number(drive.stats.km, decimals: 1, unit: "km")) · \(Fmt.duration(drive.durationSeconds()))")
                            .font(.app(.caption)).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                let removed = offsets.map { store.drives[$0] }
                removed.forEach { store.delete($0) }
            }
        } header: {
            Text("Storico percorsi").eyebrow().pinnedHeader()
        }
    }
}

/// Big live numbers while recording.
struct LiveDrivePanel: View {
    @Environment(DriveRecorder.self) private var recorder
    @Environment(AlertCenter.self) private var alerts
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let session = recorder.session {
                let elapsed = session.durationSeconds()
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(recorder.isPaused ? Theme.warning : Theme.danger).frame(width: 8, height: 8)
                            Text(recorder.isPaused ? String(localized: "In pausa") : String(localized: "Registrazione")).eyebrow(recorder.isPaused ? Theme.warning : Theme.danger)
                        }
                        Spacer()
                        if let acc = recorder.gpsAccuracy {
                            Text("GPS ±\(Int(acc)) m").font(.metric(11)).foregroundStyle(acc <= 15 ? Theme.ok : Theme.warning)
                        }
                    }
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Distanza").eyebrow()
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(Fmt.number(session.stats.km, decimals: session.stats.km < 100 ? 2 : 1))
                                    .font(.metric(54, .bold)).foregroundStyle(Theme.text)
                                Text("km").font(.sans(17, .medium)).foregroundStyle(Theme.dim)
                            }
                            Text("Tempo \(Fmt.clock(elapsed))").font(.metric(14)).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        let speeding = recorder.speedKmh > recorder.settings.speedLimit + 3
                        ArcGauge(value: recorder.speedKmh / 130, color: speeding ? Theme.danger : Theme.accent,
                                 lineWidth: 8, label: "\(Int(recorder.speedKmh.rounded()))", caption: "KM/H")
                            .frame(width: 104, height: 104)
                    }
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            Metric(title: String(localized: "Velocità max"), value: Fmt.number(session.stats.maxKmh, unit: "km/h"), systemImage: "gauge.with.dots.needle.100percent")
                            Metric(title: String(localized: "drive.average", defaultValue: "Media"), value: Fmt.number(session.stats.averageKmh(totalSeconds: elapsed), unit: "km/h"), systemImage: "speedometer")
                            Metric(title: String(localized: "Quota"), value: Fmt.number(session.points.last?.alt, unit: "m"), systemImage: "mountain.2")
                        }
                        GridRow {
                            Metric(title: String(localized: "In marcia"), value: Fmt.clock(session.stats.movingSeconds), systemImage: "car")
                            Metric(title: String(localized: "Salita"), value: Fmt.number(session.stats.elevationGain, unit: "m"), systemImage: "arrow.up.right")
                            Metric(title: String(localized: "Soste"), value: "\(session.stats.stops)", systemImage: "parkingsign")
                        }
                        GridRow {
                            Metric(title: String(localized: "Km auto"), value: Fmt.number(session.odometerEnd, decimals: 0), systemImage: "gauge.open.with.lines.needle.33percent")
                            Metric(title: String(localized: "Litri"), value: Fmt.number(session.stats.fuelLitres(recorder.settings), decimals: 1, unit: "l"), systemImage: "fuelpump")
                            Metric(title: String(localized: "Costo"), value: Fmt.number(session.stats.fuelCost(recorder.settings), unit: String(localized: "ISK")), systemImage: "creditcard")
                        }
                    }
                    if let latest = alerts.latest, Date().timeIntervalSince(latest.date) < 3600 {
                        AlertRow(event: latest)
                            .padding(8)
                            .background(latest.risk.color.opacity(0.12), in: Rectangle())
                    }
                    nearbyFuel
                    HStack {
                        if recorder.isPaused {
                            Button { recorder.resume() } label: { Label("Riprendi", systemImage: "play.fill").frame(maxWidth: .infinity) }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button { recorder.pause() } label: { Label("Pausa", systemImage: "pause.fill").frame(maxWidth: .infinity) }
                                .buttonStyle(.bordered)
                        }
                    }
                    .controlSize(.large)
                    ExpandableMap(height: 220, title: String(localized: "Registrazione")) {
                        LiveTrackMap(points: recorder.recentPoints)
                    }
                }
            }
        }
    }

    @ViewBuilder private var nearbyFuel: some View {
        if let here = recorder.session?.points.last?.coordinate, let stations = model.fuel?.value {
            let nearest = FuelStations.nearest(stations, to: here, kind: .fuel, limit: 1)
            if let first = nearest.first {
                Label("Distributore più vicino: \(first.station.name) a \(Fmt.number(first.km, decimals: first.km < 10 ? 1 : 0, unit: "km"))", systemImage: "fuelpump.fill")
                    .font(.app(.caption)).foregroundStyle(.secondary)
            }
        }
    }
}

struct LiveTrackMap: View {
    let points: [TrackPoint]
    @State private var position: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            if points.count >= 2 {
                MapPolyline(coordinates: points.map(\.coordinate.clCoordinate))
                    .stroke(.red, lineWidth: 4)
            }
        }
        .mapControls { MapUserLocationButton() }
    }
}

struct DriveDetailView: View {
    @Environment(DriveStore.self) private var store
    @Environment(DriveRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    let drive: DriveSession
    @State private var full: DriveSession?
    @State private var name = ""
    @State private var notes = ""
    @State private var gpxURL: URL?

    private var session: DriveSession { full ?? drive }

    var body: some View {
        List {
            Section {
                ExpandableMap(height: 280, title: session.name) {
                    DriveTrackMap(points: DriveMath.downsample(session.points))
                }
                .listRowInsets(EdgeInsets())
                HStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { bucket in
                        HStack(spacing: 3) {
                            Rectangle().fill(DriveTrackMap.color(bucket)).frame(width: 14, height: 5)
                            Text(["<30", "30–60", "60–80", "80–95", ">95"][bucket]).font(.app(.caption2))
                        }
                    }
                }
            }

            Section {
                let s = session.stats
                let total = session.durationSeconds()
                LabeledContent("Distanza", value: Fmt.number(s.km, decimals: 2, unit: "km"))
                LabeledContent("Durata totale", value: Fmt.clock(total))
                LabeledContent("In movimento", value: Fmt.clock(s.movingSeconds))
                LabeledContent("Velocità media", value: Fmt.number(s.averageKmh(totalSeconds: total), decimals: 1, unit: "km/h"))
                LabeledContent("Media in movimento", value: Fmt.number(s.movingAverageKmh, decimals: 1, unit: "km/h"))
                LabeledContent("Velocità massima", value: Fmt.number(s.maxKmh, unit: "km/h"))
                LabeledContent("Dislivello", value: "+\(Fmt.number(s.elevationGain, unit: "m")) / −\(Fmt.number(s.elevationLoss, unit: "m"))")
                if let minA = s.minAltitude, let maxA = s.maxAltitude {
                    LabeledContent("Quota", value: "\(Int(minA))–\(Int(maxA)) m")
                }
                LabeledContent("Soste (>2 min)", value: "\(s.stops)")
                if s.speedingSeconds > 0 {
                    LabeledContent("Oltre il limite", value: String(localized: "\(Fmt.clock(s.speedingSeconds)) · max \(Int(s.speedingMaxKmh)) km/h"))
                }
                if let start = session.odometerStart, let end = session.odometerEnd {
                    LabeledContent("Contachilometri", value: "\(Fmt.number(start, unit: "")) → \(Fmt.number(end, unit: "km"))")
                }
                LabeledContent("Carburante stimato", value: "\(Fmt.number(s.fuelLitres(recorder.settings), decimals: 1, unit: "l")) · \(Fmt.number(s.fuelCost(recorder.settings), unit: "ISK"))")
                LabeledContent("Inizio", value: Fmt.dayTime(session.start))
                if let end = session.end { LabeledContent("Fine", value: Fmt.dayTime(end)) }
            } header: { Text("Riepilogo").pinnedHeader() }

            if session.points.count > 10 {
                Section {
                    SpeedAltitudeChart(points: DriveMath.downsample(session.points, maxPoints: 400))
                        .frame(height: 200)
                } header: { Text("Velocità e quota").pinnedHeader() }
            }

            Section {
                TextField("Nome", text: $name)
                TextField("Note", text: $notes, axis: .vertical)
                Button("Salva modifiche") {
                    var updated = session
                    updated.name = name
                    updated.notes = notes
                    store.updateMetadata(updated)
                }
            } header: { Text("Dettagli").pinnedHeader() }

            Section {
                if let gpxURL {
                    ShareLink(item: gpxURL) { Label("Esporta GPX", systemImage: "square.and.arrow.up") }
                }
                Button("Elimina percorso", role: .destructive) {
                    store.delete(session)
                    dismiss()
                }
            }
        }
        .themedList()
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            full = store.load(drive.id) ?? drive
            name = session.name
            notes = session.notes
            gpxURL = store.exportGPX(session)
        }
    }
}

struct DriveTrackMap: View {
    let points: [TrackPoint]

    static func color(_ bucket: Int) -> Color {
        switch bucket {
        case 0: return .blue
        case 1: return .teal
        case 2: return .green
        case 3: return .orange
        default: return .red
        }
    }

    var body: some View {
        let runs = DriveMath.speedRuns(points)
        Map(initialPosition: .automatic) {
            ForEach(Array(runs.enumerated()), id: \.offset) { item in
                if item.element.points.count >= 2 {
                    MapPolyline(coordinates: item.element.points.map(\.coordinate.clCoordinate))
                        .stroke(Self.color(item.element.bucket), lineWidth: 4)
                }
            }
            if let first = points.first {
                Marker(String(localized: "Partenza"), systemImage: "flag.fill", coordinate: first.coordinate.clCoordinate).tint(.green)
            }
            if let last = points.last, points.count > 1 {
                Marker(String(localized: "Arrivo"), systemImage: "flag.checkered", coordinate: last.coordinate.clCoordinate).tint(.red)
            }
        }
    }
}

struct SpeedAltitudeChart: View {
    let points: [TrackPoint]

    private struct Row: Identifiable {
        let id: Int
        let km: Double
        let speed: Double
        let altitude: Double?
    }

    private var rows: [Row] {
        var km = 0.0
        var result: [Row] = []
        for (i, p) in points.enumerated() {
            if i > 0 { km += Geo.distanceKm(points[i - 1].coordinate, p.coordinate) }
            result.append(Row(id: i, km: km, speed: p.kmh, altitude: p.alt))
        }
        return result
    }

    var body: some View {
        let data = rows
        let maxAlt = data.compactMap(\.altitude).max() ?? 1
        let maxSpeed = max(data.map(\.speed).max() ?? 1, 1)
        Chart {
            ForEach(data) { row in
                if let alt = row.altitude {
                    AreaMark(x: .value("km", row.km), y: .value(String(localized: "Quota (scalata)"), alt / max(maxAlt, 1) * maxSpeed))
                        .foregroundStyle(.brown.opacity(0.2))
                }
                LineMark(x: .value("km", row.km), y: .value("km/h", row.speed))
                    .foregroundStyle(.blue)
            }
        }
        .chartXAxisLabel("km")
        .chartYAxisLabel("km/h")
    }
}
