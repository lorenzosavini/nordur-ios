import SwiftUI
import MapKit

extension Bath.Kind {
    var imageName: String { self == .pool ? "kind-bath" : "kind-geothermal" }
    var tint: Color { self == .pool ? .teal : .orange }
}

extension Bath {
    /// Open now / closes at… only when OpenStreetMap has the hours; nil otherwise
    /// (nothing is shown rather than a guess).
    func status(at now: Date = Date()) -> (text: String, open: Bool)? {
        guard let hours else { return nil }
        let open = hours.isOpen(at: now)
        let next = hours.nextChange(after: now)
        if open {
            guard let next else { return (String(localized: "Aperto 24 ore"), true) }
            return (String(localized: "Aperto · chiude alle \(Fmt.time(next, in: .iceland))"), true)
        }
        guard let next else { return (String(localized: "Chiuso"), false) }
        let sameDay = Calendar.iceland.isDate(next, inSameDayAs: now)
        return (sameDay ? String(localized: "Chiuso · apre alle \(Fmt.time(next, in: .iceland))")
                        : String(localized: "Chiuso · apre \(Fmt.dayTime(next, in: .iceland))"), false)
    }
}

/// Public swimming pools, geothermal baths and natural hot springs around a
/// place: on a map and as a list by distance, with "open now" where the hours
/// are known, directions and photos like the other places.
struct BathsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Around this place (a trip stop); otherwise the place shown in the app.
    var center: Place?
    var inSheet = false

    @State private var kind: Bath.Kind?
    @State private var openNow = false
    @State private var radiusKm = 80.0
    @State private var query = ""
    @State private var selected: Bath?

    var body: some View {
        ProGate(feature: .baths) {
            if inSheet {
                NavigationStack {
                    list.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
                }
            } else {
                list
            }
        }
    }

    private var list: some View {
        let place = center ?? model.activePlace
        let now = Date()
        let all = Baths.nearest(model.baths?.value ?? [], to: place.coordinate,
                                kinds: kind.map { Set([$0]) } ?? Set(Bath.Kind.allCases), within: radiusKm)
        let shown = all.filter { item in
            (query.isEmpty || item.bath.name.localizedCaseInsensitiveContains(query) || (item.bath.nameEnglish ?? "").localizedCaseInsensitiveContains(query))
                && (!openNow || item.bath.status(at: now)?.open == true)
        }
        let hasNatural = shown.contains { $0.bath.kind == .natural }
        return List {
            Section {
                ExpandableMap(height: 260, title: String(localized: "Piscine e sorgenti vicino a \(place.name)")) {
                    Map(initialPosition: .region(MKCoordinateRegion(center: place.coordinate.clCoordinate,
                                                                    span: MKCoordinateSpan(latitudeDelta: radiusKm / 70, longitudeDelta: radiusKm / 30)))) {
                        Marker(place.name, systemImage: "mappin", coordinate: place.coordinate.clCoordinate).tint(.indigo)
                        ForEach(Array(shown.prefix(200))) { item in
                            Annotation("", coordinate: item.bath.coordinate.clCoordinate) {
                                Button { selected = item.bath } label: { BathPin(bath: item.bath) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(item.bath.name)
                            }
                        }
                        UserAnnotation()
                    }
                }
                .listRowInsets(EdgeInsets())
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip(String(localized: "Tutte"), symbol: "square.grid.2x2", selected: kind == nil) { kind = nil }
                        ForEach(Bath.Kind.allCases) { k in
                            chip(k.plural, symbol: k.symbol, selected: kind == k) { kind = kind == k ? nil : k }
                        }
                    }
                }
                Toggle("Solo aperte adesso (dove l'orario è noto)", isOn: $openNow).tint(Theme.accent)
                Stepper("Entro \(Int(radiusKm)) km", value: $radiusKm, in: 20...300, step: 20)
            }
            if hasNatural || kind == .natural {
                Section {
                    Label(Baths.safety, systemImage: "exclamationmark.triangle.fill")
                        .font(.app(.caption, .semibold)).foregroundStyle(Theme.caution)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                if model.baths == nil {
                    if let error = model.errors[.baths] { ErrorNote(message: error) } else { SkeletonRows(count: 5) }
                } else if shown.isEmpty {
                    EmptyState(symbol: "figure.pool.swim", title: String(localized: "Nessun risultato"),
                               message: openNow ? String(localized: "Nessuna con orari noti aperta adesso in questa zona.")
                                                : String(localized: "Nessuna piscina o sorgente in questa zona con questi filtri."),
                               actionTitle: openNow ? String(localized: "Mostra anche le chiuse")
                                                    : (radiusKm < 300 ? String(localized: "Cerca entro 300 km") : nil)) {
                        if openNow { openNow = false } else { radiusKm = 300 }
                    }
                } else {
                    ForEach(shown.prefix(120)) { item in
                        Button { selected = item.bath } label: { BathRow(bath: item.bath, km: item.km, now: now) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("bath.row")
                    }
                }
            } header: {
                Text(String(localized: "\(shown.count) entro \(Int(radiusKm)) km da \(place.name)")).pinnedHeader()
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Le piscine comunali (sundlaug) sono il modo islandese di stare al caldo: doccia senza costume prima di entrare, è obbligatoria. Orari e ingresso a pagamento solo quando sono indicati su OpenStreetMap: verifica sul sito del posto, soprattutto nei festivi.")
                    if let baths = model.baths {
                        FreshnessLabel(date: baths.date, isStale: baths.isStale, source: String(localized: "OpenStreetMap"))
                    }
                }
            }
        }
        .themedList()
        .navigationTitle("Piscine e sorgenti calde")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: String(localized: "Nome, es. Laugardalslaug"))
        .task { await model.loadBaths() }
        .refreshable { await model.loadBaths(force: true) }
        .sheet(item: $selected) { bath in
            BathDetail(bath: bath, from: place).presentationDetents([.medium, .large])
        }
    }

    private func chip(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            action()
        } label: {
            Label(title, systemImage: symbol)
                .font(.mono(10.5, .semibold))
                .padding(.horizontal, 10).frame(height: 30)
                .background(selected ? Theme.accent : Theme.surface)
                .foregroundStyle(selected ? Theme.onAccent : Theme.text)
        }
        .buttonStyle(.plain)
    }
}

