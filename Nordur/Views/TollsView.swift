import SwiftUI
import MapKit

/// Strade › Pedaggi e parcheggi: toll tunnels and roads, paid parking and the
/// rules worth knowing (km charge), on a map and as a list by distance. Prices
/// from official sources, with the day they were checked.
struct TollsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(TollVehicle.key) private var vehicleRaw = TollVehicle.car.rawValue
    @State private var selected: TollEntry?

    private var vehicle: TollVehicle { TollVehicle(rawValue: vehicleRaw) ?? .car }

    var body: some View {
        ProGate(feature: .tolls) { list }
    }

    private var list: some View {
        let here = model.location.coordinate ?? model.activePlace.coordinate
        let entries = (model.tolls?.value ?? []).filter { $0.isActive() || $0.since != nil }
        func km(_ e: TollEntry) -> Double { e.distanceKm(from: here) ?? .infinity }
        let roads = entries.filter { $0.isToll || ($0.kind == .info && $0.coordinate != nil) }.sorted { km($0) < km($1) }
        let parking = entries.filter(\.isParking).sorted { km($0) < km($1) }
        let general = entries.filter { $0.kind == .info && $0.coordinate == nil }
        return List {
            Section {
                ExpandableMap(height: 280, title: String(localized: "Pedaggi e parcheggi")) { overview(entries) }
                .listRowInsets(EdgeInsets())
                Picker(String(localized: "Il tuo veicolo"), selection: $vehicleRaw) {
                    ForEach(TollVehicle.allCases) { Text($0.label).tag($0.rawValue) }
                }
            } footer: {
                Text("I prezzi mostrati sono quelli per il tuo veicolo: tunnel e strade si pagano in base al peso registrato, i parcheggi in base ai posti.")
            }

            if model.tolls == nil {
                Section {
                    if let error = model.errors[.tolls] { ErrorNote(message: error) } else { SkeletonRows(count: 4) }
                }
            } else if entries.isEmpty {
                Section {
                    EmptyState(symbol: "eurosign.circle", title: String(localized: "Nessun pedaggio in elenco"),
                               message: String(localized: "Il catalogo è vuoto: riprova più tardi."),
                               actionTitle: String(localized: "Aggiorna")) {
                        Task { await model.loadTolls(force: true) }
                    }
                }
            } else {
                Section {
                    ForEach(roads) { entry in row(entry, km: km(entry)) }
                } header: { Text("Tunnel e strade").pinnedHeader() }
                Section {
                    ForEach(parking) { entry in row(entry, km: km(entry)) }
                } header: { Text("Parcheggi a pagamento").pinnedHeader() } footer: {
                    Text("Solo i parcheggi con un prezzo pubblicato dal gestore. In molti altri siti si paga: guarda i cartelli all'ingresso.")
                }
                if !general.isEmpty {
                    Section {
                        ForEach(general) { entry in row(entry, km: nil) }
                    } header: { Text("Da sapere").pinnedHeader() }
                }
            }

            Section {
                TollDisclaimer(date: model.tolls?.value.compactMap(\.verifiedDate).max())
                if let tolls = model.tolls {
                    FreshnessLabel(date: tolls.date, isStale: tolls.isStale, source: String(localized: "Norður · fonti ufficiali"))
                }
            }
        }
        .themedList()
        .navigationTitle("Pedaggi e parcheggi")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadTolls() }
        .refreshable { await model.loadTolls(force: true) }
        .sheet(item: $selected) { entry in
            TollDetail(entry: entry).presentationDetents([.medium, .large])
        }
    }

    private func overview(_ entries: [TollEntry]) -> some View {
        let lines = entries.filter { $0.pathCoordinates.count >= 2 }
        let pins = entries.filter { $0.coordinate != nil }
        let iceland = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 64.9, longitude: -18.6),
                                         span: MKCoordinateSpan(latitudeDelta: 4.2, longitudeDelta: 12))
        return Map(initialPosition: .region(iceland)) {
            ForEach(lines) { entry in
                MapPolyline(coordinates: entry.pathCoordinates.map(\.clCoordinate))
                    .stroke(entry.isToll ? Color.yellow : Color.green, lineWidth: 5)
            }
            ForEach(pins) { entry in
                Annotation("", coordinate: (entry.coordinate ?? Coordinate(lat: 64.9, lon: -18.6)).clCoordinate) {
                    Button { selected = entry } label: { TollPin(entry: entry) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(entry.name)
                }
            }
            UserAnnotation()
        }
    }

    private func row(_ entry: TollEntry, km: Double?) -> some View {
        Button { selected = entry } label: { TollRow(entry: entry, km: km, vehicle: vehicle) }
            .buttonStyle(.plain)
            .accessibilityIdentifier("toll.row")
    }
}

