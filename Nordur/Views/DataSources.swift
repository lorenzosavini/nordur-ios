import SwiftUI

/// "How is this worked out?": a small link next to a figure that opens a short
/// explanation in a bubble, instead of long method sections on the page.
struct InfoTip: View {
    let title: String
    let text: String
    var label: String = String(localized: "Come si calcola")
    @State private var shown = false

    var body: some View {
        Button { shown = true } label: {
            Label(label, systemImage: "info.circle")
                .font(.mono(10.5, .semibold)).foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $shown) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased()).font(.mono(11, .semibold)).foregroundStyle(Theme.accent)
                Text(text).font(.app(.subheadline)).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(idealWidth: 330, maxWidth: 360)
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// Settings › Sources and data status: every feed of the app with when it was
/// last had, the aurora sources as the backend reports them, and how well the
/// Kp forecasts did. Kept off the screens that show the data.
struct DataSourcesView: View {
    @Environment(AppModel.self) private var model
    @State private var backtest: BacktestResponse?

    var body: some View {
        let state = model.aurora?.value
        List {
            Section {
                ForEach(AppModel.Source.allCases, id: \.self) { source in
                    let f = model.freshness(source)
                    let error = model.errors[source]
                    HStack(spacing: 10) {
                        Circle().fill(error != nil ? Theme.danger : f == nil ? Theme.faint : f!.stale ? Theme.caution : Theme.aurora)
                            .frame(width: 9, height: 9)
                        Text(source.rawValue.loc).font(.app(.subheadline)).foregroundStyle(Theme.text)
                        Spacer()
                        Text(f.map { $0.stale ? String(localized: "copia del \(Fmt.dayTime($0.date))") : Fmt.relative($0.date) }
                             ?? (error != nil ? String(localized: "errore")
                                : [.flights, .ferry, .grid, .radar].contains(source) ? String(localized: "quando apri la sezione")
                                : String(localized: "non ancora caricato")))
                            .font(.mono(11)).foregroundStyle(error != nil ? Theme.danger : Theme.dim).lineLimit(1)
                    }
                }
            } header: { Text("Dati dell'app").pinnedHeader() } footer: {
                Text("Verde: aggiornato. Giallo: copia salvata sul telefono (senza rete o fonte lenta). Rosso: ultimo tentativo fallito.")
            }

            Section {
                if let sources = state?.sources {
                    ForEach(sources.keys.sorted(), id: \.self) { key in
                        let s = sources[key]!
                        HStack(spacing: 10) {
                            Circle().fill(s.status == "ok" ? Theme.aurora : s.status == "stale" ? Theme.caution : Theme.danger).frame(width: 9, height: 9)
                            Text(Self.auroraSourceName(key)).font(.app(.subheadline)).foregroundStyle(Theme.text)
                            Spacer()
                            Text([s.provider, s.ageMinutes.map { String(localized: "\(Int($0)) min") }, s.status == "ok" ? nil : s.status == "stale" ? String(localized: "copia salvata") : String(localized: "non risponde")].compactMap { $0 }.joined(separator: " · "))
                                .font(.mono(11)).foregroundStyle(s.status == "ok" ? Theme.dim : Theme.warning).lineLimit(1)
                        }
                    }
                } else {
                    ErrorNote(message: model.errors[.aurora] ?? String(localized: "Stato delle fonti non disponibile"))
                }
            } header: { Text("Aurora: fonti scientifiche").pinnedHeader() } footer: {
                Text("Giallo: la fonte non ha risposto e si usa la sua ultima copia buona. Rosso: non risponde e non c'è una copia; il problema è della fonte, e il resto (Kp, previsioni) viene comunque da NOAA.")
            }

            Section {
                if let bt = backtest {
                    if bt.sufficient {
                        ForEach(bt.buckets.keys.sorted(), id: \.self) { key in
                            if let b = bt.buckets[key], let n = b.blend.n, n > 0 {
                                Text("\(key): errore medio NOAA \(Fmt.number(b.noaa.mae, decimals: 2)), combinato \(Fmt.number(b.blend.mae, decimals: 2)) (n = \(n))")
                                    .font(.mono(11)).foregroundStyle(Theme.dim)
                            }
                        }
                    } else {
                        Text(bt.note ?? String(localized: "Dati insufficienti")).font(.app(.caption)).foregroundStyle(Theme.dim)
                    }
                } else {
                    SkeletonRows(count: 2)
                }
            } header: { Text("Verifica delle previsioni Kp").pinnedHeader() } footer: {
                Text("Ogni previsione Kp viene confrontata con il Kp misurato poi da GFZ Potsdam: l'errore medio dice quanto ci si può fidare a ogni orizzonte.")
            }

            Section {
                Text(Self.method).font(.app(.subheadline)).foregroundStyle(Theme.dim)
            } header: { Text("Metodo dell'aurora").pinnedHeader() }
        }
        .themedList()
        .navigationTitle("Fonti e stato dei dati")
        .navigationBarTitleDisplayMode(.inline)
        .task { backtest = try? await BacktestResponse.load() }
        .refreshable { await model.refreshAll() }
    }

    static let method = String(localized: "L'indice di osservabilità è una stima euristica trasparente, non una probabilità: moltiplica attività prevista (OVATION entro la sua validità, poi Kp e posizione dell'ovale su latitudine geomagnetica), cielo sereno per strati, buio (altezza del Sole), Luna (fase e altezza) e le luci artificiali misurate dal satellite VIIRS (NASA Black Marble, media annuale) pesate con la distanza, e l'orizzonte del terreno. Le percentuali di probabilità richiedono un modello calibrato su osservazioni reali: le segnalazioni degli utenti servono a costruirlo.")

    static func auroraSourceName(_ key: String) -> String {
        [
            "kpForecast": String(localized: "Kp previsto NOAA"), "kpEstimated": String(localized: "Kp stimato NOAA (1 min)"), "kpGFZ": String(localized: "Kp GFZ Potsdam"),
            "solarWind": String(localized: "Vento solare RTSW"), "ovation": String(localized: "OVATION Prime"), "enlil": String(localized: "WSA-ENLIL NOAA"), "scales": String(localized: "Scale NOAA"),
            "alerts": String(localized: "Avvisi NOAA"), "hemisphericPower": String(localized: "Potenza emisferica"), "hp30": String(localized: "Hp30 GFZ"), "magnetometer": String(localized: "Magnetometro Narsarsuaq"), "outlook27": String(localized: "Tendenza 27 giorni"),
            "forecast45": String(localized: "Previsione 45 giorni"), "donki": String(localized: "NASA DONKI"),
        ][key] ?? key
    }
}
