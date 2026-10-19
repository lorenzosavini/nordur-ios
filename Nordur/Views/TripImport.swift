import SwiftUI
import UniformTypeIdentifiers

/// A file chosen or opened to become the trip, before it is applied.
struct TripImportFile: Identifiable {
    let id = UUID()
    let name: String
    var items: [TripFileItem]

    static func read(_ url: URL) throws -> TripImportFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard let items = TripFileReader.read(data) else {
            throw NSError(domain: "Nordur", code: 1, userInfo: [NSLocalizedDescriptionKey:
                String(localized: "Nel file non ci sono punti (waypoint o segnaposti). Se è un KMZ di Google My Maps, esportalo come KML.")])
        }
        return TripImportFile(name: url.deletingPathExtension().lastPathComponent, items: items)
    }

    static let types: [UTType] = [UTType(filenameExtension: "gpx"), UTType(filenameExtension: "kml"), .xml].compactMap { $0 }

    /// A GPX with a recorded track (and no waypoints) is a drive; everything else is a trip.
    static func isTrip(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == "kml" { return true }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let text = String(data: data.prefix(4_000_000), encoding: .utf8) else { return false }
        return text.contains("<wpt") || (text.contains("<rtept") && !text.contains("<trkpt"))
    }
}

/// What the file contains, each place as a stop or an attraction, the start
/// date when the file has none, and whether it replaces the current trip.
struct TripImportSheet: View {
    @Environment(TripStore.self) private var trip
    @Environment(\.dismiss) private var dismiss
    @State var file: TripImportFile
    @State private var start = Calendar.iceland.startOfDay(for: Date().addingTimeInterval(86400))
    @State private var replacing = true

    var body: some View {
        let stops = file.items.filter(\.isStop).count
        let needsStart = file.items.contains { $0.isStop && $0.date == nil }
        NavigationStack {
            List {
                Section {
                    Text(String(localized: "\(file.items.count) luoghi: \(stops) tappe e \(file.items.count - stops) attrazioni."))
                        .font(.app(.subheadline, .semibold))
                    if needsStart {
                        DatePicker("Primo giorno", selection: $start, displayedComponents: .date)
                            .environment(\.timeZone, .iceland)
                    }
                    if !trip.stops.isEmpty {
                        Picker("Viaggio attuale", selection: $replacing) {
                            Text("Sostituiscilo").tag(true)
                            Text("Aggiungi in coda").tag(false)
                        }
                    }
                } header: { Text(file.name).pinnedHeader() } footer: {
                    Text("Le tappe sono i posti dove dormi; ogni attrazione va sotto la tappa del suo giorno o la più vicina. Puoi cambiare tutto anche dopo.")
                }
                Section {
                    ForEach($file.items) { $item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: item.isStop ? "bed.double.fill" : "binoculars.fill")
                                    .foregroundStyle(item.isStop ? Theme.accent : Theme.dim).frame(width: 24)
                                Text(item.name).font(.app(.subheadline, .semibold)).lineLimit(2)
                                Spacer()
                                if let d = item.date {
                                    Text(Fmt.day(d, in: .iceland)).font(.mono(10)).foregroundStyle(Theme.dim)
                                }
                            }
                            Picker("", selection: $item.isStop) {
                                Text("Tappa").tag(true)
                                Text("Attrazione").tag(false)
                            }
                            .pickerStyle(.segmented)
                            if item.isStop {
                                Stepper(String(localized: "Notti: \(item.nights ?? 1)"), value: Binding(get: { item.nights ?? 1 }, set: { item.nights = $0 }), in: 0...30)
                                    .font(.app(.caption))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: { Text("Luoghi nel file").pinnedHeader() }
            }
            .themedList()
            .navigationTitle("Importa viaggio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importa") {
                        trip.importItems(file.items, start: start, replacing: replacing || trip.stops.isEmpty)
                        Haptics.result(true)
                        dismiss()
                    }
                    .disabled(stops == 0 && trip.stops.isEmpty)
                }
            }
        }
    }
}
