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

                TogetherSection()

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
                } header: { Text("Invia una copia via email").pinnedHeader() } footer: {
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
                } header: { Text("Invia una copia a un utente Norður").pinnedHeader() } footer: {
                    Text("Una copia separata: gli compare in Viaggio › Ricevuti. Le modifiche non si sincronizzano: per quello usa «Modificatelo insieme» qui sopra.")
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
        days.map { day -> (day: String, title: String, items: [String]) in
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
        var out: [String] = [title, ""]
        for line in lines(days) {
            out.append(line.day + " — " + line.title)
            for item in line.items { out.append("  • " + item) }
            out.append("")
        }
        out.append(String(localized: "Allegato: il viaggio in GPX, da aprire con Norður."))
        return out.joined(separator: "\n")
    }

    static func html(_ days: [TripDay], title: String) -> String {
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;") }
        var out = "<div style=\"font-family:-apple-system,Helvetica,Arial,sans-serif;font-size:16px;line-height:1.45\"><h2>\(esc(title))</h2>"
        for l in lines(days) {
            out += "<p><b>\(esc(l.day))</b><br>\(esc(l.title))</p><ul>"
            for item in l.items { out += "<li>\(esc(item))</li>" }
            out += "</ul>"
        }
        let note = esc(String(localized: "In allegato il viaggio in GPX: aprilo con Norður per importarlo, o con Google Maps / un'app GPS."))
        out += "<p style=\"color:#666\">\(note)</p></div>"
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

/// Trips other users sent to this account: invitations to plan together, and
/// copies. Inline at the top of Trip when there is something, and as its own page.
struct ReceivedTripsSection: View {
    @Environment(Account.self) private var account
    @Environment(TripStore.self) private var trip
    /// The page shows its sections even when empty, with what to do.
    var page = false
    @State private var choosing: Account.ReceivedTrip?
    @State private var joining: Account.SharedTripSummary?
    @State private var joinError: String?
    @State private var signingIn = false

    var body: some View {
        Group {
            if page && !account.isSignedIn {
                Section {
                    Button { signingIn = true } label: { Label("Accedi per vedere i viaggi condivisi con te", systemImage: "person.crop.circle") }
                } footer: {
                    Text("I viaggi arrivano all'indirizzo email del tuo account Norður: accedi con quello a cui te li hanno mandati.")
                }
            }
            if !trip.invitations.isEmpty || (page && account.isSignedIn) {
                Section {
                    if trip.invitations.isEmpty {
                        Text("Nessun invito. Quando qualcuno ti invita a modificare insieme un viaggio, compare qui.")
                            .font(.app(.subheadline)).foregroundStyle(Theme.dim)
                    }
                    ForEach(trip.invitations) { invite in
                        Button { joining = invite } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.2.fill").font(.system(size: 20)).foregroundStyle(Theme.aurora).frame(width: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(invite.title).font(.app(.headline)).foregroundStyle(Theme.text)
                                    Text(String(localized: "Da modificare insieme · di \(invite.owner) · \(invite.stops) tappe"))
                                        .font(.app(.caption)).foregroundStyle(Theme.dim)
                                }
                                Spacer()
                                Text("PARTECIPA").font(.mono(11, .semibold)).foregroundStyle(Theme.aurora)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if let joinError { Text(joinError).font(.app(.caption)).foregroundStyle(Theme.danger) }
                } header: { Text("Inviti a modificare insieme").pinnedHeader() }
            }
            if !trip.received.isEmpty || (page && account.isSignedIn) {
                Section {
                    if trip.received.isEmpty {
                        Text("Nessuna copia ricevuta.").font(.app(.subheadline)).foregroundStyle(Theme.dim)
                    }
                    ForEach(trip.received) { item in
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
                } header: { Text("Copie ricevute").pinnedHeader() }
            }
        }
        .task(id: account.isSignedIn) { await trip.refreshInbox() }
        .sheet(isPresented: $signingIn) { AccountView() }
        .confirmationDialog(joining?.title ?? "", isPresented: Binding(get: { joining != nil }, set: { if !$0 { joining = nil } }), titleVisibility: .visible) {
            if let invite = joining {
                Button(trip.stops.isEmpty ? String(localized: "Partecipa") : String(localized: "Partecipa (sostituisce il viaggio sul telefono)")) {
                    Task {
                        do {
                            try await trip.join(invite.id)
                            await trip.refreshInbox()
                            joinError = nil
                            Haptics.result(true)
                        } catch {
                            joinError = error.localizedDescription
                        }
                    }
                }
            }
        } message: { Text("Da qui in poi le modifiche di ognuno arrivano a tutti.") }
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

    private func remove(_ item: Account.ReceivedTrip) {
        Haptics.result(true)
        Task { await trip.removeReceived(item.id) }
    }
}

/// Trip › RICEVUTI: everything shared with this account, always reachable.
struct ReceivedTripsView: View {
    @Environment(TripStore.self) private var trip
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ReceivedTripsSection(page: true)
            }
            .themedList()
            .navigationTitle("Viaggi ricevuti")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
            .refreshable { await trip.refreshInbox() }
        }
    }
}

/// "Plan it together": the trip lives on the server, every member's phone keeps
/// it in step, and each change reaches the others within half a minute.
struct TogetherSection: View {
    @Environment(TripStore.self) private var trip
    @Environment(Account.self) private var account
    @State private var email = ""
    @State private var working = false
    @State private var message: String?
    @State private var failed = false
    @State private var confirmLeave = false
    @State private var signingIn = false

    var body: some View {
        Section {
            if let shared = trip.shared {
                ForEach(shared.members, id: \.self) { member in
                    Label(member == account.email ? String(localized: "\(member) (tu)") : member,
                          systemImage: member == shared.owner ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                        .font(.app(.subheadline))
                }
                SharedStatusLine()
            }
            if account.isSignedIn {
                TextField("Email della persona da invitare", text: $email)
                    .keyboardType(.emailAddress).textContentType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button { Task { await invite() } } label: {
                    HStack {
                        Label(trip.shared == nil ? String(localized: "Modificatelo insieme") : String(localized: "Invita anche questa persona"),
                              systemImage: "person.2.fill").font(.app(.headline))
                        if working { Spacer(); ProgressView() }
                    }
                }
                .disabled(working || !email.contains("@") || trip.stops.isEmpty)
                if trip.shared != nil {
                    Button(role: .destructive) { confirmLeave = true } label: {
                        Label("Smetti di modificare insieme", systemImage: "person.2.slash")
                    }
                }
            } else {
                Button { signingIn = true } label: { Label("Accedi per modificarlo insieme", systemImage: "person.crop.circle") }
            }
            if let message {
                Label(message, systemImage: failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.app(.subheadline, .semibold)).foregroundStyle(failed ? Theme.danger : Theme.aurora)
            }
        } header: { Text("Modificatelo insieme").pinnedHeader() } footer: {
            Text("Le persone invitate lo trovano in Viaggio › Ricevuti e partecipano: da quel momento tappe, attrazioni, orari e note cambiati da uno arrivano a tutti in pochi secondi. Se due persone cambiano cose diverse restano entrambe le modifiche; sulla stessa cosa vale la più recente.")
        }
        .confirmationDialog("Smettere di modificare insieme?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Smetti", role: .destructive) { Task { await trip.leaveShared() } }
        } message: { Text("Il viaggio resta sul tuo telefono com'è adesso; gli altri continuano con il loro.") }
        .sheet(isPresented: $signingIn) { AccountView() }
    }

    private func invite() async {
        working = true
        defer { working = false }
        do {
            let notified = try await trip.shareTogether(title: trip.shared?.title ?? String(localized: "Il nostro viaggio in Islanda"),
                                                        with: email.trimmingCharacters(in: .whitespaces).lowercased())
            failed = false
            message = notified ? String(localized: "Invito inviato, anche per email.") : String(localized: "Invito inviato: lo trova in Viaggio › Ricevuti.")
            email = ""
            Haptics.result(true)
        } catch {
            failed = true
            message = error.localizedDescription
            Haptics.result(false)
        }
    }
}

/// "Edited together with … · up to date 10 s ago".
struct SharedStatusLine: View {
    @Environment(TripStore.self) private var trip
    @Environment(Account.self) private var account

    var body: some View {
        if let shared = trip.shared {
            let others = shared.members.filter { $0 != account.email }
            VStack(alignment: .leading, spacing: 3) {
                Label(others.isEmpty ? String(localized: "Condiviso: in attesa che gli invitati partecipino")
                                     : String(localized: "Insieme a \(others.joined(separator: ", "))"),
                      systemImage: "person.2.fill")
                    .font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text)
                TimelineView(.periodic(from: .now, by: 10)) { _ in
                    Text(trip.isSyncingShared ? String(localized: "Sincronizzazione…")
                         : trip.sharedError.map { String(localized: "Non sincronizzato: \($0)") }
                         ?? shared.lastSynced.map { String(localized: "Aggiornato \(Fmt.relative($0))") } ?? "")
                        .font(.app(.caption)).foregroundStyle(trip.sharedError == nil ? Theme.dim : Theme.danger)
                }
            }
        }
    }
}
