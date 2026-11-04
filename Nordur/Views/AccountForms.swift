import SwiftUI

/// Account actions that need a form: password reset (code by e-mail or recovery code),
/// password change, new recovery code, account deletion.
enum AccountAction: String, Identifiable {
    case reset, change, recovery, delete
    var id: String { rawValue }

    var title: String {
        switch self {
        case .reset: return String(localized: "Recupera")
        case .change: return String(localized: "Password")
        case .recovery: return String(localized: "Codice")
        case .delete: return String(localized: "Elimina")
        }
    }

    var subtitle: String {
        switch self {
        case .reset: return String(localized: "Password dimenticata")
        case .change: return String(localized: "Cambia password")
        case .recovery: return String(localized: "Nuovo codice di recupero")
        case .delete: return String(localized: "Elimina account")
        }
    }
}

struct AccountActionSheet: View {
    let action: AccountAction
    @Environment(Account.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""
    @State private var current = ""
    @State private var new = ""
    @State private var confirmText = ""
    @State private var working = false
    @State private var message: String?
    /// Reset: the code by e-mail was sent / the recovery code is used instead.
    @State private var codeSent = false
    @State private var useRecoveryCode = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(title: action.title, subtitle: action.subtitle)
                    switch action {
                    case .reset:
                        field(String(localized: "Email")) { TextField("", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled() }
                        if useRecoveryCode {
                            explanation(String(localized: "Il codice di recupero ti è stato mostrato quando hai creato l'account. Dopo l'uso ne riceverai uno nuovo."))
                            field(String(localized: "Codice di recupero")) { TextField("", text: $code, prompt: Text("XXXX-XXXX-XXXX-XXXX").foregroundStyle(Theme.faint)).textInputAutocapitalization(.characters).autocorrectionDisabled().font(.mono(16)) }
                            field(String(localized: "Nuova password")) { SecureField("", text: $new, prompt: Text("Almeno 8 caratteri").foregroundStyle(Theme.faint)).textContentType(.newPassword) }
                            primary(String(localized: "Imposta la nuova password"), enabled: !email.isEmpty && code.count >= 16 && new.count >= 8) {
                                _ = try await account.resetPassword(email: email, recoveryCode: code, newPassword: new)
                                return String(localized: "Password aggiornata, accesso eseguito.")
                            }
                        } else if !codeSent {
                            explanation(String(localized: "Ti mandiamo per email un codice di 6 cifre, valido 15 minuti."))
                            primary(String(localized: "Invia il codice"), enabled: email.contains("@"), closes: false) {
                                try await account.requestResetCode(email: email)
                                codeSent = true
                                code = ""
                                return String(localized: "Se esiste un account con questa email, il codice è in arrivo. Controlla anche la posta indesiderata.")
                            }
                        } else {
                            field(String(localized: "Codice dall'email")) {
                                TextField("", text: $code, prompt: Text("000000").foregroundStyle(Theme.faint))
                                    .textContentType(.oneTimeCode).keyboardType(.numberPad).font(.mono(20))
                            }
                            field(String(localized: "Nuova password")) { SecureField("", text: $new, prompt: Text("Almeno 8 caratteri").foregroundStyle(Theme.faint)).textContentType(.newPassword) }
                            primary(String(localized: "Imposta la nuova password"), enabled: code.filter(\.isNumber).count == 6 && new.count >= 8) {
                                _ = try await account.resetPassword(email: email, emailCode: code, newPassword: new)
                                return String(localized: "Password aggiornata, accesso eseguito.")
                            }
                            secondary(String(localized: "Invia un nuovo codice")) {
                                try await account.requestResetCode(email: email)
                                return String(localized: "Nuovo codice inviato.")
                            }
                        }
                        secondary(useRecoveryCode ? String(localized: "Usa il codice via email") : String(localized: "Ho il codice di recupero")) {
                            useRecoveryCode.toggle()
                            code = ""
                            return nil
                        }
                    case .change:
                        field(String(localized: "Password attuale")) { SecureField("", text: $current).textContentType(.password) }
                        field(String(localized: "Nuova password")) { SecureField("", text: $new, prompt: Text("Almeno 8 caratteri").foregroundStyle(Theme.faint)).textContentType(.newPassword) }
                        primary(String(localized: "Cambia password"), enabled: !current.isEmpty && new.count >= 8) {
                            try await account.changePassword(current: current, new: new)
                            return String(localized: "Password cambiata.")
                        }
                    case .recovery:
                        explanation(String(localized: "Il nuovo codice sostituisce quello precedente, che smette di funzionare."))
                        field(String(localized: "Password")) { SecureField("", text: $current).textContentType(.password) }
                        primary(String(localized: "Genera nuovo codice"), enabled: !current.isEmpty) {
                            try await account.regenerateRecoveryCode(password: current)
                            return nil
                        }
                    case .delete:
                        explanation(String(localized: "L'account, il backup online e i tuoi avvistamenti vengono eliminati in modo definitivo. I dati sul telefono restano. Scrivi ELIMINA per confermare."))
                        field(String(localized: "Password")) { SecureField("", text: $current).textContentType(.password) }
                        field(String(localized: "Conferma")) { TextField("", text: $confirmText, prompt: Text("Elimina").foregroundStyle(Theme.faint)).textInputAutocapitalization(.characters) }
                        primary(String(localized: "Elimina account"), enabled: !current.isEmpty && confirmText == String(localized: "Elimina"), destructive: true) {
                            try await account.deleteAccount(password: current)
                            return String(localized: "Account eliminato.")
                        }
                    }
                    if let message { Text(message.loc).font(.app(.footnote)).foregroundStyle(Theme.text) }
                }
                .padding(18)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
        }
        .onAppear { email = account.email ?? "" }
    }

    private func explanation(_ text: String) -> some View {
        Text(text.loc).font(.app(.caption)).foregroundStyle(Theme.dim)
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

    /// A text button for the alternatives of a form (no closing of the sheet).
    private func secondary(_ title: String, action: @escaping () async throws -> String?) -> some View {
        Button {
            message = nil
            Task {
                do { message = try await action() } catch { message = error.localizedDescription }
            }
        } label: {
            Text(title.loc).font(.mono(10, .semibold)).foregroundStyle(Theme.accent)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(working)
    }

    private func primary(_ title: String, enabled: Bool, destructive: Bool = false, closes: Bool = true,
                         action: @escaping () async throws -> String?) -> some View {
        Button {
            working = true
            message = nil
            Task {
                do {
                    message = try await action()
                    Haptics.result(true)
                    if !closes {
                        // The form continues (e.g. the code was sent).
                    } else if message != nil && self.action != .recovery {
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        dismiss()
                    } else if self.action == .recovery {
                        dismiss()
                    }
                } catch {
                    message = error.localizedDescription
                    Haptics.result(false)
                }
                working = false
            }
        } label: {
            HStack {
                Text(title.loc).font(.mono(12, .semibold))
                Spacer()
                if working { ProgressView().tint(Theme.onAccent) } else { Text("→").font(.mono(15, .semibold)) }
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(destructive ? Theme.danger : Theme.accent)
        }
        .buttonStyle(.plain)
        .disabled(working || !enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// Shown once after sign-up, reset or regeneration.
struct RecoveryCodeSheet: View {
    let code: String
    let done: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScreenHeader(title: String(localized: "Codice"), subtitle: String(localized: "Codice di recupero"))
            Text("Conservalo in un posto sicuro (ad esempio in un gestore di password). Serve a reimpostare la password se l'email con il codice non ti arriva; Norður non può recuperarlo.")
                .font(.app(.subheadline)).foregroundStyle(Theme.text)
            Text(code)
                .font(.mono(24, .semibold))
                
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: 1))
                .textSelection(.enabled)
            Button {
                UIPasteboard.general.string = code
                copied = true
            } label: {
                Text(copied ? String(localized: "Copiato") : String(localized: "Copia")).font(.mono(12, .semibold))
                    .foregroundStyle(Theme.text).frame(maxWidth: .infinity).frame(height: 44)
                    .overlay(Rectangle().strokeBorder(Theme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button(action: done) {
                HStack {
                    Text("L'ho salvato").font(.mono(12, .semibold))
                    Spacer()
                    Text("→").font(.mono(15, .semibold))
                }
                .foregroundStyle(Theme.onAccent).padding(.horizontal, 14).frame(height: 50).background(Theme.accent)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(18)
        .background(Theme.bg.ignoresSafeArea())
        .interactiveDismissDisabled()
    }
}
