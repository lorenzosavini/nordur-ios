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
                VStack(spacing: 14) {
                    topBar
                    hero
                    windCard
                    HStack(alignment: .top, spacing: 14) {
                        auroraTile
                        drivingTile
                    }
                    warningsStrip
                    roadsCard
                    webcamsRow
                    tilesGrid
                    newsCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await model.refreshAll()
                await alerts.check()
            }
            .sheet(isPresented: $showInfo) { InfoView() }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("Norður").font(.display(24, .heavy)).foregroundStyle(Theme.text)
            if model.isRefreshing { ProgressView().controlSize(.small).tint(Theme.dim) }
            Spacer()
            Button { showInfo = true } label: {
                Text("SOS")
                    .font(.geist(13, .bold))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(Theme.danger, in: Capsule())
            }
            .buttonStyle(.plain)
            AppearanceButton()
            HeaderButton(systemImage: "bell", tint: alerts.unreadCount > 0 ? Theme.accent : Theme.text, dot: alerts.unreadCount > 0) {
                alerts.openInbox = true
            }
        }
        .padding(.top, 6)
    }

    // MARK: Hero

    @ViewBuilder private var hero: some View {
        let current = model.forecast?.value.current
        let sky = Theme.sky(code: current?.weather_code, isDay: (current?.is_day ?? 1) == 1)
        VStack(alignment: .leading, spacing: 16) {
            PlaceHeader(onHero: true)
            if let fetched = model.forecast, let current {
                let info = WeatherCode.describe(current.weather_code, isDay: current.is_day != 0)
                let today = fetched.value.days.first
                HStack(alignment: .top) {
                    HStack(alignment: .top, spacing: 0) {
                        Text(current.temperature_2m.map { "\(Int($0.rounded()))" } ?? "–")
                            .font(.display(108, .semibold))
                            .foregroundStyle(.white)
                        Text("°").font(.display(54, .semibold)).foregroundStyle(.white.opacity(0.7)).padding(.top, 10)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Image(systemName: info.symbol)
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 34))
                            .foregroundStyle(.white)
                        Text(info.text).font(.geist(17, .semibold)).foregroundStyle(.white).multilineTextAlignment(.trailing)
                        Text("Percepita \(Fmt.temp(current.apparent_temperature))").font(.geist(14)).foregroundStyle(.white.opacity(0.8))
                        if let today {
                            Text("Min \(Fmt.temp(today.minTemp))  Max \(Fmt.temp(today.maxTemp))").font(.geist(13, .medium)).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .padding(.top, 18)
                }

                let next = fetched.value.upcomingHours(7)
                HStack(spacing: 0) {
                    ForEach(Array(next.enumerated()), id: \.offset) { index, hour in
                        VStack(spacing: 6) {
                            Text(index == 0 ? "Ora" : Fmt.time(hour.date, in: zone)).font(.geist(11, .medium)).foregroundStyle(.white.opacity(0.75))
                            Image(systemName: WeatherCode.describe(hour.code, isDay: hour.isDay).symbol)
                                .symbolRenderingMode(.hierarchical).font(.system(size: 16)).foregroundStyle(.white).frame(height: 20)
                            Text(Fmt.temp(hour.temperature)).font(.metric(16)).foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 12)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack {
                    Label(Fmt.time(today?.sunrise, in: zone), systemImage: "sunrise.fill")
                    Spacer()
                    Text("\(Fmt.duration(today?.daylight)) di luce")
                    Spacer()
                    Label(Fmt.time(today?.sunset, in: zone), systemImage: "sunset.fill")
                }
                .font(.geist(12, .medium))
                .foregroundStyle(.white.opacity(0.85))
            } else if let error = model.errors[.forecast] {
                ErrorNote(message: error).foregroundStyle(.white)
            } else {
                ProgressView().tint(.white).frame(maxWidth: .infinity, minHeight: 180)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: sky, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 32, style: .continuous)
        )
        .shadow(color: (sky.first ?? .black).opacity(0.35), radius: 20, x: 0, y: 10)
    }

    private var heroDate: String {
        let formatter = DateFormatter()
        formatter.locale = Fmt.italian
        formatter.timeZone = zone
        formatter.dateFormat = "EEEE d MMMM · HH:mm"
        return formatter.string(from: Date())
    }

    // MARK: Wind

    @ViewBuilder private var windCard: some View {
        if let fetched = model.forecast, let current = fetched.value.current {
            HStack(spacing: 18) {
                WindDial(direction: current.wind_direction_10m, speed: current.wind_speed_10m, gust: current.wind_gusts_10m, size: 112)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Vento").eyebrow()
                        Spacer()
                        RiskBadge(risk: Risk.wind(mean: current.wind_speed_10m, gust: current.wind_gusts_10m))
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(current.wind_gusts_10m.map { "\(Int($0.rounded()))" } ?? "–").font(.metric(34, .bold)).foregroundStyle(Theme.text)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("m/s raffiche").font(.geist(12, .medium)).foregroundStyle(Theme.dim)
                            Text("da \(Fmt.compass(current.wind_direction_10m))").font(.geist(12)).foregroundStyle(Theme.faint)
                        }
                    }
                    GustScale(mean: current.wind_speed_10m, gust: current.wind_gusts_10m)
                    HStack {
                        Text("0"); Spacer(); Text("10"); Spacer(); Text("18"); Spacer(); Text("25"); Spacer(); Text("40")
                    }
                    .font(.geist(9, .medium)).foregroundStyle(Theme.faint)
                }
            }
            .panel()
        }
    }

    // MARK: Aurora & driving tiles

    private var auroraTile: some View {
        NavigationLink { AuroraView() } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text("Aurora").eyebrow()
                if let outlook = model.auroraOutlook {
                    let score = outlook.best?.score ?? 0
                    ArcGauge(value: Double(score) / 100, color: Theme.aurora, lineWidth: 8, label: "\(score)", caption: "SU 100")
                        .frame(width: 88, height: 88)
                        .frame(maxWidth: .infinity)
                    Text(outlook.verdict.text).font(.geist(14, .semibold)).foregroundStyle(Theme.text).lineLimit(2)
                    if outlook.hasDarkness {
                        MiniBars(values: outlook.darkHours.map { Double($0.score) }, maxValue: 100, color: Theme.aurora, height: 22)
                    }
                } else {
                    ProgressView().tint(Theme.dim).frame(maxWidth: .infinity, minHeight: 88)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
            .panel(padding: 16)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var drivingTile: some View {
        let driving = model.drivingRiskNext12h
        let hours = model.forecast?.value.upcomingHours(12) ?? []
        VStack(alignment: .leading, spacing: 12) {
            Text("Guida 12 h").eyebrow()
            Text(driving.risk.label).font(.display(26, .bold)).foregroundStyle(driving.risk.color)
            RiskTimeline(risks: hours.map { max($0.windRisk, $0.iceRisk) })
            VStack(alignment: .leading, spacing: 6) {
                miniRow("Raffica max", Fmt.ms(driving.maxGust))
                miniRow("Minima", Fmt.temp(driving.minTemp))
                miniRow("Neve", Fmt.number(driving.snow, decimals: 1, unit: "cm"))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .panel(padding: 16)
    }

    private func miniRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.geist(12)).foregroundStyle(Theme.dim)
            Spacer()
            Text(value).font(.metric(14)).foregroundStyle(Theme.text)
        }
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
                    Text("\(model.warnings?.value.count ?? 0) in Islanda").font(.app(.caption)).foregroundStyle(Theme.faint)
                    Image(systemName: "chevron.right").font(.app(.caption, .semibold)).foregroundStyle(Theme.faint)
                }
                if here.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle").foregroundStyle(Theme.ok)
                        Text("Nessuna allerta per questa zona").font(.app(.subheadline)).foregroundStyle(Theme.text)
                    }
                } else {
                    ForEach(here.prefix(3)) { warning in
                        HStack(alignment: .top, spacing: 12) {
                            RoundedRectangle(cornerRadius: 2).fill(warning.color.color).frame(width: 4)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    WarningBadge(color: warning.color)
                                    Text(warning.isActive() ? "In corso" : "Dalle \(Fmt.dayTime(warning.onset, in: .iceland))")
                                        .font(.app(.caption, .medium)).foregroundStyle(Theme.dim)
                                }
                                Text(warning.headline).font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text)
                                Text("\(warning.region) · fino alle \(Fmt.dayTime(warning.expires, in: .iceland))")
                                    .font(.app(.caption)).foregroundStyle(Theme.dim)
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
                        Text(latest.title).font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text)
                        Text(latest.body).font(.app(.caption)).foregroundStyle(Theme.dim).lineLimit(2)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .panel(padding: 14)
            }
            .buttonStyle(.plain)
        }
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
                    Image(systemName: "chevron.right").font(.app(.caption, .semibold)).foregroundStyle(Theme.faint)
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
                                    Text(item.station.name).font(.app(.subheadline, .medium)).foregroundStyle(Theme.text).lineLimit(1)
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
            Text(label).font(.geist(11)).foregroundStyle(Theme.dim)
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
                        Text("Tutte").font(.app(.caption, .semibold)).foregroundStyle(Theme.accent)
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
                    Text("scosse").font(.app(.caption)).foregroundStyle(Theme.dim)
                }
                MiniBars(values: quakeHistogram(recent), color: Theme.warning, height: 26)
                if let strongest = recent.max(by: { $0.magnitude < $1.magnitude }) {
                    Text("Max M\(Fmt.number(strongest.magnitude, decimals: 1)) \(strongest.region)")
                        .font(.app(.caption2)).foregroundStyle(Theme.dim).lineLimit(1)
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
                    Text("m").font(.app(.caption)).foregroundStyle(Theme.dim)
                    Text("\(Fmt.number(c.wave_period, decimals: 0)) s").font(.metric(13)).foregroundStyle(Theme.dim)
                }
                HStack(spacing: 6) {
                    Text("Spiagge").font(.app(.caption2)).foregroundStyle(Theme.dim)
                    Circle().fill(marine.beachRisk.color).frame(width: 7, height: 7)
                    Text("Traghetti").font(.app(.caption2)).foregroundStyle(Theme.dim)
                    Circle().fill(marine.seaRisk.color).frame(width: 7, height: 7)
                }
                Text("Acqua \(Fmt.temp(c.sea_surface_temperature))").font(.app(.caption2)).foregroundStyle(Theme.faint)
            } else {
                Text("Non disponibile per questa località").font(.app(.caption)).foregroundStyle(Theme.faint)
            }
        }
    }

    @ViewBuilder private var fuelTile: some View {
        tile("Carburante") {
            if let stations = model.fuel?.value, let first = FuelStations.nearest(stations, to: model.activePlace.coordinate, kind: .fuel, limit: 1).first {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Fmt.number(first.km, decimals: first.km < 10 ? 1 : 0)).font(.metric(30, .semibold)).foregroundStyle(Theme.text)
                    Text("km").font(.app(.caption)).foregroundStyle(Theme.dim)
                }
                Text(first.station.name).font(.app(.caption)).foregroundStyle(Theme.dim).lineLimit(1)
                if let charger = FuelStations.nearest(stations, to: model.activePlace.coordinate, kind: .charger, limit: 1).first {
                    Text("Ricarica EV a \(Fmt.number(charger.km, decimals: 0)) km").font(.app(.caption2)).foregroundStyle(Theme.faint)
                }
            } else {
                Text(model.errors[.fuel] == nil ? "Download in corso" : "Non disponibile").font(.app(.caption)).foregroundStyle(Theme.faint)
            }
        }
    }

    private var transportTile: some View {
        NavigationLink { TransportView() } label: {
            tile("Voli e traghetti") {
                let followed = (model.flights?.value ?? []).filter { alerts.isFollowing($0.flightNumber) }
                if let flight = followed.first {
                    Text(flight.flightNumber).font(.metric(22, .semibold)).foregroundStyle(Theme.text)
                    Text(flight.statusInfo.text).font(.app(.caption))
                        .foregroundStyle(flight.statusInfo.risk == .ok ? Theme.dim : flight.statusInfo.risk.color).lineLimit(2)
                } else {
                    Image(systemName: "airplane.departure").font(.geist(24)).foregroundStyle(Theme.accent)
                    Text("Keflavík in tempo reale, Herjólfur").font(.app(.caption)).foregroundStyle(Theme.dim)
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
                Text(item.title).font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
                Text(item.summary).font(.app(.caption)).foregroundStyle(Theme.dim).lineLimit(2).multilineTextAlignment(.leading)
                if let date = item.date { Text(Fmt.relative(date)).font(.app(.caption2)).foregroundStyle(Theme.faint) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