/// "Prezzi indicativi, controlla sul sito ufficiale", always next to a price.
struct TollDisclaimer: View {
    var date: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let date {
                Label(String(localized: "Verificato il \(Fmt.day(date, in: .iceland))"), systemImage: "checkmark.seal")
                    .font(.app(.caption, .semibold)).foregroundStyle(Theme.dim)
            }
            Text("Prezzi indicativi, controlla sul sito ufficiale prima di pagare.")
                .font(.app(.caption)).foregroundStyle(Theme.dim)
        }
    }
}

struct TollPin: View {
    let entry: TollEntry

    var body: some View {
        Image(systemName: entry.isParking ? "parkingsign" : entry.isToll ? "eurosign" : "info")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(entry.isToll ? Color.black : Color.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(entry.isToll ? Color.yellow : entry.isParking ? Color.blue : Color.green))
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            .shadow(radius: 1)
    }
}

struct TollRow: View {
    let entry: TollEntry
    let km: Double?
    var vehicle: TollVehicle = .current

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(entry.isToll ? Theme.caution : entry.isParking ? Theme.accent : Theme.aurora)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.name).font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer()
                    if let km, km.isFinite {
                        Text("\(Fmt.number(km, decimals: km < 10 ? 1 : 0)) km").font(.mono(10.5, .semibold)).foregroundStyle(Theme.dim)
                    }
                }
                Text(entry.kindLabel).font(.app(.caption)).foregroundStyle(Theme.dim)
                if let price = entry.price(for: vehicle) {
                    Text("≈ \(price.iskText) \(price.unitLabel)").font(.app(.caption, .semibold)).foregroundStyle(Theme.text)
                    if let differ = entry.reportsDisagree(for: vehicle) {
                        Label(String(localized: "\(differ.count) viaggiatori segnalano \(Fmt.number(differ.isk)) ISK"), systemImage: "person.2.fill")
                            .font(.app(.caption2, .semibold)).foregroundStyle(Theme.caution)
                    }
                } else if let reported = entry.reportedPrice(for: vehicle) {
                    Text("≈ \(reported.iskText) \(reported.unitLabel) · segnalato da \(entry.community(for: vehicle)?.count ?? 0)")
                        .font(.app(.caption, .semibold)).foregroundStyle(Theme.text)
                } else if entry.isParking || entry.isToll {
                    Text("A pagamento: verifica il prezzo sul posto").font(.app(.caption)).foregroundStyle(Theme.caution)
                } else if let summary = entry.text.summary {
                    Text(summary).font(.app(.caption)).foregroundStyle(Theme.text).lineLimit(2)
                }
                if !entry.isActive(), let since = entry.since.flatMap(TollEntry.day) {
                    Text("A pagamento dal \(Fmt.day(since, in: .iceland))").font(.app(.caption2)).foregroundStyle(Theme.caution)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// One toll or car park: prices by class (yours first), how and when to pay,
/// what happens otherwise, the free alternative, the official source.
struct TollDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let entry: TollEntry

    var body: some View {
        NavigationStack {
            List { TollDetailSections(entry: entry) }
                .themedList()
                .navigationTitle(entry.kindLabel)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
        }
    }
}

