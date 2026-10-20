import SwiftUI

/// Settings › Backup: how often the account backup runs, when it last ran, and a
/// button to run it now.
struct BackupSettingsSection: View {
    @Environment(Account.self) private var account
    @State private var signingIn = false

    var body: some View {
        @Bindable var account = account
        Section {
            if account.isSignedIn {
                Picker(selection: $account.backupFrequency) {
                    ForEach(Account.BackupFrequency.allCases) { Text($0.label).tag($0) }
                } label: {
                    Label("Backup automatico", systemImage: "arrow.triangle.2.circlepath.icloud")
                }
                .pickerStyle(.menu)
                LabeledContent {
                    Text(account.isSyncing ? String(localized: "in corso…") : account.lastSync.map { Fmt.relative($0) } ?? String(localized: "mai"))
                        .foregroundStyle(account.lastError == nil ? Theme.dim : Theme.danger)
                } label: {
                    Label("Ultimo backup", systemImage: "clock")
                }
                Button {
                    Task { await account.sync() }
                } label: {
                    Label("Esegui backup ora", systemImage: "icloud.and.arrow.up")
                }
                .disabled(account.isSyncing)
                if let error = account.lastError {
                    Text(error).font(.app(.caption)).foregroundStyle(Theme.danger)
                }
            } else {
                Button { signingIn = true } label: {
                    Label("Accedi per attivare il backup", systemImage: "person.crop.circle.badge.plus")
                }
            }
        } header: { Text("Backup").pinnedHeader() } footer: {
            Text("Viaggio, percorsi registrati, allerte e impostazioni vanno sul tuo account, cifrati. Con «a ogni modifica» il backup parte entro mezzo minuto da ogni cambiamento e invia solo ciò che è cambiato; uscendo dall'app viene sempre salvato l'ultimo stato (tranne con «una volta al giorno» e «solo a mano»).")
        }
        .sheet(isPresented: $signingIn) { AccountView() }
    }
}
