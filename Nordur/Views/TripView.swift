import SwiftUI
import MapKit

struct TripView: View {
    @Environment(AppModel.self) private var model
    @Environment(TripStore.self) private var trip
    @State private var creating = false
    @State private var showAccount = false
    /// Import from a GPX/KML file, and the GPX export of the trip.
    @State private var importing = false
    @State private var importFile: TripImportFile?
    @State private var importError: String?
    @State private var exportURL: URL?
    /// Days (everything on one page), stops (cards to open), or the route on a map.
    @AppStorage("trip.view") private var mode = "days"
    @State private var dayVisit: VisitDraft?
    @State private var dayAdd: DayAdd?
    @State private var pendingVisit: VisitDraft?
    @State private var mapStop: TripStop?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                Section {
                    ScreenHeader(title: String(localized: "Viaggio"), subtitle: trip.stops.isEmpty ? String(localized: "Itinerario") : String(localized: "\(trip.stops.count) tappe"), index: "05") {
                        HStack(spacing: 8) {
                            if !trip.stops.isEmpty { EditButton().font(.mono(11, .semibold)) }
                            HeaderButton(systemImage: "person", label: String(localized: "ACCOUNT")) { showAccount = true }
                            HeaderButton(systemImage: "plus") { creating = true }
                                .accessibilityLabel("Aggiungi tappa")
                                .accessibilityIdentifier("trip.add")
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))

                // The picture only for an empty trip: once planned, the days come first.
                if trip.stops.isEmpty {
                    Section {
                        HeroHeader(hero: .trip, eyebrow: String(localized: "Kirkjufell · Snæfellsnes"), title: String(localized: "Il tuo viaggio"),
                                   subtitle: String(localized: "Per ogni tappa: meteo, allerte, strade e aurora"), height: 150)
                            .heroRow()
                    }
                    .listSectionSeparator(.hidden)
                }

                if trip.stops.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("NESSUNA TAPPA").font(.display(28, .bold)).foregroundStyle(Theme.text)
                        Text("Per ogni tappa: meteo del giorno, allerte, mare e strade lungo il tragitto.")
                            .font(.app(.subheadline)).foregroundStyle(Theme.dim)
                        Button { creating = true } label: {
                            HStack {
                                Text("AGGIUNGI LA PRIMA TAPPA").font(.mono(12, .semibold)).tracking(0.8)
                                Spacer()
                                Text("+").font(.mono(16, .semibold))
                            }
                            .foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 12)
                    .listRowSeparator(.hidden)
                }
                if !trip.stops.isEmpty {
                    Section {
                        TripOverview()
                        HStack(spacing: 8) {
                            actionButton(String(localized: "TAPPA"), "plus") { creating = true }
                            actionButton(String(localized: "IMPORTA"), "square.and.arrow.down") { importing = true }
                            if let exportURL { ShareLink(item: exportURL) { actionLabel(String(localized: "ESPORTA"), "square.and.arrow.up") } }
                        }
                        .buttonStyle(.plain)
                        Picker("Vista", selection: $mode) {
                            Text("Giorni").tag("days")
                            Text("Tappe").tag("stops")
                            Text("Mappa").tag("map")
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("trip.mode")
                    }
                }
                if mode == "days" {
                    TripDaysSections(onEdit: { item in
                        dayVisit = VisitDraft(stop: item.stop, visit: item.visit, isNew: false)
                    }, onAdd: { dayAdd = $0 })
                } else if mode == "map", !trip.stops.isEmpty {
                    Section {
                        TripMap { mapStop = $0 }
                            .frame(height: 480)
                            .listRowInsets(EdgeInsets())
                    } footer: {
                        Text("Tocca un numero per aprire la tappa.")
                    }
                } else {
                ForEach(Array(trip.stops.enumerated()), id: \.element.id) { index, stop in
                    Section {
                        NavigationLink {
                            StopDetailView(stopID: stop.id, fallback: stop)
                        } label: {
                            StopCard(stop: stop, index: index)
                        }
                        .accessibilityIdentifier("trip.stop")
                        if let next = trip.next(after: stop) {
                            if next.transport == .car || next.transport == .bus {
                                NavigationLink {
                                    RouteForecastView(from: stop.place, to: next.place, departure: max(next.date, Date()))
                                } label: { LegLine(from: stop, to: next) }
                            } else {
                                LegLine(from: stop, to: next)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    // Each stop is its own section, so the offset is the stop index.
                    trip.delete(at: offsets)
                }
                }
                if trip.stops.isEmpty {
                    Section {
                        Button { importing = true } label: {
                            Label("Importa un viaggio da file GPX o KML", systemImage: "square.and.arrow.down")
                        }
                    } footer: {
                        Text("Crea tappe e attrazioni con Google My Maps, gpx.studio, Komoot o un altro programma ed esportale in GPX o KML.")
                    }
                }
            }
            .themedList()
            .onAppear {
                // During the trip the day view opens on today.
                let today = Calendar.iceland.startOfDay(for: Date())
                if mode == "days", trip.days.contains(where: { $0.date == today }) {
                    DispatchQueue.main.async { proxy.scrollTo(today, anchor: .top) }
                }
            }
            }
            .navigationDestination(item: $mapStop) { stop in StopDetailView(stopID: stop.id, fallback: stop) }
            .sheet(item: $dayVisit) { draft in VisitEditor(draft: draft) }
            .sheet(item: $dayAdd, onDismiss: {
                if let pending = pendingVisit {
                    pendingVisit = nil
                    dayVisit = pending
                }
            }) { add in
                AttractionPicker(stop: add.stop) { place, kind, minutes in
                    pendingVisit = VisitDraft(stop: add.stop, visit: .next(at: place, kind: kind, minutes: minutes, in: add.stop, on: add.day), isNew: true)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await model.refreshGlobal(force: true)
                await trip.loadForecasts()
            }
            .task(id: trip.stops.map { ([$0.place] + $0.visits.map(\.place)).map(\.coordinate.key).joined() }.joined()) {
                await trip.loadForecasts()
            }
            .sheet(isPresented: $showAccount) { AccountView() }
            .sheet(isPresented: $creating) {
                StopEditor(stop: nil)
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: TripImportFile.types) { result in
                do {
                    importFile = try TripImportFile.read(try result.get())
                } catch {
                    importError = error.localizedDescription
                }
            }
            .sheet(item: $importFile) { file in TripImportSheet(file: file) }
            .onChange(of: model.pendingTripImport?.id) {
                if let file = model.pendingTripImport {
                    importFile = file
                    model.pendingTripImport = nil
                }
            }
            .onAppear {
                if let file = model.pendingTripImport {
                    importFile = file
                    model.pendingTripImport = nil
                }
            }
            .task(id: trip.stops) { exportURL = trip.exportGPX() }
            .alert("Importazione non riuscita", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(importError ?? "") }
        }
    }

    private func actionButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { actionLabel(title, symbol) }
    }

