import SwiftUI
import MapKit

/// Choose start, destination and departure time, then see the route forecast.
struct RoutePlannerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var from: Place?
    @State private var to: Place?
    @State private var departure = Date()
    @State private var picking: Which?

    enum Which: Identifiable { case from, to; var id: Int { self == .from ? 0 : 1 } }

    var body: some View {
        Form {
            Section {
                Button { picking = .from } label: {
                    LabeledContent("Partenza", value: from?.name ?? String(localized: "Posizione attuale"))
                }
                Button { picking = .to } label: {
                    LabeledContent("Arrivo", value: to?.name ?? String(localized: "Scegli…"))
                }
                DatePicker(String(localized: "Partenza alle"), selection: $departure, in: Date().addingTimeInterval(-3600)...Date().addingTimeInterval(15 * 24 * 3600))
            } header: { Text("Percorso").pinnedHeader() }
            if let to {
                Section {
                    NavigationLink {
                        RouteForecastView(from: from ?? model.activePlace, to: to, departure: departure)
                    } label: {
                        Label("Mostra meteo e strade sul percorso", systemImage: "cloud.sun.rain")
                    }
                }
            }
        }
        .themedList()
        .navigationTitle("Pianifica percorso")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } }
        }
        .sheet(item: $picking) { which in
            PlacePicker(allowCurrentLocation: which == .from) { choice in
                switch (which, choice) {
                case (.from, .current): from = nil
                case (.from, .place(let p)): from = p
                case (.to, .place(let p)): to = p
                case (.to, .current): break
                }
            }
        }
    }
}

struct RouteForecastView: View {
    @Environment(AppModel.self) private var model
    let from: Place
    let to: Place
    let departure: Date

    @State private var plan: RoutePlan?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        List {
            if loading && plan == nil {
                HStack { ProgressView(); Text("Calcolo percorso e previsioni…") }
            }
            if let error { ErrorNote(message: error) }
            if let plan { content(plan) }
        }
        .themedList()
        .navigationTitle("\(from.name) → \(to.name)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        if model.roads == nil || model.webcams == nil { await model.refreshGlobal(force: true) }
        do {
            plan = try await RoutePlanner.plan(from: from, to: to, departure: departure, model: model)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func snowText(_ snow: Double?) -> String {
        guard let snow, snow > 0 else { return "" }
        return String(localized: " · neve ") + Fmt.number(snow, decimals: 1, unit: "cm")
    }

    @ViewBuilder private func content(_ plan: RoutePlan) -> some View {
        Section {
            ExpandableMap(height: 260, title: String(localized: "Percorso")) {
            Map(initialPosition: .automatic) {
                MapPolyline(coordinates: plan.polyline.map(\.clCoordinate))
                    .stroke(.blue, lineWidth: 4)
                ForEach(plan.waypoints) { w in
                    Annotation("", coordinate: w.sample.coordinate.clCoordinate) {
                        Circle().fill(w.risk.color).frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    }
                }
                ForEach(plan.warnings) { warning in
                    ForEach(Array(warning.polygons.enumerated()), id: \.offset) { item in
                        MapPolygon(coordinates: item.element.map(\.clCoordinate))
                            .foregroundStyle(warning.color.color.opacity(0.2))
                    }
                }
            }
            }
            .listRowInsets(EdgeInsets())

            HStack {
                Metric(title: String(localized: "Distanza"), value: Fmt.number(plan.distanceKm, unit: "km"), systemImage: "road.lanes")
                Metric(title: String(localized: "Durata"), value: Fmt.duration(plan.travelTime), systemImage: "clock")
                Metric(title: String(localized: "Arrivo"), value: Fmt.time(plan.arrival), systemImage: "flag.checkered")
            }
            HStack {
                Text("Valutazione complessiva").font(.app(.subheadline))
                Spacer()
                RiskBadge(risk: plan.worstRisk)
            }
            Button {
                RoutePlanner.openInMaps(from: plan.from, to: plan.to)
            } label: {
                Label("Avvia navigazione in Mappe", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
            }
            ForEach(plan.notices, id: \.self) { notice in
                Label(notice, systemImage: "info.circle").font(.app(.caption))
            }
        }

        if !plan.warnings.isEmpty {
            Section {
                ForEach(plan.warnings) { WarningRow(warning: $0) }
            } header: { Text("Allerte IMO sul percorso all'ora del passaggio").pinnedHeader() }
        }

        Section {
            ForEach(plan.waypoints) { w in
                HStack(spacing: 10) {
                    VStack(alignment: .leading) {
                        Text("km \(Int(w.sample.kmFromStart))").font(.app(.caption, .semibold))
                        Text(Fmt.time(w.sample.eta)).font(.app(.caption2)).foregroundStyle(.secondary)
                    }
                    .frame(width: 56, alignment: .leading)
                    if let h = w.hour {
                        let info = WeatherCode.describe(h.code, isDay: h.isDay)
                        Image(systemName: info.symbol).symbolRenderingMode(.hierarchical).frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(Fmt.temp(h.temperature)) · \(info.text)").font(.app(.caption))
                            Text("vento \(Fmt.ms(h.wind)) raff. \(Fmt.ms(h.gust))" + snowText(h.snowfall))
                                .font(.app(.caption2)).foregroundStyle(h.windRisk.color == .green ? Color.secondary : h.windRisk.color)
                        }
                        Spacer()
                        RiskBadge(risk: w.risk)
                    } else {
                        Text("Previsione non disponibile").font(.app(.caption)).foregroundStyle(.secondary)
                    }
                }
            }
        } header: { Text("Meteo previsto quando passi").pinnedHeader() }

        if !plan.problemSegments.isEmpty {
            Section {
                ForEach(plan.problemSegments) { segment in
                    HStack {
                        Circle().fill((segment.risk ?? .ok).color).frame(width: 8, height: 8)
                        Text(segment.name).font(.app(.caption))
                        Spacer()
                        Text(segment.conditionItalian).font(.app(.caption2)).foregroundStyle((segment.risk ?? .ok).color)
                    }
                }
            } header: { Text("Strade: problemi adesso").pinnedHeader() }
        }

        if let network = model.roads?.value, !plan.stations.isEmpty {
            Section {
                ForEach(plan.stations.sorted { ($0.Vindhvida ?? 0) > ($1.Vindhvida ?? 0) }.prefix(8)) { station in
                    StationRow(station: station, network: network)
                }
            } header: { Text("Stazioni stradali lungo il percorso (\(plan.stations.count))").pinnedHeader() }
        }

        if !plan.webcams.isEmpty {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(plan.webcams) { site in
                            NavigationLink { WebcamSiteView(site: site) } label: { WebcamThumb(site: site) }
                        }
                    }
                }
            } header: { Text("Webcam lungo il percorso").pinnedHeader() }
        }

        if !plan.fuel.isEmpty {
            Section {
                ForEach(plan.fuel.prefix(10)) { station in
                    Label("\(station.name)\(station.openingHours.map { " · \($0)" } ?? "")", systemImage: "fuelpump.fill").font(.app(.caption))
                }
            } header: { Text("Distributori sul percorso (\(plan.fuel.count))").pinnedHeader() }
        }
    }
}
