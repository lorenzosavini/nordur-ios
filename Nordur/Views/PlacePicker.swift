import SwiftUI
import MapKit

enum PlaceChoice {
    case current
    case place(Place)
}

/// Pick a preset Icelandic location, search any place in the world, or use GPS.
struct PlacePicker: View {
    var allowCurrentLocation: Bool
    var onSelect: (PlaceChoice) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Place] = []
    @State private var searching = false

    var body: some View {
        NavigationStack {
            List {
                if allowCurrentLocation && query.isEmpty {
                    Button {
                        onSelect(.current)
                        dismiss()
                    } label: {
                        Label("Usa la mia posizione", systemImage: "location.fill")
                    }
                }

                if !query.isEmpty {
                    Section {
                        if searching { ProgressView() }
                        ForEach(results) { place in
                            row(place)
                        }
                        if !searching && results.isEmpty {
                            Text("Nessun risultato").foregroundStyle(.secondary)
                        }
                    } header: { Text("Risultati").pinnedHeader() }
                }

                Section {
                    ForEach(filteredPresets) { place in
                        row(place)
                    }
                } header: { Text("Islanda – luoghi principali").pinnedHeader() }
            }
            .themedList()
            .navigationTitle("Scegli un luogo")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: String(localized: "Cerca un luogo nel mondo"))
            .task(id: query) { await search() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }

    private var filteredPresets: [Place] {
        guard !query.isEmpty else { return Place.presets }
        return Place.presets.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func row(_ place: Place) -> some View {
        Button {
            onSelect(.place(place))
            dismiss()
        } label: {
            VStack(alignment: .leading) {
                Text(place.name).foregroundStyle(.primary)
                if let subtitle = place.subtitle {
                    Text(subtitle.loc).font(.app(.caption)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { results = []; return }
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.address, .pointOfInterest]
        guard let response = try? await MKLocalSearch(request: request).start() else { results = []; return }
        results = response.mapItems.prefix(15).map { item in
            let mark = item.placemark
            let subtitle = [mark.locality, mark.administrativeArea, mark.country].compactMap { $0 }.joined(separator: ", ")
            return Place(name: item.name ?? text, coordinate: Coordinate(mark.coordinate), subtitle: subtitle.isEmpty ? nil : subtitle)
        }
    }
}
