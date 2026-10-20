import SwiftUI
import MessageUI

/// Sharing the trip: by e-mail with the plan in the text and the GPX attached
/// (anyone; Norður opens the file and imports it), or straight to another
/// Norður account by its e-mail address (it appears in their Trip › Received).
struct TripShareSheet: View {
    @Environment(TripStore.self) private var trip
    @Environment(Account.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var title = String(localized: "Il mio viaggio in Islanda")
    @State private var recipient = ""
    @State private var composing = false
    @State private var sending = false
    @State private var message: String?
    @State private var failed = false
    @State private var signingIn = false

    var body: some View {
        let gpx = trip.exportGPX()
        NavigationStack {
            List {
                Section {
                    TextField("Nome del viaggio", text: $title)
                        .font(.app(.headline))
                } header: { Text("Viaggio").pinnedHeader() } footer: {
                    Text(String(localized: "\(trip.stops.count) tappe, \(trip.stops.reduce(0) { $0 + $1.visits.count }) attrazioni, \(trip.days.count) giorni."))
                }

                Section {
                    if MFMailComposeViewController.canSendMail(), gpx != nil {
                        Button { composing = true } label: {
                            Label("Scrivi un'email con il viaggio", systemImage: "envelope.fill").font(.app(.headline))
                        }
                    }
                    if let gpx {
                        ShareLink(item: gpx, subject: Text(title), message: Text(TripSummary.text(trip.days, title: title))) {
                            Label("Altre app (WhatsApp, Messaggi, File…)", systemImage: "square.and.arrow.up").font(.app(.headline))
                        }
                    }
                } header: { Text("Via email, a chiunque").pinnedHeader() } footer: {
                    Text("Nel testo il programma giorno per giorno; allegato il file GPX con tappe e attrazioni. Chi ha Norður tocca il file e lo importa nel suo Viaggio; gli altri lo aprono con Google Maps, Komoot o un'app GPS.")
                }

                Section {
                    if account.isSignedIn {
                        TextField("Email del destinatario", text: $recipient)
                            .keyboardType(.emailAddress).textContentType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button {
                            Task { await send() }
                        } label: {
                            HStack {
                                Label("Invia a questo utente Norður", systemImage: "paperplane.fill").font(.app(.headline))
                                if sending { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(sending || !recipient.contains("@") || trip.stops.isEmpty)
                    } else {
                        Button { signingIn = true } label: {
                            Label("Accedi per inviarlo a un altro utente", systemImage: "person.crop.circle")
                        }
                    }
                    if let message {
                        Label(message, systemImage: failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.app(.subheadline, .semibold)).foregroundStyle(failed ? Theme.danger : Theme.aurora)
                    }
                } header: { Text("A un altro utente Norður").pinnedHeader() } footer: {
                    Text("Il viaggio gli compare in Viaggio › Ricevuti, con l'accesso fatto con quell'indirizzo; se non ha ancora un account, lo trova appena lo crea.")
                }
            }
            .themedList()
            .navigationTitle("Condividi il viaggio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
            .sheet(isPresented: $composing) {
                if let gpx {
                    MailComposer(subject: title, html: TripSummary.html(trip.days, title: title), attachment: gpx) { composing = false }
                        .ignoresSafeArea()
                }
            }
            .sheet(isPresented: $signingIn) { AccountView() }
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        do {
            let notified = try await account.shareTrip(trip.stops, title: title, to: recipient.trimmingCharacters(in: .whitespaces))
            failed = false
            message = notified ? String(localized: "Inviato: gli arriva anche un'email di avviso.")
                               : String(localized: "Inviato: lo trova in Viaggio › Ricevuti.")
            Haptics.result(true)
        } catch {
            failed = true
            message = error.localizedDescription
            Haptics.result(false)
        }
    }
}

/// The plan day by day, as text and as HTML for the e-mail.
enum TripSummary {
    static func lines(_ days: [TripDay]) -> [(day: String, title: String, items: [String])] {
        days.map { day in
            let title: String
            if let a = day.arriving, let f = day.from { title = "\(f.place.name) → \(a.place.name)" }
            else if let n = day.night { title = n.place.name }
            else { title = String(localized: "Rientro") }
            var items = day.visits.map { "\(Fmt.time($0.visit.date, in: .iceland)) \($0.visit.place.name)" }
            if let n = day.night { items.append(String(localized: "Notte: \(n.place.name)")) }
            return (String(localized: "Giorno \(day.number) · \(Fmt.day(day.date, in: .iceland))"), title, items)
        }
    }

    static func text(_ days: [TripDay], title: String) -> String {
        ([title, ""] + lines(days).flatMap { [$0.day + " — " + $0.title] + $0.items.map { "  • " + $0 } + [""] }
            + [String(localized: "Allegato: il viaggio in GPX, da aprire con Norður.")]).joined(separator: "\n")
    }

    static func html(_ days: [TripDay], title: String) -> String {
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;") }
        var out = "<div style=\"font-family:-apple-system,Helvetica,Arial,sans-serif;font-size:16px;line-height:1.45\"><h2>\(esc(title))</h2>"
        for l in lines(days) {
            out += "<p><b>\(esc(l.day))</b><br>\(esc(l.title))</p><ul>" + l.items.map { "<li>\(esc($0))</li>" }.joined() + "</ul>"
        }
        out += "<p style=\"color:#666\">" + esc(String(localized: "In allegato il viaggio in GPX: aprilo con Norður per importarlo, o con Google Maps / un'app GPS.")) + "</p></div>"
        return out
    }
}

/// Mail's own composer, with the GPX attached.
struct MailComposer: UIViewControllerRepresentable {
    let subject: String
    let html: String
    let attachment: URL
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let mail = MFMailComposeViewController()
        mail.mailComposeDelegate = context.coordinator
        mail.setSubject(subject)
        mail.setMessageBody(html, isHTML: true)
        if let data = try? Data(contentsOf: attachment) {
            mail.addAttachmentData(data, mimeType: "application/gpx+xml", fileName: "\(subject).gpx")
        }
        return mail
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish()
        }
    }
}

/// Trips other users sent to this account, at the top of Trip.
struct ReceivedTripsSection: View {
    @Environment(Account.self) private var account
    @Environment(TripStore.self) private var trip
    @State private var items: [Account.ReceivedTrip] = []
    @State private var choosing: Account.ReceivedTrip?

    var body: some View {
        Group {
            if !items.isEmpty {
                Section {
                    ForEach(items) { item in
                        Button { choosing = item } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 20)).foregroundStyle(Theme.accent).frame(width: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.app(.headline)).foregroundStyle(Theme.text)
                                    Text(String(localized: "Da \(item.from) · \(item.payload.count) tappe"))
                                        .font(.app(.caption)).foregroundStyle(Theme.dim)
                                }
                                Spacer()
                                Text("APRI").font(.mono(11, .semibold)).foregroundStyle(Theme.accent)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: { Text("Ricevuti").pinnedHeader() }
            }
        }
        .task(id: account.isSignedIn) { await load() }
        .confirmationDialog(choosing?.title ?? "", isPresented: Binding(get: { choosing != nil }, set: { if !$0 { choosing = nil } }), titleVisibility: .visible) {
            if let item = choosing {
                Button(trip.stops.isEmpty ? String(localized: "Importa come mio viaggio") : String(localized: "Sostituisci il mio viaggio")) {
                    trip.adopt(item.payload, replacing: true); remove(item)
                }
                if !trip.stops.isEmpty {
                    Button("Aggiungi dopo il mio viaggio") { trip.adopt(item.payload, replacing: false); remove(item) }
                }
                Button("Elimina", role: .destructive) { remove(item) }
            }
        } message: { Text(String(localized: "Condiviso da \(choosing?.from ?? "")")) }
    }

    private func load() async {
        guard account.isSignedIn else { items = []; return }
        items = (try? await account.receivedTrips()) ?? []
    }

    private func remove(_ item: Account.ReceivedTrip) {
        items.removeAll { $0.id == item.id }
        Haptics.result(true)
        Task { try? await account.deleteReceived(item.id) }
    }
}
