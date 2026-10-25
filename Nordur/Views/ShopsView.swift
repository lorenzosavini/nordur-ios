import SwiftUI

extension Shop {
    /// "Aperto · chiude 19:00", "Chiuso · apre sab 10:00", or the raw OSM hours.
    func status(at now: Date = Date()) -> (text: String, open: Bool?) {
        guard let hours else {
            return (openingHours ?? String(localized: "Orari non indicati"), nil)
        }
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

/// Where to do the shopping around a place: supermarkets first, with whether
/// they are open now, the discount chains marked, and directions.
struct ShopsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Around this place (a trip stop); otherwise the place shown in the app.
    var center: Place?
    var inSheet = false

    @State private var kind: Shop.Kind?
    @State private var openNow = false
    @State private var query = ""
    @State private var selected: Shop?

    var body: some View {
        if inSheet {
            NavigationStack {
                list.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
            }
        } else {
            list
        }
    }

    private var list: some View {
        let place = center ?? model.activePlace
        let now = Date()
        let all = Shops.nearest(model.shops?.value ?? [], to: place.coordinate, kinds: kind.map { Set([$0]) } ?? Set(Shop.Kind.allCases), within: 250)
        let shown = all.filter { item in
            (query.isEmpty || item.shop.name.localizedCaseInsensitiveContains(query) || (item.shop.town ?? "").localizedCaseInsensitiveContains(query))
                && (!openNow || item.shop.status(at: now).open == true)
        }.prefix(80)
        return List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip(String(localized: "Tutti"), symbol: "square.grid.2x2", selected: kind == nil) { kind = nil }
                        ForEach(Shop.Kind.allCases) { k in
                            chip(k.label, symbol: k.symbol, selected: kind == k) { kind = kind == k ? nil : k }
                        }
                    }
                }
                Toggle("Solo aperti adesso", isOn: $openNow).tint(Theme.accent)
            }
            Section {
                if model.shops == nil {
                    if let error = model.errors[.shops] { ErrorNote(message: error) } else { SkeletonRows(count: 5) }
                } else if shown.isEmpty {
                    EmptyState(symbol: "cart", title: String(localized: "Nessun negozio trovato"),
                               message: openNow ? String(localized: "Prova a togliere \"Solo aperti adesso\".") : nil)
                } else {
                    ForEach(Array(shown)) { item in
                        Button { selected = item.shop } label: { ShopRow(shop: item.shop, km: item.km, now: now) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("shop.row")
                    }
                }
            } header: {
                Text(String(localized: "Vicino a \(place.name)")).pinnedHeader()
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bónus, Krónan e Nettó sono i supermercati più economici; i minimarket e i negozi dei distributori (N1, Olís, Orkan) costano di più ma sono spesso aperti fino a tardi.")
                    Text("Vino, birra forte e superalcolici si comprano solo da Vínbúðin, con orari ridotti (spesso chiusa la domenica). Nei supermercati c'è solo birra leggera.")
                    Text("Fuori dalle città i negozi sono pochi e chiudono presto: fai scorta prima delle tappe lunghe. Orari da OpenStreetMap, verifica nei giorni festivi.")
                    if let shops = model.shops {
                        FreshnessLabel(date: shops.date, isStale: shops.isStale, source: String(localized: "OpenStreetMap"))
                    }
                }
            }
        }
        .themedList()
        .navigationTitle("Spesa e negozi")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: String(localized: "Bónus, Krónan, città…"))
        .task { await model.loadShops() }
        .refreshable { await model.loadShops(force: true) }
        .sheet(item: $selected) { shop in
            ShopDetail(shop: shop, from: place).presentationDetents([.medium, .large])
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

struct ShopRow: View {
    let shop: Shop
    let km: Double?
    var now = Date()

    var body: some View {
        let status = shop.status(at: now)
        HStack(alignment: .top, spacing: 12) {
            KindIcon(name: shop.kind.imageName, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(shop.name).font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    if shop.isBudget {
                        Text("ECONOMICO").font(.mono(8.5, .semibold)).foregroundStyle(Theme.aurora)
                            .padding(.horizontal, 4).overlay(Rectangle().strokeBorder(Theme.aurora.opacity(0.6)))
                    }
                    Spacer()
                    if let km {
                        Text("\(Fmt.number(km, decimals: km < 10 ? 1 : 0)) km").font(.mono(10.5, .semibold)).foregroundStyle(Theme.dim)
                    }
                }
                Text([shop.kind.label, shop.town].compactMap { $0 }.joined(separator: " · "))
                    .font(.app(.caption)).foregroundStyle(Theme.dim)
                Text(status.text).font(.app(.caption, .semibold))
                    .foregroundStyle(status.open == true ? Theme.aurora : status.open == false ? Theme.danger : Theme.faint)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

struct ShopDetail: View {
    let shop: Shop
    let from: Place
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let c = shop.coordinate
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        KindIcon(name: shop.kind.imageName, size: 72)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(shop.kind.label.uppercased()).font(.mono(11, .semibold)).foregroundStyle(Theme.accent)
                            Text(shop.name).font(.display(28, .bold)).foregroundStyle(Theme.text).lineLimit(2).minimumScaleFactor(0.7)
                        }
                    }
                    .padding(.vertical, 6)
                    ShopRow(shop: shop, km: Geo.distanceKm(from.coordinate, c))
                }
                if let raw = shop.openingHours {
                    Section {
                        Text(raw.replacingOccurrences(of: "; ", with: "\n")).font(.mono(12)).foregroundStyle(Theme.text)
                    } header: { Text("Orari (OpenStreetMap)").pinnedHeader() }
                }
                Section {
                    DirectionsRows(to: c)
                }
            }
            .themedList()
            .navigationTitle(shop.kind.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
        }
    }
}

