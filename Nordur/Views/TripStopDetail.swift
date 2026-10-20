import SwiftUI

// The trip as a list of compact stop cards with the legs between them; each
// card opens the stop's own page (weather, the plan day by day, suggestions,
// shops, the way to the next stop).

/// The whole trip at a glance.
struct TripOverview: View {
    @Environment(TripStore.self) private var trip

    var body: some View {
        let stops = trip.stops
        let first = stops.first?.date
        let last = stops.last.map { $0.endDate }
        let nights = stops.reduce(0) { $0 + $1.nights }
        let legs = zip(stops, stops.dropFirst()).reduce(0.0) { $0 + Geo.distanceKm($1.0.place.coordinate, $1.1.place.coordinate) * 1.3 }
        let visits = stops.reduce(0) { $0 + $1.visits.count }
        VStack(alignment: .leading, spacing: 10) {
            if let first, let last {
                Text("\(Fmt.day(first, in: .iceland)) → \(Fmt.day(last, in: .iceland))".uppercased())
                    .font(.mono(11, .semibold)).foregroundStyle(Theme.accent)
            }
            HStack(spacing: 0) {
                figure("\(stops.count)", String(localized: "TAPPE"))
                figure("\(nights)", String(localized: "NOTTI"))
                figure("~\(Int(legs.rounded()))", String(localized: "KM"))
                figure("\(visits)", String(localized: "ATTRAZIONI"))
            }
        }
        .padding(.vertical, 6)
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.metric(26, .semibold)).foregroundStyle(Theme.text)
            Text(label).font(.mono(9)).foregroundStyle(Theme.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One stop in the list: number, place, dates, the weather of the day and what is planned.
struct StopCard: View {
    @Environment(AppModel.self) private var model
    @Environment(TripStore.self) private var trip
    let stop: TripStop
    let index: Int

    var body: some View {
        let forecast = trip.forecast(for: stop)
        let day = forecast?.day(for: stop.date)
        let warnings = model.warnings(at: stop.place.coordinate, from: stop.date.addingTimeInterval(-12 * 3600), to: stop.endDate)
        let visits = stop.sortedVisits
        HStack(alignment: .top, spacing: 14) {
            // A photo of the place, numbered.
            PlaceThumb(place: stop.place, kind: .town, size: 72)
                .overlay(alignment: .topLeading) {
                    Text(String(format: "%02d", index + 1))
                        .font(.metric(17, .bold)).foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 6).frame(height: 24).background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .offset(x: -6, y: -6)
                }
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(stop.place.name).font(.app(.headline)).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer()
                    if let day { RiskBadge(risk: day.overallRisk) }
                }
                Text(dates).font(.mono(10.5, .semibold)).foregroundStyle(Theme.dim)
                if let day {
                    let info = WeatherCode.describe(day.code)
                    HStack(spacing: 10) {
                        Label("\(Fmt.temp(day.minTemp))/\(Fmt.temp(day.maxTemp))", systemImage: info.symbol).symbolRenderingMode(.multicolor)
                        Text(String(localized: "raff. \(Fmt.ms(day.maxGust))")).foregroundStyle(day.windRisk == .ok ? Theme.dim : day.windRisk.color)
                    }
                    .font(.app(.caption))
                }
                if !warnings.isEmpty {
                    Label(String(localized: "\(warnings.count) allerte IMO"), systemImage: "exclamationmark.triangle.fill")
                        .font(.app(.caption, .semibold)).foregroundStyle(warnings.map(\.color).max()?.color ?? Theme.warning)
                }
                if !visits.isEmpty {
                    Text(visits.prefix(3).map(\.place.name).joined(separator: " · ") + (visits.count > 3 ? " +\(visits.count - 3)" : ""))
                        .font(.app(.caption)).foregroundStyle(Theme.text).lineLimit(2)
                        .padding(.top, 2)
                } else {
                    Text("Nessuna attrazione: apri la tappa per i consigli").font(.app(.caption)).foregroundStyle(Theme.faint)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var dates: String {
        let transport = stop.transport.label.uppercased()
        if stop.nights == 0 { return "\(Fmt.day(stop.date, in: .iceland).uppercased()) · \(String(localized: "DI PASSAGGIO")) · \(transport)" }
        let nights = stop.nights == 1 ? String(localized: "1 NOTTE") : String(localized: "\(stop.nights) NOTTI")
        return "\(Fmt.day(stop.date, in: .iceland).uppercased()) → \(Fmt.day(stop.endDate, in: .iceland).uppercased()) · \(nights)"
    }
}

/// Between two cards: how you get to the next stop, roughly how long, and the roads now.
struct LegLine: View {
    @Environment(AppModel.self) private var model
    let from: TripStop
    let to: TripStop

    var body: some View {
        let km = Geo.distanceKm(from.place.coordinate, to.place.coordinate) * (to.transport == .car || to.transport == .bus ? 1.3 : 1)
        let byRoad = to.transport == .car || to.transport == .bus
        let network = byRoad ? model.roads?.value : nil
        let worst = network.flatMap { n in n.corridor(from: from.place.coordinate, to: to.place.coordinate).map { n.worstRisk(of: $0) }.max() }
        HStack(spacing: 10) {
            Rectangle().fill(Theme.hairline).frame(width: 2, height: 28).padding(.leading, 21)
            Image(systemName: to.transport.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.dim)
            Text(byRoad ? String(localized: "~\(Int(km.rounded())) km · ~\(Fmt.duration(km / 70 * 3600))") : String(localized: "~\(Int(km.rounded())) km in linea d'aria"))
                .font(.mono(10.5, .semibold)).foregroundStyle(Theme.dim)
            if let worst, worst > .ok { RiskBadge(risk: worst, text: String(localized: "strade")) }
            Spacer()
            if byRoad { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.faint) }
        }
    }
}

/// Everything about one stop, readable top to bottom.
struct StopDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(TripStore.self) private var trip
    @Environment(\.dismiss) private var dismiss
    let stopID: UUID
    let fallback: TripStop

    @State private var editing = false
    @State private var pickingDay: PickedDay?
    @State private var pendingVisit: VisitDraft?
    @State private var visitDraft: VisitDraft?
    @State private var showingSights = false
    @State private var showingShops = false
    @State private var selectedSight: Attraction?

    private var stop: TripStop { trip.stops.first { $0.id == stopID } ?? fallback }

    var body: some View {
        let stop = self.stop
        let index = (trip.stops.firstIndex { $0.id == stop.id } ?? 0) + 1
        let previous = trip.previous(before: stop)
        let next = trip.next(after: stop)
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "TAPPA \(index) DI \(trip.stops.count)")).font(.mono(10, .semibold)).foregroundStyle(Theme.accent)
                    Text(stop.place.name).font(.display(30, .bold)).foregroundStyle(Theme.text)
                    Label(stop.nights == 0 ? String(localized: "\(Fmt.day(stop.date, in: .iceland)) · di passaggio")
                                           : String(localized: "\(Fmt.day(stop.date, in: .iceland)) → \(Fmt.day(stop.endDate, in: .iceland)) · \(stop.nights) notti"),
                          systemImage: "calendar")
                        .font(.app(.subheadline)).foregroundStyle(Theme.dim)
                    Label(String(localized: "Arrivo: \(stop.transport.label)"), systemImage: stop.transport.symbol)
                        .font(.app(.subheadline)).foregroundStyle(Theme.dim)
                    if !stop.notes.isEmpty {
                        Text(stop.notes).font(.app(.caption)).foregroundStyle(Theme.dim).padding(.top, 2)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                StopSummary(stop: stop, showsHeader: false)
            } header: { Text("Meteo e allerte").pinnedHeader() }

