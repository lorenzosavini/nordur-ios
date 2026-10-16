import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    PlaceHeader()
                    warningsSection
                    currentSection
                    drivingSection
                    auroraSection
                    roadsSection
                    seaSection
                    quakesSection
                    newsSection
                    sourcesFooter
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Norður")
            .refreshable { await model.refreshAll() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if model.isRefreshing { ProgressView() }
                }
            }
        }
    }

    // MARK: Warnings

    @ViewBuilder private var warningsSection: some View {
        let here = model.warningsHere
        let all = model.warnings?.value ?? []
        NavigationLink {
            WarningsView()
        } label: {
            Card(title: "Allerte meteo ufficiali (IMO)", systemImage: "exclamationmark.triangle.fill",
                 tint: here.map(\.color).max()?.color ?? .green) {
                if here.isEmpty {
                    Text(all.isEmpty ? "Nessuna allerta attiva in Islanda." : "Nessuna allerta qui. \(all.count) allerte attive in altre zone dell'Islanda.")
                        .font(.subheadline)
                } else {
                    ForEach(here.prefix(3)) { warning in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                WarningBadge(color: warning.color)
                                Text(warning.isActive() ? "IN CORSO" : "dalle \(Fmt.dayTime(warning.onset, in: .iceland))")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Text(warning.headline).font(.subheadline.weight(.semibold))
                            Text(warning.region).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if here.count > 3 {
                        Text("+ altre \(here.count - 3)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ErrorNote(message: model.errors[.warnings])
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Current conditions

    @ViewBuilder private var currentSection: some View {
        if let fetched = model.forecast, let current = fetched.value.current {
            let info = WeatherCode.describe(current.weather_code, isDay: current.is_day != 0)
            let windRisk = Risk.wind(mean: current.wind_speed_10m, gust: current.wind_gusts_10m)
            let today = fetched.value.days.first
            Card(title: "Adesso", systemImage: info.symbol) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Fmt.temp(current.temperature_2m)).font(.system(size: 54, weight: .thin))
                    VStack(alignment: .leading) {
                        Text(info.text).font(.headline)
                        Text("Percepita \(Fmt.temp(current.apparent_temperature))").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                HStack {
                    WindArrow(degrees: current.wind_direction_10m)
                    Text("\(Fmt.ms(current.wind_speed_10m)) \(Fmt.compass(current.wind_direction_10m)) · raffiche \(Fmt.ms(current.wind_gusts_10m))")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    RiskBadge(risk: windRisk)
                }
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Metric(title: "Precipitazioni", value: Fmt.number(current.precipitation, decimals: 1, unit: "mm"), systemImage: "drop.fill")
                        Metric(title: "Nuvole", value: Fmt.percent(current.cloud_cover), systemImage: "cloud.fill")
                        Metric(title: "Umidità", value: Fmt.percent(current.relative_humidity_2m), systemImage: "humidity.fill")
                    }
                    GridRow {
                        Metric(title: "Alba", value: Fmt.time(today?.sunrise, in: fetched.value.timeZone), systemImage: "sunrise.fill")
                        Metric(title: "Tramonto", value: Fmt.time(today?.sunset, in: fetched.value.timeZone), systemImage: "sunset.fill")
                        Metric(title: "Luce", value: Fmt.duration(today?.daylight), systemImage: "sun.max")
                    }
                }
                FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: "Open-Meteo")
            }
        } else {
            Card(title: "Adesso", systemImage: "cloud") {
                if let error = model.errors[.forecast] {
                    ErrorNote(message: error)
                } else {
                    ProgressView("Carico le previsioni…")
                }
            }
        }
    }

    // MARK: Driving

    @ViewBuilder private var drivingSection: some View {
        if model.forecast != nil {
            let driving = model.drivingRiskNext12h
            Card(title: "Guidare nelle prossime 12 ore", systemImage: "car.fill", tint: driving.risk.color) {
                HStack {
                    RiskBadge(risk: driving.risk)
                    Spacer()
                }
                HStack {
                    Metric(title: "Raffica max", value: Fmt.ms(driving.maxGust), systemImage: "wind")
                    Metric(title: "Temp. minima", value: Fmt.temp(driving.minTemp), systemImage: "thermometer.snowflake")
                    Metric(title: "Neve", value: Fmt.number(driving.snow, decimals: 1, unit: "cm"), systemImage: "snowflake")
                }
                Text(Risk.windAdvice(Risk.wind(mean: nil, gust: driving.maxGust)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Aurora

    @ViewBuilder private var auroraSection: some View {
        NavigationLink {
            AuroraView()
        } label: {
            Card(title: "Aurora boreale stanotte", systemImage: "sparkles", tint: .mint) {
                if let outlook = model.auroraOutlook {
                    let verdict = outlook.verdict
                    HStack(alignment: .center) {
                        Gauge(value: Double(outlook.best?.score ?? 0), in: 0...100) {
                            Text("")
                        } currentValueLabel: {
                            Text("\(outlook.best?.score ?? 0)")
                        }
                        .gaugeStyle(.accessoryCircular)
                        .tint(Gradient(colors: [.gray, .green, .mint]))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verdict.text).font(.subheadline.weight(.semibold))
                            if let best = outlook.best, best.score > 0 {
                                Text("Momento migliore: \(Fmt.time(best.date, in: model.forecast?.value.timeZone ?? .current)) · nuvole \(Fmt.percent(best.cloudCover))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text("Kp max stanotte \(Fmt.number(outlook.maxKp, decimals: 1)) · serve circa \(Fmt.number(outlook.kpNeeded, decimals: 0))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ProgressView()
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Roads

    @ViewBuilder private var roadsSection: some View {
        NavigationLink {
            RoadsView()
        } label: {
            Card(title: "Strade (Vegagerðin)", systemImage: "road.lanes", tint: .blue) {
                if let network = model.roads?.value {
                    let problems = network.problemSegments
                    let closed = problems.filter { $0.risk == .danger }.count
                    Text("\(problems.count) tratti con ghiaccio/neve o problemi · \(closed) impraticabili o chiusi")
                        .font(.subheadline)
                    ForEach(network.nearestStations(to: model.activePlace.coordinate, count: 3)) { item in
                        HStack {
                            Circle().fill(network.worstRisk(of: item.station).color).frame(width: 8, height: 8)
                            Text(item.station.name).font(.caption.weight(.medium))
                            Text("\(Int(item.distance)) km").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Fmt.ms(item.station.Vindhradi)) / \(Fmt.ms(item.station.Vindhvida)) · asfalto \(Fmt.temp(item.station.Veghiti))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if let fetched = model.roads {
                        FreshnessLabel(date: fetched.date, isStale: fetched.isStale)
                    }
                } else if let error = model.errors[.roads] {
                    ErrorNote(message: error)
                } else {
                    ProgressView()
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Sea

    @ViewBuilder private var seaSection: some View {
        if let marine = model.marine?.value, marine.hasData, let current = marine.current {
            NavigationLink {
                WeatherView()
            } label: {
                Card(title: "Mare e spiagge", systemImage: "water.waves", tint: .teal) {
                    HStack {
                        Metric(title: "Onde", value: Fmt.number(current.wave_height, decimals: 1, unit: "m"))
                        Metric(title: "Periodo", value: Fmt.number(current.wave_period, decimals: 0, unit: "s"))
                        Metric(title: "Acqua", value: Fmt.temp(current.sea_surface_temperature))
                    }
                    HStack {
                        Text("Spiagge (onde anomale)").font(.caption)
                        RiskBadge(risk: marine.beachRisk)
                        Spacer()
                        Text("Traghetti").font(.caption)
                        RiskBadge(risk: marine.seaRisk)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Quakes

    @ViewBuilder private var quakesSection: some View {
        NavigationLink {
            QuakesView()
        } label: {
            Card(title: "Terremoti e vulcani", systemImage: "waveform.path.ecg", tint: .brown) {
                let recent = model.recentQuakes24h
                if model.quakes != nil {
                    let strongest = recent.max { $0.magnitude < $1.magnitude }
                    Text("\(recent.count) scosse nelle ultime 24 ore")
                        .font(.subheadline)
                    if let strongest {
                        Text("Più forte: M\(Fmt.number(strongest.magnitude, decimals: 1)) – \(strongest.region), \(Fmt.relative(strongest.date))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    let near = recent.filter { Geo.distanceKm($0.coordinate, model.activePlace.coordinate) < 50 && $0.magnitude >= 2 }
                    if !near.isEmpty {
                        Label("\(near.count) scosse M2+ entro 50 km da te", systemImage: "location.circle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                } else if let error = model.errors[.quakes] {
                    ErrorNote(message: error)
                } else {
                    ProgressView()
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: News

    @ViewBuilder private var newsSection: some View {
        if let news = model.news?.value, !news.isEmpty {
            Card(title: "SafeTravel – avvisi ai viaggiatori", systemImage: "megaphone.fill", tint: .red) {
                ForEach(news.prefix(4)) { item in
                    if let link = item.link {
                        Link(destination: link) { newsRow(item) }
                    } else {
                        newsRow(item)
                    }
                }
            }
        }
    }

    private func newsRow(_ item: NewsItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if item.risk > .ok {
                    Circle().fill(item.risk.color).frame(width: 8, height: 8)
                }
                Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            }
            if let date = item.date {
                Text(Fmt.relative(date)).font(.caption2).foregroundStyle(.secondary)
            }
            Text(item.summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourcesFooter: some View {
        Text("Dati: Veðurstofa Íslands (IMO), Vegagerðin, Open-Meteo, NOAA SWPC, SafeTravel.is. In caso di dubbio vale sempre l'informazione ufficiale.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 8)
    }
}