struct TollDetailSections: View {
    @Environment(AppModel.self) private var model
    let entry: TollEntry

    var body: some View {
        let text = entry.text
        let mine = entry.price()
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(entry.kindLabel, systemImage: entry.symbol)
                    .font(.mono(10, .semibold)).foregroundStyle(entry.isToll ? Theme.caution : Theme.accent)
                Text(entry.name).font(.display(26, .bold)).foregroundStyle(Theme.text)
                if let summary = text.summary {
                    Text(summary).font(.app(.subheadline)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                }
                if let mine {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("≈ \(mine.iskText) \(mine.unitLabel)").font(.metric(24, .semibold)).foregroundStyle(Theme.text)
                        if let other = Tolls.converted(mine.isk, rates: model.rates?.value) {
                            Text(other).font(.mono(11)).foregroundStyle(Theme.dim)
                        }
                        Text(TollVehicle.current.label).font(.app(.caption)).foregroundStyle(Theme.dim)
                    }
                } else if entry.isParking || entry.isToll {
                    Text("A pagamento: verifica il prezzo sul posto").font(.app(.subheadline, .semibold)).foregroundStyle(Theme.caution)
                }
            }
            .padding(.vertical, 4)
        }

        if !entry.allPrices.isEmpty {
            Section {
                ForEach(entry.allPrices, id: \.self) { price in
                    LabeledContent(price.classLabel) {
                        Text("\(price.iskText) \(price.unitLabel)")
                            .font(.app(.subheadline, price == mine ? Font.Weight.semibold : Font.Weight.regular))
                            .foregroundStyle(price == mine ? Theme.text : Theme.dim)
                    }
                }
            } header: { Text("Prezzi indicativi").pinnedHeader() }
        }

        if text.payment != nil || entry.payURL != nil {
            Section {
                if let payment = text.payment { Text(payment).font(.app(.subheadline)).fixedSize(horizontal: false, vertical: true) }
                if let app = entry.appName {
                    Label(String(localized: "App: \(app)"), systemImage: "iphone").font(.app(.subheadline))
                }
                if let url = entry.payURL {
                    Link(destination: url) {
                        Label(entry.isParking ? String(localized: "Paga il parcheggio online") : String(localized: "Paga online"), systemImage: "creditcard")
                            .font(.app(.headline))
                    }
                }
            } header: { Text("Come pagare").pinnedHeader() }
        }

        if entry.isToll || entry.isParking {
            Section {
                TollReportsBlock(entry: entry)
            } header: { Text("Segnalazioni dei viaggiatori").pinnedHeader() } footer: {
                Text("Quanto dicono di aver pagato le persone che usano Norður negli ultimi 120 giorni (una segnalazione per telefono al giorno, anonima). Non sostituiscono il prezzo ufficiale.")
            }
        }

        TollTextSections(text: text)

        if let c = entry.coordinate {
            Section {
                ExpandableMap(height: 200, title: entry.name) {
                    Map(initialPosition: .region(MKCoordinateRegion(center: c.clCoordinate, span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.3)))) {
                        if entry.pathCoordinates.count >= 2 {
                            MapPolyline(coordinates: entry.pathCoordinates.map(\.clCoordinate)).stroke(Color.yellow, lineWidth: 5)
                        }
                        Marker(entry.name, systemImage: entry.symbol, coordinate: c.clCoordinate).tint(entry.isToll ? .yellow : .blue)
                        UserAnnotation()
                    }
                }
                .listRowInsets(EdgeInsets())
                DirectionsRows(to: c)
            } header: { Text("Dove").pinnedHeader() }
        }

        Section {
            TollDisclaimer(date: entry.verifiedDate)
            if let url = entry.sourceURL {
                Link(destination: url) {
                    Label(String(localized: "Fonte ufficiale: \(entry.sourceName ?? url.host() ?? entry.sourceUrl)"), systemImage: "building.columns")
                }
            }
            ForEach((entry.sources ?? []).filter { $0.url != entry.sourceUrl }, id: \.url) { source in
                if let url = URL(string: source.url) {
                    Link(destination: url) { Label(source.name, systemImage: "doc.text") }
                }
            }
        } header: { Text("Fonte").pinnedHeader() }
    }
}

