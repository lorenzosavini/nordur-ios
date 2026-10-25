import SwiftUI

/// Settings › Unità di misura › Valute: up to three currencies of the world the
/// prices in króna are also shown in, searchable by name or code.
struct CurrencyChoiceView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(CurrencyDisplay.key) private var stored = CurrencyDisplay.both.rawValue
    @State private var query = ""

    var body: some View {
        let chosen = (CurrencyDisplay(rawValue: stored) ?? .both).codes
        let codes = ExchangeRates.codes(model.rates?.value).filter { code in
            query.isEmpty || code.localizedCaseInsensitiveContains(query) || ExchangeRates.name(code).localizedCaseInsensitiveContains(query)
        }
        List {
            if query.isEmpty {
                Section {
                    if chosen.isEmpty {
                        Text("Solo corone").foregroundStyle(Theme.dim)
                    }
                    ForEach(chosen, id: \.self) { code in
                        row(code, selected: true, chosen: chosen)
                    }
                } header: { Text("Mostrate accanto alle corone").pinnedHeader() } footer: {
                    Text("Fino a \(CurrencyDisplay.limit) valute. Tocca per togliere o aggiungere.")
                }
            }
            Section {
                ForEach(codes.filter { !chosen.contains($0) }, id: \.self) { code in
                    row(code, selected: false, chosen: chosen)
                }
            } header: { Text("Tutte le valute").pinnedHeader() }
        }
        .themedList()
        .searchable(text: $query, prompt: Text("Cerca valuta o codice"))
        .navigationTitle(String(localized: "Valute"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadRates() }
    }

    private func row(_ code: String, selected: Bool, chosen: [String]) -> some View {
        Button {
            var codes = chosen
            if selected { codes.removeAll { $0 == code } } else if codes.count < CurrencyDisplay.limit { codes.append(code) } else { return }
            stored = CurrencyDisplay(codes: codes).rawValue
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ExchangeRates.name(code)).foregroundStyle(Theme.text)
                    if let rates = model.rates?.value, let value = rates.convert(1000, from: "ISK", to: code) {
                        Text("1.000 kr ≈ \(ExchangeRates.format(value, code))").font(.mono(11)).foregroundStyle(Theme.dim)
                    }
                }
                Spacer()
                Text(code).font(.mono(12, .semibold)).foregroundStyle(Theme.dim)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Theme.accent : Theme.faint)
            }
        }
        .disabled(!selected && chosen.count >= CurrencyDisplay.limit)
    }
}

/// Converter between any two currencies of the world (króna first), with the
/// day's rates.
struct CurrencyConverterView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("currency.converter.from") private var from = "ISK"
    @AppStorage("currency.converter.to") private var to = "EUR"
    @State private var amount: Double? = 1000
    @FocusState private var editing: Bool

    var body: some View { ProGate(feature: .currencyConverter) { content } }

    @ViewBuilder private var content: some View {
        let rates = model.rates?.value
        let codes = ["ISK"] + ExchangeRates.codes(rates)
        List {
            Section {
                TextField(String(localized: "Importo"), value: $amount, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .font(.metric(34, .semibold))
                    .focused($editing)
                picker(String(localized: "Da"), selection: $from, codes: codes)
                Button {
                    (from, to) = (to, from)
                } label: {
                    Label("Inverti", systemImage: "arrow.up.arrow.down")
                }
                picker(String(localized: "A"), selection: $to, codes: codes)
            }
            Section {
                if let rates, let amount, let result = rates.convert(amount, from: from, to: to) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ExchangeRates.format(amount, from)).font(.app(.subheadline)).foregroundStyle(Theme.dim)
                        Text(ExchangeRates.format(result, to, decimals: result < 1 ? 4 : 2))
                            .font(.metric(40, .semibold)).foregroundStyle(Theme.text)
                            .lineLimit(1).minimumScaleFactor(0.5)
                        if let one = rates.convert(1, from: from, to: to) {
                            Text("1 \(from) = \(ExchangeRates.format(one, to, decimals: one < 1 ? 4 : 2))").font(.mono(11)).foregroundStyle(Theme.dim)
                        }
                    }
                    .padding(.vertical, 4)
                } else if rates == nil {
                    Text(model.errors[.rates] == nil ? String(localized: "Cambi in arrivo…") : String(localized: "Cambi non disponibili"))
                        .foregroundStyle(Theme.dim)
                } else {
                    Text("Nessun cambio per questa valuta.").foregroundStyle(Theme.dim)
                }
            } footer: {
                if let rates {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cambio del \(rates.date) (\(rates.source ?? "–")), indicativo: banche e carte applicano commissioni.")
                        if rates.source == "ExchangeRate-API" {
                            Link("Rates By Exchange Rate API", destination: URL(string: "https://www.exchangerate-api.com")!)
                        }
                    }
                }
            }
        }
        .themedList()
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fine") { editing = false }
            }
        }
        .navigationTitle(String(localized: "Convertitore valute"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadRates() }
    }

    private func picker(_ title: String, selection: Binding<String>, codes: [String]) -> some View {
        Picker(title, selection: selection) {
            ForEach(codes, id: \.self) { code in
                Text("\(code == "ISK" ? String(localized: "Corona islandese") : ExchangeRates.name(code)) (\(code))").tag(code)
            }
        }
        .pickerStyle(.navigationLink)
    }
}
