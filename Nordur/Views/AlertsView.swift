import SwiftUI
import CoreLocation
import AVFoundation

/// Inbox of every alert raised, newest first.
struct AlertsView: View {
    @Environment(AlertCenter.self) private var alerts
    @Environment(\.dismiss) private var dismiss
    @State private var filter: AlertCategory?
    @State private var query = ""
    @State private var onlyUnread = false
    @State private var opened: AlertEvent?

    private var shown: [AlertEvent] {
        alerts.events.filter { event in
            (filter == nil || event.category == filter)
                && (!onlyUnread || !event.read)
                && (query.isEmpty || event.title.localizedCaseInsensitiveContains(query) || event.body.localizedCaseInsensitiveContains(query))
        }
    }

    /// Shown alerts in three parts: in progress now, still to come, ended.
    private var phases: [(phase: AlertLifecycle.Phase, events: [AlertEvent])] {
        let now = Date()
        let groups = Dictionary(grouping: shown) { AlertLifecycle.phase(starts: $0.starts, expires: $0.expires, noticed: $0.date, now: now) }
        return AlertLifecycle.Phase.allCases.compactMap { phase in
            guard let list = groups[phase], !list.isEmpty else { return nil }
            let sorted = phase == .upcoming ? list.sorted { ($0.starts ?? $0.date) < ($1.starts ?? $1.date) } : list.sorted { $0.date > $1.date }
            return (phase, sorted)
        }
    }

    private func phaseTitle(_ phase: AlertLifecycle.Phase) -> String {
        switch phase {
        case .now: return String(localized: "Adesso")
        case .upcoming: return String(localized: "In arrivo")
        case .ended: return String(localized: "Terminate")
        }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: alerts.notificationsAllowed ? "bell.badge.fill" : "bell.slash.fill")
                        .foregroundStyle(alerts.notificationsAllowed ? Color.green : Color.red)
                    VStack(alignment: .leading) {
                        Text(alerts.notificationsAllowed ? String(localized: "Notifiche attive") : String(localized: "Notifiche disattivate")).font(.app(.subheadline, .semibold))
                        if let last = alerts.lastCheck {
                            Text("Ultimo controllo \(Fmt.relative(last))").font(.app(.caption)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if alerts.isChecking {
                        ProgressView()
                    } else {
                        Button("Controlla ora") { Task { await alerts.check() } }
                            .buttonStyle(.bordered)
                    }
                }
                if !alerts.notificationsAllowed {
                    Button("Attiva le notifiche") { Task { await alerts.requestNotificationPermission() } }
                }
                NavigationLink {
                    AlertSettingsView()
                } label: {
                    Label("Impostazioni allerte", systemImage: "slider.horizontal.3")
                }
            }

            Section {
                Toggle(isOn: $onlyUnread) { Label("Solo da leggere (\(alerts.unreadCount))", systemImage: "envelope.badge") }
                    .font(.app(.subheadline))
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    chip(nil, String(localized: "Tutte"), count: alerts.events.count)
                    ForEach(AlertCategory.allCases) { category in
                        let count = alerts.events.filter { $0.category == category }.count
                        if count > 0 || filter == category { chip(category, category.shortLabel, count: count) }
                    }
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }

            if shown.isEmpty {
                if alerts.events.isEmpty {
                    ContentUnavailableView("Nessuna allerta", systemImage: "checkmark.seal",
                                           description: Text("Qui compaiono le allerte inviate."))
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }

            ForEach(phases, id: \.phase) { group in
                Section {
                    ForEach(group.events) { event in
                        NavigationLink(value: event) {
                            AlertRow(event: event)
                        }
                        .accessibilityIdentifier("alert.row")
                        .swipeActions {
                            Button(role: .destructive) { alerts.delete(event) } label: { Label("Elimina", systemImage: "trash") }
                        }
                        .swipeActions(edge: .leading) {
                            if !event.read {
                                Button { alerts.markRead(event) } label: { Label("Letta", systemImage: "envelope.open") }.tint(.blue)
                            }
                        }
                    }
                } header: {
                    Text("\(phaseTitle(group.phase)) · \(group.events.count)").pinnedHeader().pinnedHeader().pinnedHeader()
                }
            }
        }
        .searchable(text: $query, prompt: Text("Cerca nelle allerte"))
        .navigationDestination(for: AlertEvent.self) { AlertDetailView(event: $0) }
        .navigationDestination(item: $opened) { AlertDetailView(event: $0) }
        .onAppear(perform: openFocused)
        .onChange(of: alerts.focusedAlertID) { openFocused() }
        .themedList()
        .navigationTitle("Allerte")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Chiudi") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Segna tutte come lette", systemImage: "envelope.open") { alerts.markAllRead() }
                    Button("Svuota", systemImage: "trash", role: .destructive) { alerts.clearAll() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .refreshable { await alerts.check() }
    }

