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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    ScreenHeader(title: "Account", subtitle: account.isSignedIn ? "Backup attivo" : "Backup dei tuoi dati")
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
            .confirmationDialog("Eliminare i dati salvati online?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Elimina dati online", role: .destructive) {
                    run { try await account.deleteRemoteData(); return "Dati online eliminati. Quelli sul telefono restano." }
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
                modeButton("Accedi", selected: !register) { register = false }
                modeButton("Crea account", selected: register) { register = true }
            }
            .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: 1))

            field("EMAIL") {
                TextField("nome@esempio.it", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            field("PASSWORD") {
                SecureField(register ? "Almeno 8 caratteri" : "Password", text: $password)
                    .textContentType(register ? .newPassword : .password)
            }

            Button {
                run {
                    let restored = try await account.authenticate(email: email, password: password, register: register)
                    password = ""
                    return restored > 0 ? "Accesso eseguito: \(restored) elementi ripristinati." : "Accesso eseguito. Da ora i dati vengono salvati online."
                }
            } label: {
                HStack {
                    Text(register ? "CREA ACCOUNT" : "ACCEDI").font(.mono(13, .semibold)).tracking(1)
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

            if let message { Text(message).font(.app(.footnote)).foregroundStyle(Theme.text) }
        }
    }

    private func modeButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title.uppercased())
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
            Text(label).font(.mono(9.5)).foregroundStyle(Theme.faint)
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
                Reading(label: "Account", value: account.email ?? "–", size: 20),
                Reading(label: "Ultimo backup", value: account.lastSync.map { Fmt.relative($0) } ?? "mai", size: 20),
            ])
            .overlay(alignment: .top) { Rule() }
            .overlay(alignment: .bottom) { Rule() }

            if let error = account.lastError { ErrorNote(message: error) }
            if let message { Text(message).font(.app(.footnote)).foregroundStyle(Theme.text) }

            actionRow("Esegui backup ora", detail: account.isSyncing ? "In corso…" : nil) {
                run { await account.sync(); return account.lastError == nil ? "Backup completato." : nil }
            }
            actionRow("Ripristina dal backup", detail: "Scarica i dati salvati sul telefono") {
                run { let n = try await account.restore(); return n > 0 ? "\(n) elementi ripristinati." : "Il telefono era già aggiornato." }
            }
            actionRow("Esci dall'account", detail: "I dati restano sul telefono") {
                account.signOut()
                message = nil
            }
            actionRow("Elimina dati online", detail: nil, destructive: true) { confirmDelete = true }
        }
    }

    private func actionRow(_ title: String, detail: String?, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.app(.subheadline, .medium)).foregroundStyle(destructive ? Theme.danger : Theme.text)
                        if let detail { Text(detail).font(.app(.caption)).foregroundStyle(Theme.dim) }
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
            SectionLabel(title: "Cosa viene salvato")
            VStack(alignment: .leading, spacing: 0) {
                item("Viaggio", "tappe, date e note")
                item("Percorsi in auto", "tracce GPS, km, velocità, consumi, contachilometri")
                item("Allerte", "storico delle notifiche ricevute")
                item("Impostazioni", "soglie di allerta, guida, aspetto, località scelta, livelli mappa")
            }
            Text("I dati sono cifrati (AES-256) prima di essere salvati. Dopo aver reinstallato l'app basta accedere con la stessa email: tutto torna com'era. Il backup parte da solo quando chiudi l'app e ogni 5 minuti mentre la usi.")
                .font(.app(.caption)).foregroundStyle(Theme.dim)
        }
    }

    private func item(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title.uppercased()).font(.mono(10, .semibold)).foregroundStyle(Theme.text).frame(width: 120, alignment: .leading)
                Text(detail).font(.app(.caption)).foregroundStyle(Theme.dim)
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
            do { message = try await operation() } catch { message = error.localizedDescription }
            working = false
        }
    }
}