/// When to pay, what happens otherwise, rental cars, the free alternative.
struct TollTextSections: View {
    let text: TollEntry.Texts

    var body: some View {
        if let window = text.window {
            Section { Text(window).font(.app(.subheadline)).fixedSize(horizontal: false, vertical: true) } header: { Text("Quando").pinnedHeader() }
        }
        if let penalty = text.penalty {
            Section { Text(penalty).font(.app(.subheadline)).fixedSize(horizontal: false, vertical: true) } header: { Text("Se non paghi").pinnedHeader() }
        }
        if let rental = text.rental {
            Section { Text(rental).font(.app(.subheadline)).fixedSize(horizontal: false, vertical: true) } header: { Text("Auto a noleggio").pinnedHeader() }
        }
        if let alternative = text.alternative {
            Section {
                Label(alternative, systemImage: "arrow.triangle.branch").font(.app(.subheadline)).fixedSize(horizontal: false, vertical: true)
            } header: { Text("Alternativa gratuita").pinnedHeader() }
        }
        if let note = text.note {
            Section { Text(note).font(.app(.subheadline)).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// "3 people reported 1,200 ISK", a warning when most reports disagree with the
/// official price, and the button to report what you paid.
struct TollReportsBlock: View {
    let entry: TollEntry
    @State private var reporting = false
    @State private var sentToday = false

    var body: some View {
        let reports = Array((entry.reports ?? []).prefix(6))
        if let differ = entry.reportsDisagree() {
            Label(String(localized: "La maggior parte delle segnalazioni recenti dice \(Fmt.number(differ.isk)) ISK: il prezzo potrebbe essere cambiato, verifica sul sito ufficiale."),
                  systemImage: "exclamationmark.triangle.fill")
                .font(.app(.caption, .semibold)).foregroundStyle(Theme.caution)
                .fixedSize(horizontal: false, vertical: true)
        }
        if reports.isEmpty {
            Text("Nessuna segnalazione per ora.").font(.app(.caption)).foregroundStyle(Theme.dim)
        }
        ForEach(reports, id: \.self) { report in
            VStack(alignment: .leading, spacing: 1) {
                Text(report.count == 1 ? String(localized: "1 persona ha segnalato \(Fmt.number(report.isk)) ISK")
                                       : String(localized: "\(report.count) persone hanno segnalato \(Fmt.number(report.isk)) ISK"))
                    .font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text)
                Text(TollEntry.Price(cls: report.cls, isk: report.isk, unit: "trip").classLabel)
                    .font(.app(.caption)).foregroundStyle(Theme.dim)
            }
        }
        if sentToday || Tolls.reportedToday(entry) {
            Label("Grazie: hai già segnalato oggi", systemImage: "checkmark.circle.fill")
                .font(.app(.caption, .semibold)).foregroundStyle(Theme.aurora)
        } else {
            Button { reporting = true } label: {
                Label("Segnala quanto hai pagato", systemImage: "square.and.pencil").font(.app(.headline))
            }
            .sheet(isPresented: $reporting) {
                TollReportForm(entry: entry) { sentToday = true }
                    .presentationDetents([.medium])
            }
        }
    }
}

/// What you paid: vehicle class and amount in króna.
struct TollReportForm: View {
    @Environment(\.dismiss) private var dismiss
    let entry: TollEntry
    var onSent: () -> Void
    @State private var cls = ""
    @State private var amount: Int?
    @State private var sending = false
    @State private var error: String?

    private var classes: [String] {
        let official = entry.allPrices.map(\.cls)
        if !official.isEmpty { return official }
        return entry.isToll ? ["under_3_5t", "t3_5_7_5", "over_7_5t"] : ["car_5", "car_6_9", "motorcycle", "bus_10_19", "bus_20_32", "bus_33"]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(String(localized: "Veicolo"), selection: $cls) {
                        ForEach(classes, id: \.self) { c in
                            Text(TollEntry.Price(cls: c, isk: 0, unit: "trip").classLabel).tag(c)
                        }
                    }
                    TextField(String(localized: "Importo in corone (ISK)"), value: $amount, format: .number)
                        .keyboardType(.numberPad)
                } header: { Text(entry.name).pinnedHeader() } footer: {
                    Text("Scrivi il prezzo pieno di un passaggio o di un giorno, in corone islandesi, come l'hai pagato. La segnalazione è anonima: una al giorno per questo luogo.")
                }
                if let error {
                    Section { Text(error).font(.app(.caption)).foregroundStyle(Theme.danger) }
                }
                Section {
                    Button {
                        send()
                    } label: {
                        if sending { ProgressView() } else { Label("Invia segnalazione", systemImage: "paperplane.fill") }
                    }
                    .disabled(sending || (amount ?? 0) <= 0 || cls.isEmpty)
                }
            }
            .navigationTitle("Segnala il prezzo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
            .onAppear {
                if cls.isEmpty {
                    cls = TollVehicle.current.classes.first(where: { classes.contains($0) }) ?? classes.first ?? ""
                }
            }
        }
    }

    private func send() {
        guard let amount else { return }
        sending = true
        error = nil
        Task {
            do {
                try await Tolls.report(entry: entry, cls: cls, isk: amount)
                Haptics.result(true)
                onSent()
                dismiss()
            } catch {
                self.error = error.localizedDescription
                Haptics.result(false)
            }
            sending = false
        }
    }
}

/// In an alert about a toll: pay, and the full card.
struct TollAlertLinks: View {
    @Environment(AppModel.self) private var model
    let event: AlertEvent

