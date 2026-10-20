import SwiftUI

/// Hold an attraction: edit it, move it to another day or stop, or take it off.
struct VisitMenu: View {
    @Environment(TripStore.self) private var trip
    let stop: TripStop
    let visit: TripVisit
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) { Label("Modifica", systemImage: "pencil") }
        let otherDays = stop.days.filter { !Calendar.iceland.isDate($0, inSameDayAs: visit.date) }
        if !otherDays.isEmpty {
            Menu {
                ForEach(otherDays, id: \.self) { day in
                    Button(Fmt.day(day, in: .iceland)) {
                        trip.move(visit, from: stop.id, to: stop.id, day: day)
                        Haptics.result(true)
                    }
                }
            } label: { Label("Sposta a un altro giorno", systemImage: "calendar") }
        }
        let otherStops = trip.stops.filter { $0.id != stop.id }
        if !otherStops.isEmpty {
            Menu {
                ForEach(otherStops) { other in
                    Button("\(other.place.name) · \(Fmt.day(other.date, in: .iceland))") {
                        // Same day if the other stop covers it, otherwise the day you arrive there.
                        let day = other.includes(day: visit.date) ? visit.date : other.date
                        trip.move(visit, from: stop.id, to: other.id, day: day)
                        Haptics.result(true)
                    }
                }
            } label: { Label("Sposta in un'altra tappa", systemImage: "arrow.left.arrow.right") }
        }
        Button(role: .destructive) { trip.delete(visit, in: stop.id) } label: {
            Label("Togli dal viaggio", systemImage: "trash")
        }
    }
}

/// The nearest supermarket to where you sleep, and the way to all the shops around.
struct ShopsLine: View {
    @Environment(AppModel.self) private var model
    let stop: TripStop
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                KindIcon(name: Shop.Kind.supermarket.imageName, size: 44)
                if let market = Shops.nearest(model.shops?.value ?? [], to: stop.place.coordinate, kinds: [.supermarket], within: 80, limit: 1).first {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Spesa: \(market.shop.name), \(Fmt.number(market.km, decimals: market.km < 10 ? 1 : 0)) km"))
                            .font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        let status = market.shop.status()
                        Text(status.text).font(.app(.caption))
                            .foregroundStyle(status.open == true ? Theme.aurora : status.open == false ? Theme.danger : Theme.faint)
                    }
                } else {
                    Text(model.shops == nil ? String(localized: "Supermercati vicino alla tappa") : String(localized: "Nessun supermercato entro 80 km: fai scorta prima"))
                        .font(.app(.subheadline, .semibold)).foregroundStyle(model.shops == nil ? Theme.text : Theme.caution).lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.faint)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("trip.shops")
        .task { await model.loadShops() }
    }
}

/// One line per day: kilometres and driving time between the places of the day,
/// time spent visiting, and whether it all fits in the daylight.
struct DayPlanLine: View {
    @Environment(TripStore.self) private var trip
    let stop: TripStop
    let day: Date
    let visits: [TripVisit]
    var showsDate = true

    var body: some View {
        let plan = DayPlan(stop: stop, previous: trip.previous(before: stop), day: day, visits: visits)
        let sun = daylight
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                if showsDate {
                    Text(Fmt.day(day, in: .iceland).uppercased()).font(.mono(10, .semibold)).foregroundStyle(Theme.accent)
                } else {
                    Text(visits.isEmpty ? String(localized: "LUCE DEL GIORNO") : String(localized: "TEMPI DEL GIORNO")).font(.mono(10, .semibold)).foregroundStyle(Theme.accent)
                }
                Spacer()
                let others = stop.days.filter { !Calendar.iceland.isDate($0, inSameDayAs: day) }
                if !others.isEmpty {
                    Menu {
                        Section("Sposta la giornata") {
                            ForEach(others, id: \.self) { other in
                                let busy = stop.visits.contains { Calendar.iceland.isDate($0.date, inSameDayAs: other) }
                                Button(busy ? String(localized: "Scambia con \(Fmt.day(other, in: .iceland))")
                                            : String(localized: "Sposta a \(Fmt.day(other, in: .iceland))")) {
                                    trip.swapDays(day, other, in: stop.id)
                                    Haptics.result(true)
                                }
                            }
                        }
                    } label: {
                        Label("Sposta", systemImage: "arrow.up.arrow.down")
                            .font(.mono(10, .semibold)).foregroundStyle(Theme.accent)
                            .padding(.horizontal, 8).frame(height: 24)
                            .overlay(Rectangle().strokeBorder(Theme.hairline))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("trip.moveDay")
                }
            }
            if !visits.isEmpty {
                Text(String(localized: "\(visits.count) attrazioni · ~\(Int(plan.km.rounded())) km · ~\(Fmt.duration(plan.driveMinutes * 60)) di guida + \(Fmt.duration(plan.visitMinutes * 60)) di visita"))
                    .font(.app(.caption)).foregroundStyle(Theme.text)
            }
            if let sun {
                let late = visits.last.map { $0.end > sun.set } ?? false
                Label(late ? String(localized: "Luce \(Fmt.time(sun.rise, in: .iceland))–\(Fmt.time(sun.set, in: .iceland)): l'ultima visita finisce al buio")
                           : String(localized: "Luce \(Fmt.time(sun.rise, in: .iceland))–\(Fmt.time(sun.set, in: .iceland))"),
                      systemImage: late ? "moon.fill" : "sun.horizon.fill")
                    .font(.app(.caption2)).foregroundStyle(late ? Theme.caution : Theme.dim)
            }
        }
        .padding(.top, 2)
    }

    private var daylight: (rise: Date, set: Date)? {
        let c = visits.first?.place.coordinate ?? stop.place.coordinate
        if let d = trip.forecast(at: c)?.day(for: day), let rise = d.sunrise, let set = d.sunset { return (rise, set) }
        let start = Calendar.iceland.startOfDay(for: day)
        let crossing = Astro.crossings(of: -0.833, from: start, at: c)
        guard let up = crossing.up, let down = crossing.down, up < down else { return nil }
        return (up, down)
    }
}

