import SwiftUI

struct RoadsView: View {
    @Environment(AppModel.self) private var model
    @State private var mode = Mode.problems
    @State private var query = ""

    enum Mode: String, CaseIterable, Identifiable {
        case problems = "Tratti critici"
        case stations = "Stazioni meteo stradali"
        var id: String { rawValue }
    }

    var body: some View {
        List {
            Section {
                Picker("Vista", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue.loc).tag($0) }
                }
                .pickerStyle(.segmented)
                if let fetched = model.roads {
                    FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: String(localized: "Vegagerðin"))
                }
                ErrorNote(message: model.errors[.roads])
            }

            if let network = model.roads?.value {
                switch mode {
                case .problems: problems(network)
                case .stations: stations(network)
                }
            } else if model.errors[.roads] == nil {
                ProgressView()
            }

            Section {
                NavigationLink { WebcamsView() } label: { Label("Webcam stradali (\(model.webcams?.value.count ?? 0) siti)", systemImage: "video") }
            }

            Section("Ufficiale") {
                LinkRow(title: String(localized: "Umferdin.is – mappa strade in tempo reale"), subtitle: String(localized: "Chiusure, condizioni, webcam"), url: "https://umferdin.is/en", systemImage: "map")
                LinkRow(title: String(localized: "Road.is – Vegagerðin"), subtitle: String(localized: "Info stradali, strade F nelle Highlands"), url: "https://www.road.is/", systemImage: "road.lanes")
                LinkRow(title: String(localized: "Chiama il 1777"), subtitle: String(localized: "Informazioni stradali (8–16, inverno anche 6:30–22)"), url: "tel:1777", systemImage: "phone.fill")
            }
        }
        .themedList()
        .navigationTitle("Strade")
        .searchable(text: $query, prompt: String(localized: "Cerca strada o località"))
        .refreshable { await model.refreshGlobal(force: true) }
    }

    @ViewBuilder private func problems(_ network: RoadNetwork) -> some View {
        let list = network.problemSegments.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        Section("\(list.count) tratti con problemi") {
            if list.isEmpty {
                Label("Nessun problema segnalato", systemImage: "checkmark.circle").foregroundStyle(.green)
            }
            ForEach(list) { segment in
                HStack(alignment: .top) {
                    Circle().fill((segment.risk ?? .ok).color).frame(width: 10, height: 10).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(segment.name).font(.app(.subheadline, .semibold))
                        Text(segment.conditionItalian).font(.app(.caption)).foregroundStyle((segment.risk ?? .ok).color)
                        if let extra = segment.FrkvLysingEn, !extra.isEmpty {
                            Text(extra).font(.app(.caption2)).foregroundStyle(.secondary)
                        }
                        if let axle = segment.AsthungiLysingEn, !axle.isEmpty {
                            Text("Limite di carico: \(axle)").font(.app(.caption2)).foregroundStyle(.secondary)
                        }
                        if let updated = segment.updated {
                            Text("Aggiornato \(Fmt.relative(updated))").font(.app(.caption2)).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func stations(_ network: RoadNetwork) -> some View {
        let here = model.activePlace.coordinate
        let list = network.stations
            .filter { !$0.isOutdated && $0.coordinate != nil }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { Geo.distanceKm(here, $0.coordinate!) < Geo.distanceKm(here, $1.coordinate!) }
        Section("Ordinate per distanza da \(model.activePlace.name)") {
            ForEach(list) { station in
                StationRow(station: station, network: network, distance: station.coordinate.map { Geo.distanceKm(here, $0) })
            }
        }
    }
}

struct StationRow: View {
    let station: RoadStation
    let network: RoadNetwork
    var distance: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(network.worstRisk(of: station).color).frame(width: 10, height: 10)
                Text(station.name).font(.app(.subheadline, .semibold))
                if let h = station.Haed { Text("\(Int(h)) m").font(.app(.caption2)).foregroundStyle(.secondary) }
                Spacer()
                if let distance { Text("\(Int(distance)) km").font(.app(.caption)).foregroundStyle(.secondary) }
            }
            HStack(spacing: 12) {
                Label("\(Fmt.ms(station.Vindhradi)) \(station.windDirection)", systemImage: "wind")
                Label("raff. \(Fmt.ms(station.Vindhvida))", systemImage: "tornado")
                    .foregroundStyle(station.windRisk.color)
                Label(Fmt.temp(station.Hiti), systemImage: "thermometer.medium")
                Label("asfalto \(Fmt.temp(station.Veghiti))", systemImage: "road.lanes")
                    .foregroundStyle(station.surfaceRisk.color)
            }
            .font(.app(.caption))
            .labelStyle(CompactLabelStyle())
            ForEach(network.segments(for: station)) { segment in
                Text("\(segment.name): \(segment.conditionItalian)")
                    .font(.app(.caption2))
                    .foregroundStyle((segment.risk ?? .ok) > .ok ? (segment.risk ?? .ok).color : Color.secondary)
            }
            if let date = station.date {
                Text("Lettura \(Fmt.relative(date))").font(.app(.caption2)).foregroundStyle(.tertiary)
            }
        }
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.app(.caption2))
            configuration.title
        }
    }
}
