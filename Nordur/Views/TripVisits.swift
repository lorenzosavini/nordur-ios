import SwiftUI

/// What to see during a stop: the day plan (driving and visiting time against
/// the hours of daylight) and one row per attraction, with the weather at the
/// time you arrive, darkness, roads nearby and the warnings of the place.
struct StopVisits: View {
    @Environment(AppModel.self) private var model
    @Environment(TripStore.self) private var trip
    let stop: TripStop
    let onAdd: () -> Void
    let onEdit: (TripVisit) -> Void

    var body: some View {
        let visits = stop.sortedVisits
        VStack(alignment: .leading, spacing: 10) {
            ForEach(days(of: visits), id: \.self) { day in
                let dayVisits = visits.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
                DayPlanLine(stop: stop, day: day, visits: dayVisits)
                ForEach(dayVisits) { visit in
                    VisitRow(visit: visit)
                        .contentShape(Rectangle())
                        .onTapGesture { onEdit(visit) }
                        .accessibilityIdentifier("trip.visit")
                }
            }
            Button(action: onAdd) {
                Label(visits.isEmpty ? String(localized: "Aggiungi attrazioni da vedere") : String(localized: "Aggiungi un'altra attrazione"),
                      systemImage: "plus.circle.fill")
                    .font(.app(.subheadline, .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trip.addVisit")
        }
        .padding(.vertical, 4)
    }

    private func days(of visits: [TripVisit]) -> [Date] {
        var seen: [Date] = []
        for v in visits {
            let d = Calendar.current.startOfDay(for: v.date)
            if !seen.contains(d) { seen.append(d) }
        }
        return seen
    }
}

/// One line per day: kilometres and driving time between the places of the day,
/// time spent visiting, and whether it all fits in the daylight.
struct DayPlanLine: View {
    @Environment(TripStore.self) private var trip
    let stop: TripStop
    let day: Date
    let visits: [TripVisit]

    var body: some View {
        let plan = DayPlan(stop: stop, previous: trip.previous(before: stop), day: day, visits: visits)
        let sun = daylight
        VStack(alignment: .leading, spacing: 3) {
            Text(Fmt.day(day, in: .iceland).uppercased()).font(.mono(10, .semibold)).foregroundStyle(Theme.accent)
            Text(String(localized: "\(visits.count) attrazioni · ~\(Int(plan.km.rounded())) km · ~\(Fmt.duration(plan.driveMinutes * 60)) di guida + \(Fmt.duration(plan.visitMinutes * 60)) di visita"))
                .font(.app(.caption)).foregroundStyle(Theme.text)
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
        let start = Calendar.current.startOfDay(for: day)
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
        let start = Calendar.current.isDate(day, inSameDayAs: stop.date) && stop.transport == .car ? (previous?.place ?? stop.place) : stop.place
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
            Image(systemName: (visit.kind ?? attraction?.kind)?.symbol ?? "mappin.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 30, height: 30)
                .background(Theme.accent)
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
    let stop: TripStop
    let onPick: (Place, AttractionKind?, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var searchingOther = false

    var body: some View {
        let all = Attraction.near(stop.place.coordinate, within: 2000)
        let filtered = query.isEmpty ? all : all.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.region.localizedCaseInsensitiveContains(query) || $0.kind.label.localizedCaseInsensitiveContains(query)
        }
        let near = filtered.filter { Geo.distanceKm(stop.place.coordinate, $0.coordinate) <= 150 }
        let far = filtered.filter { Geo.distanceKm(stop.place.coordinate, $0.coordinate) > 150 }
        NavigationStack {
            List {
                Section {
                    Button { searchingOther = true } label: {
                        Label("Cerca un altro luogo", systemImage: "magnifyingglass")
                    }
                }
                if !near.isEmpty {
                    Section {
                        ForEach(near) { row($0) }
                    } header: { Text(String(localized: "Vicino a \(stop.place.name)")).pinnedHeader() }
                }
                if !far.isEmpty {
                    Section {
                        ForEach(far) { row($0) }
                    } header: { Text("Resto dell'Islanda").pinnedHeader() }
                }
            }
            .themedList()
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
            HStack(spacing: 12) {
                Image(systemName: a.kind.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.name).font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text)
                    Text("\(a.region) · \(a.kind.label) · \(Fmt.duration(Double(a.minutes) * 60))")
                        .font(.app(.caption)).foregroundStyle(Theme.dim)
                }
                Spacer()
                Text("\(Int(Geo.distanceKm(stop.place.coordinate, a.coordinate).rounded())) km")
                    .font(.mono(10.5)).foregroundStyle(Theme.faint)
            }
        }
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(((visit.kind ?? attraction?.kind)?.label ?? String(localized: "Luogo")).uppercased())
                            .font(.mono(10, .semibold)).foregroundStyle(Theme.accent)
                        Text(visit.place.name).font(.display(28, .bold)).foregroundStyle(Theme.text)
                        Text(String(localized: "\(Int(Geo.distanceKm(draft.stop.place.coordinate, visit.place.coordinate).rounded())) km in linea d'aria da \(draft.stop.place.name)"))
                            .font(.mono(10)).foregroundStyle(Theme.dim)
                        if let caution = attraction?.caution {
                            Label(caution, systemImage: "exclamationmark.triangle").font(.app(.caption)).foregroundStyle(Theme.caution)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    DatePicker("Arrivo", selection: $date, in: range, displayedComponents: [.date, .hourAndMinute])
                    Stepper(String(localized: "Visita: \(Fmt.duration(Double(minutes) * 60))"), value: $minutes, in: 15...600, step: 15)
                    TextField("Note (biglietti, parcheggio, orari…)", text: $notes, axis: .vertical)
                } header: { Text("Quando").pinnedHeader() } footer: {
                    Text("Il meteo e la luce vengono calcolati per l'ora di arrivo.")
                }
                Section {
                    Button {
                        var v = draft.visit
                        v.date = date
                        v.minutes = minutes
                        v.notes = notes
                        trip.upsert(v, in: draft.stop.id)
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
                    if let url = URL(string: "http://maps.apple.com/?daddr=\(visit.place.coordinate.lat),\(visit.place.coordinate.lon)&q=\(visit.place.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                        Link(destination: url) { Label("Indicazioni in Mappe", systemImage: "arrow.triangle.turn.up.right.diamond") }
                    }
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
        .onAppear {
            date = draft.visit.date
            minutes = draft.visit.minutes
            notes = draft.visit.notes
        }
    }

    /// From the day you arrive at the stop to the day you leave.
    private var range: ClosedRange<Date> {
        let start = Calendar.current.startOfDay(for: draft.stop.date)
        let end = Calendar.current.date(byAdding: .day, value: max(draft.stop.nights, 0) + 1, to: start)!.addingTimeInterval(-60)
        return start...end
    }
}

extension TripVisit {
    /// A new visit after the last one of the stop (or at 10:00 on the day you arrive).
    static func next(at place: Place, kind: AttractionKind?, minutes: Int, in stop: TripStop) -> TripVisit {
        var calendar = Calendar.current
        calendar.timeZone = .iceland
        let date: Date
        if let last = stop.sortedVisits.last {
            let travel = Geo.distanceKm(last.place.coordinate, place.coordinate) * 1.3 / 70 * 3600
            date = last.end.addingTimeInterval(max(15 * 60, (travel / 900).rounded() * 900))
        } else {
            date = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: stop.date) ?? stop.date
        }
        return TripVisit(place: place, date: date, minutes: minutes, kind: kind)
    }
}
