import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(AlertCenter.self) private var alerts
    @Environment(DriveRecorder.self) private var recorder
    @State private var showInfo = false
    @State private var showAccount = false
    @Environment(Account.self) private var account

    private var zone: TimeZone { model.forecast?.value.timeZone ?? .iceland }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    VStack(alignment: .leading, spacing: 18) {
                        topBar
                        PlaceHeader(size: 44)
                        statusBanner
                        now
                    }
                    nextHours
                    windSection
                    warningsSection
                    outlookSection
                    roadsSection
                    webcamsSection
                    moreSection
                    newsSection
                    daylight
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await model.refreshAll()
                await alerts.check()
            }
            .sheet(isPresented: $showInfo) { InfoView() }
            .sheet(isPresented: $showAccount) { AccountView() }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            Text("NORÐUR").font(.mono(13, .semibold)).tracking(2.5).foregroundStyle(Theme.text)
            Text(Fmt.time(Date(), in: .iceland)).font(.mono(10.5)).foregroundStyle(Theme.faint)
            if model.isRefreshing { ProgressView().controlSize(.mini).tint(Theme.dim) }
            Spacer()
            Button { showInfo = true } label: {
                Text("SOS 112")
                    .font(.mono(10.5, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 9)
                    .frame(height: 34)
                    .overlay(Rectangle().strokeBorder(Theme.danger, lineWidth: 1))
            }
            .buttonStyle(.plain)
            AppearanceButton()
            HeaderButton(systemImage: account.isSignedIn ? "person.fill" : "person", dot: !account.isSignedIn) { showAccount = true }
                .accessibilityLabel("Account e backup")
            HeaderButton(systemImage: "bell", tint: Theme.text, dot: alerts.unreadCount > 0) {
                alerts.openInbox = true
            }
        }
        .padding(.top, 6)
    }

    // MARK: Status

    @ViewBuilder private var statusBanner: some View {
        let driving = model.drivingRiskNext12h
        let here = model.warningsHere
        let worstWarning = here.map(\.color).max()
        let risk = max(driving.risk, worstWarning?.risk ?? .ok)
        let headline: String = {
            if let w = here.first { return "\(w.color.label) · \(w.hazardItalian) · \(w.region)" }
            switch driving.risk {
            case .ok: return String(localized: "Nessuna criticità nelle prossime 12 ore")
            default: return String(localized: "Guida: \(driving.risk.label.lowercased()) · raffiche fino a \(Fmt.ms(driving.maxGust))")
            }
        }()
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(risk == .ok ? String(localized: "STATO") : String(localized: "ATTENZIONE")).font(.mono(10.5, .semibold)).tracking(0.8)
            Text(headline).font(.sans(14, .medium)).lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(risk >= .warning ? Theme.onAccent : Theme.text)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(risk >= .warning ? risk.color : .clear)
        .overlay(alignment: .leading) {
            if risk < .warning { Rectangle().fill(risk == .ok ? Theme.rule : risk.color).frame(width: 3) }
        }
        .overlay(Rectangle().strokeBorder(risk >= .warning ? .clear : Theme.hairline, lineWidth: 1))
    }

    // MARK: Now

    @ViewBuilder private var now: some View {
        if let fetched = model.forecast, let current = fetched.value.current {
            let today = fetched.value.days.first
            let info = WeatherCode.describe(current.weather_code, isDay: current.is_day != 0)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 16) {
                    HStack(alignment: .top, spacing: 2) {
                        Text(current.temperature_2m.map { "\(Int($0.rounded()))" } ?? "–")
                            .font(.metric(128, .semibold))
                            .foregroundStyle(Theme.text)
                            .padding(.top, -14)
                        Text("°C").font(.mono(14, .medium)).foregroundStyle(Theme.dim).padding(.top, 10)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(info.text.uppercased()).font(.display(24, .semibold)).foregroundStyle(Theme.text)
                            .lineLimit(2).minimumScaleFactor(0.7)
                        dataLine(String(localized: "PERCEPITA"), Fmt.temp(current.apparent_temperature))
                        dataLine(String(localized: "MIN / MAX"), "\(Fmt.temp(today?.minTemp)) / \(Fmt.temp(today?.maxTemp))")
                        dataLine(String(localized: "PIOGGIA OGGI"), Fmt.number(today?.precipitation, decimals: 1, unit: "mm"))
                    }
                    .padding(.top, 6)
                    Spacer(minLength: 0)
                }
                ReadingGrid(items: [
                    Reading(label: String(localized: "Vento"), value: Fmt.number(current.wind_speed_10m), unit: "m/s",
                            note: current.wind_direction_10m == nil ? nil : String(localized: "da \(Fmt.compass(current.wind_direction_10m))"), size: 28),
                    Reading(label: String(localized: "Raffiche"), value: Fmt.number(current.wind_gusts_10m), unit: "m/s",
                            tint: windTint(current.wind_gusts_10m), size: 28),
                    Reading(label: String(localized: "Precip."), value: Fmt.number(current.precipitation, decimals: 1), unit: "mm/h", size: 28),
                    Reading(label: String(localized: "Nuvole"), value: Fmt.number(current.cloud_cover), unit: "%", size: 28),
                    Reading(label: String(localized: "Pressione"), value: Fmt.number(current.pressure_msl), unit: "hPa", size: 28),
                    Reading(label: String(localized: "Umidità"), value: Fmt.number(current.relative_humidity_2m), unit: "%", size: 28),
                ], columns: 3)
                .overlay(alignment: .top) { Rule() }
                .overlay(alignment: .bottom) { Rule() }
                FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: fetched.value.sources.joined(separator: " + "))
            }
        } else if let error = model.errors[.forecast] {
            ErrorNote(message: error)
        } else {
            ProgressView().tint(Theme.dim).frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    private func dataLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label.loc).font(.mono(9.5)).foregroundStyle(Theme.faint).frame(width: 82, alignment: .leading)
            Text(value).font(.metric(17, .semibold)).foregroundStyle(Theme.text)
        }
    }

    private func windTint(_ gust: Double?) -> Color {
        guard let gust else { return Theme.text }
        if gust >= 25 { return Theme.danger }
        if gust >= 18 { return Theme.warning }
        if gust >= 13 { return Theme.caution }
        return Theme.text
    }

    // MARK: Next hours (meteogram table)

    @ViewBuilder private var nextHours: some View {
        if let forecast = model.forecast?.value {
            let hours = forecast.upcomingHours(18)
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(index: "01", title: String(localized: "Prossime ore"), trailing: String(localized: "ORA LOCALE"))
                HourTable(hours: hours, zone: forecast.timeZone)
            }
        }
    }

    // MARK: Wind

    @ViewBuilder private var windSection: some View {
        if let current = model.forecast?.value.current {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(index: "02", title: String(localized: "Vento"), trailing: Risk.wind(mean: current.wind_speed_10m, gust: current.wind_gusts_10m).label.uppercased(),
                             trailingColor: Risk.wind(mean: current.wind_speed_10m, gust: current.wind_gusts_10m).color)
                HStack(alignment: .center, spacing: 20) {
                    WindDial(direction: current.wind_direction_10m, speed: current.wind_speed_10m, gust: current.wind_gusts_10m, size: 118)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(Fmt.number(current.wind_gusts_10m)).font(.metric(48, .bold)).foregroundStyle(windTint(current.wind_gusts_10m))
                            VStack(alignment: .leading, spacing: 0) {
                                Text("M/S RAFFICHE").font(.mono(9.5)).foregroundStyle(Theme.dim)
                                Text("DA \(Fmt.compass(current.wind_direction_10m))").font(.mono(9.5)).foregroundStyle(Theme.faint)
                            }
                        }
                        GustScale(mean: current.wind_speed_10m, gust: current.wind_gusts_10m)
                    }
                }
                Text("Sopra 25 m/s le portiere si aprono a fatica e i mezzi alti rischiano di ribaltarsi: tieni la portiera con due mani.")
                    .font(.app(.caption)).foregroundStyle(Theme.dim)
            }
        }
    }

    // MARK: Warnings / alerts

    @ViewBuilder private var warningsSection: some View {
        let here = model.warningsHere
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(index: "03", title: String(localized: "Allerte"), trailing: String(localized: "\(model.warnings?.value.count ?? 0) IN ISLANDA"))

            if recorder.isRecording, let session = recorder.session {
                HStack(spacing: 10) {
                    Rectangle().fill(Theme.danger).frame(width: 8, height: 8)
                    Text("REC").font(.mono(10.5, .semibold)).foregroundStyle(Theme.danger)
                    Spacer()
                    Text("\(Fmt.number(session.stats.km, decimals: 1)) KM").font(.mono(12, .semibold)).foregroundStyle(Theme.text)
                    Text("\(Int(recorder.speedKmh)) KM/H").font(.mono(12)).foregroundStyle(Theme.dim)
                }
                .padding(.vertical, 8)
                Rule()
            }

            NavigationLink { WarningsView() } label: {
                VStack(alignment: .leading, spacing: 0) {
                    if here.isEmpty {
                        row(marker: Theme.hairline) {
                            Text("Nessuna allerta IMO per questa zona").font(.app(.subheadline)).foregroundStyle(Theme.text)
                        }
                    } else {
                        ForEach(here.prefix(3)) { warning in
                            row(marker: warning.color.color) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        WarningBadge(color: warning.color)
                                        Text(warning.isActive() ? String(localized: "IN CORSO") : String(localized: "DALLE \(Fmt.dayTime(warning.onset, in: .iceland).uppercased())"))
                                            .font(.mono(9.5)).foregroundStyle(Theme.dim)
                                    }
                                    Text(warning.headline).font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text)
                                    Text("\(warning.region) · fino alle \(Fmt.dayTime(warning.expires, in: .iceland))")
                                        .font(.app(.caption)).foregroundStyle(Theme.dim)
                                }
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            ErrorNote(message: model.errors[.warnings])

            if let latest = alerts.latest, !latest.read, Date().timeIntervalSince(latest.date) < 6 * 3600 {
                Button { alerts.openInbox = true } label: {
                    row(marker: latest.risk.color) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("ULTIMA NOTIFICA · \(Fmt.relative(latest.date).uppercased())").font(.mono(9.5)).foregroundStyle(Theme.faint)
                            Text(latest.title).font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text)
                            Text(latest.body).font(.app(.caption)).foregroundStyle(Theme.dim).lineLimit(2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Table row with a coloured marker on the left and a rule below.
    private func row<Content: View>(marker: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Rectangle().fill(marker).frame(width: 3)
                content()
                Spacer(minLength: 0)
                Text("→").font(.mono(12)).foregroundStyle(Theme.faint)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 11)
            Rule()
        }
        .contentShape(Rectangle())
    }

    // MARK: Driving + aurora

    private var outlookSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(index: "04", title: String(localized: "Guida e aurora"))
            HStack(alignment: .top, spacing: 0) {
                drivingColumn.padding(.trailing, 14)
                Theme.hairline.frame(width: 1)
                auroraColumn.padding(.leading, 14)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var drivingColumn: some View {
        let driving = model.drivingRiskNext12h
        let hours = model.forecast?.value.upcomingHours(12) ?? []
        VStack(alignment: .leading, spacing: 10) {
            Text("GUIDA · 12 H").font(.mono(9.5)).foregroundStyle(Theme.faint)
            Text(driving.risk.label.uppercased()).font(.display(28, .bold))
                .foregroundStyle(driving.risk == .ok ? Theme.text : driving.risk.color)
            RiskTimeline(risks: hours.map { max($0.windRisk, $0.iceRisk) })
            VStack(spacing: 6) {
                miniRow(String(localized: "RAFF. MAX"), Fmt.ms(driving.maxGust))
                miniRow(String(localized: "MINIMA"), Fmt.temp(driving.minTemp))
                miniRow(String(localized: "NEVE"), Fmt.number(driving.snow, decimals: 1, unit: "cm"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var auroraColumn: some View {
        NavigationLink { AuroraView() } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text("AURORA · STANOTTE").font(.mono(9.5)).foregroundStyle(Theme.faint)
                if !model.auroraSlots.isEmpty {
                    let best = model.auroraBestTonight
                    let cls = best?.observability ?? .veryPoor
                    Text(cls.label.uppercased()).font(.display(24, .bold))
                        .foregroundStyle(cls >= .good ? Theme.aurora : cls == .moderate ? Theme.caution : Theme.text)
                        .lineLimit(2).minimumScaleFactor(0.7)
                    HStack(spacing: 2) {
                        ForEach(0..<4, id: \.self) { i in
                            Rectangle().fill(i < cls.rawValue ? Theme.aurora : Theme.hairline).frame(height: 8)
                        }
                    }
                    if let best {
                        Text("VERSO LE \(Fmt.time(best.date, in: zone)) · \(best.reasons.first ?? best.darkness.label)")
                            .font(.mono(9)).foregroundStyle(Theme.dim).lineLimit(3)
                    } else {
                        Text("NESSUNA ORA DI BUIO").font(.mono(9)).foregroundStyle(Theme.dim)
                    }
                    MiniBars(values: model.auroraSlots.prefix(24).map(\.index), maxValue: 0.6, color: Theme.aurora, height: 20)
                    Text("PREVISIONE COMPLETA →").font(.mono(9.5, .semibold)).foregroundStyle(Theme.accent)
                } else {
                    ProgressView().tint(Theme.dim)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func miniRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label.loc).font(.mono(9.5)).foregroundStyle(Theme.dim)
            Spacer()
            Text(value).font(.metric(16, .semibold)).foregroundStyle(Theme.text)
        }
    }

    // MARK: Roads

    private var roadsSection: some View {
        NavigationLink { RoadsView() } label: {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(index: "05", title: String(localized: "Strade"), trailing: String(localized: "TUTTE →"), trailingColor: Theme.accent)
                if let network = model.roads?.value {
                    let risks = network.segments.map(\.risk)
                    let order: [Risk?] = [.ok, .caution, .warning, .danger, nil]
                    let counts: [(Risk?, Int)] = order.map { r in (r, risks.filter { $0 == r }.count) }
                    HStack(spacing: 0) {
                        roadCount(counts[0].1, String(localized: "PERCORRIBILI"), Theme.text)
                        Theme.hairline.frame(width: 1)
                        roadCount(counts[1].1 + counts[2].1, String(localized: "NEVE / GHIACCIO"), counts[1].1 + counts[2].1 > 0 ? Theme.caution : Theme.text)
                        Theme.hairline.frame(width: 1)
                        roadCount(counts[3].1, String(localized: "CHIUSI"), counts[3].1 > 0 ? Theme.danger : Theme.text)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    StackedBar(parts: counts.map { (value: Double($0.1), color: $0.0 == .ok ? Theme.rule : ($0.0?.color ?? Theme.hairline)) })
                    VStack(spacing: 0) {
                        HStack {
                            Text("STAZIONE").frame(maxWidth: .infinity, alignment: .leading)
                            Text("VENTO/RAFF").frame(width: 92, alignment: .trailing)
                            Text("ASFALTO").frame(width: 62, alignment: .trailing)
                        }
                        .font(.mono(9)).foregroundStyle(Theme.faint).padding(.bottom, 6)
                        Rule()
                        ForEach(network.nearestStations(to: model.activePlace.coordinate, count: 4)) { item in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.station.name).font(.app(.subheadline, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                                    Text("\(Int(item.distance)) KM").font(.mono(9.5)).foregroundStyle(Theme.faint)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(Fmt.number(item.station.Vindhradi))/\(Fmt.number(item.station.Vindhvida))")
                                    .font(.metric(18, .semibold))
                                    .foregroundStyle(item.station.windRisk == .ok ? Theme.text : item.station.windRisk.color)
                                    .frame(width: 92, alignment: .trailing)
                                Text(Fmt.temp(item.station.Veghiti)).font(.metric(18, .semibold))
                                    .foregroundStyle(item.station.surfaceRisk == .ok ? Theme.text : item.station.surfaceRisk.color)
                                    .frame(width: 62, alignment: .trailing)
                            }
                            .padding(.vertical, 9)
                            Rule()
                        }
                    }
                    if let fetched = model.roads { FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: String(localized: "Vegagerðin")) }
                } else if let error = model.errors[.roads] {
                    ErrorNote(message: error)
                } else {
                    ProgressView().tint(Theme.dim)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func roadCount(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)").font(.metric(34, .semibold)).foregroundStyle(color)
            Text(label.loc).font(.mono(9)).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 10)
    }

    // MARK: Webcams

    @ViewBuilder private var webcamsSection: some View {
        let near = Webcams.nearest(model.webcams?.value ?? [], to: model.activePlace.coordinate, within: 60, limit: 6)
        if !near.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink { WebcamsView() } label: {
                    SectionLabel(index: "06", title: String(localized: "Webcam vicine"), trailing: String(localized: "TUTTE →"), trailingColor: Theme.accent)
                }
                .buttonStyle(.plain)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(near) { site in
                            NavigationLink { WebcamSiteView(site: site) } label: { WebcamThumb(site: site, width: 200) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: More

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(index: "07", title: String(localized: "Terra, mare, servizi"))
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    quakesCell
                    Theme.hairline.frame(width: 1)
                    seaCell
                }
                .fixedSize(horizontal: false, vertical: true)
                Rule()
                HStack(spacing: 0) {
                    fuelCell
                    Theme.hairline.frame(width: 1)
                    transportCell
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .overlay(alignment: .top) { Rule() }
            .overlay(alignment: .bottom) { Rule() }
        }
    }

    private func cell<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.loc).font(.mono(9.5)).foregroundStyle(Theme.faint)
            content()
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private var quakesCell: some View {
        NavigationLink { QuakesView() } label: {
            cell(String(localized: "TERREMOTI · 24 H")) {
                let recent = model.recentQuakes24h
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(recent.count)").font(.metric(34, .semibold)).foregroundStyle(Theme.text)
                    Text("SCOSSE").font(.mono(9.5)).foregroundStyle(Theme.dim)
                }
                MiniBars(values: quakeHistogram(recent), color: Theme.text, height: 22)
                if let strongest = recent.max(by: { $0.magnitude < $1.magnitude }) {
                    Text("MAX M\(Fmt.number(strongest.magnitude, decimals: 1)) \(strongest.region)")
                        .font(.mono(9)).foregroundStyle(strongest.magnitude >= 3 ? Theme.warning : Theme.dim).lineLimit(1)
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

    private var seaCell: some View {
        cell(String(localized: "MARE · ONDE")) {
            if let marine = model.marine?.value, marine.hasData, let c = marine.current {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Fmt.number(c.wave_height, decimals: 1)).font(.metric(34, .semibold)).foregroundStyle(Theme.text)
                    Text("M · \(Fmt.number(c.wave_period, decimals: 0)) S").font(.mono(9.5)).foregroundStyle(Theme.dim)
                }
                HStack(spacing: 6) {
                    RiskBadge(risk: marine.beachRisk, text: String(localized: "Spiagge"))
                    RiskBadge(risk: marine.seaRisk, text: String(localized: "Barca"))
                }
                Text("ACQUA \(Fmt.temp(c.sea_surface_temperature))").font(.mono(9)).foregroundStyle(Theme.faint)
            } else {
                Text("Non disponibile per questa località").font(.app(.caption)).foregroundStyle(Theme.faint)
            }
        }
    }

    private var fuelCell: some View {
        cell(String(localized: "CARBURANTE")) {
            if let stations = model.fuel?.value, let first = FuelStations.nearest(stations, to: model.activePlace.coordinate, kind: .fuel, limit: 1).first {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Fmt.number(first.km, decimals: first.km < 10 ? 1 : 0)).font(.metric(34, .semibold)).foregroundStyle(Theme.text)
                    Text("KM").font(.mono(9.5)).foregroundStyle(Theme.dim)
                }
                Text(first.station.name).font(.app(.caption)).foregroundStyle(Theme.dim).lineLimit(1)
                if let charger = FuelStations.nearest(stations, to: model.activePlace.coordinate, kind: .charger, limit: 1).first {
                    Text("RICARICA EV \(Fmt.number(charger.km, decimals: 0)) KM").font(.mono(9)).foregroundStyle(Theme.faint)
                }
            } else {
                Text(model.errors[.fuel] == nil ? String(localized: "Download in corso") : String(localized: "Non disponibile")).font(.app(.caption)).foregroundStyle(Theme.faint)
            }
        }
    }

    private var transportCell: some View {
        NavigationLink { TransportView() } label: {
            cell(String(localized: "VOLI E TRAGHETTI")) {
                let followed = (model.flights?.value ?? []).filter { alerts.isFollowing($0.flightNumber) }
                if let flight = followed.first {
                    Text(flight.flightNumber).font(.metric(30, .semibold)).foregroundStyle(Theme.text)
                    Text(flight.statusInfo.text).font(.app(.caption))
                        .foregroundStyle(flight.statusInfo.risk == .ok ? Theme.dim : flight.statusInfo.risk.color).lineLimit(2)
                } else {
                    Text("KEF").font(.metric(34, .semibold)).foregroundStyle(Theme.text)
                    Text("Arrivi e partenze live, Herjólfur").font(.app(.caption)).foregroundStyle(Theme.dim)
                }
            }
        }
        .buttonStyle(.plain)
        .task { if model.flights == nil && !alerts.settings.followedFlights.isEmpty { await model.refreshTransport() } }
    }

    // MARK: News

    @ViewBuilder private var newsSection: some View {
        if let news = model.news?.value, !news.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(index: "08", title: String(localized: "SafeTravel")).padding(.bottom, 8)
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
        row(marker: item.risk > .ok ? item.risk.color : Theme.hairline) {
            VStack(alignment: .leading, spacing: 3) {
                if let date = item.date { Text(Fmt.relative(date).uppercased()).font(.mono(9)).foregroundStyle(Theme.faint) }
                Text(item.title.loc).font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
                Text(item.summary).font(.app(.caption)).foregroundStyle(Theme.dim).lineLimit(2).multilineTextAlignment(.leading)
            }
        }
    }

    // MARK: Daylight

    @ViewBuilder private var daylight: some View {
        if let today = model.forecast?.value.days.first {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(title: String(localized: "Luce"), trailing: Fmt.duration(today.daylight).uppercased())
                DaylightBar(sunrise: today.sunrise, sunset: today.sunset, zone: zone)
                HStack {
                    Text("ALBA \(Fmt.time(today.sunrise, in: zone))")
                    Spacer()
                    Text("TRAMONTO \(Fmt.time(today.sunset, in: zone))")
                }
                .font(.mono(10)).foregroundStyle(Theme.dim)
            }
        }
    }
}

/// Hour-by-hour table: one column per hour, one row per variable.
/// Values past the safety thresholds are set in the signal colours.
struct HourTable: View {
    let hours: [HourPoint]
    let zone: TimeZone

    private let labelWidth: CGFloat = 52
    private let columnWidth: CGFloat = 40

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                label(String(localized: "ORA")); label(String(localized: "CIELO")); label("°C"); label(String(localized: "VENTO")); label(String(localized: "RAFF.")); label(String(localized: "DIR")); label("MM")
            }
            .frame(width: labelWidth, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(hours.enumerated()), id: \.offset) { index, hour in
                        VStack(spacing: 0) {
                            cell(index == 0 ? String(localized: "now.short", defaultValue: "ORA") : Fmt.hour(hour.date, in: zone), mono: true, color: index == 0 ? Theme.accent : Theme.dim)
                            Image(systemName: WeatherCode.describe(hour.code, isDay: hour.isDay).symbol)
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.text)
                                .frame(height: 30)
                            cell(Fmt.number(hour.temperature), color: Theme.text)
                            cell(Fmt.number(hour.wind), color: hour.wind.map { $0 >= 15 ? Theme.warning : Theme.text } ?? Theme.text)
                            gustCell(hour.gust)
                            WindArrow(degrees: hour.windDirection).font(.system(size: 11)).foregroundStyle(Theme.dim).frame(height: 30)
                            cell(precip(hour.precipitation), color: (hour.precipitation ?? 0) >= 2 ? Theme.accent : ((hour.precipitation ?? 0) > 0 ? Theme.text : Theme.faint))
                        }
                        .frame(width: columnWidth)
                        .overlay(alignment: .leading) { Theme.hairline.frame(width: 1) }
                    }
                }
            }
        }
        .overlay(alignment: .top) { Rule() }
        .overlay(alignment: .bottom) { Rule() }
    }

    private func label(_ text: String) -> some View {
        Text(text.loc).font(.mono(9)).foregroundStyle(Theme.faint).frame(height: 30, alignment: .leading)
    }

    private func cell(_ text: String, mono: Bool = false, color: Color) -> some View {
        Text(text.loc)
            .font(mono ? .mono(10, .medium) : .metric(18, .semibold))
            .foregroundStyle(color)
            .frame(height: 30)
    }

    @ViewBuilder private func gustCell(_ gust: Double?) -> some View {
        let value = gust ?? 0
        let background: Color = value >= 25 ? Theme.danger : (value >= 18 ? Theme.warning : .clear)
        Text(Fmt.number(gust))
            .font(.metric(18, .bold))
            .foregroundStyle(value >= 18 ? Theme.onAccent : (value >= 13 ? Theme.caution : Theme.text))
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(background)
    }

    private func precip(_ value: Double?) -> String {
        guard let value else { return "–" }
        if value == 0 { return "·" }
        return value < 10 ? String(format: "%.1f", value) : String(Int(value.rounded()))
    }
}
