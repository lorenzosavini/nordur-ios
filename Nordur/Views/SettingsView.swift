import SwiftUI

/// Everything adjustable in one place: units, appearance, alerts, account,
/// offline data, sources and credits.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Account.self) private var account
    @AppStorage(WindUnit.key) private var windUnit = WindUnit.ms.rawValue
    @AppStorage(Appearance.key) private var appearance = Appearance.system.rawValue
    @State private var showAccount = false
    @AppStorage(NightVision.key) private var nightVision = false
    @AppStorage(NightVision.autoKey) private var nightAuto = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(selection: $windUnit) {
                        ForEach(WindUnit.allCases) { Text($0.label).tag($0.rawValue) }
                    } label: {
                        Label("Vento", systemImage: "wind")
                    }
                    .pickerStyle(.menu)
                    LabeledContent {
                        Text("°C · mm · km").foregroundStyle(.secondary)
                    } label: {
                        Label("Temperatura, pioggia, distanze", systemImage: "thermometer.medium")
                    }
                } header: { Text("Unità di misura").pinnedHeader() } footer: {
                    Text("Esempio: 15 m/s = \(Int((15 * 3.6).rounded())) km/h = \(Int((15 * 1.943844).rounded())) nodi. Le soglie degli avvisi restano le stesse, cambia solo come vengono mostrate.")
                }

                Section {
                    Picker(selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0.rawValue) }
                    } label: {
                        Label("Aspetto", systemImage: "circle.lefthalf.filled")
                    }
                    .pickerStyle(.menu)
                    Toggle(isOn: $nightVision) {
                        Label("Visione notturna (rosso)", systemImage: "moon.fill")
                    }
                    Toggle(isOn: $nightAuto) {
                        Label("Da sola di notte nella scheda Aurora", systemImage: "moon.stars")
                    }
                } header: { Text("Schermo").pinnedHeader() } footer: {
                    Text("Lo schermo diventa rosso scuro su nero: la luce bianca e blu fa perdere l'adattamento degli occhi al buio (servono 20-30 minuti per recuperarlo), il rosso no. Abbassa anche la luminosità del telefono.")
                }

                BackupSettingsSection()

                Section {
                    NavigationLink { AlertSettingsView() } label: { Label("Allerte e notifiche", systemImage: "bell.badge") }
                    NavigationLink { OfflineView() } label: { Label("Pacchetto offline", systemImage: "arrow.down.circle") }
                    NavigationLink { DataSourcesView() } label: { Label("Fonti e stato dei dati", systemImage: "doc.text.magnifyingglass") }
                    NavigationLink { CrashLogView() } label: {
                        LabeledContent {
                            if !CrashLog.shared.entries.isEmpty { Text("\(CrashLog.shared.entries.count)").foregroundStyle(Theme.danger) }
                        } label: { Label("Registro errori", systemImage: "ladybug") }
                    }
                    Button { showAccount = true } label: {
                        Label(account.isSignedIn ? String(localized: "Account e backup") : String(localized: "Accedi o crea un account"), systemImage: "person.crop.circle")
                    }
                } header: { Text("App").pinnedHeader() }

                Section {
                    NavigationLink { InfoView(embedded: true) } label: { Label("Info, SOS, fonti e crediti", systemImage: "info.circle") }
                } header: { Text("Informazioni").pinnedHeader() }
            }
            .themedList()
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
            .sheet(isPresented: $showAccount) { AccountView() }
        }
    }
}