    private func actionLabel(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.mono(10.5, .semibold))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity).frame(height: 36)
            .overlay(Rectangle().strokeBorder(Theme.hairline))
    }
}

struct StopSummary: View {
    @Environment(AppModel.self) private var model
    @Environment(TripStore.self) private var trip
    let stop: TripStop
    var showsHeader = true

    var body: some View {
        let forecast = trip.forecast(for: stop)
        let day = forecast?.day(for: stop.date)
        let zone = forecast?.timeZone ?? .iceland
        let warnings = model.warnings(at: stop.place.coordinate, from: stop.date.addingTimeInterval(-12 * 3600), to: stop.endDate)

        VStack(alignment: .leading, spacing: 8) {
            if showsHeader {
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
        if days < 0 { return String(localized: "Tappa passata.") }
        return String(localized: "Previsioni disponibili circa 10 giorni prima (mancano \(days) giorni).")
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
                    DirectionsMenu(to: to.place.coordinate, from: from.place.coordinate) { Text("Indicazioni") }
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
    @State private var photo: PlacePhoto?
    @State private var confirmDelete = false
    @State private var shiftLater = true

    init(stop: TripStop?) {
        original = stop
        _place = State(initialValue: stop?.place)
        _date = State(initialValue: stop?.date ?? Date())
        _nights = State(initialValue: stop?.nights ?? 1)
        _transport = State(initialValue: stop?.transport ?? .car)
        _notes = State(initialValue: stop?.notes ?? "")
    }

    /// The stop before this one (by date), for the distance line.
    private var previous: TripStop? {
        trip.stops.filter { $0.id != original?.id && $0.date < date }.max { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    hero
                    VStack(alignment: .leading, spacing: 26) {
                        step("01", String(localized: "Luogo")) { placeCard }
                        step("02", String(localized: "Quando")) { whenCard }
                        step("03", String(localized: "Come ci arrivi")) { transportGrid }
                        step("04", String(localized: "Note")) { notesBox }
                        saveButton
                        if original != nil {
                            Button(role: .destructive) { confirmDelete = true } label: {
                                Label("Elimina tappa", systemImage: "trash").font(.mono(11, .semibold))
                                    .frame(maxWidth: .infinity).frame(height: 44)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.danger)
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(original == nil ? String(localized: "Nuova tappa") : String(localized: "Modifica tappa"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            }
            .sheet(isPresented: $pickingPlace) {
                PlacePicker(allowCurrentLocation: false) { choice in
                    if case .place(let picked) = choice { place = picked }
                }
            }
            .confirmationDialog(String(localized: "Eliminare questa tappa?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Elimina tappa", role: .destructive) {
                    if let original { trip.delete(original) }
                    dismiss()
                }
            }
            .task(id: place?.coordinate.key) {
                photo = nil
                if let place { photo = await PlacePhotoService.shared.photo(for: place) }
            }
        }
    }

    // MARK: Parts

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            if let photo {
                RemoteImage(url: photo.imageURL).frame(height: 200).frame(maxWidth: .infinity).clipped()
            } else {
                HeroPhoto(hero: .trip).frame(height: 200)
            }
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text((place == nil ? String(localized: "Nuova tappa") : String(localized: "Tappa")).uppercased())
                    .font(.mono(10, .semibold)).tracking(0.9).foregroundStyle(.white.opacity(0.85))
                Text(place?.name ?? String(localized: "Dove vai?"))
                    .font(.display(40, .bold)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.6)
                if let photo {
                    Text(photo.credit).font(.mono(8)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 14)
        }
        .frame(height: 200)
        .clipped()
    }

    private func step<Content: View>(_ index: String, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(index: index, title: title)
            content()
        }
    }

    private var placeCard: some View {
        Button { pickingPlace = true } label: { placeCardLabel }
            .buttonStyle(.plain)
            .accessibilityIdentifier("stop.place")
    }

    private var placeCardLabel: some View {
        Group {
            HStack(spacing: 14) {
                Image(systemName: place == nil ? "magnifyingglass" : "mappin.and.ellipse")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 46, height: 46)
                    .background(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(place?.name ?? String(localized: "Cerca una città, un hotel, una cascata…"))
                        .font(.sans(16, .semibold)).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
                    if let place {
                        Text([place.subtitle, Fmt.coordinate(place.coordinate)].compactMap { $0 }.joined(separator: " · "))
                            .font(.mono(10)).foregroundStyle(Theme.dim)
                        if let previous {
                            Text(String(localized: "\(Int(Geo.distanceKm(previous.place.coordinate, place.coordinate).rounded())) km in linea d'aria da \(previous.place.name)"))
                                .font(.mono(10)).foregroundStyle(Theme.faint)
                        }
                    } else {
                        Text("Luoghi principali d'Islanda o qualsiasi indirizzo").font(.app(.caption)).foregroundStyle(Theme.dim)
                    }
                }
                Spacer(minLength: 0)
                Text(place == nil ? String(localized: "SCEGLI") : String(localized: "CAMBIA")).font(.mono(10, .semibold)).foregroundStyle(Theme.accent)
            }
            .padding(12)
            .overlay(Rectangle().strokeBorder(place == nil ? Theme.accent : Theme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
    }

    private var whenCard: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Arrivo", systemImage: "calendar").font(.app(.subheadline, .medium)).foregroundStyle(Theme.text)
                Spacer()
                DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .environment(\.locale, Fmt.italian)
            }
            .padding(12)
            Rule()
            HStack(spacing: 12) {
                Label("Notti", systemImage: "moon.zzz.fill").font(.app(.subheadline, .medium)).foregroundStyle(Theme.text)
                Spacer()
                squareButton("minus") { nights = max(0, nights - 1) }.disabled(nights == 0)
                Text("\(nights)").font(.metric(30, .semibold)).foregroundStyle(Theme.text).frame(minWidth: 40)
                squareButton("plus") { nights = min(30, nights + 1) }.disabled(nights == 30)
            }
            .padding(12)
            Rule()
            HStack {
                Text(nights == 0 ? String(localized: "SOLO DI PASSAGGIO") : String(localized: "PARTENZA"))
                    .font(.mono(9.5)).foregroundStyle(Theme.faint)
                Spacer()
                if nights > 0 {
                    Text(Fmt.day(Calendar.current.date(byAdding: .day, value: nights, to: date) ?? date))
                        .font(.mono(11, .semibold)).foregroundStyle(Theme.text)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            if let original, dayShift != 0 {
                Rule()
                VStack(alignment: .leading, spacing: 8) {
                    if !original.visits.isEmpty {
                        let shift = (dayShift > 0 ? "+" : "") + String(dayShift)
                        Label(String(localized: "Le attrazioni della tappa si spostano con lei (\(shift) g)"),
                              systemImage: "calendar.badge.clock")
                            .font(.app(.caption)).foregroundStyle(Theme.dim)
                    }
                    if laterStops > 0 {
                        Toggle(isOn: $shiftLater) {
                            Text(String(localized: "Sposta anche le \(laterStops) tappe successive"))
                                .font(.app(.subheadline, .medium)).foregroundStyle(Theme.text)
                        }
                        .tint(Theme.accent)
                    }
                }
                .padding(12)
            }
        }
        .overlay(Rectangle().strokeBorder(Theme.hairline))
    }

    /// Days the arrival moves by, when editing a stop.
    private var dayShift: Int {
        guard let original else { return 0 }
        return TripStore.dayShift(from: original.date, to: date)
    }

    private var laterStops: Int {
        guard let original else { return 0 }
        return trip.stops.filter { $0.id != original.id && $0.date > original.date }.count
    }

    private func squareButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .bold))
                .frame(width: 38, height: 38)
                .overlay(Rectangle().strokeBorder(Theme.rule))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.text)
    }

    private var transportGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
            ForEach(Transport.allCases) { t in
                let selected = transport == t
                Button { transport = t } label: {
                    VStack(spacing: 6) {
                        Image(systemName: t.symbol).font(.system(size: 22, weight: .semibold))
                        Text(t.label).font(.mono(9.5, .semibold)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .padding(.horizontal, 4)
                    .foregroundStyle(selected ? Theme.onAccent : Theme.text)
                    .background(selected ? Theme.accent : Color.clear)
                    .overlay(Rectangle().strokeBorder(selected ? Color.clear : Theme.hairline))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var notesBox: some View {
        TextField("Prenotazioni, orari, telefono alloggio…", text: $notes, axis: .vertical)
            .lineLimit(3...8)
            .font(.app(.subheadline))
            .padding(12)
            .overlay(Rectangle().strokeBorder(Theme.hairline))
    }

    private var saveButton: some View {
        saveButtonBody.accessibilityIdentifier("stop.save")
    }

    private var saveButtonBody: some View {
        Button { save() } label: {
            HStack {
                Text(original == nil ? String(localized: "AGGIUNGI TAPPA") : String(localized: "SALVA MODIFICHE"))
                    .font(.mono(13, .semibold)).tracking(1)
                Spacer()
                Image(systemName: "arrow.right").font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 16).frame(height: 52)
            .background(place == nil ? Theme.faint : Theme.accent)
        }
        .buttonStyle(.plain)
        .disabled(place == nil)
    }

    private func save() {
        guard let place else { return }
        // The stored version: its attractions may have changed since the editor opened.
        var stop = original.flatMap { o in trip.stops.first { $0.id == o.id } } ?? original ?? TripStop(place: place, date: date)
        stop.place = place
        stop.date = date
        stop.nights = nights
        stop.transport = transport
        stop.notes = notes
        trip.upsert(stop, shiftingLater: shiftLater && laterStops > 0)
        dismiss()
    }
}