/// Distances and times of a day of visits (road ≈ 1.3 × straight line, 70 km/h on average).
struct DayPlan {
    let km: Double
    let driveMinutes: Double
    let visitMinutes: Double

    init(stop: TripStop, previous: TripStop?, day: Date, visits: [TripVisit]) {
        // On the arrival day you leave from the previous stop; on the other days from this one.
        let start = Calendar.iceland.isDate(day, inSameDayAs: stop.date) && stop.transport == .car ? (previous?.place ?? stop.place) : stop.place
        let points = [start.coordinate] + visits.map(\.place.coordinate) + [stop.place.coordinate]
        let straight = zip(points, points.dropFirst()).reduce(0) { $0 + Geo.distanceKm($1.0, $1.1) }
        km = straight * 1.3
        driveMinutes = km / 70 * 60
        visitMinutes = Double(visits.reduce(0) { $0 + $1.minutes })
    }
}

struct VisitRow: View {
    @Environment(AppModel.self) private var model
    @Environment(TripStore.self) private var trip
    let visit: TripVisit

    var body: some View {
        let hour = trip.forecast(at: visit.place.coordinate)?.hours.min { abs($0.date.timeIntervalSince(visit.date)) < abs($1.date.timeIntervalSince(visit.date)) }
        let usable = hour.map { abs($0.date.timeIntervalSince(visit.date)) < 2 * 3600 } ?? false
        let dark = Astro.sunAltitude(visit.date, at: visit.place.coordinate) < -6
        let attraction = Attraction.named(visit.place.name)
        let roads = (model.roadInfo?.value.sections ?? [])
            .filter { ($0.risk ?? .ok) >= .warning && ($0.distanceKm(to: visit.place.coordinate) ?? .infinity) < 15 }

        HStack(alignment: .top, spacing: 12) {
            PlaceThumb(place: visit.place, kind: visit.kind ?? attraction?.kind ?? .landscape, size: 60)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(visit.place.name).font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text)
                    Spacer()
                    Text("\(Fmt.time(visit.date, in: .iceland))–\(Fmt.time(visit.end, in: .iceland))")
                        .font(.mono(10.5, .semibold)).foregroundStyle(Theme.dim)
                }
                HStack(spacing: 10) {
                    if let hour, usable {
                        let info = WeatherCode.describe(hour.code, isDay: hour.isDay)
                        Label(Fmt.temp(hour.temperature), systemImage: info.symbol).symbolRenderingMode(.multicolor)
                        Text(String(localized: "raff. \(Fmt.ms(hour.gust))")).foregroundStyle(hour.windRisk == .ok ? Theme.dim : hour.windRisk.color)
                    } else {
                        Text("Meteo disponibile circa 10 giorni prima").foregroundStyle(Theme.faint)
                    }
                    if dark { Label("buio", systemImage: "moon.fill").foregroundStyle(Theme.caution) }
                }
                .font(.app(.caption))
                if let hour, usable, (visit.kind ?? attraction?.kind) == .beach, (hour.gust ?? 0) >= 15 {
                    Label("Vento forte sulla spiaggia: onde pericolose, valuta di saltarla", systemImage: "exclamationmark.triangle.fill")
                        .font(.app(.caption2, .semibold)).foregroundStyle(Theme.danger)
                }
                if let road = roads.first {
                    Label(String(localized: "Strada vicina: \(road.name) · \(road.condition?.text ?? String(localized: "difficile"))"), systemImage: "road.lanes")
                        .font(.app(.caption2, .semibold)).foregroundStyle(Theme.danger)
                }
                if let caution = attraction?.caution {
                    Text(caution).font(.app(.caption2)).foregroundStyle(Theme.dim)
                }
                if !visit.notes.isEmpty {
                    Text(visit.notes).font(.app(.caption2)).foregroundStyle(Theme.dim)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Choosing an attraction

/// The attractions of Iceland, nearest to the stop first, with search; any
/// other place can be searched like a stop.
struct AttractionPicker: View {
    @Environment(AppModel.self) private var model
    let stop: TripStop
    let onPick: (Place, AttractionKind?, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var searchingOther = false

    var body: some View {
        // Near the stop: everything (the app's list and OpenStreetMap), the best-known first;
        // farther away: the main sights only, unless searching.
        let c = stop.place.coordinate
        let matches: (Attraction) -> Bool = { a in
            query.isEmpty || a.name.localizedCaseInsensitiveContains(query) || a.region.localizedCaseInsensitiveContains(query) || a.kind.label.localizedCaseInsensitiveContains(query)
        }
        let rank: (Attraction) -> Int = { $0.isTop ? 0 : $0.notable ? 1 : 2 }
        let near = model.spots.filter { Geo.distanceKm(c, $0.coordinate) <= 60 && matches($0) }
            .sorted { rank($0) != rank($1) ? rank($0) < rank($1) : Geo.distanceKm(c, $0.coordinate) < Geo.distanceKm(c, $1.coordinate) }
            .prefix(query.isEmpty ? 120 : 300)
        let far = (query.isEmpty ? Attraction.catalog : model.spots)
            .filter { Geo.distanceKm(c, $0.coordinate) > 60 && matches($0) }
            .sorted { Geo.distanceKm(c, $0.coordinate) < Geo.distanceKm(c, $1.coordinate) }
            .prefix(150)
        NavigationStack {
            List {
                Section {
                    Button { searchingOther = true } label: {
                        Label("Cerca un altro luogo", systemImage: "magnifyingglass")
                    }
                }
                let shops = Shops.nearest(model.shops?.value ?? [], to: stop.place.coordinate, kinds: [.supermarket, .convenience, .mall, .alcohol], within: 40)
                    .filter { query.isEmpty || $0.shop.name.localizedCaseInsensitiveContains(query) || "spesa supermercato".localizedCaseInsensitiveContains(query) }
                    .prefix(query.isEmpty ? 5 : 20)
                if !shops.isEmpty {
                    Section {
                        ForEach(Array(shops)) { item in
                            Button {
                                onPick(item.shop.place, .shop, 30)
                                dismiss()
                            } label: { ShopRow(shop: item.shop, km: item.km) }
                            .buttonStyle(.plain)
                        }
                    } header: { Text("Fare la spesa").pinnedHeader() }
                }
                if !near.isEmpty {
                    Section {
                        ForEach(Array(near)) { row($0) }
                    } header: { Text(String(localized: "Entro 60 km da \(stop.place.name)")).pinnedHeader() }
                }
                if !far.isEmpty {
                    Section {
                        ForEach(Array(far)) { row($0) }
                    } header: { Text("Resto dell'Islanda").pinnedHeader() }
                }
            }
            .themedList()
            .task { await model.loadShops() }
            .task { await model.loadSights() }
            .navigationTitle("Aggiungi attrazione")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: String(localized: "Cascata, spiaggia, ghiacciaio…"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
            .sheet(isPresented: $searchingOther) {
                PlacePicker(allowCurrentLocation: false) { choice in
                    if case .place(let place) = choice {
                        onPick(place, nil, 60)
                        dismiss()
                    }
                }
            }
        }
    }

    private func row(_ a: Attraction) -> some View {
        Button {
            onPick(a.place, a.kind, a.minutes)
            dismiss()
        } label: {
            SightRow(sight: a, km: Geo.distanceKm(stop.place.coordinate, a.coordinate))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("attraction.\(a.name)")
    }
}

// MARK: - Editing a visit

struct VisitDraft: Identifiable {
    let id = UUID()
    let stop: TripStop
    var visit: TripVisit
    let isNew: Bool
}

struct VisitEditor: View {
    @Environment(TripStore.self) private var trip
    @Environment(\.dismiss) private var dismiss
    let draft: VisitDraft
    @State private var stopID = UUID()
    @State private var day = Date()
    @State private var date = Date()
    @State private var minutes = 60
    @State private var notes = ""
    @State private var confirmDelete = false

    var body: some View {
        let visit = draft.visit
        let attraction = Attraction.named(visit.place.name)
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        PlaceHero(place: visit.place, kind: visit.kind ?? attraction?.kind, title: visit.place.name,
                                  eyebrow: (visit.kind ?? attraction?.kind)?.label ?? String(localized: "Luogo"))
                        Label(String(localized: "\(Int(Geo.distanceKm(target.place.coordinate, visit.place.coordinate).rounded())) km in linea d'aria da \(target.place.name)"),
                              systemImage: "location")
                            .font(.app(.subheadline)).foregroundStyle(Theme.dim)
                        if let caution = attraction?.caution {
                            Label(caution, systemImage: "exclamationmark.triangle.fill").font(.app(.subheadline, .semibold)).foregroundStyle(Theme.caution)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                Section {
                    if trip.stops.count > 1 {
                        Picker("Tappa", selection: $stopID) {
                            ForEach(trip.stops) { s in
                                Text("\(s.place.name) · \(Fmt.day(s.date, in: .iceland))").tag(s.id)
                            }
                        }
                    }
                    Picker("Giorno", selection: $day) {
                        ForEach(target.days, id: \.self) { d in
                            Text(Fmt.day(d, in: .iceland)).tag(d)
                        }
                    }
                    DatePicker("Ora di arrivo", selection: $date, displayedComponents: [.hourAndMinute])
                        .environment(\.timeZone, .iceland)
                    Stepper(String(localized: "Visita: \(Fmt.duration(Double(minutes) * 60))"), value: $minutes, in: 15...600, step: 15)
                    TextField("Note (biglietti, parcheggio, orari…)", text: $notes, axis: .vertical)
                } header: { Text("Quando").pinnedHeader() } footer: {
                    Text("Giorni e orari sono in ora islandese (un'ora indietro rispetto all'Italia in inverno). Il meteo e la luce vengono calcolati per l'ora di arrivo.")
                }
                Section {
                    Button {
                        var v = draft.visit
                        v.date = date
                        v.minutes = minutes
                        v.notes = notes
                        v = v.moved(to: day)
                        if stopID != draft.stop.id, !draft.isNew { trip.delete(draft.visit, in: draft.stop.id) }
                        trip.upsert(v, in: stopID)
                        Haptics.result(true)
                        dismiss()
                    } label: {
                        Label(draft.isNew ? String(localized: "Aggiungi al viaggio") : String(localized: "Salva modifiche"), systemImage: "checkmark.circle.fill")
                            .font(.app(.headline))
                    }
                    .accessibilityIdentifier("visit.save")
                    if !draft.isNew {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Togli dal viaggio", systemImage: "trash")
                        }
                    }
                    DirectionsRows(to: visit.place.coordinate)
                }
            }
            .themedList()
            .navigationTitle(draft.isNew ? String(localized: "Nuova attrazione") : String(localized: "Attrazione"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
            .confirmationDialog("Togliere questa attrazione dal viaggio?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Togli", role: .destructive) {
                    trip.delete(draft.visit, in: draft.stop.id)
                    dismiss()
                }
            }
        }
        .onChange(of: stopID) {
            // Another stop: keep the day if it covers it, otherwise its first day.
            if !target.includes(day: day) { day = target.days.first ?? target.date }
        }
        .onAppear {
            stopID = draft.stop.id
            day = Calendar.iceland.startOfDay(for: draft.visit.date)
            if !draft.stop.includes(day: day) { day = draft.stop.days.first ?? day }
            date = draft.visit.date
            minutes = draft.visit.minutes
            notes = draft.visit.notes
        }
    }

    /// The stop the visit belongs to once saved (it can be moved to another).
    private var target: TripStop {
        trip.stops.first { $0.id == stopID } ?? draft.stop
    }
}

extension TripVisit {
    /// A new visit after the last one of the stop (or at 10:00 on the day you arrive).
    /// With `day`, after the last visit of that day (or at 10:00 that day).
    static func next(at place: Place, kind: AttractionKind?, minutes: Int, in stop: TripStop, on day: Date? = nil) -> TripVisit {
        let calendar = Calendar.iceland
        let date: Date
        let visits = day.map { d in stop.sortedVisits.filter { calendar.isDate($0.date, inSameDayAs: d) } } ?? stop.sortedVisits
        if let last = visits.last {
            let travel = Geo.distanceKm(last.place.coordinate, place.coordinate) * 1.3 / 70 * 3600
            date = last.end.addingTimeInterval(max(15 * 60, (travel / 900).rounded() * 900))
        } else {
            let base = day ?? stop.date
            date = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: base) ?? base
        }
        return TripVisit(place: place, date: date, minutes: minutes, kind: kind)
    }
}