    var body: some View {
        let id = TollWatch.entryID(of: event)
        if let entry = model.tolls?.value.first(where: { $0.id == id }) {
            if let url = entry.payURL {
                Link(destination: url) { Label(String(localized: "Paga online"), systemImage: "creditcard") }
            }
            NavigationLink { List { TollDetailSections(entry: entry) }.themedList().navigationTitle(entry.name) } label: {
                Label(String(localized: "Prezzi, pagamento e fonte: \(entry.name)"), systemImage: entry.symbol)
            }
        }
        NavigationLink { TollsView() } label: { Label("Pedaggi e parcheggi", systemImage: "eurosign.circle") }
    }
}

// MARK: - Trip

/// The "€" next to a drive that passes a toll or arrives at paid parking.
struct TollBadge: View {
    var body: some View {
        Text(verbatim: "€")
            .font(.mono(10.5, .bold))
            .foregroundStyle(.black)
            .frame(width: 18, height: 18)
            .background(Circle().fill(Color.yellow))
            .accessibilityLabel(String(localized: "Pedaggi o parcheggi a pagamento"))
    }
}

/// Under a leg in the stop: the tolls on the way and the paid parking there.
struct TollChargeLines: View {
    let charges: [TollCharge]

    var body: some View {
        ForEach(charges) { charge in
            NavigationLink {
                List { TollDetailSections(entry: charge.entry) }
                    .themedList()
                    .navigationTitle(charge.entry.name)
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TollBadge()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(charge.atStop ? String(localized: "Parcheggio a pagamento: \(charge.entry.name)") : String(localized: "\(charge.entry.kindLabel): \(charge.entry.name)"))
                            .font(.app(.caption, .semibold)).foregroundStyle(Theme.text)
                        if let price = charge.price, charge.entry.price() == nil {
                            Text("≈ \(price.iskText) \(price.unitLabel) · segnalato dai viaggiatori").font(.app(.caption2)).foregroundStyle(Theme.dim)
                        } else if let price = charge.price {
                            Text("≈ \(price.iskText) \(price.unitLabel)").font(.app(.caption2)).foregroundStyle(Theme.dim)
                        } else {
                            Text("A pagamento: verifica il prezzo sul posto").font(.app(.caption2)).foregroundStyle(Theme.caution)
                        }
                    }
                }
            }
        }
    }
}