    /// Opens the alert whose notification was tapped.
    private func openFocused() {
        guard let id = alerts.focusedAlertID else { return }
        alerts.focusedAlertID = nil
        opened = alerts.events.first { $0.id == id }
    }

    private func chip(_ category: AlertCategory?, _ title: String, count: Int) -> some View {
        Button {
            filter = category
        } label: {
            Label("\(title) \(count)", systemImage: category?.symbol ?? "tray.full")
                .font(.app(.caption))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(filter == category ? Theme.bg : Theme.text)
                .background(filter == category ? Theme.text : Color.clear, in: Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AlertRow: View {
    let event: AlertEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Same picture as the notification: category colour and symbol.
            Image(systemName: event.category.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color(NotificationIcon.color(event.category)))
                .overlay(alignment: .bottom) {
                    if event.risk >= .warning { event.risk.color.frame(height: 3) }
                }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(event.title).font(.app(.subheadline, event.read ? .regular : .semibold))
                    if !event.read { Circle().fill(Color.accentColor).frame(width: 7, height: 7) }
                }
                Text(event.body).font(.app(.caption)).foregroundStyle(.secondary).lineLimit(3)
                HStack(spacing: 6) {
                    // When it was noticed, and whether it still applies.
                    Text(Fmt.dayTime(event.date)).font(.app(.caption2)).foregroundStyle(.tertiary)
                    switch AlertLifecycle.phase(starts: event.starts, expires: event.expires, noticed: event.date, now: Date()) {
                    case .upcoming:
                        Text("· dalle \(Fmt.dayTime(event.starts))").font(.app(.caption2, .semibold)).foregroundStyle(event.risk.color)
                    case .now:
                        if let expires = event.expires {
                            Text("· in corso fino alle \(Fmt.time(expires))").font(.app(.caption2, .semibold)).foregroundStyle(event.risk.color)
                        }
                    case .ended:
                        Text("· terminata").font(.app(.caption2)).foregroundStyle(.tertiary)
                    }
                    if event.coordinate != nil {
                        Image(systemName: "mappin.and.ellipse").font(.app(.caption2)).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .opacity(AlertLifecycle.phase(starts: event.starts, expires: event.expires, noticed: event.date, now: Date()) == .ended ? 0.55 : 1)
    }
}

struct AlertSettingsView: View {
    @Environment(AlertCenter.self) private var alerts
    @State private var draft = AlertSettings()
    @State private var loaded = false
    @State private var newFlight = ""

    var body: some View {
        Form {
            Section {
                ForEach(AlertCategory.allCases.filter { $0 != .notice && $0 != .summary }) { category in
                    Toggle(isOn: binding(for: category)) {
                        Label(category.label, systemImage: category.symbol)
                    }
                }
            } header: {
                Text("Cosa monitorare").pinnedHeader().pinnedHeader().pinnedHeader()
            } footer: {
                Text("Allerte IMO, vento, pioggia forte, neve, ghiaccio e strade vengono controllati dove sei davvero, alle tappe del viaggio nei giorni in cui ci sarai e lungo i tragitti tra una tappa e l'altra fino a dopodomani. Durante una registrazione di guida anche la strada davanti a te.")
            }

            Section {
                if draft.followed.isEmpty {
                    Text("Nessun luogo seguito. Scegli un luogo in alto nella schermata Oggi e tocca la campanella.")
                        .font(.app(.subheadline)).foregroundStyle(Theme.dim)
                }
                ForEach(draft.followed) { place in
                    Label(place.name, systemImage: "bell.fill")
                }
                .onDelete { offsets in
                    var list = draft.followed
                    list.remove(atOffsets: offsets)
                    draft.followedPlaces = list
                }
            } header: { Text("Luoghi seguiti").pinnedHeader() } footer: {
                Text("Fino a \(AlertSettings.followLimit) luoghi seguiti anche senza metterli nel viaggio: ricevi le allerte meteo IMO, le strade chiuse e i terremoti vicini. Vento, raffiche e aurora restano per dove sei davvero e per le tappe del viaggio.")
            }

            Section {
                Toggle(isOn: Binding(get: { draft.eveningSummary }, set: { draft.eveningSummaryOff = !$0 })) {
                    Label("Riepilogo serale del viaggio", systemImage: "calendar.badge.clock")
                }
                Toggle(isOn: Binding(get: { draft.quietNights }, set: { draft.quietNightsOff = !$0 })) {
                    Label("Notti silenziose", systemImage: "moon.zzz")
                }
            } header: { Text("Quando avvisare").pinnedHeader() } footer: {
                Text("Una notifica arriva quando un'allerta è nuova, peggiora o inizia prima; se resta uguale si aggiorna solo nell'elenco. Un luogo che stai solo guardando compare nelle schermate ma non manda notifiche, a meno che tu non lo segua con la campanella. Il riepilogo arriva la sera prima di ogni giorno di viaggio (dalle 19:30, ora islandese): il tragitto, vento, pioggia, strade chiuse, allerte e aurora. Di notte (22:30–7:00) solo il pericolo suona; l'arancione arriva senza suono, il resto in silenzio nel Centro notifiche.")
            }

            Section {
                Toggle("Includi allerte gialle", isOn: $draft.includeYellow)
                Stepper("Raffiche da \(Fmt.ms(draft.gustThreshold))", value: $draft.gustThreshold, in: 12...40, step: 1)
                Stepper("…entro \(Int(draft.gustRadiusKm)) km", value: $draft.gustRadiusKm, in: 5...100, step: 5)
                Stepper("Strade chiuse entro \(Int(draft.roadRadiusKm)) km", value: $draft.roadRadiusKm, in: 10...150, step: 10)
                Stepper("Terremoti da M\(Fmt.number(draft.quakeMagnitude, decimals: 1))", value: $draft.quakeMagnitude, in: 1...6, step: 0.5)
                Stepper("…entro \(Int(draft.quakeRadiusKm)) km", value: $draft.quakeRadiusKm, in: 10...400, step: 10)
                Picker("Aurora: avvisa da", selection: Binding(get: { draft.auroraClass.rawValue }, set: { draft.auroraMinClass = $0 })) {
                    ForEach([ObservabilityClass.moderate, .good, .excellent], id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
                Stepper("Avvisi NOAA e CME NASA da Kp \(Fmt.number(draft.auroraKp))", value: Binding(get: { draft.auroraKp }, set: { draft.auroraKpAlert = $0 }), in: 3...8, step: 1)
            } header: { Text("Soglie").pinnedHeader() }

            Section {
                Picker("Sorveglianza aurora", selection: Binding(get: { draft.auroraWatch }, set: { draft.auroraWatchMode = $0.rawValue })) {
                    ForEach(AuroraWatchMode.allCases) { Text($0.label).tag($0) }
                }
                if AuroraWatch.shared.isActive {
                    Label(AuroraWatch.shared.lastRun.map { String(localized: "Attiva: ultimo controllo alle \(Fmt.time($0))") } ?? String(localized: "Attiva"),
                          systemImage: "dot.radiowaves.left.and.right")
                        .font(.app(.caption)).foregroundStyle(Theme.aurora)
                }
            } header: {
                Text("Aurora in tempo reale").pinnedHeader()
            } footer: {
                Text("Con l'app chiusa iOS la sveglia solo di rado, soprattutto di notte. Con la sorveglianza attiva l'aurora (attività adesso, Bz, allerte NOAA) viene controllata ogni 3 minuti per il luogo scelto, o per la tappa del viaggio di stanotte: l'app resta attiva in background con la posizione a bassa precisione (vedi l'indicatore blu) e consuma un po' più batteria. «Di notte» si accende al tramonto e si spegne all'alba.")
            }

            Section {
                Toggle("Suoni Norður per ogni tipo di avviso", isOn: Binding(get: { draft.customSounds }, set: { draft.customSoundsOff = !$0 }))
                if draft.customSounds {
                    ForEach(NotificationSoundPreview.all, id: \.file) { item in
                        Button { NotificationSoundPreview.play(item.file) } label: {
                            Label(item.label, systemImage: "speaker.wave.2")
                        }
                    }
                }
            } header: {
                Text("Suoni").pinnedHeader()
            } footer: {
                Text("L'aurora ha il suo suono, gli altri avvisi uno diverso per tipo: capisci cos'è senza guardare. Tocca per ascoltarli. Con il telefono in silenzioso non suonano.")
            }

            Section {
                Toggle("Avvisi vocali durante la guida", isOn: $draft.spoken)
                Toggle("Allerte in base a dove ti trovi, anche ad app chiusa", isOn: $draft.backgroundLocation)
                if draft.backgroundLocation && alerts.backgroundLocationStatus != .authorizedAlways {
                    Label("Serve l'accesso alla posizione «Sempre»: Impostazioni › Norður › Posizione.", systemImage: "location.slash")
                        .font(.app(.caption)).foregroundStyle(.orange)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Apri Impostazioni", destination: url)
                    }
                }
            } header: {
                Text("In viaggio").pinnedHeader().pinnedHeader().pinnedHeader()
            } footer: {
                Text("Ogni volta che ti sposti di circa 2 km l'app controlla allerte, strade, vento e terremoti intorno a te, anche se non stai registrando un percorso. Serve l'accesso alla posizione «Sempre».")
            }

            Section {
                ForEach(draft.followedFlights, id: \.self) { flight in
                    Text(flight)
                }
                .onDelete { draft.followedFlights.remove(atOffsets: $0) }
                HStack {
                    TextField("Es. FI204", text: $newFlight)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("Aggiungi") {
                        let code = newFlight.uppercased().replacingOccurrences(of: " ", with: "")
                        if !code.isEmpty && !draft.followedFlights.contains(code) { draft.followedFlights.append(code) }
                        newFlight = ""
                    }
                    .disabled(newFlight.isEmpty)
                }
            } header: { Text("Voli seguiti").pinnedHeader() }

            Section {
                Button("Invia una notifica di prova") {
                    alerts.record(AlertEvent(id: "test:\(Date().timeIntervalSince1970)", date: Date(), category: .weatherWarning,
                                             severity: Risk.caution.rawValue, title: String(localized: "Notifica di prova"),
                                             body: String(localized: "Le notifiche funzionano.")), notify: true, speak: false)
                }
            }
        }
        .themedList()
        .navigationTitle("Impostazioni allerte")
        .onAppear {
            if !loaded { draft = alerts.settings; loaded = true }
        }
        .onChange(of: draft) { _, value in alerts.update(value) }
    }

    private func binding(for category: AlertCategory) -> Binding<Bool> {
        Binding(
            get: { draft.enabled.contains(category) },
            set: { on in
                if on { draft.enabled.insert(category) } else { draft.enabled.remove(category) }
            }
        )
    }
}

/// Plays the notification sounds in Settings, to hear which is which.
enum NotificationSoundPreview {
    static let all: [(file: String, label: String)] = [
        ("aurora_now", String(localized: "Aurora: esci adesso")),
        ("aurora_soon", String(localized: "Aurora: preparati, stanotte")),
        ("warning", String(localized: "Allerta meteo gialla")),
        ("warning_urgent", String(localized: "Allerta meteo arancione o rossa")),
        ("wind", String(localized: "Vento e raffiche")),
        ("road", String(localized: "Strade")),
        ("quake", String(localized: "Terremoti")),
        ("info", String(localized: "SafeTravel")),
        ("flight", String(localized: "Voli")),
        ("ferry", String(localized: "Traghetto")),
        ("speed", String(localized: "Velocità in guida")),
    ]
    private static var player: AVAudioPlayer?

    static func play(_ file: String) {
        guard let url = Bundle.main.url(forResource: file, withExtension: "wav") else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}
