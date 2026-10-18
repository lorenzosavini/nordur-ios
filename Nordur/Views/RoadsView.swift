import SwiftUI

struct RoadsView: View {
    @Environment(AppModel.self) private var model
    @State private var mode = Mode.news
    @State private var query = ""

    enum Mode: String, CaseIterable, Identifiable {
        case news = "Notizie"
        case problems = "Critici"
        case all = "Tutte"
        case stations = "Stazioni"
        var id: String { rawValue }
    }

    private var here: Coordinate { model.activePlace.coordinate }

    var body: some View {
        List {
            Section {
                HeroHeader(hero: .roads, eyebrow: String(localized: "Vegagerðin · umferdin.is"), title: String(localized: "Strade"), subtitle: String(localized: "Condizioni, chiusure, lavori e notizie in tempo reale"))
                    .heroRow()
            }
            .listSectionSeparator(.hidden)
            if !model.inIceland {
                Section { CoverageNote(feature: String(localized: "Strade e condizioni Vegagerðin"), showsIcelandData: true) }
                    .listRowSeparator(.hidden)
            }
            Section {
                Picker("Vista", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue.loc).tag($0) }
                }
                .pickerStyle(.segmented)
                if let fetched = model.roadInfo {
                    FreshnessLabel(date: fetched.date, isStale: fetched.isStale || fetched.value.stale == true, source: String(localized: "Vegagerðin · umferdin.is"))
                } else if let fetched = model.roads {
                    FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: String(localized: "Vegagerðin"))
                }
                ErrorNote(message: model.errors[.roadInfo] ?? model.errors[.roads])
            }

            switch mode {
            case .news: news
            case .problems: problems
            case .all: allRoads
            case .stations:
                if let network = model.roads?.value { stations(network) } else { SkeletonRows() }
            }

            Section {
                NavigationLink { WebcamsView() } label: { Label("Webcam stradali (\(model.webcams?.value.count ?? 0) siti)", systemImage: "video") }
            }

            Section {
                LinkRow(title: String(localized: "Umferdin.is – mappa strade in tempo reale"), subtitle: String(localized: "Chiusure, condizioni, webcam"), url: "https://umferdin.is/en", systemImage: "map")
                LinkRow(title: String(localized: "Road.is – Vegagerðin"), subtitle: String(localized: "Info stradali, strade F nelle Highlands"), url: "https://www.road.is/", systemImage: "road.lanes")
                LinkRow(title: String(localized: "Chiama il 1777"), subtitle: String(localized: "Informazioni stradali (8–16, inverno anche 6:30–22)"), url: "tel:1777", systemImage: "phone.fill")
            } header: { Text("Ufficiale").pinnedHeader() }
        }
        .themedList()
        .navigationTitle("Strade")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: String(localized: "Cerca strada, numero o località"))
        .refreshable { await model.refreshGlobal(force: true) }
    }

    private func matches(_ section: RoadInfo.Section) -> Bool {
        query.isEmpty || section.name.localizedCaseInsensitiveContains(query)
            || section.roads.contains { $0.nr.caseInsensitiveCompare(query) == .orderedSame || ($0.name ?? "").localizedCaseInsensitiveContains(query) }
    }

    // MARK: News

    @ViewBuilder private var news: some View {
        if let info = model.roadInfo?.value {
            let items = info.news.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) || ($0.place ?? "").localizedCaseInsensitiveContains(query) || ($0.region ?? "").localizedCaseInsensitiveContains(query) }
            Section {
                if items.isEmpty { Label("Nessuna notizia sulle strade", systemImage: "checkmark.circle").foregroundStyle(.green) }
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text((item.region ?? "").uppercased()).font(.mono(9.5, .semibold)).foregroundStyle(Theme.accent)
                            if let place = item.place { Text("· \(place)").font(.mono(9.5)).foregroundStyle(Theme.dim) }
                            Spacer()
                            if let date = item.published { Text(Fmt.relative(date)).font(.mono(9)).foregroundStyle(Theme.faint) }
                        }
                        Text(item.text).font(.app(.subheadline)).foregroundStyle(Theme.text)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Notizie in tempo reale").pinnedHeader().pinnedHeader().pinnedHeader()
            } footer: {
                Text("Testi originali di Vegagerðin (in inglese), aggiornati ogni 5 minuti.")
            }
        } else if model.errors[.roadInfo] == nil {
            SkeletonRows()
        }
    }

    // MARK: Problems: closures, difficult sections, roadworks and hazards

    @ViewBuilder private var problems: some View {
        if let info = model.roadInfo?.value {
            let critical = info.sections
                .filter { ($0.risk ?? .ok) >= .caution && matches($0) }
                .map { RoadItem(section: $0, km: model.roadGeometry?.value.distanceKm(from: here, to: $0.id) ?? $0.distanceKm(to: here) ?? .infinity) }
                .sorted { ($0.section.risk ?? .ok) != ($1.section.risk ?? .ok) ? ($0.section.risk ?? .ok) > ($1.section.risk ?? .ok) : $0.km < $1.km }
            Section {
                if critical.isEmpty { Label("Nessun problema segnalato", systemImage: "checkmark.circle").foregroundStyle(.green) }
                ForEach(critical) { item in
                    NavigationLink { RoadSectionView(section: item.section) } label: { RoadSectionRow(section: item.section, km: item.km) }
                }
            } header: { Text("\(critical.count) tratti con problemi").pinnedHeader() }
            let hazards = info.sections.filter { matches($0) }
                .flatMap { section in section.hazards.map { HazardItem(section: section, hazard: $0, km: $0.at.map { Geo.distanceKm(here, $0.coordinate) } ?? .infinity) } }
                .sorted { $0.km < $1.km }
            Section {
                ForEach(hazards) { entry in
                    NavigationLink { RoadSectionView(section: entry.section) } label: {
                        HazardRow(hazard: entry.hazard, section: entry.section, km: entry.km)
                    }
                }
            } header: { Text("Lavori e pericoli (\(hazards.count))").pinnedHeader() }
        } else if let network = model.roads?.value {
            legacyProblems(network)
        } else if model.errors[.roadInfo] == nil {
            SkeletonRows()
        }
    }

    // MARK: All roads

    @ViewBuilder private var allRoads: some View {
        if let info = model.roadInfo?.value {
            let list = info.sections.filter { matches($0) }
                .map { RoadItem(section: $0, km: model.roadGeometry?.value.distanceKm(from: here, to: $0.id) ?? $0.distanceKm(to: here) ?? .infinity) }
                .sorted { $0.km < $1.km }
            Section {
                ForEach(Array(list.prefix(query.isEmpty ? 150 : 400))) { item in
                    NavigationLink { RoadSectionView(section: item.section) } label: { RoadSectionRow(section: item.section, km: item.km) }
                }
            } header: { Text("\(list.count) tratti · ordinati per distanza da \(model.activePlace.name)").pinnedHeader() }
        } else if model.errors[.roadInfo] == nil {
            SkeletonRows()
        }
    }

    @ViewBuilder private func legacyProblems(_ network: RoadNetwork) -> some View {
        let list = network.problemSegments.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        Section {
            if list.isEmpty {
                Label("Nessun problema segnalato", systemImage: "checkmark.circle").foregroundStyle(.green)
            }
            ForEach(list) { segment in
                HStack(alignment: .top) {
                    Circle().fill((segment.risk ?? .ok).color).frame(width: 10, height: 10).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(segment.name).font(.app(.subheadline, .semibold))
                        Text(segment.conditionItalian).font(.app(.caption)).foregroundStyle((segment.risk ?? .ok).color)
                        if let updated = segment.updated {
                            Text("Aggiornato \(Fmt.relative(updated))").font(.app(.caption2)).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        } header: { Text("\(list.count) tratti con problemi").pinnedHeader() }
    }

    @ViewBuilder private func stations(_ network: RoadNetwork) -> some View {
        let list = network.stations
            .filter { !$0.isOutdated && $0.coordinate != nil }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { Geo.distanceKm(here, $0.coordinate!) < Geo.distanceKm(here, $1.coordinate!) }
        Section {
            ForEach(list) { station in
                StationRow(station: station, network: network, distance: station.coordinate.map { Geo.distanceKm(here, $0) })
            }
        } header: { Text("Ordinate per distanza da \(model.activePlace.name)").pinnedHeader() }
    }
}

struct RoadItem: Identifiable {
    let section: RoadInfo.Section
    let km: Double
    var id: String { section.id }
}

struct HazardItem: Identifiable {
    let section: RoadInfo.Section
    let hazard: RoadInfo.Hazard
    let km: Double
    var id: String { "\(section.id)-\(hazard.id)" }
}

struct RoadSectionRow: View {
    let section: RoadInfo.Section
    var km: Double?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle().fill((section.risk ?? .ok) > .ok ? (section.risk ?? .ok).color : Theme.hairline).frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if !section.numbers.isEmpty {
                        Text(section.numbers).font(.mono(10, .semibold)).foregroundStyle(Theme.text)
                            .padding(.horizontal, 5).padding(.vertical, 2).overlay(Rectangle().strokeBorder(Theme.hairline))
                    }
                    Text(section.name).font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text).lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(section.label).font(.app(.caption)).foregroundStyle((section.risk ?? .ok) > .ok ? (section.risk ?? .ok).color : Theme.dim)
                    if section.worsened { Text("PEGGIORATA").font(.mono(8.5, .semibold)).foregroundStyle(Theme.warning) }
                    if !section.hazards.isEmpty {
                        Label("\(section.hazards.count)", systemImage: "cone.fill").font(.app(.caption2)).foregroundStyle(Theme.caution)
                    }
                }
            }
            Spacer(minLength: 4)
            if let km, km.isFinite { Text("\(Int(km.rounded())) km").font(.mono(10)).foregroundStyle(Theme.dim) }
        }
        .padding(.vertical, 2)
    }
}

struct HazardRow: View {
    let hazard: RoadInfo.Hazard
    let section: RoadInfo.Section
    var km: Double?

    var body: some View {
        let kind = RoadCode.hazard(hazard.code)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind.symbol).foregroundStyle(Theme.caution).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.label).font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text)
                Text(section.numbers.isEmpty ? section.name : "\(section.numbers) · \(section.name)").font(.app(.caption)).foregroundStyle(Theme.dim)
                if let text = hazard.text, !text.isEmpty { Text(text).font(.app(.caption)).foregroundStyle(Theme.text) }
                if let end = hazard.end { Text("Fino al \(Fmt.dayTime(end, in: .iceland))").font(.app(.caption2)).foregroundStyle(Theme.faint) }
            }
            Spacer(minLength: 4)
            if let km, km.isFinite { Text("\(Int(km.rounded())) km").font(.mono(10)).foregroundStyle(Theme.dim) }
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
