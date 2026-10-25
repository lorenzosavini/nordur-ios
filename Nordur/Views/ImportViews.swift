import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let gpx = UTType(importedAs: "com.topografix.gpx", conformingTo: .xml)
}

/// "Import activity" in the Drive tab: from Apple Health (Garmin Connect,
/// Apple Watch, Strava…) or from a GPX file.
struct ImportSection: View {
    @Environment(DriveStore.self) private var store
    @State private var showHealth = false
    @State private var pickingFile = false
    @State private var message: String?
    @State private var opened: DriveSession?

    var body: some View {
        Section {
            Button { if Entitlements.shared.check(.driveHealth) { showHealth = true } } label: {
                Label("Da Salute: Garmin, Apple Watch, Strava…", systemImage: "heart.text.square")
            }
            Button { if Entitlements.shared.check(.tripFiles) { pickingFile = true } } label: {
                Label("Da un file GPX", systemImage: "doc.badge.plus")
            }
            if let message {
                Text(message.loc).font(.app(.caption)).foregroundStyle(Theme.dim)
            }
        } header: {
            Text("Importa attività").eyebrow().pinnedHeader()
        } footer: {
            Text("Garmin: in Garmin Connect › Altro › Impostazioni › App collegate › Salute di Apple attiva la condivisione. Garmin passa a Salute tempo, distanza, calorie e frequenza cardiaca ma non il tracciato GPS: per il percorso, su connect.garmin.com apri l'attività › ingranaggio › Esporta in GPX e apri il file con Norður. Funziona anche da File, Mail o dal menu Condividi di Strava, Komoot e altre app.")
        }
        .sheet(isPresented: $showHealth) { NavigationStack { HealthImportSheet() } }
        .sheet(item: $opened) { session in NavigationStack { DriveDetailView(drive: session) } }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.gpx, .xml], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            var imported: [DriveSession] = [], failures: [String] = []
            for url in urls {
                do { imported.append(try store.importGPX(url)) } catch { failures.append(error.localizedDescription) }
            }
            Haptics.result(failures.isEmpty)
            if imported.count == 1, failures.isEmpty { opened = imported[0]; message = nil; return }
            message = ([imported.isEmpty ? nil : String(localized: "\(imported.count) tracce importate.")] + failures.map { Optional($0) })
                .compactMap { $0 }.joined(separator: " ")
        }
    }
}

/// Workouts found in Apple Health, with a button to import each one.
struct HealthImportSheet: View {
    @Environment(DriveStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var workouts: [HealthImport.Workout] = []
    @State private var loading = true
    @State private var error: String?
    @State private var working: String?

    var body: some View {
        List {
            if loading {
                SkeletonRows(count: 6)
            } else if let error {
                Section {
                    EmptyState(symbol: "heart.slash", title: String(localized: "Salute non disponibile"), message: error)
                }
            } else if workouts.isEmpty {
                Section {
                    EmptyState(symbol: "figure.run", title: String(localized: "Nessuna attività negli ultimi 4 mesi"),
                               message: String(localized: "Se usi Garmin, attiva in Garmin Connect la condivisione con Salute e sincronizza l'orologio. Poi torna qui."))
                }
            } else {
                Section {
                    ForEach(workouts) { item in row(item) }
                } header: {
                    Text("\(workouts.count) attività in Salute").pinnedHeader()
                } footer: {
                    Text("Norður legge da Salute solo le attività che importi; non scrive nulla.")
                }
            }
        }
        .themedList()
        .navigationTitle("Da Salute")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
        .task { await load() }
    }

    private func row(_ item: HealthImport.Workout) -> some View {
        let done = store.hasImported("health:\(item.id)")
        return HStack(spacing: 12) {
            Image(systemName: item.symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.accent).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.activity).font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text)
                Text([Fmt.dayTime(item.workout.startDate), item.km.map { Fmt.number($0, decimals: 1, unit: "km") }, Fmt.duration(item.workout.duration), item.source]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.app(.caption)).foregroundStyle(Theme.dim)
            }
            Spacer()
            if working == item.id {
                ProgressView()
            } else if done {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
            } else {
                Button("Importa") { Task { await importWorkout(item) } }
                    .buttonStyle(.bordered).font(.mono(11, .semibold))
            }
        }
    }

    private func load() async {
        let health = HealthImport.shared
        guard health.isAvailable else {
            error = String(localized: "Su questo dispositivo Salute non è disponibile.")
            loading = false
            return
        }
        do {
            workouts = try await health.recentWorkouts()
        } catch {
            if error.localizedDescription.localizedCaseInsensitiveContains("entitlement") {
                // Signed without the HealthKit permission (Sideloadly/AltStore with a free Apple ID).
                self.error = String(localized: "Questa installazione di Norður non ha il permesso di Salute: Sideloadly lo toglie quando firma con un Apple ID gratuito. Installa l'app con Xcode per usare Salute, oppure importa le attività da file GPX (per Garmin: connect.garmin.com › attività › ingranaggio › Esporta in GPX).")
            } else {
                self.error = String(localized: "Non è stato possibile leggere Salute: \(error.localizedDescription). Controlla in Impostazioni › Salute › Accesso ai dati e dispositivi › Norður.")
            }
        }
        loading = false
    }

    private func importWorkout(_ item: HealthImport.Workout) async {
        working = item.id
        defer { working = nil }
        do {
            store.saveImported(try await HealthImport.shared.session(for: item))
            Haptics.result(true)
        } catch {
            self.error = error.localizedDescription
            Haptics.result(false)
        }
    }
}
