import SwiftUI
import MapKit

struct TripView: View {
    @Environment(AppModel.self) private var model
    @Environment(TripStore.self) private var trip
    @State private var editing: TripStop?
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScreenHeader(title: "Viaggio", subtitle: trip.stops.isEmpty ? "Itinerario" : "\(trip.stops.count) tappe") {
                        HStack(spacing: 8) {
                            if !trip.stops.isEmpty { EditButton().font(.geist(15, .medium)) }
                            HeaderButton(systemImage: "plus") { creating = true }
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))

                if trip.stops.isEmpty {
                    ContentUnavailableView {
                        Label("Nessuna tappa", systemImage: "map")
                    } description: {
                        Text("Per ogni tappa: meteo del giorno, allerte, mare e strade lungo il tragitto.")
                    } actions: {
                        Button("Aggiungi la prima tappa") { creating = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
                ForEach(trip.stops) { stop in
                    Section {
                        StopSummary(stop: stop)
                            .contentShape(Rectangle())
                            .onTapGesture { editing = stop }
                        if let next = trip.next(after: stop) {
                            LegSummary(from: stop, to: next)
                        }
                    }
                }
                .onDelete { offsets in
                    // Each stop is its own section, so the offset is the stop index.
                    trip.delete(at: offsets)
                }
            }
            .themedList()
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await model.refreshGlobal(force: true)
                await trip.loadForecasts()
            }
            .task(id: trip.stops.map(\.place.coordinate.key).joined()) {
                await trip.loadForecasts()
            }
            .sheet(isPresented: $creating) {
                StopEditor(stop: nil)
            }
            .sheet(item: $editing) { stop in
                StopEditor(stop: stop)
            }
        }
    }
}

struct StopSummary: View {
    @Environment(AppModel.self) private var model
    @Environment(TripStore.self) private var trip
    let stop: TripStop

    var body: some View {
        let forecast = trip.forecast(for: stop)
        let day = forecast?.day(for: stop.date)
        let zone = forecast?.timeZone ?? .iceland
        let warnings = model.warnings(at: stop.place.coordinate, from: stop.date.addingTimeInterval(-12 * 3600), to: stop.endDate)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: stop.transport.symbol).foregroundStyle(.indigo).frame(width: 26)
                VStack(alignment: .leading) {
                    Text(stop.place.name).font(.app(.headline))
                    Text("\(Fmt.day(stop.date, in: zone)) · \(stop.nights) \(stop.nights == 1 ? "notte" : "notti")")
                        .font(.app(.caption)).foregroundStyle(.secondary)
                }
                Spacer()
                if let day { RiskBadge(risk: day.overallRisk) }
            }

            if let day {
                let info = WeatherCode.describe(day.code)
                HStack(spacing: 12) {
                    Label(info.text, systemImage: info.symbol).symbolRenderingMode(.hierarchical)
                    Text("\(Fmt.temp(day.minTemp))/\(Fmt.temp(day.maxTemp))")
                    Text("raff. \(Fmt.ms(day.maxGust))").foregroundStyle(day.windRisk.color)
                }
                .font(.app(.caption))
                HStack(spacing: 12) {
                    if let snow = day.snowfall, snow > 0 { Label(Fmt.number(snow, decimals: 1, unit: "cm"), systemImage: "snowflake") }
                    Label(Fmt.number(day.precipitation, decimals: 1, unit: "mm"), systemImage: "drop.fill")
                    Label("\(Fmt.time(day.sunrise, in: zone))–\(Fmt.time(day.sunset, in: zone))", systemImage: "sun.horizon")
                }
                .font(.app(.caption2)).foregroundStyle(.secondary)
            } else if forecast != nil {
                Text(daysUntilText).font(.app(.caption)).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }

            if stop.transport.caresAboutSea, let marine = trip.marine(for: stop), marine.hasData {
                HStack {
                    Text("Mare ora: onde \(Fmt.number(marine.current?.wave_height, decimals: 1, unit: "m"))").font(.app(.caption))
                    RiskBadge(risk: marine.seaRisk)
                }
            }

            ForEach(warnings) { warning in
                HStack {
                    WarningBadge(color: warning.color)
                    Text(warning.headline).font(.app(.caption))
                }
            }

            if !stop.notes.isEmpty {
                Text(stop.notes).font(.app(.caption)).foregroundStyle(.secondary)
            }
        }
    }

    private var daysUntilText: String {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: stop.date).day ?? 0
        if days < 0 { return "Tappa passata." }
        return "Previsioni disponibili circa 16 giorni prima (mancano \(days) giorni)."
    }
}

/// The drive (or crossing) from one stop to the next.
struct LegSummary: View {
    @Environment(AppModel.self) private var model
    @Environment(TripStore.self) private var trip
    let from: TripStop
    let to: TripStop

