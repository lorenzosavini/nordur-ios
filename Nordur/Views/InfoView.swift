import SwiftUI

struct InfoView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Pushed inside Settings (no own navigation stack or close button).
    var embedded = false

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack {
                content.toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } }
                }
            }
        }
    }

    private var content: some View {
            List {
                Section {
                    LinkRow(title: String(localized: "Emergenza: 112"), subtitle: String(localized: "Polizia, ambulanza, vigili del fuoco, soccorso alpino"), url: "tel:112", systemImage: "phone.fill")
                    LinkRow(title: String(localized: "Numero alternativo: 599-0112"), subtitle: String(localized: "Se il 112 non si connette (spegnimento reti 2G/3G)"), url: "tel:5990112", systemImage: "phone.badge.waveform.fill")
                    LinkRow(title: String(localized: "112.is – Centrale emergenze"), subtitle: String(localized: "Chat con il 112 e informazioni per i viaggiatori"), url: "https://www.112.is/en", systemImage: "sos")
                    LinkRow(title: String(localized: "Registra il piano di viaggio"), subtitle: String(localized: "SafeTravel – i soccorsi sapranno dove cercarti"), url: "https://safetravel.is/travel-plan", systemImage: "doc.text.fill")
                    LinkRow(title: String(localized: "Guardia medica 1700"), subtitle: String(localized: "Consulenza sanitaria non urgente"), url: "tel:1700", systemImage: "cross.case.fill")
                } header: {
                    Text("Sicurezza").pinnedHeader().pinnedHeader()
                }

                Section {
                    NavigationLink { AlertSettingsView() } label: { Label("Allerte e notifiche", systemImage: "bell.badge") }
                    NavigationLink { AlertsView() } label: { Label("Storico allerte", systemImage: "tray.full") }
                    NavigationLink { OfflineView() } label: { Label("Pacchetto offline", systemImage: "arrow.down.circle") }
                    NavigationLink { TransportView() } label: { Label("Voli KEF e traghetti", systemImage: "airplane.departure") }
                    NavigationLink { WebcamsView() } label: { Label("Webcam stradali", systemImage: "video") }
                    NavigationLink { RoadsView() } label: { Label("Condizioni delle strade", systemImage: "road.lanes") }
                    NavigationLink { QuakesView() } label: { Label("Terremoti e vulcani", systemImage: "waveform.path.ecg") }
                } header: { Text("Strumenti").pinnedHeader() }


                Section {
                    LinkRow(title: String(localized: "Vedur.is – Meteo ufficiale islandese"), subtitle: String(localized: "Previsioni, allerte, mappe del vento"), url: "https://en.vedur.is/")
                    LinkRow(title: String(localized: "Windy"), subtitle: String(localized: "Modelli a confronto, vento e raffiche"), url: "https://www.windy.com/?64.9,-18.6,6")
                    LinkRow(title: "Yr.no", subtitle: String(localized: "Previsioni norvegesi (MET Norway)"), url: "https://www.yr.no/en")
                    LinkRow(title: String(localized: "Blika.is"), subtitle: String(localized: "Previsioni islandesi dettagliate"), url: "https://blika.is/")
                } header: { Text("Meteo").pinnedHeader() }

                Section {
                    LinkRow(title: String(localized: "Umferdin.is"), subtitle: String(localized: "Mappa ufficiale di strade, chiusure e webcam"), url: "https://umferdin.is/en", systemImage: "map")
                    LinkRow(title: String(localized: "SafeTravel – condizioni"), subtitle: String(localized: "Avvisi e mappa delle condizioni"), url: "https://safetravel.is/", systemImage: "exclamationmark.shield")
                    LinkRow(title: String(localized: "Strade F (Highlands)"), subtitle: String(localized: "Date di apertura – solo 4x4, guadi"), url: "https://www.road.is/travel-info/highland-roads/", systemImage: "mountain.2")
                    LinkRow(title: String(localized: "Distributori e ricarica"), subtitle: String(localized: "Mappa di N1 / Orkan / Olís"), url: "https://www.n1.is/en/", systemImage: "fuelpump")
                } header: { Text("Strade").pinnedHeader() }

                Section {
                    LinkRow(title: String(localized: "Keflavík – arrivi e partenze"), subtitle: String(localized: "Isavia KEF"), url: "https://www.isavia.is/en/keflavik-airport", systemImage: "airplane")
                    LinkRow(title: String(localized: "Voli interni"), subtitle: String(localized: "Icelandair, Norlandair, Mýflug"), url: "https://www.icelandair.com/", systemImage: "airplane.circle")
                    LinkRow(title: String(localized: "Flybus / Airport Direct"), subtitle: String(localized: "Navette aeroporto ↔ Reykjavík"), url: "https://www.re.is/", systemImage: "bus")
                    LinkRow(title: String(localized: "Strætó – bus di linea"), subtitle: String(localized: "Reykjavík e lunga distanza"), url: "https://www.straeto.is/en", systemImage: "bus.fill")
                    LinkRow(title: String(localized: "Herjólfur"), subtitle: String(localized: "Traghetto per Vestmannaeyjar"), url: "https://www.herjolfur.is/en/", systemImage: "ferry")
                    LinkRow(title: String(localized: "Baldur (Sæferðir)"), subtitle: String(localized: "Traghetto Stykkishólmur – Brjánslækur"), url: "https://www.saeferdir.is/en/", systemImage: "ferry.fill")
                    LinkRow(title: String(localized: "Smyril Line"), subtitle: String(localized: "Traghetto Seyðisfjörður – Fær Øer – Danimarca"), url: "https://www.smyrilline.com/", systemImage: "ferry")
                } header: { Text("Voli, bus e traghetti").pinnedHeader() }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• Con vento forte apri la portiera tenendola con due mani: il vento può strapparla (danno non coperto dall'assicurazione).")
                        Text("• Fuoristrada vietato per legge. Le strade F richiedono un 4x4 e i guadi non sono coperti dall'assicurazione.")
                        Text("• Ponti a una corsia: ha la precedenza chi arriva prima.")
                        Text("• Fai rifornimento appena puoi nell'Est e nei fiordi occidentali: i distributori sono distanti.")
                        Text("• In inverno le giornate sono brevi: pianifica le tratte nelle ore di luce.")
                    }
                    .font(.app(.caption))
                } header: { Text("Consigli per guidare in Islanda").pinnedHeader() }

                Section {
                    ForEach(AppModel.Source.allCases, id: \.self) { source in
                        HStack {
                            Text(source.rawValue.loc)
                            Spacer()
                            if let error = model.errors[source] {
                                Text(error).font(.app(.caption2)).foregroundStyle(.red).lineLimit(1)
                            } else {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                        .font(.app(.caption))
                    }
                    Text("Veðurstofa Íslands (vedur.is), Vegagerðin (umferdin.is), Open-Meteo, NOAA Space Weather Prediction Center, SafeTravel.is. L'app aggrega dati pubblici: in caso di dubbio prevalgono le fonti ufficiali.")
                        .font(.app(.caption2)).foregroundStyle(.secondary)
                } header: { Text("Stato delle fonti").pinnedHeader() }

                Section {
                    ForEach(Hero.allCases, id: \.self) { hero in
                        let credit = hero.credit
                        if let url = URL(string: credit.page) {
                            Link(destination: url) {
                                HStack(spacing: 10) {
                                    Image(hero.asset).resizable().scaledToFill().frame(width: 54, height: 36).clipped()
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(credit.author).font(.app(.caption, .semibold)).foregroundStyle(Theme.text)
                                        Text("\(credit.license) · Wikimedia Commons").font(.app(.caption2)).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } header: { Text("Crediti foto").pinnedHeader() }
            }
            .themedList()
            .navigationTitle("Info & SOS")
    }
}