/// Trip › summary: what tolls and paid parking the whole trip costs, in króna
/// and in the currencies chosen in Settings.
struct TripTollsSummary: View {
    @Environment(AppModel.self) private var model
    @Environment(TripStore.self) private var trip

    var body: some View {
        let byStop = TripTolls.charges(stops: trip.stops, entries: model.tolls?.value ?? [])
        if Entitlements.shared.shows(.tolls), !byStop.isEmpty {
            let all = byStop.flatMap(\.charges)
            let total = TripTolls.total(all)
            NavigationLink { TripTollsList() } label: {
                HStack(spacing: 10) {
                    TollBadge()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Costi stradali del viaggio").font(.mono(10.5, .semibold)).foregroundStyle(Theme.dim)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("≈ \(Fmt.number(total.isk)) ISK").font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text)
                            if let other = Tolls.converted(total.isk, rates: model.rates?.value) {
                                Text(other).font(.mono(10.5)).foregroundStyle(Theme.dim)
                            }
                        }
                        Text(total.unpriced > 0
                             ? String(localized: "\(all.count) tra pedaggi e parcheggi, \(total.unpriced) senza prezzo")
                             : String(localized: "\(all.count) tra pedaggi e parcheggi"))
                            .font(.app(.caption2)).foregroundStyle(Theme.dim)
                    }
                }
            }
            .task { await model.loadRates() }
        }
    }
}

struct TripTollsList: View {
    @Environment(AppModel.self) private var model
    @Environment(TripStore.self) private var trip

    var body: some View {
        let byStop = TripTolls.charges(stops: trip.stops, entries: model.tolls?.value ?? [])
        let all = byStop.flatMap(\.charges)
        let total = TripTolls.total(all)
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("≈ \(Fmt.number(total.isk)) ISK").font(.metric(30, .semibold)).foregroundStyle(Theme.text)
                    if let other = Tolls.converted(total.isk, rates: model.rates?.value) {
                        Text(other).font(.mono(12)).foregroundStyle(Theme.dim)
                    }
                    Text(TollVehicle.current.label).font(.app(.caption)).foregroundStyle(Theme.dim)
                    if total.unpriced > 0 {
                        Text("\(total.unpriced) senza prezzo ufficiale: non sono nel totale.").font(.app(.caption)).foregroundStyle(Theme.caution)
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                Text("Un passaggio per ogni pedaggio sul tragitto tra le tappe (secondo il percorso di Apple Mappe) e un giorno di sosta per ogni parcheggio a pagamento alla tappa o alle sue attrazioni. Non comprende la tassa per chilometro (kílómetragjald), che per le auto a noleggio paga il noleggiatore.")
            }
            ForEach(byStop) { item in
                Section {
                    TollChargeLines(charges: item.charges)
                } header: { Text("\(item.stop.place.name) · \(Fmt.day(item.stop.date, in: .iceland))").pinnedHeader() }
            }
            Section {
                TollDisclaimer(date: model.tolls?.value.compactMap(\.verifiedDate).max())
                NavigationLink { TollsView() } label: { Label("Tutti i pedaggi e i parcheggi", systemImage: "eurosign.circle") }
            }
        }
        .themedList()
        .navigationTitle("Costi stradali")
        .navigationBarTitleDisplayMode(.inline)
    }
}