struct BathPin: View {
    let bath: Bath

    var body: some View {
        let size: CGFloat = bath.notable ? 24 : 18
        Image(systemName: bath.kind.symbol)
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(bath.kind.tint))
            .overlay(Circle().strokeBorder(.white, lineWidth: bath.notable ? 2 : 1))
            .shadow(radius: 1)
    }
}

struct BathRow: View {
    let bath: Bath
    let km: Double?
    var now = Date()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Photos for the best-known places (with Wikipedia/Wikidata), as for the sights.
            PlaceThumb(place: bath.place, kind: bath.kind == .pool ? .bath : .geothermal, size: 56, photo: bath.notable)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(bath.name).font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer()
                    if let km {
                        Text("\(Fmt.number(km, decimals: km < 10 ? 1 : 0)) km").font(.mono(10.5, .semibold)).foregroundStyle(Theme.dim)
                    }
                }
                Text(bath.detail).font(.app(.caption)).foregroundStyle(Theme.dim).lineLimit(1)
                if let status = bath.status(at: now) {
                    Text(status.text).font(.app(.caption, .semibold))
                        .foregroundStyle(status.open ? Theme.aurora : Theme.danger)
                        .lineLimit(1)
                }
                if bath.kind == .natural {
                    Text(Baths.safetyShort).font(.app(.caption2)).foregroundStyle(Theme.caution).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// One pool or spring: photo, open now and hours (when known), fee (when
/// tagged), the safety note for natural springs, directions, and adding it to a stop.
struct BathDetail: View {
    @Environment(TripStore.self) private var trip
    @Environment(\.dismiss) private var dismiss
    let bath: Bath
    let from: Place
    @State private var added: String?

    var body: some View {
        let c = bath.coordinate
        let km = Geo.distanceKm(from.coordinate, c)
        let nearestStop = trip.stops.min { Geo.distanceKm($0.place.coordinate, c) < Geo.distanceKm($1.place.coordinate, c) }
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        PlaceHero(place: bath.place, kind: bath.kind == .pool ? .bath : .geothermal, title: bath.name, eyebrow: bath.detail,
                                  describe: bath.notable)
                        Label(String(localized: "\(Fmt.number(km, decimals: km < 10 ? 1 : 0)) km in linea d'aria da \(from.name)"), systemImage: "location")
                            .font(.app(.subheadline)).foregroundStyle(Theme.dim)
                        if let english = bath.nameEnglish {
                            Text(english).font(.app(.subheadline)).foregroundStyle(Theme.dim)
                        }
                        if let status = bath.status() {
                            Text(status.text).font(.app(.headline)).foregroundStyle(status.open ? Theme.aurora : Theme.danger)
                        }
                        if let fee = bath.fee {
                            Label(fee ? String(localized: "Ingresso a pagamento") : String(localized: "Ingresso libero"),
                                  systemImage: fee ? "creditcard" : "hand.thumbsup")
                                .font(.app(.subheadline)).foregroundStyle(Theme.dim)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                if bath.kind == .natural {
                    Section {
                        Label(Baths.safety, systemImage: "exclamationmark.triangle.fill")
                            .font(.app(.subheadline, .semibold)).foregroundStyle(Theme.caution)
                            .fixedSize(horizontal: false, vertical: true)
                    } header: { Text("Sicurezza").pinnedHeader() }
                }
                if let raw = bath.openingHours {
                    Section {
                        Text(raw.replacingOccurrences(of: "; ", with: "\n")).font(.mono(12)).foregroundStyle(Theme.text)
                    } header: { Text("Orari (OpenStreetMap)").pinnedHeader() }
                }
                if let site = bath.website.flatMap({ URL(string: $0.hasPrefix("http") ? $0 : "https://\($0)") }) {
                    Section {
                        Link(destination: site) { Label("Sito del posto", systemImage: "safari") }
                    }
                }
                Section {
                    if trip.stops.isEmpty {
                        Text("Aggiungi una tappa al viaggio per mettere questo luogo nel programma.").font(.app(.caption)).foregroundStyle(Theme.dim)
                    } else {
                        Menu {
                            ForEach(trip.stops) { stop in
                                Button("\(stop.place.name) · \(Fmt.day(stop.date, in: .iceland)) · \(Int(Geo.distanceKm(stop.place.coordinate, c).rounded())) km") {
                                    add(to: stop)
                                }
                            }
                        } label: {
                            Label(String(localized: "Aggiungi al viaggio"), systemImage: "plus.circle.fill").font(.app(.headline))
                        }
                        if let nearestStop {
                            Button { add(to: nearestStop) } label: {
                                Label(String(localized: "Aggiungi alla tappa più vicina: \(nearestStop.place.name)"), systemImage: "bed.double")
                            }
                        }
                        if let added {
                            Label(String(localized: "Aggiunto a \(added): trovi giorno e ora nella tappa"), systemImage: "checkmark.circle.fill")
                                .font(.app(.caption, .semibold)).foregroundStyle(Theme.aurora)
                        }
                    }
                } header: { Text("Viaggio").pinnedHeader() }
                Section {
                    DirectionsRows(to: c)
                }
            }
            .themedList()
            .navigationTitle(bath.kind.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
        }
    }

    private func add(to stop: TripStop) {
        let sight = bath.attraction
        trip.upsert(.next(at: sight.place, kind: sight.kind, minutes: sight.minutes, in: stop), in: stop.id)
        Haptics.result(true)
        added = stop.place.name
    }
}
