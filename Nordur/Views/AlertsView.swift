import SwiftUI
import CoreLocation

/// Inbox of every alert raised, newest first.
struct AlertsView: View {
    @Environment(AlertCenter.self) private var alerts
    @Environment(\.dismiss) private var dismiss
    @State private var filter: AlertCategory?

    private var shown: [AlertEvent] {
        guard let filter else { return alerts.events }
        return alerts.events.filter { $0.category == filter }
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        chip(nil, String(localized: "Tutte"))
                        ForEach(AlertCategory.allCases) { category in
                            chip(category, category.label)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }

            if shown.isEmpty {
                ContentUnavailableView("Nessuna allerta", systemImage: "checkmark.seal",
                                       description: Text("Qui compaiono le allerte inviate."))
            }

            ForEach(shown) { event in
                AlertRow(event: event)
                    .swipeActions {
                        Button(role: .destructive) { alerts.delete(event) } label: { Label("Elimina", systemImage: "trash") }
                    }
            }
        }
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
        .onDisappear { alerts.markAllRead() }
    }

    private func chip(_ category: AlertCategory?, _ title: String) -> some View {
        Button {
            filter = category
        } label: {
            Label(title, systemImage: category?.symbol ?? "tray.full")
                .font(.app(.caption))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(filter == category ? Theme.text : Color.clear, in: Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AlertRow: View {
    let event: AlertEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.category.symbol)
                .foregroundStyle(event.risk.color)
                .font(.app(.title3))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(event.title).font(.app(.subheadline, event.read ? .regular : .semibold))
                    if !event.read { Circle().fill(Color.accentColor).frame(width: 7, height: 7) }
                }
                Text(event.body).font(.app(.caption)).foregroundStyle(.secondary)
                Text(Fmt.dayTime(event.date)).font(.app(.caption2)).foregroundStyle(.tertiary)
            }
        }
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
                ForEach(AlertCategory.allCases) { category in
                    Toggle(isOn: binding(for: category)) {
                        Label(category.label, systemImage: category.symbol)
                    }
                }
            } header: {
                Text("Cosa monitorare")
            } footer: {
                Text("Le allerte IMO e i terremoti vengono controllati per la tua posizione e per le tappe del viaggio dei prossimi 3 giorni.")
            }

            Section("Soglie") {
                Toggle("Includi allerte gialle", isOn: $draft.includeYellow)
                Stepper("Raffiche da \(Int(draft.gustThreshold)) m/s", value: $draft.gustThreshold, in: 12...40, step: 1)
                Stepper("…entro \(Int(draft.gustRadiusKm)) km", value: $draft.gustRadiusKm, in: 5...100, step: 5)
                Stepper("Strade chiuse entro \(Int(draft.roadRadiusKm)) km", value: $draft.roadRadiusKm, in: 10...150, step: 10)
                Stepper("Terremoti da M\(Fmt.number(draft.quakeMagnitude, decimals: 1))", value: $draft.quakeMagnitude, in: 1...6, step: 0.5)
                Stepper("…entro \(Int(draft.quakeRadiusKm)) km", value: $draft.quakeRadiusKm, in: 10...400, step: 10)
                Picker("Aurora: avvisa da", selection: Binding(get: { draft.auroraClass.rawValue }, set: { draft.auroraMinClass = $0 })) {
                    ForEach([ObservabilityClass.moderate, .good, .excellent], id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
                Stepper("Avvisi NOAA e CME NASA da Kp \(Fmt.number(draft.auroraKp))", value: Binding(get: { draft.auroraKp }, set: { draft.auroraKpAlert = $0 }), in: 3...8, step: 1)
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
                Text("In viaggio")
            } footer: {
                Text("Ogni volta che ti sposti di circa 2 km l'app controlla allerte, strade, vento e terremoti intorno a te, anche se non stai registrando un percorso. Serve l'accesso alla posizione «Sempre».")
            }

            Section("Voli seguiti") {
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
            }

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
