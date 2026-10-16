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
                        Label("Scarica tutto per l'offline", systemImage: "arrow.down.circle.fill")
                        if running { Spacer(); ProgressView() }
                    }
                }
                .disabled(running)
                ForEach(log, id: \.self) { line in
                    Text(line).font(.app(.caption2)).foregroundStyle(.secondary)
                }
            } header: {
                Text("Dati dell'app")
            }

            Section {
                Text("Apple Mappe: foto profilo › Mappe offline › Scarica nuova mappa › Islanda.")
                    .font(.app(.caption))
                if let url = URL(string: "maps://") {
                    Link(destination: url) { Label("Apri Apple Mappe", systemImage: "map") }
                }
            } header: {
                Text("Mappa di base")
            }

            Section("Distributori salvati sul telefono") {
                if let fuel = model.fuel {
                    let stations = fuel.value
                    LabeledContent("Carburante", value: "\(stations.filter { $0.kind == .fuel }.count)")
                    LabeledContent("Colonnine di ricarica", value: "\(stations.filter { $0.kind == .charger }.count)")
                    FreshnessLabel(date: fuel.date, isStale: fuel.isStale, source: "OpenStreetMap")
                } else {
                    ErrorNote(message: model.errors[.fuel] ?? "Non ancora scaricati")
                }
            }
        }
        .themedList()
        .navigationTitle("Pacchetto offline")
    }

    private func downloadAll() async {
        running = true
        log = []
        defer { running = false }
        log.append("Allerte, strade, terremoti, aurora, SafeTravel…")
        await model.refreshGlobal(force: true)
        log.append("Webcam e distributori…")
        await model.refreshStatic(force: true)
        log.append("Previsioni per la posizione…")
        await model.refreshPlace()
        log.append("Previsioni per \(trip.stops.count) tappe del viaggio…")
        await trip.loadForecasts()
        log.append("Voli e traghetti…")
        await model.refreshTransport()
        let failed = AppModel.Source.allCases.filter { model.errors[$0] != nil }.map(\.rawValue)
        log.append(failed.isEmpty ? "Completato" : "Non riuscito: \(failed.joined(separator: ", "))")
    }
}
