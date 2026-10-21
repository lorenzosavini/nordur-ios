import SwiftUI

/// Settings › Registro errori: the closings (crashes, iOS ending the app) and
/// every error met while running, with the details to send.
struct CrashLogView: View {
    private var log: CrashLog { CrashLog.shared }
    @State private var tab = "closings"
    @State private var errors: [ErrorLog.Entry] = ErrorLog.entries()

    var body: some View {
        List {
            Section {
                Picker("Mostra", selection: $tab) {
                    Text("Chiusure (\(log.entries.count))").tag("closings")
                    Text("Errori (\(errors.count))").tag("errors")
                }
                .pickerStyle(.segmented)
                if !log.entries.isEmpty || !errors.isEmpty {
                    ShareLink(item: fullText, subject: Text("Norður: registro errori")) {
                        Label("Invia il registro", systemImage: "square.and.arrow.up")
                    }
                    Button { UIPasteboard.general.string = fullText; Haptics.result(true) } label: {
                        Label("Copia tutto", systemImage: "doc.on.doc")
                    }
                }
            }
            if tab == "closings" { closings } else { errorList }
        }
        .themedList()
        .navigationTitle("Registro errori")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: ErrorLog.didChange)) { _ in errors = ErrorLog.entries() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Svuota", role: .destructive) {
                    if tab == "closings" { log.clear() } else { ErrorLog.clear(); errors = [] }
                }
                .disabled(tab == "closings" ? log.entries.isEmpty : errors.isEmpty)
            }
        }
    }

    @ViewBuilder private var closings: some View {
        if log.entries.isEmpty {
            EmptyState(symbol: "checkmark.seal", title: String(localized: "Nessuna chiusura registrata"),
                       message: String(localized: "Se l'app si chiude da sola, qui trovi quando, dove e perché."))
        } else {
            Section {
                ForEach(log.entries) { entry in
                    NavigationLink { LogTextView(title: entry.kind, text: Self.text(entry)) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(entry.kind) · \(Fmt.dayTime(entry.date))").font(.app(.caption, .semibold)).foregroundStyle(Theme.danger)
                            Text(entry.summary).font(.app(.subheadline)).foregroundStyle(Theme.text).lineLimit(3)
                            if let screen = entry.screen {
                                Text("Schermata: \(screen)").font(.app(.caption)).foregroundStyle(Theme.dim)
                            }
                        }
                    }
                }
                .onDelete { offsets in offsets.map { log.entries[$0] }.forEach(log.delete) }
            } footer: {
                Text("Il registro resta sul telefono e parte solo se lo invii tu. I rapporti di iOS («rapporto iOS») arrivano a un avvio successivo, a volte il giorno dopo.")
            }
        }
    }

    @ViewBuilder private var errorList: some View {
        if errors.isEmpty {
            EmptyState(symbol: "checkmark.seal", title: String(localized: "Nessun errore registrato"),
                       message: String(localized: "Qui finiscono le fonti che non rispondono, i dati non leggibili, i backup e le sincronizzazioni non riuscite, il GPS."))
        } else {
            Section {
                ForEach(errors) { entry in
                    NavigationLink { LogTextView(title: entry.source, text: Self.text(entry)) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(entry.source) · \(Fmt.dayTime(entry.last))\(entry.count > 1 ? " · ×\(entry.count)" : "")")
                                .font(.app(.caption, .semibold)).foregroundStyle(Theme.caution)
                            Text(entry.message).font(.app(.subheadline)).foregroundStyle(Theme.text).lineLimit(3)
                        }
                    }
                }
            } footer: {
                Text("Lo stesso errore ripetuto entro 10 minuti viene contato (×N) invece di ripetuto. Molti errori di rete sono normali senza campo: l'app mostra l'ultima copia salvata.")
            }
        }
    }

    private var fullText: String {
        var parts: [String] = []
        if !log.entries.isEmpty { parts.append("CHIUSURE\n\n" + log.entries.map(Self.text).joined(separator: "\n\n————\n\n")) }
        if !errors.isEmpty { parts.append("ERRORI\n\n" + errors.map(Self.text).joined(separator: "\n\n")) }
        return ([CrashLog.version] + parts).joined(separator: "\n\n========\n\n")
    }

    static func text(_ e: CrashLog.Entry) -> String {
        ["\(e.kind) · \(Fmt.dayTime(e.date))", e.summary, e.screen.map { String(localized: "Schermata: \($0)") }, e.version, "", e.details]
            .compactMap { $0 }.joined(separator: "\n")
    }

    static func text(_ e: ErrorLog.Entry) -> String {
        let when = e.count > 1 ? "\(Fmt.dayTime(e.date)) → \(Fmt.dayTime(e.last)) · ×\(e.count)" : Fmt.dayTime(e.date)
        return ["\(when) · \(e.source)", e.message, e.detail].compactMap { $0 }.joined(separator: "\n")
    }
}

private struct LogTextView: View {
    let title: String
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.mono(11))
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
            }
        }
    }
}