    var body: some View {
        let distance = Geo.distanceKm(from.place.coordinate, to.place.coordinate)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: to.transport.symbol).foregroundStyle(.secondary)
                Text("Verso \(to.place.name) · ~\(Int(distance)) km in linea d'aria")
                    .font(.app(.caption, .semibold))
                Spacer()
                if to.transport == .car {
                    Button("Indicazioni") { openDirections() }
                        .font(.app(.caption))
                        .buttonStyle(.bordered)
                }
            }

            if to.transport == .car || to.transport == .bus {
                NavigationLink {
                    RouteForecastView(from: from.place, to: to.place, departure: max(to.date, Date()))
                } label: {
                    Label("Meteo, strade e webcam lungo il percorso", systemImage: "cloud.sun.rain")
                        .font(.app(.caption, .semibold))
                }
            }

            if to.transport == .car || to.transport == .bus, let network = model.roads?.value {
                let corridor = network.corridor(from: from.place.coordinate, to: to.place.coordinate)
                let worst = corridor.map { network.worstRisk(of: $0) }.max() ?? .ok
                let maxGust = corridor.compactMap(\.Vindhvida).max()
                let badSegments = corridor.flatMap { network.segments(for: $0) }.filter { ($0.risk ?? .ok) >= .caution }
                HStack {
                    Text("Ora lungo il tragitto:").font(.app(.caption))
                    RiskBadge(risk: worst)
                    Text("\(corridor.count) stazioni · raffica max \(Fmt.ms(maxGust))").font(.app(.caption2)).foregroundStyle(.secondary)
                }
                ForEach(uniqueSegments(badSegments).prefix(4)) { segment in
                    Text("• \(segment.name): \(segment.conditionItalian)")
                        .font(.app(.caption2))
                        .foregroundStyle((segment.risk ?? .ok).color)
                }
                if Calendar.current.isDateInToday(to.date) || Calendar.current.isDateInTomorrow(to.date) {
                    Text("Dati attuali: ricontrolla prima di partire.").font(.app(.caption2)).foregroundStyle(.secondary)
                }
            }

            if to.transport == .plane {
                Text("Stato del volo: Voli e traghetti.").font(.app(.caption2)).foregroundStyle(.secondary)
            }
            if to.transport == .ferry {
                Text("Con mare grosso i traghetti possono essere cancellati.").font(.app(.caption2)).foregroundStyle(.secondary)
            }
        }
    }

    private func uniqueSegments(_ segments: [RoadSegment]) -> [RoadSegment] {
        var seen = Set<Int>()
        return segments.filter { seen.insert($0.id).inserted }
    }

    private func openDirections() {
        let origin = MKMapItem(placemark: MKPlacemark(coordinate: from.place.coordinate.clCoordinate))
        origin.name = from.place.name
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: to.place.coordinate.clCoordinate))
        destination.name = to.place.name
        MKMapItem.openMaps(with: [origin, destination], launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

struct StopEditor: View {
    @Environment(TripStore.self) private var trip
    @Environment(\.dismiss) private var dismiss

    let original: TripStop?
    @State private var place: Place?
    @State private var date: Date
    @State private var nights: Int
    @State private var transport: Transport
    @State private var notes: String
    @State private var pickingPlace = false

    init(stop: TripStop?) {
        original = stop
        _place = State(initialValue: stop?.place)
        _date = State(initialValue: stop?.date ?? Date())
        _nights = State(initialValue: stop?.nights ?? 1)
        _transport = State(initialValue: stop?.transport ?? .car)
        _notes = State(initialValue: stop?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Luogo") {
                    Button {
                        pickingPlace = true
                    } label: {
                        HStack {
                            Text(place?.name ?? "Scegli un luogo…").foregroundStyle(place == nil ? Color.accentColor : Color.primary)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Quando") {
                    DatePicker("Arrivo", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    Stepper("Notti: \(nights)", value: $nights, in: 0...30)
                }
                Section("Come ci arrivi") {
                    Picker("Mezzo", selection: $transport) {
                        ForEach(Transport.allCases) { t in
                            Label(t.label, systemImage: t.symbol).tag(t)
                        }
                    }
                }
                Section("Note") {
                    TextField("Prenotazioni, orari, telefono alloggio…", text: $notes, axis: .vertical)
                }
                if let original {
                    Section {
                        Button("Elimina tappa", role: .destructive) {
                            trip.delete(original)
                            dismiss()
                        }
                    }
                }
            }
            .themedList()
            .navigationTitle(original == nil ? "Nuova tappa" : "Modifica tappa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }
                        .disabled(place == nil)
                }
            }
            .sheet(isPresented: $pickingPlace) {
                PlacePicker(allowCurrentLocation: false) { choice in
                    if case .place(let picked) = choice { place = picked }
                }
            }
        }
    }

    private func save() {
        guard let place else { return }
        var stop = original ?? TripStop(place: place, date: date)
        stop.place = place
        stop.date = date
        stop.nights = nights
        stop.transport = transport
        stop.notes = notes
        trip.upsert(stop)
        dismiss()
    }
}
