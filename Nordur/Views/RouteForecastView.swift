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
            Section("Percorso") {
                Button { picking = .from } label: {
                    LabeledContent("Partenza", value: from?.name ?? "Posizione attuale")
                }
                Button { picking = .to } label: {
                    LabeledContent("Arrivo", value: to?.name ?? "Scegli…")
                }
                DatePicker("Partenza alle", selection: $departure, in: Date().addingTimeInterval(-3600)...Date().addingTimeInterval(15 * 24 * 3600))
            }
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
        return " · neve " + Fmt.number(snow, decimals: 1, unit: "cm")
    }

    @ViewBuilder private func content(_ plan: RoutePlan) -> some View {
        Section {
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
            .frame(height: 260)
            .listRowInsets(EdgeInsets())

            HStack {
                Metric(title: "Distanza", value: Fmt.number(plan.distanceKm, unit: "km"), systemImage: "road.lanes")
                Metric(title: "Durata", value: Fmt.duration(plan.travelTime), systemImage: "clock")
                Metric(title: "Arrivo", value: Fmt.time(plan.arrival), systemImage: "flag.checkered")
            }
            HStack {
                Text("Valutazione complessiva").font(.subheadline)
                Spacer()
                RiskBadge(risk: plan.worstRisk)
            }
            Button {
                RoutePlanner.openInMaps(from: plan.from, to: plan.to)
            } label: {
                Label("Avvia navigazione in Mappe", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
            }
            ForEach(plan.notices, id: \.self) { notice in
                Label(notice, systemImage: "info.circle").font(.caption)
            }
        }

        if !plan.warnings.isEmpty {
            Section("Allerte IMO sul percorso all'ora del passaggio") {
                ForEach(plan.warnings) { WarningRow(warning: $0) }
            }
        }

        Section("Meteo previsto quando passi") {
            ForEach(plan.waypoints) { w in
                HStack(spacing: 10) {
                    VStack(alignment: .leading) {
                        Text("km \(Int(w.sample.kmFromStart))").font(.caption.weight(.semibold))
                        Text(Fmt.time(w.sample.eta)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(width: 56, alignment: .leading)
                    if let h = w.hour {
                        let info = WeatherCode.describe(h.code, isDay: h.isDay)
                        Image(systemName: info.symbol).symbolRenderingMode(.hierarchical).frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(Fmt.temp(h.temperature)) · \(info.text)").font(.caption)
                            Text("vento \(Fmt.ms(h.wind)) raff. \(Fmt.ms(h.gust))" + snowText(h.snowfall))
                                .font(.caption2).foregroundStyle(h.windRisk.color == .green ? Color.secondary : h.windRisk.color)
                        }
                        Spacer()
                        RiskBadge(risk: w.risk)
                    } else {
                        Text("Previsione non disponibile").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }

        if !plan.problemSegments.isEmpty {
            Section("Strade: problemi adesso") {
                ForEach(plan.problemSegments) { segment in
                    HStack {
                        Circle().fill((segment.risk ?? .ok).color).frame(width: 8, height: 8)
                        Text(segment.name).font(.caption)
                        Spacer()
                        Text(segment.conditionItalian).font(.caption2).foregroundStyle((segment.risk ?? .ok).color)
                    }
                }
            }
        }

        if let network = model.roads?.value, !plan.stations.isEmpty {
            Section("Stazioni stradali lungo il percorso (\(plan.stations.count))") {
                ForEach(plan.stations.sorted { ($0.Vindhvida ?? 0) > ($1.Vindhvida ?? 0) }.prefix(8)) { station in
                    StationRow(station: station, network: network)
                }
            }
        }

        if !plan.webcams.isEmpty {
            Section("Webcam lungo il percorso") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(plan.webcams) { site in
                            NavigationLink { WebcamSiteView(site: site) } label: { WebcamThumb(site: site) }
                        }
                    }
                }
            }
        }

        if !plan.fuel.isEmpty {
            Section("Distributori sul percorso (\(plan.fuel.count))") {
                ForEach(plan.fuel.prefix(10)) { station in
                    Label("\(station.name)\(station.openingHours.map { " · \($0)" } ?? "")", systemImage: "fuelpump.fill").font(.caption)
                }
            }
        }
    }
}