extension FuelStation {
    var imageName: String { kind == .charger ? "kind-charger" : "kind-fuel" }
    var hours: OpeningHours? { openingHours.flatMap(OpeningHours.init) }

    /// Open now / closes at… from the OSM hours, like the shops.
    func status(at now: Date = Date()) -> (text: String, open: Bool?) {
        guard let hours else { return (openingHours ?? String(localized: "Orari non indicati (spesso self-service 24 h con carta)"), nil) }
        let open = hours.isOpen(at: now)
        let next = hours.nextChange(after: now)
        if open {
            guard let next else { return (String(localized: "Aperto 24 ore"), true) }
            return (String(localized: "Aperto · chiude alle \(Fmt.time(next, in: .iceland))"), true)
        }
        guard let next else { return (String(localized: "Chiuso"), false) }
        return (Calendar.iceland.isDate(next, inSameDayAs: now) ? String(localized: "Chiuso · apre alle \(Fmt.time(next, in: .iceland))")
                                                                : String(localized: "Chiuso · apre \(Fmt.dayTime(next, in: .iceland))"), false)
    }
}

/// A fuel station or charger: brand, open now, the hours, directions.
struct FuelDetail: View {
    let station: FuelStation
    let from: Place
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @AppStorage(CurrencyDisplay.key) private var currency = CurrencyDisplay.both.rawValue

