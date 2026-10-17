import MapKit
import SwiftUI

/// One alert from the inbox: full text, when it was raised and until when it
/// applies, where it is (map and distance from you) and the screen with the
/// live data behind it.
struct AlertDetailView: View {
    @Environment(AlertCenter.self) private var alerts
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let event: AlertEvent

    private var expired: Bool { event.expires.map { $0 < Date() } ?? false }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(event.category.label, systemImage: event.category.symbol)
                        .font(.mono(10, .semibold)).foregroundStyle(event.risk.color)
                    Text(event.title).font(.display(24, .bold)).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(event.body).font(.app(.body)).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }

            Section {
                LabeledContent(String(localized: "Ricevuta"), value: "\(Fmt.dayTime(event.date)) · \(Fmt.relative(event.date))")
                if let expires = event.expires {
                    LabeledContent(expired ? String(localized: "Non più valida dalle") : String(localized: "Valida fino alle"),
                                   value: Fmt.dayTime(expires))
                }
                LabeledContent(String(localized: "Livello"), value: riskLabel)
            } header: { Text("Quando").pinnedHeader() }

            if let c = event.coordinate {
                Section {
                    ExpandableMap(height: 200, title: event.title) {
                        Map(initialPosition: .region(MKCoordinateRegion(center: c.clCoordinate,
                                                                        span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 1.2)))) {
                            Marker(event.category.label, systemImage: event.category.symbol, coordinate: c.clCoordinate).tint(event.risk.color)
                            UserAnnotation()
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    if let here = model.location.coordinate {
                        LabeledContent(String(localized: "Distanza da te ora"), value: "\(Int(Geo.distanceKm(here, c).rounded())) km")
                    }
                    LabeledContent(String(localized: "Coordinate"), value: Fmt.coordinate(c))
                    if let url = URL(string: "http://maps.apple.com/?daddr=\(c.lat),\(c.lon)") {
                        Link(destination: url) { Label("Indicazioni in Mappe", systemImage: "arrow.triangle.turn.up.right.diamond") }
                    }
                } header: { Text("Dove").pinnedHeader() }
            }

            Section {
                related
            } header: { Text("Dati aggiornati").pinnedHeader() }

            Section {
                ShareLink(item: "\(event.title)\n\(event.body)\n\(Fmt.dayTime(event.date))") {
                    Label("Condividi", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    alerts.delete(event)
                    dismiss()
                } label: {
                    Label("Elimina dallo storico", systemImage: "trash")
                }
            } footer: {
                Text("Il testo è quello inviato al momento dell'allerta. Per la situazione attuale apri i dati aggiornati.")
            }
        }
        .themedList()
        .navigationTitle(event.category.label)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { alerts.markRead(event) }
    }

    private var riskLabel: String {
        switch event.risk {
        case .ok: return String(localized: "Informazione")
        case .caution: return String(localized: "Attenzione")
        case .warning: return String(localized: "Avviso")
        case .danger: return String(localized: "Pericolo")
        }
    }

    /// The screen with the live data behind the alert, picked from its key.
    @ViewBuilder private var related: some View {
        let parts = event.id.split(separator: ":", maxSplits: 2).map(String.init)
        let prefix = parts.first ?? "", key = parts.count > 1 ? parts[1] : ""
        switch prefix {
        case "ri", "rwi", "rh", "rwh":
            if let section = section(prefix: prefix, key: key) {
                NavigationLink { RoadSectionView(section: section) } label: {
                    Label(String(localized: "Tratto \(section.numbers) · \(section.name)"), systemImage: "road.lanes")
                }
            }
            NavigationLink { RoadsView() } label: { Label("Strade e notizie", systemImage: "road.lanes") }
        case "r", "rw", "g", "rwg":
            NavigationLink { RoadsView() } label: { Label("Strade e stazioni", systemImage: "road.lanes") }
        case "w":
            if let warning = model.warnings?.value.first(where: { $0.identifier == key }) {
                NavigationLink { WarningDetail(warning: warning) } label: { Label("Allerta IMO completa", systemImage: "exclamationmark.triangle") }
            }
            NavigationLink { WarningsView() } label: { Label("Tutte le allerte IMO", systemImage: "exclamationmark.triangle") }
        case "q":
            NavigationLink { QuakesView() } label: { Label("Terremoti", systemImage: "waveform.path.ecg") }
        case "s":
            LinkRow(title: String(localized: "SafeTravel.is"), subtitle: String(localized: "Avvisi ufficiali per chi viaggia"), url: "https://safetravel.is", systemImage: "megaphone")
        case "h":
            NavigationLink { TransportView() } label: { Label("Voli e traghetti", systemImage: "airplane.departure") }
        default:
            switch event.category {
            case .aurora:
                NavigationLink { AuroraView() } label: { Label("Aurora", systemImage: "moon.stars") }
                NavigationLink { AuroraLiveView() } label: { Label("Mappa dell'ovale e avvistamenti", systemImage: "map") }
            case .flight, .ferry:
                NavigationLink { TransportView() } label: { Label("Voli e traghetti", systemImage: "airplane.departure") }
            case .wind, .road, .speed:
                NavigationLink { RoadsView() } label: { Label("Strade e stazioni", systemImage: "road.lanes") }
            case .weatherWarning:
                NavigationLink { WarningsView() } label: { Label("Tutte le allerte IMO", systemImage: "exclamationmark.triangle") }
            case .quake:
                NavigationLink { QuakesView() } label: { Label("Terremoti", systemImage: "waveform.path.ecg") }
            case .safeTravel:
                LinkRow(title: String(localized: "SafeTravel.is"), subtitle: nil, url: "https://safetravel.is", systemImage: "megaphone")
            }
        }
    }

    private func section(prefix: String, key: String) -> RoadInfo.Section? {
        let sections = model.roadInfo?.value.sections ?? []
        if prefix == "ri" || prefix == "rwi" { return sections.first { $0.id == key } }
        return sections.first { $0.hazards.contains { $0.id == key } }
    }
}
