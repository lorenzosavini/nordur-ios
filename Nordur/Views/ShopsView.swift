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
            Image(systemName: shop.kind.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 30, height: 30)
                .background(shop.kind == .alcohol ? Theme.dim : Theme.accent)
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
        let name = shop.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        NavigationStack {
            List {
                Section {
                    ShopRow(shop: shop, km: Geo.distanceKm(from.coordinate, c))
                }
                if let raw = shop.openingHours {
                    Section {
                        Text(raw.replacingOccurrences(of: "; ", with: "\n")).font(.mono(12)).foregroundStyle(Theme.text)
                    } header: { Text("Orari (OpenStreetMap)").pinnedHeader() }
                }
                Section {
                    if let url = URL(string: "http://maps.apple.com/?daddr=\(c.lat),\(c.lon)&q=\(name)") {
                        Link(destination: url) { Label("Indicazioni in Mappe", systemImage: "arrow.triangle.turn.up.right.diamond") }
                    }
                    if let url = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(c.lat),\(c.lon)") {
                        Link(destination: url) { Label("Indicazioni in Google Maps", systemImage: "map") }
                    }
                }
            }
            .themedList()
            .navigationTitle(shop.kind.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
        }
    }
}
