import SwiftUI

struct InfoView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Notifier.Key.warnings) private var notifyWarnings = false
    @AppStorage(Notifier.Key.includeYellow) private var notifyYellow = false
    @AppStorage(Notifier.Key.aurora) private var notifyAurora = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LinkRow(title: "Emergenza: 112", subtitle: "Polizia, ambulanza, vigili del fuoco, soccorso alpino", url: "tel:112", systemImage: "phone.fill")
                    LinkRow(title: "Numero alternativo: 599-0112", subtitle: "Se il 112 non si connette (spegnimento reti 2G/3G)", url: "tel:5990112", systemImage: "phone.badge.waveform.fill")
                    LinkRow(title: "112.is – Centrale emergenze", subtitle: "Chat con il 112 e informazioni per i viaggiatori", url: "https://www.112.is/en", systemImage: "sos")
                    LinkRow(title: "Registra il piano di viaggio", subtitle: "SafeTravel – i soccorsi sapranno dove cercarti", url: "https://safetravel.is/travel-plan", systemImage: "doc.text.fill")
                    LinkRow(title: "Guardia medica 1700", subtitle: "Consulenza sanitaria non urgente", url: "tel:1700", systemImage: "cross.case.fill")
                } header: {
                    Text("Sicurezza")
                }

                Section {
                    Toggle("Allerte arancioni e rosse", isOn: $notifyWarnings)
                    Toggle("Anche le allerte gialle", isOn: $notifyYellow).disabled(!notifyWarnings)
                    Toggle("Notti buone per l'aurora", isOn: $notifyAurora)
                } header: {
                    Text("Notifiche")
                } footer: {
                    Text("Controlla in background la tua posizione e le tappe dei prossimi 3 giorni. iOS decide quando eseguire i controlli (di solito ogni 1–2 ore se l'app è usata spesso).")
                }
                .onChange(of: notifyWarnings) { _, on in if on { Task { _ = await Notifier.requestAuthorization() } } }
                .onChange(of: notifyAurora) { _, on in if on { Task { _ = await Notifier.requestAuthorization() } } }

                Section("Meteo") {
                    LinkRow(title: "Vedur.is – Meteo ufficiale islandese", subtitle: "Previsioni, allerte, mappe del vento", url: "https://en.vedur.is/")
                    LinkRow(title: "Windy", subtitle: "Modelli a confronto, vento e raffiche", url: "https://www.windy.com/?64.9,-18.6,6")
                    LinkRow(title: "Yr.no", subtitle: "Previsioni norvegesi (MET Norway)", url: "https://www.yr.no/en")
                    LinkRow(title: "Blika.is", subtitle: "Previsioni islandesi dettagliate", url: "https://blika.is/")
                }

                Section("Strade") {
                    LinkRow(title: "Umferdin.is", subtitle: "Mappa ufficiale di strade, chiusure e webcam", url: "https://umferdin.is/en", systemImage: "map")
                    LinkRow(title: "SafeTravel – condizioni", subtitle: "Avvisi e mappa delle condizioni", url: "https://safetravel.is/", systemImage: "exclamationmark.shield")
                    LinkRow(title: "Strade F (Highlands)", subtitle: "Date di apertura – solo 4x4, guadi", url: "https://www.road.is/travel-info/highland-roads/", systemImage: "mountain.2")
                    LinkRow(title: "Distributori e ricarica", subtitle: "Mappa di N1 / Orkan / Olís", url: "https://www.n1.is/en/", systemImage: "fuelpump")
                }

                Section("Voli, bus e traghetti") {
                    LinkRow(title: "Keflavík – arrivi e partenze", subtitle: "Isavia KEF", url: "https://www.isavia.is/en/keflavik-airport", systemImage: "airplane")
                    LinkRow(title: "Voli interni", subtitle: "Icelandair, Norlandair, Mýflug", url: "https://www.icelandair.com/", systemImage: "airplane.circle")
                    LinkRow(title: "Flybus / Airport Direct", subtitle: "Navette aeroporto ↔ Reykjavík", url: "https://www.re.is/", systemImage: "bus")
                    LinkRow(title: "Strætó – bus di linea", subtitle: "Reykjavík e lunga distanza", url: "https://www.straeto.is/en", systemImage: "bus.fill")
                    LinkRow(title: "Herjólfur", subtitle: "Traghetto per Vestmannaeyjar", url: "https://www.herjolfur.is/en/", systemImage: "ferry")
                    LinkRow(title: "Baldur (Sæferðir)", subtitle: "Traghetto Stykkishólmur – Brjánslækur", url: "https://www.saeferdir.is/en/", systemImage: "ferry.fill")
                    LinkRow(title: "Smyril Line", subtitle: "Traghetto Seyðisfjörður – Fær Øer – Danimarca", url: "https://www.smyrilline.com/", systemImage: "ferry")
                }

                Section("Consigli per guidare in Islanda") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• Con vento forte apri la portiera tenendola con due mani: il vento può strapparla (danno non coperto dall'assicurazione).")
                        Text("• Fuoristrada vietato per legge. Le strade F richiedono un 4x4 e i guadi non sono coperti dall'assicurazione.")
                        Text("• Ponti a una corsia: ha la precedenza chi arriva prima.")
                        Text("• Fai rifornimento appena puoi nell'Est e nei fiordi occidentali: i distributori sono distanti.")
                        Text("• In inverno le giornate sono brevi: pianifica le tratte con la luce.")
                    }
                    .font(.caption)
                }

                Section("Stato delle fonti") {
                    ForEach(AppModel.Source.allCases, id: \.self) { source in
                        HStack {
                            Text(source.rawValue)
                            Spacer()
                            if let error = model.errors[source] {
                                Text(error).font(.caption2).foregroundStyle(.red).lineLimit(1)
                            } else {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                        .font(.caption)
                    }
                    Text("Veðurstofa Íslands (vedur.is), Vegagerðin (umferdin.is), Open-Meteo, NOAA Space Weather Prediction Center, SafeTravel.is. L'app aggrega dati pubblici: in caso di dubbio prevalgono le fonti ufficiali.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Info & SOS")
        }
    }
}