    var body: some View {
        let status = station.status()
        let km = Geo.distanceKm(from.coordinate, station.coordinate)
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        KindIcon(name: station.imageName, size: 72)
                        VStack(alignment: .leading, spacing: 4) {
                            Text((station.kind == .charger ? String(localized: "Ricarica auto elettriche") : String(localized: "Distributore")).uppercased())
                                .font(.mono(11, .semibold)).foregroundStyle(Theme.accent)
                            Text(station.name).font(.display(28, .bold)).foregroundStyle(Theme.text).lineLimit(2).minimumScaleFactor(0.7)
                            if let brand = station.brand, brand != station.name {
                                Text(brand).font(.app(.subheadline)).foregroundStyle(Theme.dim)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    Label(String(localized: "\(Fmt.number(km, decimals: km < 10 ? 1 : 0)) km da \(from.name)"), systemImage: "location")
                        .font(.app(.subheadline)).foregroundStyle(Theme.dim)
                    Text(status.text).font(.app(.headline))
                        .foregroundStyle(status.open == true ? Theme.aurora : status.open == false ? Theme.danger : Theme.dim)
                }
                if station.kind == .fuel { prices }
                if let raw = station.openingHours {
                    Section {
                        Text(raw.replacingOccurrences(of: "; ", with: "\n")).font(.mono(13)).foregroundStyle(Theme.text)
                    } header: { Text("Orari (OpenStreetMap)").pinnedHeader() }
                }
                Section {
                    Text(station.kind == .charger
                         ? String(localized: "In Islanda le colonnine veloci sono soprattutto di ON, Ísorka e N1: serve spesso l'app o la tessera dell'operatore.")
                         : String(localized: "Fuori città molti distributori sono solo self-service: si paga alla colonnina con carta e PIN (o carta prepagata N1/Olís). Fai il pieno prima delle tratte lunghe."))
                        .font(.app(.subheadline)).foregroundStyle(Theme.dim)
                }
                Section { DirectionsRows(to: station.coordinate) }
            }
            .themedList()
            .task {
                // Opening a pump: prices older than 5 minutes are fetched again.
                if let fetched = model.fuelPrices, Date().timeIntervalSince(fetched.date) < 300, !fetched.isStale { return }
                await model.loadFuelPrices(force: true)
            }
            .refreshable { await model.loadFuelPrices(force: true) }
            .navigationTitle(station.kind == .charger ? String(localized: "Ricarica") : String(localized: "Carburante"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
        }
    }
}

extension FuelDetail {
    /// Prices at this pump now, in króna and the other currency chosen, and the
    /// cheapest pump around.
    @ViewBuilder var prices: some View {
        let all = model.fuelPrices?.value ?? []
        let display = CurrencyDisplay(rawValue: currency) ?? .both
        let rates = model.rates?.value
        Section {
            if let price = FuelPrices.match(station, in: all) {
                ForEach(FuelKind.allCases) { fuel in
                    if let value = price.price(fuel) {
                        FuelPriceRow(label: fuel.label, isk: value, discount: price.discount(fuel), display: display, rates: rates)
                    }
                }
                if price.name != station.name {
                    Text(String(localized: "Prezzi di \(price.company) \(price.name)")).font(.app(.caption)).foregroundStyle(Theme.dim)
                }
            } else if model.fuelPrices == nil {
                Text(model.errors[.fuelPrices] == nil ? String(localized: "Prezzi in arrivo…") : String(localized: "Prezzi non disponibili"))
                    .font(.app(.subheadline)).foregroundStyle(Theme.dim)
            } else {
                Text("Nessun prezzo pubblicato per questo distributore.").font(.app(.subheadline)).foregroundStyle(Theme.dim)
            }
            NavigationLink { FuelListView(center: Place(name: station.name, coordinate: station.coordinate), embedded: true) } label: {
                Label("Confronta i prezzi nei dintorni", systemImage: "list.number")
            }
            if let best = FuelPrices.cheapest(all, near: station.coordinate, fuel: .petrol), let value = best.price.price(.petrol) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Il più economico entro 30 km").font(.app(.caption, .semibold)).foregroundStyle(Theme.aurora)
                    Text("\(best.price.company) \(best.price.name) · \(Fmt.number(value, decimals: 1)) kr/l · \(Fmt.number(best.km, decimals: best.km < 10 ? 1 : 0)) km")
                        .font(.app(.subheadline)).foregroundStyle(Theme.text)
                    Link(destination: Directions.apple(to: best.price.coordinate)) {
                        Label("Indicazioni", systemImage: "arrow.triangle.turn.up.right.diamond")
                    }
                    .font(.app(.caption, .semibold))
                }
            }
        } header: {
            Text("Prezzi adesso").pinnedHeader()
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let fetched = model.fuelPrices {
                    FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: "Gasvaktin")
                }
                Text("Prezzo alla pompa self-service al litro. «Con sconto»: con la carta o l'app della compagnia. Cambio del \(rates?.date ?? "–") (\(rates?.source ?? "–")).")
            }
        }
    }
}

private struct FuelPriceRow: View {
    let label: String
    let isk: Double
    let discount: Double?
    let display: CurrencyDisplay
    let rates: ExchangeRates?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.app(.subheadline)).foregroundStyle(Theme.text)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Fmt.number(isk, decimals: 1)) kr/l").font(.metric(22, .semibold)).foregroundStyle(Theme.text)
                if let converted = display.converted(isk, rates) {
                    Text(converted).font(.mono(11)).foregroundStyle(Theme.dim)
                }
                if let discount, discount < isk {
                    Text("Con sconto \(Fmt.number(discount, decimals: 1)) kr").font(.mono(11)).foregroundStyle(Theme.aurora)
                    if let converted = display.converted(discount, rates) {
                        Text(converted).font(.mono(10)).foregroundStyle(Theme.aurora.opacity(0.8))
                    }
                }
            }
        }
    }
}

