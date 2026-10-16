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

                Section {
                    if recorder.isRecording {
                        LiveDrivePanel()
                    } else {
                        startPanel
                    }
                }

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
                    Text("Auto e chilometraggio")
                } footer: {
                    Text("Inserisci i km del contachilometri al ritiro dell'auto a noleggio: l'app li aggiorna a ogni percorso registrato. Limiti in Islanda: 90 km/h asfalto, 80 sterrato, 50 centri abitati.")
                }
                .onChange(of: recorder.settings) { _, _ in recorder.saveSettings() }

                historySection
            }
            .navigationTitle("Guida")
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if recorder.isRecording {
                        Button("Stop", role: .destructive) { confirmStop = true }
                    }
                }
            }
        }
    }

    private var startPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Registra il percorso in auto").font(.headline)
            Text("Traccia GPS, km percorsi, tempo di guida, velocità media e massima, dislivello, soste, consumo stimato e contachilometri. Funziona anche a schermo bloccato e mostra i dati sulla schermata di blocco e nella Dynamic Island.")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                recorder.start()
            } label: {
                Label("Inizia registrazione", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.red)
            if recorder.authorization == .denied || recorder.authorization == .restricted {
                Label("Posizione negata: abilitala in Impostazioni › Norður.", systemImage: "location.slash").font(.caption).foregroundStyle(.red)
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
                    Metric(title: "Totale", value: Fmt.number(store.totalKm, decimals: 1, unit: "km"), systemImage: "road.lanes")
                    Metric(title: "Alla guida", value: Fmt.duration(store.totalSeconds), systemImage: "clock")
                    Metric(title: "Percorsi", value: "\(store.drives.count)", systemImage: "list.number")
                }
                let perDay = DriveMath.kmPerDay(store.drives)
                if perDay.count > 1 {
                    Chart(perDay) { item in
                        BarMark(x: .value("Giorno", item.day, unit: .day), y: .value("km", item.km))
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
                        Text(drive.name).font(.subheadline.weight(.semibold))
                        Text("\(Fmt.dayTime(drive.start)) · \(Fmt.number(drive.stats.km, decimals: 1, unit: "km")) · \(Fmt.duration(drive.durationSeconds()))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                let removed = offsets.map { store.drives[$0] }
                removed.forEach { store.delete($0) }
            }
        } header: {
            Text("Storico percorsi")
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
                        Label(recorder.isPaused ? "In pausa" : "Registrazione in corso", systemImage: recorder.isPaused ? "pause.circle.fill" : "record.circle")
                            .foregroundStyle(recorder.isPaused ? Color.orange : Color.red)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if let acc = recorder.gpsAccuracy {
                            Text("GPS ±\(Int(acc)) m").font(.caption2).foregroundStyle(acc <= 15 ? Color.green : Color.orange)
                        }
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(Fmt.number(session.stats.km, decimals: 2)).font(.system(size: 52, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("km").font(.title3).foregroundStyle(.secondary)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("\(Int(recorder.speedKmh.rounded()))").font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(recorder.speedKmh > recorder.settings.speedLimit + 3 ? Color.red : Color.primary)
                            Text("km/h").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            Metric(title: "Tempo", value: Fmt.clock(elapsed), systemImage: "clock")
                            Metric(title: "Media", value: Fmt.number(session.stats.averageKmh(totalSeconds: elapsed), unit: "km/h"), systemImage: "speedometer")
                            Metric(title: "Max", value: Fmt.number(session.stats.maxKmh, unit: "km/h"), systemImage: "gauge.with.dots.needle.100percent")
                        }
                        GridRow {
                            Metric(title: "In movimento", value: Fmt.clock(session.stats.movingSeconds), systemImage: "car")
                            Metric(title: "Dislivello +", value: Fmt.number(session.stats.elevationGain, unit: "m"), systemImage: "arrow.up.right")
                            Metric(title: "Soste", value: "\(session.stats.stops)", systemImage: "parkingsign")
                        }
                        GridRow {
                            Metric(title: "Contachilometri", value: Fmt.number(session.odometerEnd, decimals: 1, unit: "km"), systemImage: "gauge.open.with.lines.needle.33percent")
                            Metric(title: "Carburante", value: Fmt.number(session.stats.fuelLitres(recorder.settings), decimals: 1, unit: "l"), systemImage: "fuelpump")
                            Metric(title: "Costo", value: Fmt.number(session.stats.fuelCost(recorder.settings), unit: "ISK"), systemImage: "creditcard")
                        }
                    }
                    if let latest = alerts.latest, Date().timeIntervalSince(latest.date) < 3600 {
                        AlertRow(event: latest)
                            .padding(8)
                            .background(latest.risk.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
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
                    LiveTrackMap(points: recorder.recentPoints)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    @ViewBuilder private var nearbyFuel: some View {
        if let here = recorder.session?.points.last?.coordinate, let stations = model.fuel?.value {
            let nearest = FuelStations.nearest(stations, to: here, kind: .fuel, limit: 1)
            if let first = nearest.first {
                Label("Distributore più vicino: \(first.station.name) a \(Fmt.number(first.km, decimals: 0, unit: "km"))", systemImage: "fuelpump.fill")
                    .font(.caption).foregroundStyle(.secondary)
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
                DriveTrackMap(points: DriveMath.downsample(session.points))
                    .frame(height: 280)
                    .listRowInsets(EdgeInsets())
                HStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { bucket in
                        HStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 2).fill(DriveTrackMap.color(bucket)).frame(width: 14, height: 5)
                            Text(["<30", "30–60", "60–80", "80–95", ">95"][bucket]).font(.caption2)
                        }
                    }
                }
            }

            Section("Riepilogo") {
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
                    LabeledContent("Oltre il limite", value: "\(Fmt.clock(s.speedingSeconds)) · max \(Int(s.speedingMaxKmh)) km/h")
                }
                if let start = session.odometerStart, let end = session.odometerEnd {
                    LabeledContent("Contachilometri", value: "\(Fmt.number(start, unit: "")) → \(Fmt.number(end, unit: "km"))")
                }
                LabeledContent("Carburante stimato", value: "\(Fmt.number(s.fuelLitres(recorder.settings), decimals: 1, unit: "l")) · \(Fmt.number(s.fuelCost(recorder.settings), unit: "ISK"))")
                LabeledContent("Inizio", value: Fmt.dayTime(session.start))
                if let end = session.end { LabeledContent("Fine", value: Fmt.dayTime(end)) }
            }

            if session.points.count > 10 {
                Section("Velocità e quota") {
                    SpeedAltitudeChart(points: DriveMath.downsample(session.points, maxPoints: 400))
                        .frame(height: 200)
                }
            }

            Section("Dettagli") {
                TextField("Nome", text: $name)
                TextField("Note", text: $notes, axis: .vertical)
                Button("Salva modifiche") {
                    var updated = session
                    updated.name = name
                    updated.notes = notes
                    store.updateMetadata(updated)
                }
            }

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
                Marker("Partenza", systemImage: "flag.fill", coordinate: first.coordinate.clCoordinate).tint(.green)
            }
            if let last = points.last, points.count > 1 {
                Marker("Arrivo", systemImage: "flag.checkered", coordinate: last.coordinate.clCoordinate).tint(.red)
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
                    AreaMark(x: .value("km", row.km), y: .value("Quota (scalata)", alt / max(maxAlt, 1) * maxSpeed))
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