            ForEach(stop.days.indices, id: \.self) { i in
                let day = stop.days[i]
                let dayVisits = stop.sortedVisits.filter { Calendar.iceland.isDate($0.date, inSameDayAs: day) }
                Section {
                    DayPlanLine(stop: stop, day: day, visits: dayVisits, showsDate: false)
                    if dayVisits.isEmpty {
                        Text(i == stop.days.count - 1 && stop.nights > 0 ? String(localized: "Giorno della partenza: nessuna attrazione")
                                                                          : String(localized: "Giornata libera"))
                            .font(.app(.caption)).foregroundStyle(Theme.faint)
                    }
                    ForEach(dayVisits) { visit in
                        VisitRow(visit: visit)
                            .contentShape(Rectangle())
                            .onTapGesture { visitDraft = VisitDraft(stop: stop, visit: visit, isNew: false) }
                            .contextMenu { VisitMenu(stop: stop, visit: visit) { visitDraft = VisitDraft(stop: stop, visit: visit, isNew: false) } }
                            .accessibilityIdentifier("trip.visit")
                    }
                    Button { pickingDay = PickedDay(day: day) } label: {
                        Label(String(localized: "Aggiungi un'attrazione a questo giorno"), systemImage: "plus.circle.fill")
                            .font(.app(.subheadline, .semibold)).foregroundStyle(Theme.accent)
                    }
                    .accessibilityIdentifier("trip.addVisit")
                } header: {
                    Text(String(localized: "Giorno \(i + 1) · \(Fmt.day(day, in: .iceland))")).pinnedHeader()
                } footer: {
                    if i == 0, dayVisits.count > 0 {
                        Text("Tieni premuta un'attrazione per spostarla a un altro giorno o a un'altra tappa.")
                    }
                }
            }

