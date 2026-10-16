import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(AlertCenter.self) private var alerts
    @Environment(DriveRecorder.self) private var recorder
    @State private var showInfo = false

    private var zone: TimeZone { model.forecast?.value.timeZone ?? .iceland }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    hero
                    warningsStrip
                    drivingCard
                    auroraCard
                    roadsCard
                    webcamsRow
                    tilesGrid
                    newsCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await model.refreshAll()
                await alerts.check()
            }
            .sheet(isPresented: $showInfo) { InfoView() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showInfo = true } label: {
                        Text("SOS").font(.system(size: 13, weight: .heavy).width(.expanded)).foregroundStyle(Theme.danger)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        if model.isRefreshing { ProgressView().tint(Theme.dim) }
                        Button { alerts.openInbox = true } label: {
                            Image(systemName: alerts.unreadCount > 0 ? "bell.badge.fill" : "bell")
                                .foregroundStyle(alerts.unreadCount > 0 ? Theme.accent : Theme.dim)
                        }
                    }
                }
            }
        }
    }

    // MARK: Hero

    @ViewBuilder private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            PlaceHeader()
            Text(heroDate).eyebrow(Theme.faint)

            if let fetched = model.forecast, let current = fetched.value.current {
                let info = WeatherCode.describe(current.weather_code, isDay: current.is_day != 0)
                let today = fetched.value.days.first
                HStack(alignment: .top) {
                    HStack(alignment: .top, spacing: 2) {
                        Text(current.temperature_2m.map { "\(Int($0.rounded()))" } ?? "–")
                            .font(.system(size: 96, weight: .thin, design: .rounded))
                            .foregroundStyle(Theme.text)
                        Text("°").font(.system(size: 44, weight: .thin, design: .rounded)).foregroundStyle(Theme.dim).padding(.top, 12)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Image(systemName: info.symbol)
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 30))
                            .foregroundStyle(Theme.accent)
                        Text(info.text).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                        Text("Percepita \(Fmt.temp(current.apparent_temperature))").font(.subheadline).foregroundStyle(Theme.dim)
                        if let today {
                            Text("\(Fmt.temp(today.minTemp)) / \(Fmt.temp(today.maxTemp))").font(.metric(15)).foregroundStyle(Theme.dim)
                        }
                    }
                    .padding(.top, 14)
                }

                HStack(spacing: 18) {
                    WindDial(direction: current.wind_direction_10m, speed: current.wind_speed_10m, gust: current.wind_gusts_10m, size: 104)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Vento").eyebrow()
                            Spacer()
                            RiskBadge(risk: Risk.wind(mean: current.wind_speed_10m, gust: current.wind_gusts_10m))
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(Fmt.compass(current.wind_direction_10m)).font(.metric(22, .semibold)).foregroundStyle(Theme.text)
                            Text("raffiche").font(.caption).foregroundStyle(Theme.dim)
                            Text(current.wind_gusts_10m.map { "\(Int($0.rounded()))" } ?? "–").font(.metric(22, .semibold)).foregroundStyle(Theme.text)
                            Text("m/s").font(.caption).foregroundStyle(Theme.dim)
                        }
                        GustScale(mean: current.wind_speed_10m, gust: current.wind_gusts_10m)
                        HStack {
                            Text("0").font(.system(size: 9)); Spacer(); Text("10"); Spacer(); Text("18"); Spacer(); Text("25"); Spacer(); Text("40")
                        }
                        .font(.system(size: 9)).foregroundStyle(Theme.faint)
                    }
                }
                .panel(padding: 14)

                HStack(spacing: 0) {
                    heroStat("Pioggia", Fmt.number(current.precipitation, decimals: 1), "mm")
                    heroStat("Nuvole", current.cloud_cover.map { "\(Int($0))" } ?? "–", "%")
                    heroStat("Umidità", current.relative_humidity_2m.map { "\(Int($0))" } ?? "–", "%")
                    heroStat("Pressione", current.pressure_msl.map { "\(Int($0))" } ?? "–", "hPa")
                }

                VStack(spacing: 8) {
                    DaylightBar(sunrise: today?.sunrise, sunset: today?.sunset, zone: fetched.value.timeZone)
                    HStack {
                        Label(Fmt.time(today?.sunrise, in: zone), systemImage: "sunrise")
                        Spacer()
                        Text("\(Fmt.duration(today?.daylight)) di luce")
                        Spacer()
                        Label(Fmt.time(today?.sunset, in: zone), systemImage: "sunset")
                    }
                    .font(.metric(12)).foregroundStyle(Theme.dim)
                }
                FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: "Open-Meteo")
            } else if let error = model.errors[.forecast] {
                ErrorNote(message: error)
            } else {
                ProgressView().tint(Theme.dim).frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .padding(.top, 4)
    }

    private var heroDate: String {
        let formatter = DateFormatter()
        formatter.locale = Fmt.italian
        formatter.timeZone = zone
        formatter.dateFormat = "EEEE d MMMM · HH:mm"
        return formatter.string(from: Date())
    }

    private func heroStat(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).eyebrow(Theme.faint)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.metric(20, .semibold)).foregroundStyle(Theme.text)
                Text(unit).font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Warnings / alerts

    @ViewBuilder private var warningsStrip: some View {
        if recorder.isRecording, let session = recorder.session {
            HStack {
                Circle().fill(Theme.danger).frame(width: 8, height: 8)
                Text("Registrazione").eyebrow(Theme.danger)
                Spacer()
                Text("\(Fmt.number(session.stats.km, decimals: 1)) km").font(.metric(15, .semibold)).foregroundStyle(Theme.text)
                Text("\(Int(recorder.speedKmh)) km/h").font(.metric(15)).foregroundStyle(Theme.dim)
            }
            .panel(padding: 14)
        }

        let here = model.warningsHere
        NavigationLink {
            WarningsView()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Allerte IMO").eyebrow()
                    Spacer()
                    Text("\(model.warnings?.value.count ?? 0) in Islanda").font(.caption).foregroundStyle(Theme.faint)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.faint)
                }
                if here.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle").foregroundStyle(Theme.ok)
                        Text("Nessuna allerta per questa zona").font(.subheadline).foregroundStyle(Theme.text)
                    }
                } else {
                    ForEach(here.prefix(3)) { warning in
                        HStack(alignment: .top, spacing: 12) {
                            RoundedRectangle(cornerRadius: 2).fill(warning.color.color).frame(width: 4)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    WarningBadge(color: warning.color)
                                    Text(warning.isActive() ? "In corso" : "Dalle \(Fmt.dayTime(warning.onset, in: .iceland))")
                                        .font(.caption.weight(.medium)).foregroundStyle(Theme.dim)
                                }
                                Text(warning.headline).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                                Text("\(warning.region) · fino alle \(Fmt.dayTime(warning.expires, in: .iceland))")
                                    .font(.caption).foregroundStyle(Theme.dim)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                ErrorNote(message: model.errors[.warnings])
            }
            .panel()
        }
        .buttonStyle(.plain)

        if let latest = alerts.latest, !latest.read, Date().timeIntervalSince(latest.date) < 6 * 3600 {
            Button { alerts.openInbox = true } label: {
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 2).fill(latest.risk.color).frame(width: 4)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ultima allerta · \(Fmt.relative(latest.date))").eyebrow(Theme.faint)
                        Text(latest.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        Text(latest.body).font(.caption).foregroundStyle(Theme.dim).lineLimit(2)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .panel(padding: 14)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Driving

    @ViewBuilder private var drivingCard: some View {
        if let forecast = model.forecast?.value {
            let driving = model.drivingRiskNext12h
            let hours = forecast.upcomingHours(12)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Guida, prossime 12 ore").eyebrow()
                    Spacer()
                    RiskBadge(risk: driving.risk)
                }
                RiskTimeline(risks: hours.map { max($0.windRisk, $0.iceRisk) },
                             labels: ["ora", "+3 h", "+6 h", "+9 h", "+12 h"])
                HStack {
                    Metric(title: "Raffica max", value: Fmt.ms(driving.maxGust), tint: Risk.wind(mean: nil, gust: driving.maxGust).color)
                    Metric(title: "Minima", value: Fmt.temp(driving.minTemp))
                    Metric(title: "Neve", value: Fmt.number(driving.snow, decimals: 1, unit: "cm"))
                }
                Text(Risk.windAdvice(Risk.wind(mean: nil, gust: driving.maxGust)))
                    .font(.footnote).foregroundStyle(Theme.dim)
            }
            .panel()
        }
    }

    // MARK: Aurora

    private var auroraCard: some View {
        NavigationLink {
            AuroraView()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Aurora stanotte").eyebrow()
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.faint)
                }
                if let outlook = model.auroraOutlook {
                    let score = outlook.best?.score ?? 0
                    HStack(spacing: 18) {
                        ArcGauge(value: Double(score) / 100, color: Theme.aurora, label: "\(score)", caption: "SU 100")
                            .frame(width: 92, height: 92)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(outlook.verdict.text).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                            if let best = outlook.best, best.score > 0 {
                                Text("Meglio verso le \(Fmt.time(best.date, in: zone)), nuvole \(Fmt.percent(best.cloudCover))")
                                    .font(.caption).foregroundStyle(Theme.dim)
                            }
                            Text("Kp max \(Fmt.number(outlook.maxKp, decimals: 1)) · serve \(Fmt.number(outlook.kpNeeded, decimals: 0))")
                                .font(.metric(12)).foregroundStyle(Theme.faint)
                        }
                    }
                    if outlook.hasDarkness {
                        VStack(alignment: .leading, spacing: 4) {
                            MiniBars(values: outlook.darkHours.map { Double($0.score) }, maxValue: 100, color: Theme.aurora, height: 30)
                            HStack {
                                Text(Fmt.time(outlook.darkHours.first?.date, in: zone))
                                Spacer()
                                Text(Fmt.time(outlook.darkHours.last?.date, in: zone))
                            }
                            .font(.metric(10)).foregroundStyle(Theme.faint)
                        }
                    }
                } else if model.errors[.forecast] != nil {
                    ErrorNote(message: "Serve la previsione delle nuvole")
                } else {
                    ProgressView().tint(Theme.dim)
                }
            }
            .panel()
        }
        .buttonStyle(.plain)
    }

    // MARK: Roads

    private var roadsCard: some View {
        NavigationLink {
            RoadsView()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Strade").eyebrow()
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.faint)
                }
                if let network = model.roads?.value {
                    let risks = network.segments.map(\.risk)
                    let order: [Risk?] = [.ok, .caution, .warning, .danger, nil]
                    let counts: [(Risk?, Int)] = order.map { r in (r, risks.filter { $0 == r }.count) }
                    StackedBar(parts: counts.map { (value: Double($0.1), color: $0.0?.color ?? Theme.raised) })
                    HStack(spacing: 14) {
                        roadCount(counts[0].1, "percorribili", Theme.ok)
                        roadCount(counts[1].1 + counts[2].1, "ghiaccio o neve", Theme.caution)
                        roadCount(counts[3].1, "chiusi", Theme.danger)
                    }
                    VStack(spacing: 0) {
                        ForEach(network.nearestStations(to: model.activePlace.coordinate, count: 3)) { item in
                            HStack {
                                Circle().fill(network.worstRisk(of: item.station).color).frame(width: 7, height: 7)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.station.name).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text).lineLimit(1)
                                    Text("\(Int(item.distance)) km").font(.metric(11)).foregroundStyle(Theme.faint)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text("\(Fmt.ms(item.station.Vindhradi)) · \(Fmt.ms(item.station.Vindhvida))")
                                        .font(.metric(13, .semibold)).foregroundStyle(item.station.windRisk == .ok ? Theme.text : item.station.windRisk.color)
                                    Text("asfalto \(Fmt.temp(item.station.Veghiti))").font(.metric(11))
                                        .foregroundStyle(item.station.surfaceRisk == .ok ? Theme.faint : item.station.surfaceRisk.color)
                                }
                            }
                            .padding(.vertical, 8)
                            Divider().overlay(Theme.hairline)
                        }
                    }
                    if let fetched = model.roads { FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: "Vegagerðin") }
                } else if let error = model.errors[.roads] {
                    ErrorNote(message: error)
                } else {
                    ProgressView().tint(Theme.dim)
                }
            }
            .panel()
        }
        .buttonStyle(.plain)
    }

    private func roadCount(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)").font(.metric(20, .semibold)).foregroundStyle(color)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.dim)
        }
    }

    // MARK: Webcams

    @ViewBuilder private var webcamsRow: some View {
        let near = Webcams.nearest(model.webcams?.value ?? [], to: model.activePlace.coordinate, within: 60, limit: 6)
        if !near.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Webcam vicine").eyebrow()
                    Spacer()
                    NavigationLink { WebcamsView() } label: {
                        Text("Tutte").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(near) { site in
                            NavigationLink { WebcamSiteView(site: site) } label: { WebcamThumb(site: site, width: 190) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Tiles

    private var tilesGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            quakesTile
            seaTile
            fuelTile
            transportTile
        }
    }

    private func tile<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).eyebrow()
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .panel(padding: 14)
    }

    private var quakesTile: some View {
        NavigationLink { QuakesView() } label: {
            tile("Terremoti 24 h") {
                let recent = model.recentQuakes24h
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(recent.count)").font(.metric(30, .semibold)).foregroundStyle(Theme.text)
                    Text("scosse").font(.caption).foregroundStyle(Theme.dim)
                }
                MiniBars(values: quakeHistogram(recent), color: Theme.warning, height: 26)
                if let strongest = recent.max(by: { $0.magnitude < $1.magnitude }) {
                    Text("Max M\(Fmt.number(strongest.magnitude, decimals: 1)) \(strongest.region)")
                        .font(.caption2).foregroundStyle(Theme.dim).lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func quakeHistogram(_ quakes: [Quake]) -> [Double] {
        var bins = Array(repeating: 0.0, count: 12)
        let now = Date()
        for q in quakes {
            let index = 11 - Int(now.timeIntervalSince(q.date) / 7200)
            if bins.indices.contains(index) { bins[index] += 1 }
        }
        return bins
    }

    @ViewBuilder private var seaTile: some View {
        tile("Mare") {
            if let marine = model.marine?.value, marine.hasData, let c = marine.current {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Fmt.number(c.wave_height, decimals: 1)).font(.metric(30, .semibold)).foregroundStyle(Theme.text)
                    Text("m").font(.caption).foregroundStyle(Theme.dim)
                    Text("\(Fmt.number(c.wave_period, decimals: 0)) s").font(.metric(13)).foregroundStyle(Theme.dim)
                }
                HStack(spacing: 6) {
                    Text("Spiagge").font(.caption2).foregroundStyle(Theme.dim)
                    Circle().fill(marine.beachRisk.color).frame(width: 7, height: 7)
                    Text("Traghetti").font(.caption2).foregroundStyle(Theme.dim)
                    Circle().fill(marine.seaRisk.color).frame(width: 7, height: 7)
                }
                Text("Acqua \(Fmt.temp(c.sea_surface_temperature))").font(.caption2).foregroundStyle(Theme.faint)
            } else {
                Text("Non disponibile per questa località").font(.caption).foregroundStyle(Theme.faint)
            }
        }
    }

    @ViewBuilder private var fuelTile: some View {
        tile("Carburante") {
            if let stations = model.fuel?.value, let first = FuelStations.nearest(stations, to: model.activePlace.coordinate, kind: .fuel, limit: 1).first {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Fmt.number(first.km, decimals: first.km < 10 ? 1 : 0)).font(.metric(30, .semibold)).foregroundStyle(Theme.text)
                    Text("km").font(.caption).foregroundStyle(Theme.dim)
                }
                Text(first.station.name).font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                if let charger = FuelStations.nearest(stations, to: model.activePlace.coordinate, kind: .charger, limit: 1).first {
                    Text("Ricarica EV a \(Fmt.number(charger.km, decimals: 0)) km").font(.caption2).foregroundStyle(Theme.faint)
                }
            } else {
                Text(model.errors[.fuel] == nil ? "Download in corso" : "Non disponibile").font(.caption).foregroundStyle(Theme.faint)
            }
        }
    }

    private var transportTile: some View {
        NavigationLink { TransportView() } label: {
            tile("Voli e traghetti") {
                let followed = (model.flights?.value ?? []).filter { alerts.isFollowing($0.flightNumber) }
                if let flight = followed.first {
                    Text(flight.flightNumber).font(.metric(22, .semibold)).foregroundStyle(Theme.text)
                    Text(flight.statusInfo.text).font(.caption)
                        .foregroundStyle(flight.statusInfo.risk == .ok ? Theme.dim : flight.statusInfo.risk.color).lineLimit(2)
                } else {
                    Image(systemName: "airplane.departure").font(.system(size: 24)).foregroundStyle(Theme.accent)
                    Text("Keflavík in tempo reale, Herjólfur").font(.caption).foregroundStyle(Theme.dim)
                }
            }
        }
        .buttonStyle(.plain)
        .task { if model.flights == nil && !alerts.settings.followedFlights.isEmpty { await model.refreshTransport() } }
    }

    // MARK: News

    @ViewBuilder private var newsCard: some View {
        if let news = model.news?.value, !news.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("SafeTravel").eyebrow()
                ForEach(news.prefix(4)) { item in
                    if let link = item.link {
                        Link(destination: link) { newsRow(item) }
                    } else {
                        newsRow(item)
                    }
                }
            }
            .panel()
        }
    }

    private func newsRow(_ item: NewsItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(item.risk > .ok ? item.risk.color : Theme.raised).frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
                Text(item.summary).font(.caption).foregroundStyle(Theme.dim).lineLimit(2).multilineTextAlignment(.leading)
                if let date = item.date { Text(Fmt.relative(date)).font(.caption2).foregroundStyle(Theme.faint) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
