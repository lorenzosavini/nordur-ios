import SwiftUI

/// Keflavík flight board, ferries and buses.
struct TransportView: View {
    @Environment(AppModel.self) private var model
    @Environment(AlertCenter.self) private var alerts
    @State private var direction = Direction.departures
    @State private var query = ""
    @State private var showPast = false

    enum Direction: String, CaseIterable, Identifiable {
        case departures = "Partenze", arrivals = "Arrivi"
        var id: String { rawValue }
    }

    private var flights: [Flight] {
        let all = model.flights?.value ?? []
        let cutoff = Date().addingTimeInterval(-90 * 60)
        return all.filter { flight in
            (flight.arrival == (direction == .arrivals))
            && (showPast || (flight.scheduled ?? .distantFuture) >= cutoff)
            && (query.isEmpty || flight.flightNumber.localizedCaseInsensitiveContains(query)
                || (flight.destination ?? "").localizedCaseInsensitiveContains(query)
                || (flight.airline ?? "").localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        List {
            Section {
                if let fetched = model.ferry {
                    if let notice = fetched.value {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Herjólfur – Vestmannaeyjar", systemImage: "ferry.fill").font(.app(.subheadline, .semibold))
                            Text(notice.text).font(.app(.caption))
                            FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: "herjolfur.is")
                        }
                    } else {
                        Label("Herjólfur: nessun avviso, orario regolare", systemImage: "ferry")
                    }
                }
                Toggle("Avvisami se cambia l'avviso Herjólfur", isOn: Binding(
                    get: { alerts.settings.isOn(.ferry) },
                    set: { on in
                        var s = alerts.settings
                        if on { s.enabled.insert(.ferry) } else { s.enabled.remove(.ferry) }
                        alerts.update(s)
                    }))
                .font(.app(.caption))
                LinkRow(title: "Herjólfur – orari e prenotazioni", subtitle: "Landeyjahöfn / Þorlákshöfn ↔ Vestmannaeyjar", url: TransportService.herjolfurPage, systemImage: "ferry")
                LinkRow(title: "Baldur (Sæferðir)", subtitle: "Stykkishólmur – Flatey – Brjánslækur", url: "https://www.saeferdir.is/en/", systemImage: "ferry.fill")
                LinkRow(title: "Smyril Line", subtitle: "Seyðisfjörður – Fær Øer – Danimarca", url: "https://www.smyrilline.com/", systemImage: "ferry")
            } header: {
                Text("Traghetti")
            }

            Section {
                Picker("Direzione", selection: $direction) {
                    ForEach(Direction.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Mostra anche i voli già passati", isOn: $showPast).font(.app(.caption))
                if let fetched = model.flights {
                    FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: "kefairport.com")
                }
                ErrorNote(message: model.errors[.flights])
                if model.flights == nil && model.errors[.flights] == nil { ProgressView() }
                ForEach(flights) { flight in
                    FlightRow(flight: flight, following: alerts.isFollowing(flight.flightNumber)) {
                        alerts.toggleFollow(flight.flightNumber)
                    }
                }
            } header: {
                Text("Aeroporto di Keflavík (oggi)")
            } footer: {
                Text("Con la stella ricevi una notifica a ogni cambio di stato, orario o gate.")
            }

            Section("Altri collegamenti") {
                LinkRow(title: "Voli interni (Reykjavík RKV, Akureyri…)", subtitle: "Isavia", url: "https://www.isavia.is/en", systemImage: "airplane.circle")
                LinkRow(title: "Flybus / Airport Direct", subtitle: "Navette KEF ↔ Reykjavík", url: "https://www.re.is/", systemImage: "bus")
                LinkRow(title: "Strætó", subtitle: "Bus urbani e di lunga distanza", url: "https://www.straeto.is/en", systemImage: "bus.fill")
            }
        }
        .themedList()
        .navigationTitle("Voli e traghetti")
        .searchable(text: $query, prompt: "Volo, città o compagnia")
        .task { await model.refreshTransport() }
        .refreshable { await model.refreshTransport() }
    }
}

struct FlightRow: View {
    let flight: Flight
    let following: Bool
    let toggle: () -> Void

    var body: some View {
        let info = flight.statusInfo
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(flight.time ?? "–").font(.app(.subheadline, .semibold).monospacedDigit())
                    Text(flight.flightNumber).font(.app(.subheadline))
                    Text(flight.airline ?? "").font(.app(.caption)).foregroundStyle(.secondary)
                }
                Text("\(flight.arrival ? "da" : "per") \(flight.destination ?? "") (\(flight.airportCode ?? ""))").font(.app(.caption))
                HStack {
                    Text(info.text).font(.app(.caption2, .semibold)).foregroundStyle(info.risk == .ok ? Color.secondary : info.risk.color)
                    if let gate = flight.gate, !gate.isEmpty, !flight.arrival { Text("Gate \(gate)").font(.app(.caption2)).foregroundStyle(.secondary) }
                }
            }
            Spacer()
            Button(action: toggle) {
                Image(systemName: following ? "star.fill" : "star").foregroundStyle(following ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}
