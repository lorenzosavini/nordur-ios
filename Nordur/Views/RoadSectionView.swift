import MapKit
import SwiftUI

/// Everything known about one road section: what kind of road it is, its
/// condition now and before, hazards and roadworks, weight limits, tolls,
/// winter-service hours, nearby road stations and webcams, and a map.
struct RoadSectionView: View {
    @Environment(AppModel.self) private var model
    let section: RoadInfo.Section

    private var info: RoadInfo? { model.roadInfo?.value }
    private var anchor: Coordinate? {
        section.center?.coordinate ?? section.bbox.flatMap { b in b.count == 4 ? Coordinate(lat: (b[1] + b[3]) / 2, lon: (b[0] + b[2]) / 2) : nil }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(section.roads, id: \.self) { road in
                            Text(road.nr).font(.mono(12, .semibold)).foregroundStyle(Theme.text)
                                .padding(.horizontal, 6).padding(.vertical, 3).overlay(Rectangle().strokeBorder(Theme.rule))
                        }
                    }
                    Text(section.name).font(.display(26, .bold)).foregroundStyle(Theme.text)
                    if let km = section.distanceKm(to: model.activePlace.coordinate) {
                        Text("\(Int(km.rounded())) km da \(model.activePlace.name)").font(.mono(10)).foregroundStyle(Theme.dim)
                    }
                }
                if let anchor {
                    ExpandableMap(height: 220, title: section.name) { map(anchor) }
                        .listRowInsets(EdgeInsets())
                }
            }

            Section("Condizioni") {
                conditionRow(String(localized: "Adesso"), section.condition, highlight: true)
                if let previous = section.previous {
                    conditionRow(String(localized: "Prima"), previous, highlight: false)
                }
                if section.worsened {
                    Label("Le condizioni sono peggiorate rispetto alla rilevazione precedente.", systemImage: "arrow.down.right")
                        .font(.app(.caption)).foregroundStyle(Theme.warning)
                }
                ForEach(section.notes, id: \.self) { note in
                    Label(RoadCode.weather(note.code) ?? note.text ?? "", systemImage: "cloud.snow")
                        .font(.app(.subheadline))
                }
                if let text = info?.explanation(section.condition?.category), !text.isEmpty {
                    Text(text).font(.app(.caption)).foregroundStyle(Theme.dim)
                }
            }

            if !section.hazards.isEmpty {
                Section("Lavori e pericoli") {
                    ForEach(section.hazards) { hazard in
                        let kind = RoadCode.hazard(hazard.code)
                        VStack(alignment: .leading, spacing: 3) {
                            Label(kind.label, systemImage: kind.symbol).font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text)
                            if let text = hazard.text, !text.isEmpty { Text(text).font(.app(.caption)) }
                            Text([hazard.start.map { String(localized: "Dal \(Fmt.dayTime($0, in: .iceland))") },
                                  hazard.end.map { String(localized: "al \(Fmt.dayTime($0, in: .iceland))") }].compactMap { $0 }.joined(separator: " "))
                                .font(.app(.caption2)).foregroundStyle(Theme.faint)
                        }
                    }
                }
            }

            if section.weight != nil || section.toll != nil {
                Section("Limitazioni") {
                    if let weight = section.weight {
                        LabeledContent(String(localized: "Limite di peso"), value: weight.limit ?? "–")
                        if let text = weight.text, !text.isEmpty { Text(text).font(.app(.caption)).foregroundStyle(Theme.dim) }
                    }
                    if let toll = section.toll {
                        LabeledContent(String(localized: "Pedaggio"), value: toll.type ?? "–")
                        if let text = toll.text, !text.isEmpty { Text(text).font(.app(.caption)).foregroundStyle(Theme.dim) }
                    }
                }
            }

            Section("Che strada è") {
                ForEach(section.roads, id: \.self) { road in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(road.nr) · \(road.name ?? "")").font(.app(.subheadline, .semibold))
                        Text(RoadCode.kind(road.nr)).font(.app(.caption)).foregroundStyle(Theme.dim)
                    }
                }
                if let service = section.service {
                    LabeledContent(String(localized: "Classe di servizio Vegagerðin"), value: "\(service)")
                }
            }

            if !section.hours.isEmpty {
                Section {
                    ForEach(weekdays, id: \.day) { day in
                        LabeledContent(day.name, value: section.serviceHours(on: day.day) ?? String(localized: "Nessun servizio"))
                    }
                } header: {
                    Text("Servizio invernale (sgombero neve)")
                } footer: {
                    Text("Fuori da questi orari la strada non viene controllata né pulita: le condizioni possono peggiorare senza aggiornamenti.")
                }
            }

            if let anchor {
                nearbyStations(anchor)
                nearbyWebcams(anchor)
            }

            Section {
                if let updated = section.condition?.updated {
                    LabeledContent(String(localized: "Ultimo aggiornamento"), value: Fmt.dayTime(updated, in: .iceland))
                }
                LinkRow(title: String(localized: "Apri su umferdin.is"), subtitle: String(localized: "Mappa ufficiale di Vegagerðin"), url: "https://umferdin.is/en", systemImage: "map")
                LinkRow(title: String(localized: "Chiama il 1777"), subtitle: String(localized: "Informazioni stradali (8–16, inverno anche 6:30–22)"), url: "tel:1777", systemImage: "phone.fill")
            } footer: {
                Text("Fonte: Vegagerðin (umferdin.is). In caso di dubbio prevalgono le informazioni ufficiali.")
            }
        }
        .themedList()
        .navigationTitle(section.numbers.isEmpty ? section.name : section.numbers)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Parts

    private func conditionRow(_ title: String, _ condition: RoadInfo.Condition?, highlight: Bool) -> some View {
        let risk = RoadCode.risk(condition?.category) ?? .ok
        return HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased()).font(.mono(9.5)).foregroundStyle(Theme.faint).frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(RoadCode.label(condition?.category) ?? condition?.text ?? "–")
                    .font(highlight ? .app(.headline) : .app(.subheadline))
                    .foregroundStyle(risk > .ok ? risk.color : Theme.text)
                if let date = condition?.updated {
                    Text(Fmt.dayTime(date, in: .iceland)).font(.app(.caption2)).foregroundStyle(Theme.faint)
                }
            }
        }
    }

    private var weekdays: [(day: Int, name: String)] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Fmt.italian
        let names = calendar.weekdaySymbols    // index 0 = Sunday
        return [1, 2, 3, 4, 5, 6, 0].map { (day: $0, name: names[$0].capitalized) }
    }

    @ViewBuilder private func nearbyStations(_ c: Coordinate) -> some View {
        if let network = model.roads?.value {
            let near = network.stations.filter { !$0.isOutdated }
                .compactMap { s in s.coordinate.map { (station: s, km: Geo.distanceKm($0, c)) } }
                .filter { $0.km <= 20 }.sorted { $0.km < $1.km }.prefix(3)
            if !near.isEmpty {
                Section("Stazioni meteo stradali vicine") {
                    ForEach(Array(near.enumerated()), id: \.offset) { entry in
                        StationRow(station: entry.element.station, network: network, distance: entry.element.km)
                    }
                }
            }
        }
    }

    @ViewBuilder private func nearbyWebcams(_ c: Coordinate) -> some View {
        let near = (model.webcams?.value ?? []).map { (site: $0, km: Geo.distanceKm($0.coordinate, c)) }
            .filter { $0.km <= 15 }.sorted { $0.km < $1.km }.prefix(4)
        if !near.isEmpty {
            Section("Webcam vicine") {
                ForEach(Array(near.enumerated()), id: \.offset) { entry in
                    let item = entry.element
                    NavigationLink { WebcamSiteView(site: item.site) } label: {
                        HStack {
                            WebcamThumb(site: item.site, width: 96)
                            VStack(alignment: .leading) {
                                Text(item.site.name).font(.app(.subheadline, .semibold))
                                Text("\(Int(item.km.rounded())) km").font(.app(.caption)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func map(_ anchor: Coordinate) -> some View {
        let box: [CLLocationCoordinate2D]? = section.bbox.flatMap { b in
            b.count == 4 ? [CLLocationCoordinate2D(latitude: b[1], longitude: b[0]), CLLocationCoordinate2D(latitude: b[1], longitude: b[2]),
                            CLLocationCoordinate2D(latitude: b[3], longitude: b[2]), CLLocationCoordinate2D(latitude: b[3], longitude: b[0])] : nil
        }
        let color = (section.risk ?? .ok) > .ok ? (section.risk ?? .ok).color : Color.blue
        return Map(initialPosition: .region(MKCoordinateRegion(center: anchor.clCoordinate,
                                                               span: MKCoordinateSpan(latitudeDelta: max(0.08, spanLat * 1.6), longitudeDelta: max(0.16, spanLon * 1.6))))) {
            if let box {
                MapPolygon(coordinates: box).foregroundStyle(color.opacity(0.12)).stroke(color, lineWidth: 2)
            }
            Marker(section.name, systemImage: "road.lanes", coordinate: anchor.clCoordinate).tint(color)
            ForEach(section.hazards) { hazard in
                if let at = hazard.at {
                    Marker(RoadCode.hazard(hazard.code).label, systemImage: RoadCode.hazard(hazard.code).symbol, coordinate: at.coordinate.clCoordinate).tint(.orange)
                }
            }
        }
    }

    private var spanLat: Double { section.bbox.map { $0.count == 4 ? $0[3] - $0[1] : 0 } ?? 0 }
    private var spanLon: Double { section.bbox.map { $0.count == 4 ? $0[2] - $0[0] : 0 } ?? 0 }
}
