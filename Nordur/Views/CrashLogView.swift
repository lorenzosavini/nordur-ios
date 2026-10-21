import SwiftUI

/// Settings › Registro errori: every time the app closed by itself, why, and
/// the details to send.
struct CrashLogView: View {
    private var log: CrashLog { CrashLog.shared }

    var body: some View {
        List {
            if log.entries.isEmpty {
                EmptyState(symbol: "checkmark.seal", title: String(localized: "Nessuna chiusura registrata"),
                           message: String(localized: "Se l'app si chiude da sola, qui trovi quando, dove e perché."))
            } else {
                Section {
                    ShareLink(item: log.text, subject: Text("Norður: registro errori")) {
                        Label("Invia il registro", systemImage: "square.and.arrow.up")
                    }
                    Button { UIPasteboard.general.string = log.text; Haptics.result(true) } label: {
                        Label("Copia tutto", systemImage: "doc.on.doc")
                    }
                }
                Section {
                    ForEach(log.entries) { entry in
                        NavigationLink { CrashEntryView(entry: entry) } label: {
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
        .themedList()
        .navigationTitle("Registro errori")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !log.entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Svuota", role: .destructive) { log.clear() }
                }
            }
        }
    }
}

private struct CrashEntryView: View {
    let entry: CrashLog.Entry

    var body: some View {
        let text = ["\(entry.kind) · \(Fmt.dayTime(entry.date))", entry.summary,
                    entry.screen.map { String(localized: "Schermata: \($0)") }, entry.version, "", entry.details]
            .compactMap { $0 }.joined(separator: "\n")
        ScrollView {
            Text(text)
                .font(.mono(11))
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle(entry.kind)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
            }
        }
    }
}
