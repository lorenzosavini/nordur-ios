import SwiftUI

/// Downloads everything useful before entering areas without coverage.
struct OfflineView: View {
    @Environment(AppModel.self) private var model
    @Environment(TripStore.self) private var trip
    @State private var running = false
    @State private var log: [String] = []

    var body: some View {
        List {
            Section {
                Text("Scarica i dati prima di entrare in zone senza copertura (Highlands, fiordi occidentali, parte dell'Est).")
                    .font(.app(.caption))
                Button {
                    Task { await downloadAll() }
                } label: {
                    HStack {
                        Label("Scarica tutto per l'uso offline", systemImage: "arrow.down.circle.fill")
                        if running { Spacer(); ProgressView() }
                    }
                }
                .disabled(running)
                ForEach(log, id: \.self) { line in
                    Text(line.loc).font(.app(.caption2)).foregroundStyle(.secondary)
                }
            } header: {
                Text("Dati dell'app").pinnedHeader()
            }

            Section {
                Text("Apple Mappe: foto profilo › Mappe offline › Scarica nuova mappa › Islanda.")
                    .font(.app(.caption))
                if let url = URL(string: "maps://?ll=64.9,-18.6&z=6") {
                    Link(destination: url) { Label("Apri Apple Mappe", systemImage: "map") }
                }
            } header: {
                Text("Apple Mappe").pinnedHeader()
            }

            Section {
                Text("Google Maps: foto profilo › Mappe offline › Seleziona la tua mappa, adatta il riquadro e tocca Scarica. Un riquadro copre circa un terzo dell'Islanda: apri le zone qui sotto una alla volta e scaricale.")
                    .font(.app(.caption))
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Self.googleAreas, id: \.name) { area in
                    Link(destination: Self.googleMaps(area.lat, area.lon, zoom: area.zoom)) {
                        Label(area.name.loc, systemImage: "arrow.down.to.line.circle")
                    }
                }
                ForEach(trip.stops) { stop in
                    Link(destination: Self.googleMaps(stop.place.coordinate.lat, stop.place.coordinate.lon, zoom: 9)) {
                        Label(String(localized: "Tappa: \(stop.place.name)"), systemImage: "flag")
                    }
                }
            } header: {
                Text("Google Maps").pinnedHeader()
            } footer: {
                Text("Google non permette ad altre app di scaricare le sue mappe: Norður apre Google Maps sulla zona giusta e il download lo avvii tu. Le mappe offline di Google scadono dopo un anno se non le aggiorni.")
            }

            Section {
                if let fuel = model.fuel {
                    let stations = fuel.value
                    LabeledContent("Carburante", value: "\(stations.filter { $0.kind == .fuel }.count)")
                    LabeledContent("Colonnine di ricarica", value: "\(stations.filter { $0.kind == .charger }.count)")
                    FreshnessLabel(date: fuel.date, isStale: fuel.isStale, source: String(localized: "OpenStreetMap"))
                } else {
                    ErrorNote(message: model.errors[.fuel] ?? String(localized: "Non ancora scaricati"))
                }
            } header: { Text("Distributori salvati sul telefono").pinnedHeader() }
        }
        .themedList()
        .navigationTitle("Pacchetto offline")
    }

    private struct Area { let name: String; let lat: Double; let lon: Double; let zoom: Int }

    /// Iceland in four areas, each about the size of one Google offline map.
    private static let googleAreas = [
        Area(name: "Sud e Ovest (Reykjavík, Golden Circle, Vík)", lat: 64.05, lon: -20.9, zoom: 7),
        Area(name: "Nord (Akureyri, Mývatn, Húsavík)", lat: 65.75, lon: -17.6, zoom: 7),
        Area(name: "Est e Sud-Est (Egilsstaðir, Höfn, Jökulsárlón)", lat: 64.75, lon: -15.0, zoom: 7),
        Area(name: "Fiordi occidentali e Snæfellsnes", lat: 65.6, lon: -23.0, zoom: 7),
    ]

    /// Opens Google Maps (the app if installed, otherwise the web) centred on a place.
    private static func googleMaps(_ lat: Double, _ lon: Double, zoom: Int) -> URL {
        URL(string: "https://www.google.com/maps/@?api=1&map_action=map&center=\(lat),\(lon)&zoom=\(zoom)")!
    }

    private func downloadAll() async {
        running = true
        log = []
        defer { running = false }
        log.append(String(localized: "Allerte, strade, terremoti, aurora, SafeTravel…"))
        await model.refreshGlobal(force: true)
        log.append(String(localized: "Webcam e distributori…"))
        await model.refreshStatic(force: true)
        log.append(String(localized: "Previsioni per la posizione…"))
        await model.refreshPlace()
        log.append(String(localized: "Previsioni per \(trip.stops.count) tappe del viaggio…"))
        await trip.loadForecasts()
        log.append(String(localized: "Voli e traghetti…"))
        await model.refreshTransport()
        let failed = AppModel.Source.allCases.filter { model.errors[$0] != nil }.map(\.rawValue)
        log.append(failed.isEmpty ? String(localized: "Completato") : String(localized: "Non riuscito: \(failed.joined(separator: ", "))"))
    }
}