            let suggestions = Sights.suggestions(in: model.spots, for: stop, previous: previous,
                                                 planned: trip.stops.flatMap(\.visits), limit: 6)
            Section {
                if suggestions.isEmpty {
                    Text("Nessun suggerimento qui vicino.").font(.app(.caption)).foregroundStyle(Theme.faint)
                }
                ForEach(suggestions) { item in
                    HStack(spacing: 8) {
                        Button { selectedSight = item.sight } label: {
                            SightRow(sight: item.sight, km: item.km)
                        }
                        .buttonStyle(.plain)
                        Button {
                            trip.upsert(.next(at: item.sight.place, kind: item.sight.kind, minutes: item.sight.minutes, in: stop), in: stop.id)
                            Haptics.result(true)
                        } label: {
                            Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.onAccent)
                                .frame(width: 34, height: 34).background(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Aggiungi \(item.sight.name)"))
                    }
                    .overlay(alignment: .topLeading) {
                        if item.onTheWay {
                            Text("SULLA STRADA").font(.mono(7.5, .semibold)).foregroundStyle(Theme.onAccent)
                                .padding(.horizontal, 3).background(Theme.dim).offset(x: -2, y: -4)
                        }
                    }
                }
                Button { showingSights = true } label: {
                    Label("Tutto quello che c'è da vedere, sulla mappa", systemImage: "map")
                        .font(.app(.subheadline, .semibold))
                }
            } header: { Text("Consigliati per questa tappa").pinnedHeader() } footer: {
                Text(previous != nil && stop.transport == .car
                     ? String(localized: "Vicino a \(stop.place.name) e lungo la strada da \(previous!.place.name). Il + li aggiunge al programma dopo l'ultima attrazione.")
                     : String(localized: "Vicino a \(stop.place.name). Il + li aggiunge al programma dopo l'ultima attrazione."))
            }

            Section {
                ShopsLine(stop: stop) { showingShops = true }
            } header: { Text("Spesa").pinnedHeader() }

            if let next {
                Section {
                    LegSummary(from: stop, to: next)
                } header: { Text(String(localized: "Verso la tappa \(index + 1): \(next.place.name)")).pinnedHeader() }
            }
        }
        .themedList()
        .navigationTitle(stop.place.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Modifica") { editing = true }.accessibilityIdentifier("stop.edit")
            }
        }
        .task { await model.loadSights() }
        // The stop was deleted from its editor: back to the trip.
        .onChange(of: trip.stops.contains { $0.id == stopID }) { _, exists in if !exists { dismiss() } }
        .sheet(isPresented: $editing) { StopEditor(stop: stop) }
        .sheet(isPresented: $showingSights) { SightsView(center: stop.place, inSheet: true) }
        .sheet(isPresented: $showingShops) { ShopsView(center: stop.place, inSheet: true) }
        .sheet(item: $selectedSight) { sight in
            SightDetail(sight: sight, from: stop.place).presentationDetents([.medium, .large])
        }
        // Choosing an attraction, then its day and time (one sheet after the other).
        .sheet(item: $pickingDay, onDismiss: {
            if let pending = pendingVisit {
                pendingVisit = nil
                visitDraft = pending
            }
        }) { picked in
            AttractionPicker(stop: stop) { place, kind, minutes in
                pendingVisit = VisitDraft(stop: stop, visit: .next(at: place, kind: kind, minutes: minutes, in: stop, on: picked.day), isNew: true)
            }
        }
        .sheet(item: $visitDraft) { draft in
            VisitEditor(draft: draft)
        }
    }
}

/// A day chosen to add an attraction to.
struct PickedDay: Identifiable {
    let day: Date
    var id: Date { day }
}
