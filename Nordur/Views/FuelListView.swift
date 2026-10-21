import SwiftUI

/// The pumps around a place with their price now, cheapest first (or nearest):
/// compare at a glance, open one for its hours and directions.
struct FuelListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CurrencyDisplay.key) private var currency = CurrencyDisplay.both.rawValue
    @AppStorage("fuel.kind") private var fuelRaw = FuelKind.petrol.rawValue
    @AppStorage("fuel.byPrice") private var byPrice = true
    @State private var radiusKm = 50.0
    @State private var selected: FuelStation?
    var center: Place?
    /// Pushed inside another navigation stack (from a pump's sheet).
    var embedded = false

    var body: some View {
        let place = center ?? model.activePlace
        let fuel = FuelKind(rawValue: fuelRaw) ?? .petrol
        let display = CurrencyDisplay(rawValue: currency) ?? .both
        let rates = model.rates?.value
        let all = model.fuelPrices?.value ?? []
        let near = all.compactMap { p -> (price: FuelPrice, km: Double, value: Double)? in
            guard let value = p.price(fuel) else { return nil }
            let km = Geo.distanceKm(p.coordinate, place.coordinate)
            return km <= radiusKm ? (p, km, value) : nil
        }
        .sorted { byPrice ? ($0.value, $0.km) < ($1.value, $1.km) : $0.km < $1.km }
        let cheapest = near.map(\.value).min()
        let list = List {
                Section {
                    Picker("Carburante", selection: $fuelRaw) {
                        ForEach(FuelKind.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Ordina", selection: $byPrice) {
                        Text("Più economico").tag(true)
                        Text("Più vicino").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Stepper("Entro \(Int(radiusKm)) km", value: $radiusKm, in: 10...200, step: 10)
                }
                Section {
                    if model.fuelPrices == nil {
                        if let error = model.errors[.fuelPrices] { ErrorNote(message: error) } else { SkeletonRows(count: 5) }
                    } else if near.isEmpty {
                        EmptyState(symbol: "fuelpump", title: String(localized: "Nessun prezzo in questa zona"),
                                   message: String(localized: "Allarga la distanza: fuori dalle città i distributori sono pochi."))
                    } else {
                        ForEach(near, id: \.price.id) { item in
                            Button {
                                selected = model.fuel?.value.first { FuelPrices.match($0, in: [item.price]) != nil }
                                    ?? FuelStation(id: abs(item.price.key.hashValue), kind: .fuel, name: item.price.name,
                                                   brand: item.price.company, openingHours: nil, coordinate: item.price.coordinate)
                            } label: {
                                FuelListRow(price: item.price, km: item.km, value: item.value, fuel: fuel, cheapest: cheapest,
                                            level: FuelPrices.level(item.value, among: all, fuel: fuel), display: display, rates: rates)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text(String(localized: "\(fuel.label) vicino a \(place.name)")).pinnedHeader()
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let fetched = model.fuelPrices {
                            FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: "Gasvaktin")
                        }
                        Text("Verde: tra i più economici d'Islanda adesso; rosso: tra i più cari. «+N kr» è quanto costa in più al litro del più economico della lista.")
                    }
                }
            }
        .themedList()
        .navigationTitle("Prezzi carburante")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadFuelPrices() }
        .refreshable { await model.loadFuelPrices(force: true) }
        .sheet(item: $selected) { station in
            FuelDetail(station: station, from: place).presentationDetents([.medium, .large])
        }
        if embedded {
            list
        } else {
            NavigationStack {
                list.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
            }
        }
    }
}

private struct FuelListRow: View {
    let price: FuelPrice
    let km: Double
    let value: Double
    let fuel: FuelKind
    let cheapest: Double?
    let level: FuelPrices.Level
    let display: CurrencyDisplay
    let rates: ExchangeRates?

    var body: some View {
        let tint: Color = level == .cheap ? Theme.aurora : level == .dear ? Theme.danger : Theme.caution
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(tint).frame(width: 5, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(price.name).font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text("\(price.company) · \(Fmt.number(km, decimals: km < 10 ? 1 : 0)) km").font(.app(.caption)).foregroundStyle(Theme.dim)
                if let discount = price.discount(fuel), discount < value {
                    Text("Con sconto \(Fmt.number(discount, decimals: 1)) kr\(display.converted(discount, rates).map { " (\($0))" } ?? "")")
                        .font(.mono(10)).foregroundStyle(Theme.aurora)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Fmt.number(value, decimals: 1)) kr").font(.metric(20, .semibold)).foregroundStyle(tint)
                if let converted = display.converted(value, rates) {
                    Text(converted).font(.mono(10)).foregroundStyle(Theme.dim)
                }
                if let cheapest {
                    let more = value - cheapest
                    Text(more < 0.05 ? String(localized: "IL PIÙ ECONOMICO") : "+\(Fmt.number(more, decimals: 1)) kr")
                        .font(.mono(9.5, .semibold)).foregroundStyle(more < 0.05 ? Theme.aurora : Theme.dim)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
