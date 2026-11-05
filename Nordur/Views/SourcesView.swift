import SwiftUI

/// "Where the data comes from": the order of reliability the app follows and,
/// section by section, which source each screen uses. For the traveller, not a
/// diagnosis (that is Settings › Sources and data status).
struct SourcesView: View {
    private struct Row: Identifiable {
        let section: String
        let what: String
        let source: String
        var id: String { section }
    }

    private var rows: [Row] {
        [
            Row(section: String(localized: "Oggi"), what: String(localized: "Condizioni adesso, prossime ore"),
                source: String(localized: "Adesso: misura della stazione vedur.is più vicina. Prossime ore: previsione vedur.is; raffiche e probabilità di pioggia dal modello.")),
            Row(section: String(localized: "Meteo"), what: String(localized: "Previsione a 10 giorni, testo del meteorologo"),
                source: String(localized: "Previsione vedur.is per tutto il suo orizzonte (circa 9 giorni), poi il modello. Testo: i meteorologi di vedur.is.")),
            Row(section: String(localized: "Mappa meteo"), what: String(localized: "Vento, raffiche, pioggia, neve, nuvole, temperatura"),
                source: String(localized: "Costruita dalle 244 stazioni vedur.is (adesso: misure ogni 10 minuti; poi: previsione). Il modello dà solo la forma tra una stazione e l'altra e copre le zone velate, dove nessuna stazione arriva.")),
            Row(section: String(localized: "Radar"), what: String(localized: "Pioggia delle ultime 2 ore"),
                source: String(localized: "RainViewer, mosaico dei radar (compresi quelli islandesi).")),
            Row(section: String(localized: "Viaggio"), what: String(localized: "Meteo delle tappe e lungo il percorso, avvisi di vento"),
                source: String(localized: "Stessa regola di Meteo, per ogni tappa e ogni punto del percorso.")),
            Row(section: String(localized: "Allerte"), what: String(localized: "Allerte gialle, arancioni, rosse"),
                source: String(localized: "vedur.is.")),
            Row(section: String(localized: "Vulcani e terremoti"), what: String(localized: "Scosse, stato dei vulcani, bollettino"),
                source: String(localized: "vedur.is.")),
            Row(section: String(localized: "Strade"), what: String(localized: "Condizioni, chiusure, stazioni stradali, webcam"),
                source: String(localized: "Vegagerðin (umferdin.is).")),
            Row(section: String(localized: "Pedaggi e parcheggi"), what: String(localized: "Prezzi"),
                source: String(localized: "Fonti ufficiali indicate per ogni voce, più le segnalazioni di chi usa l'app.")),
            Row(section: String(localized: "Avvisi di viaggio"), what: String(localized: "Notizie per chi viaggia"),
                source: String(localized: "SafeTravel.is.")),
            Row(section: String(localized: "Aurora"), what: String(localized: "Probabilità, Kp, vento solare"),
                source: String(localized: "NOAA, GFZ, NASA; nuvole dalla previsione meteo.")),
            Row(section: String(localized: "Luoghi"), what: String(localized: "Distributori, negozi, attrazioni, piscine"),
                source: String(localized: "Distributori e prezzi: Gasvaktin (le compagnie). Altri distributori, colonnine, negozi, attrazioni: OpenStreetMap.")),
            Row(section: String(localized: "Trasporti"), what: String(localized: "Voli KEF, traghetti"),
                source: String(localized: "Isavia, Herjólfur.")),
            Row(section: String(localized: "Widget e Live Activity"), what: String(localized: "Sintesi"),
                source: String(localized: "Stessa regola di Meteo.")),
        ]
    }

    var body: some View {
        List {
            Section {
                order(.measured, String(localized: "Misurato da una stazione vedur.is"),
                      String(localized: "Il dato più affidabile: quello che una stazione ha registrato negli ultimi 10–60 minuti."))
                order(.official, String(localized: "Previsto da vedur.is"),
                      String(localized: "La previsione ufficiale della stazione vicina e alla stessa quota del luogo, per circa 9 giorni."))
                order(.model, String(localized: "Modello"),
                      String(localized: "MET Norway (lo stesso di yr.no) e Open-Meteo: solo per ciò che vedur.is non dà (raffiche previste, probabilità di pioggia, neve in cm), dopo la fine della previsione vedur.is o dove nessuna stazione è adatta."))
            } header: { Text("In ordine di affidabilità").pinnedHeader() } footer: {
                Text("Ogni dato meteo dell'app porta uno di questi tre bollini. Una fonte più in basso non sostituisce mai un valore di una più in alto.")
            }

            Section {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.section).font(.app(.subheadline, .semibold))
                        Text(row.what).font(.app(.caption)).foregroundStyle(.secondary)
                        Text(row.source).font(.app(.caption)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            } header: { Text("Sezione per sezione").pinnedHeader() }

            Section {
                Text("vedur.is è il sito di Veðurstofa Íslands, l'istituto meteorologico islandese (in inglese Icelandic Met Office, IMO). Nell'app è sempre chiamato vedur.is.")
                    .font(.app(.caption)).foregroundStyle(Theme.text)
                Text("I dati sono aggiornati appena vedur.is pubblica: previsioni nuove circa ogni 3 ore, misure ogni 10 minuti, testi più volte al giorno.")
                    .font(.app(.caption)).foregroundStyle(.secondary)
                LinkRow(title: String(localized: "vedur.is"), subtitle: nil, url: "https://en.vedur.is/")
            } header: { Text("vedur.is").pinnedHeader() }
        }
        .navigationTitle(String(localized: "Da dove vengono i dati"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func order(_ origin: DataOrigin, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SourceBadge(origin: origin)
            Text(title).font(.app(.subheadline, .semibold))
            Text(text).font(.app(.caption)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
