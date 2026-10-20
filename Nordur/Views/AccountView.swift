import SwiftUI

/// Sign in / create account, backup status and restore.
struct AccountView: View {
    @Environment(Account.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var register = false
    @State private var working = false
    @State private var message: String?
    @State private var confirmDelete = false
    @State private var sheet: AccountAction?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    ScreenHeader(title: String(localized: "Account"), subtitle: account.isSignedIn ? String(localized: "Backup attivo") : String(localized: "Backup dei tuoi dati"))
                    if account.isSignedIn { signedIn } else { signIn }
                    contents
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } }
            }
            .sheet(item: $sheet) { AccountActionSheet(action: $0) }
            .sheet(isPresented: Binding(get: { account.pendingRecoveryCode != nil && sheet == nil },
                                        set: { if !$0 { account.pendingRecoveryCode = nil } })) {
                if let code = account.pendingRecoveryCode {
                    RecoveryCodeSheet(code: code) { account.pendingRecoveryCode = nil }
                }
            }
            .confirmationDialog("Eliminare i dati salvati online?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Elimina dati online", role: .destructive) {
                    run { try await account.deleteRemoteData(); return String(localized: "Dati online eliminati. Quelli sul telefono restano.") }
                }
            } message: {
                Text("Viaggio, percorsi e impostazioni restano sul telefono.")
            }
        }
    }

    // MARK: Signed out

    private var signIn: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 0) {
                modeButton(String(localized: "Accedi"), selected: !register) { register = false }
                modeButton(String(localized: "Crea account"), selected: register) { register = true }
            }
            .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: 1))

            field(String(localized: "EMAIL")) {
                TextField("", text: $email, prompt: Text("nome@esempio.it").foregroundStyle(Theme.faint))
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            field(String(localized: "PASSWORD")) {
                SecureField("", text: $password, prompt: Text(register ? String(localized: "Almeno 8 caratteri") : String(localized: "Password")).foregroundStyle(Theme.faint))
                    .textContentType(register ? .newPassword : .password)
            }

            Button {
                run {
                    let restored = try await account.authenticate(email: email, password: password, register: register)
                    password = ""
                    return restored > 0 ? String(localized: "Accesso eseguito: \(restored) elementi ripristinati.") : String(localized: "Accesso eseguito. Da ora i dati vengono salvati online.")
                }
            } label: {
                HStack {
                    Text(register ? String(localized: "CREA ACCOUNT") : String(localized: "ACCEDI")).font(.mono(13, .semibold)).tracking(1)
                    Spacer()
                    if working { ProgressView().tint(Theme.onAccent) } else { Text("→").font(.mono(15, .semibold)) }
                }
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(Theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(working || email.isEmpty || password.count < (register ? 8 : 1))
            .opacity(email.isEmpty || password.isEmpty ? 0.5 : 1)

            if let message { Text(message.loc).font(.app(.footnote)).foregroundStyle(Theme.text) }
            Button { sheet = .reset } label: {
                Text("PASSWORD DIMENTICATA?").font(.mono(10, .semibold)).foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private func modeButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title.loc.uppercased())
                .font(.mono(11, .semibold))
                .tracking(0.6)
                .foregroundStyle(selected ? Theme.bg : Theme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(selected ? Theme.text : .clear)
        }
        .buttonStyle(.plain)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.loc).font(.mono(9.5)).foregroundStyle(Theme.faint)
            content()
                .font(.sans(16))
                .padding(.horizontal, 12)
                .frame(height: 46)
                .overlay(Rectangle().strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }

    // MARK: Signed in

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: 14) {
            ReadingGrid(items: [
                Reading(label: String(localized: "Account"), value: account.email ?? "–", size: 20),
                Reading(label: String(localized: "Ultimo backup"), value: account.lastSync.map { Fmt.relative($0) } ?? "mai", size: 20),
            ])
            .overlay(alignment: .top) { Rule() }
            .overlay(alignment: .bottom) { Rule() }

            if let error = account.lastError { ErrorNote(message: error) }
            if let message { Text(message.loc).font(.app(.footnote)).foregroundStyle(Theme.text) }

            actionRow(String(localized: "Esegui backup ora"),
                      detail: account.isSyncing ? String(localized: "In corso…") : String(localized: "Automatico: \(account.backupFrequency.label.lowercased()) · cambialo in Impostazioni")) {
                run { await account.sync(); return account.lastError == nil ? String(localized: "Backup completato.") : nil }
            }
            actionRow(String(localized: "Ripristina dal backup"), detail: String(localized: "Scarica i dati salvati sul telefono")) {
                run { let n = try await account.restore(); return n > 0 ? String(localized: "\(n) elementi ripristinati.") : String(localized: "Il telefono era già aggiornato.") }
            }
            actionRow(String(localized: "Esci dall'account"), detail: String(localized: "I dati restano sul telefono")) {
                account.signOut()
                message = nil
            }
            actionRow(String(localized: "Cambia password"), detail: nil) { sheet = .change }
            actionRow(String(localized: "Nuovo codice di recupero"), detail: String(localized: "Serve per reimpostare la password")) { sheet = .recovery }
            actionRow(String(localized: "Elimina dati online"), detail: String(localized: "L'account resta attivo"), destructive: true) { confirmDelete = true }
            actionRow(String(localized: "Elimina account"), detail: String(localized: "Account, backup e avvistamenti, in modo definitivo"), destructive: true) { sheet = .delete }
        }
    }

    private func actionRow(_ title: String, detail: String?, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title.loc).font(.app(.subheadline, .medium)).foregroundStyle(destructive ? Theme.danger : Theme.text)
                        if let detail { Text(detail.loc).font(.app(.caption)).foregroundStyle(Theme.dim) }
                    }
                    Spacer()
                    Text("→").font(.mono(13)).foregroundStyle(destructive ? Theme.danger : Theme.accent)
                }
                .padding(.vertical, 12)
                Rule()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(working)
    }

    // MARK: What is saved

    private var contents: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: String(localized: "Cosa viene salvato"))
            VStack(alignment: .leading, spacing: 0) {
                item(String(localized: "Viaggio"), String(localized: "tappe, date e note"))
                item(String(localized: "Percorsi in auto"), String(localized: "tracce GPS, km, velocità, consumi, contachilometri"))
                item(String(localized: "Allerte"), String(localized: "storico delle notifiche ricevute"))
                item(String(localized: "Impostazioni"), String(localized: "soglie di allerta, guida, aspetto, località scelta, livelli mappa"))
            }
            Text("Ti scriviamo per email a ogni evento dell'account: creazione, nuovo accesso, cambio o reimpostazione della password, nuovo codice di recupero, eliminazione.")
                .font(.app(.caption)).foregroundStyle(Theme.dim)
            Text("I dati sono cifrati (AES-256) prima di essere salvati. Dopo aver reinstallato l'app basta accedere con la stessa email: tutto torna com'era. Il backup parte da solo quando chiudi l'app e ogni 5 minuti mentre la usi.")
                .font(.app(.caption)).foregroundStyle(Theme.dim)
            LinkRow(title: String(localized: "Informativa sulla privacy"), subtitle: String(localized: "Quali dati usa Norður e come"), url: "https://nordur-api.vercel.app/privacy.html")
                .padding(.top, 6)
        }
    }

    private func item(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title.loc.uppercased()).font(.mono(10, .semibold)).foregroundStyle(Theme.text).frame(width: 120, alignment: .leading)
                Text(detail.loc).font(.app(.caption)).foregroundStyle(Theme.dim)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
            Rule()
        }
    }

    private func run(_ operation: @escaping () async throws -> String?) {
        working = true
        message = nil
        Task {
            do { message = try await operation(); Haptics.result(true) } catch { message = error.localizedDescription; Haptics.result(false) }
            working = false
        }
    }
}
