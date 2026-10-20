import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(AlertCenter.self) private var alerts
    @Environment(DriveRecorder.self) private var recorder
    @State private var showInfo = false
    @State private var showAccount = false
    @State private var selectedFuel: FuelStation?
    @AppStorage("today.detail") private var detailRaw = Detail.wind.rawValue
    @Environment(Account.self) private var account

    private var zone: TimeZone { model.forecast?.value.timeZone ?? .iceland }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    VStack(alignment: .leading, spacing: 18) {
                        Group {
                            topBar
                            PlaceHeader(size: 44)
                        }
                        // A halo of the background colour keeps the text legible over the photo.
                        .shadow(color: Theme.bg.opacity(0.9), radius: 6)
                        .shadow(color: Theme.bg.opacity(0.6), radius: 14)
                        statusBanner
                        now
                    }
                    .background(alignment: .top) {
                        PlaceBackdrop()
                            .padding(.horizontal, -18)
                            .padding(.top, -120)  // reaches under the status bar
                    }
                    TodayTripCard()
                    TodayBrief()
                    warningsSection
                    VStack(spacing: 10) {
                        AuroraNowPanel()
                        AuroraReportBar(compact: true)
                        AuroraFinderButton()
                    }
                    nextHours
                    outlookSection
                    exploreSection
                    detailsSection
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selectedFuel) { station in
                FuelDetail(station: station, from: model.activePlace).presentationDetents([.medium, .large])
            }
            .refreshable {
                await model.refreshAll()
                await alerts.check()
                Haptics.result(model.errors[.forecast] == nil)
            }
            .sheet(isPresented: $showInfo) { InfoView() }
            .sheet(isPresented: $showAccount) { AccountView() }
        }
    }

    // MARK: Details (one topic at a time)

    enum Detail: String, CaseIterable, Identifiable {
        case wind, roads, webcams, more, news, light
        var id: String { rawValue }
        var title: String {
            switch self {
            case .wind: return String(localized: "Vento")
            case .roads: return String(localized: "Strade")
            case .webcams: return String(localized: "Webcam")
            case .more: return String(localized: "Terra e mare")
            case .news: return String(localized: "SafeTravel")
            case .light: return String(localized: "Luce")
            }
        }
        var symbol: String {
            switch self {
            case .wind: return "wind"
            case .roads: return "road.lanes"
            case .webcams: return "video.fill"
            case .more: return "waveform.path.ecg"
            case .news: return "megaphone.fill"
            case .light: return "sun.horizon.fill"
            }
        }
    }

    private var detailsSection: some View {
        let current = Detail(rawValue: detailRaw) ?? .wind
        return VStack(alignment: .leading, spacing: 14) {
            SectionLabel(index: "04", title: String(localized: "Dettagli"))
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(Detail.allCases) { item in
                    Button {
                        if detailRaw != item.rawValue { Haptics.select() }
                        withAnimation(.snappy(duration: 0.2)) { detailRaw = item.rawValue }
                    } label: {
                        Label(item.title.uppercased(), systemImage: item.symbol)
                            .font(.mono(10.5, .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .foregroundStyle(current == item ? Theme.onAccent : Theme.text)
                            .background(current == item ? Theme.accent : Color.clear)
                            .overlay(Rectangle().strokeBorder(current == item ? Color.clear : Theme.hairline))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(current == item ? .isSelected : [])
                }
            }
            Group {
                switch current {
                case .wind: windSection
                case .roads:
                    if model.inIceland { roadsSection } else { CoverageNote(feature: String(localized: "Strade, chiusure e stazioni Vegagerðin")) }
                case .webcams:
                    if model.inIceland { webcamsSection } else { CoverageNote(feature: String(localized: "Le webcam stradali")) }
                case .more:
                    if !model.inIceland { CoverageNote(feature: String(localized: "Terremoti, distributori, voli KEF e traghetti"), showsIcelandData: true) }
                    moreSection
                case .news:
                    if model.inIceland { newsSection } else { CoverageNote(feature: String(localized: "Gli avvisi SafeTravel")) }
                case .light: daylight
                }
            }
            .transition(.opacity)
        }
    }

    // MARK: Explore

    /// Photo tiles to the main sections, each with one live line.
    private var exploreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // What has no tab of its own (Aurora, Weather, Map and Trip are in the bar below).
            SectionLabel(title: String(localized: "Esplora"))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                NavigationLink { SightsView() } label: {
                    HeroTile(hero: .trip, title: String(localized: "Da vedere"),
                             status: String(localized: "Cascate, belvedere, sorgenti calde vicino a te"))
                }
                NavigationLink { RoadsView() } label: {
                    HeroTile(hero: .roads, title: String(localized: "Strade"), status: roadsStatus)
                }
                NavigationLink { QuakesView() } label: {
                    HeroTile(hero: .volcano, title: String(localized: "Vulcani e terremoti"),
                             status: model.inIceland ? String(localized: "\(model.recentQuakes24h.count) scosse nelle ultime 24 h") : String(localized: "Solo in Islanda, per ora"))
                }
                NavigationLink { WebcamsView() } label: {
                    HeroTile(hero: .drive, title: String(localized: "Webcam"), status: String(localized: "Le strade come sono adesso"))
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var auroraStatus: String {
        guard let best = model.auroraBestTonight else { return String(localized: "Previsione per stanotte") }
        return String(localized: "\(best.observability.label) verso le \(Fmt.time(best.date, in: zone))")
    }

    private var roadsStatus: String {
        guard model.inIceland else { return String(localized: "Solo in Islanda, per ora") }
        guard let info = model.roadInfo?.value else { return String(localized: "Condizioni e notizie Vegagerðin") }
        let closed = info.sections.filter(\.isClosed).count
        let difficult = info.sections.filter { !$0.isClosed && ($0.risk ?? .ok) >= .warning }.count
        return String(localized: "\(closed) tratti chiusi · \(difficult) difficili")
    }

    private var weatherStatus: String {
        guard let current = model.forecast?.value.current else { return String(localized: "Previsioni ora per ora") }
        let info = WeatherCode.describe(current.weather_code, isDay: current.is_day != 0)
        return "\(Fmt.temp(current.temperature_2m)) · \(info.text)"
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            LogoMark(size: 20)
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
            HeaderButton(systemImage: "gearshape") { model.showSettings = true }
                .accessibilityLabel("Impostazioni")
            HeaderButton(systemImage: "bell", tint: Theme.text, dot: alerts.unreadCount > 0) {
                alerts.openInbox = true
            }
            .accessibilityLabel("Allerte")
            .accessibilityIdentifier("today.alerts")
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
                    Reading(label: String(localized: "Vento"), value: Fmt.wind(current.wind_speed_10m), unit: Fmt.windUnit,
                            note: current.wind_direction_10m == nil ? nil : String(localized: "da \(Fmt.compass(current.wind_direction_10m))"), size: 28),
                    Reading(label: String(localized: "Raffiche"), value: Fmt.wind(current.wind_gusts_10m), unit: Fmt.windUnit,
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
            SkeletonBlock(lines: 3)
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
                SectionLabel(index: "02", title: String(localized: "Prossime ore"), trailing: String(localized: "ORA LOCALE"))
                HourTable(hours: hours, zone: forecast.timeZone)
            }
        }
    }

    // MARK: Wind

    @ViewBuilder private var windSection: some View {
        if let current = model.forecast?.value.current {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(title: String(localized: "Vento"), trailing: Risk.wind(mean: current.wind_speed_10m, gust: current.wind_gusts_10m).label.uppercased(),
                             trailingColor: Risk.wind(mean: current.wind_speed_10m, gust: current.wind_gusts_10m).color)
                HStack(alignment: .center, spacing: 20) {
                    WindDial(direction: current.wind_direction_10m, speed: current.wind_speed_10m, gust: current.wind_gusts_10m, size: 118)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(Fmt.wind(current.wind_gusts_10m)).font(.metric(48, .bold)).foregroundStyle(windTint(current.wind_gusts_10m))
                            VStack(alignment: .leading, spacing: 0) {
                                Text("\(Fmt.windUnit.uppercased()) RAFFICHE").font(.mono(9.5)).foregroundStyle(Theme.dim)
                                Text("DA \(Fmt.compass(current.wind_direction_10m))").font(.mono(9.5)).foregroundStyle(Theme.faint)
                            }
                        }
                        GustScale(mean: current.wind_speed_10m, gust: current.wind_gusts_10m)
                    }
                }
                Text("Sopra \(Fmt.ms(25)) le portiere si aprono a fatica e i mezzi alti rischiano di ribaltarsi: tieni la portiera con due mani.")
                    .font(.app(.caption)).foregroundStyle(Theme.dim)
            }
        }
    }

    // MARK: Warnings / alerts

    @ViewBuilder private var warningsSection: some View {
        let here = model.warningsHere
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(index: "01", title: String(localized: "Allerte"),
                         trailing: model.inIceland ? String(localized: "\(model.warnings?.value.count ?? 0) IN ISLANDA") : nil)

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

            if !model.inIceland {
                CoverageNote(feature: String(localized: "Le allerte meteo ufficiali (IMO)"))
            } else {
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
            }

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
            SectionLabel(index: "03", title: String(localized: "Guida e aurora"))
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
                    SkeletonBlock(lines: 2, height: 10, showsFigure: false)
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
                SectionLabel(title: String(localized: "Strade"), trailing: String(localized: "TUTTE →"), trailingColor: Theme.accent)
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
                                Text("\(Fmt.wind(item.station.Vindhradi))/\(Fmt.wind(item.station.Vindhvida))")
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
                    SkeletonBlock(lines: 2, height: 10, showsFigure: false)
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
                    SectionLabel(title: String(localized: "Webcam vicine"), trailing: String(localized: "TUTTE →"), trailingColor: Theme.accent)
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
        } else {
            NavigationLink { WebcamsView() } label: {
                Label("Nessuna webcam entro 60 km: vedi tutte le webcam stradali", systemImage: "video")
                    .font(.app(.subheadline)).foregroundStyle(Theme.text)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: More

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: String(localized: "Terra, mare, servizi"))
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
                Rule()
                sightsCell
                Rule()
                shopsCell
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
                HStack(alignment: .center, spacing: 8) {
                    KindIcon(name: first.station.imageName, size: 34)
                    Text(Fmt.number(first.km, decimals: first.km < 10 ? 1 : 0)).font(.metric(34, .semibold)).foregroundStyle(Theme.text)
                    Text("KM").font(.mono(9.5)).foregroundStyle(Theme.dim)
                }
                .contentShape(Rectangle())
                .onTapGesture { selectedFuel = first.station }
                Text(first.station.name).font(.app(.caption)).foregroundStyle(Theme.dim).lineLimit(1)
                    .onTapGesture { selectedFuel = first.station }
                if let charger = FuelStations.nearest(stations, to: model.activePlace.coordinate, kind: .charger, limit: 1).first {
                    Text("RICARICA EV \(Fmt.number(charger.km, decimals: 0)) KM").font(.mono(9)).foregroundStyle(Theme.faint)
                }
            } else {
                Text(model.errors[.fuel] == nil ? String(localized: "Download in corso") : String(localized: "Non disponibile")).font(.app(.caption)).foregroundStyle(Theme.faint)
            }
        }
    }

    /// What there is to see around the place, the best-known first.
    private var sightsCell: some View {
        NavigationLink { SightsView() } label: {
            let c = model.activePlace.coordinate
            let near = model.spots.map { (sight: $0, km: Geo.distanceKm(c, $0.coordinate)) }.filter { $0.km <= 60 }
            let best = near.filter { $0.sight.isTop }.min { $0.km < $1.km } ?? near.filter { $0.sight.notable }.min { $0.km < $1.km }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("DA VEDERE · ENTRO 60 KM").font(.mono(9.5)).foregroundStyle(Theme.faint)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.faint)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(near.count)").font(.metric(30, .semibold)).foregroundStyle(Theme.text)
                    Text("LUOGHI").font(.mono(9.5)).foregroundStyle(Theme.dim)
                    Spacer()
                    HStack(spacing: -6) {
                        ForEach(Array(Set(near.map { $0.sight.kind })).sorted { $0.rawValue < $1.rawValue }.prefix(6), id: \.self) { kind in
                            KindIcon(name: kind.imageName, size: 32)
                                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.bg, lineWidth: 2))
                        }
                    }
                }
                if let best {
                    Text(String(localized: "Da non perdere: \(best.sight.name), \(Fmt.number(best.km, decimals: best.km < 10 ? 1 : 0)) km"))
                        .font(.app(.caption, .semibold)).foregroundStyle(Theme.dim).lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today.sights")
        .task { await model.loadSights() }
    }

    /// The nearest supermarket and whether it is open: outside the towns shops close early.
    private var shopsCell: some View {
        NavigationLink { ShopsView() } label: {
            let now = Date()
            let shops = model.shops?.value ?? []
            let market = Shops.nearest(shops, to: model.activePlace.coordinate, kinds: [.supermarket], limit: 1).first
            let open = Shops.nearest(shops, to: model.activePlace.coordinate, kinds: [.supermarket, .convenience], within: 60)
                .first { $0.shop.status(at: now).open == true }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("SPESA · SUPERMERCATI").font(.mono(9.5)).foregroundStyle(Theme.faint)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.faint)
                }
                if let market {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        KindIcon(name: Shop.Kind.supermarket.imageName, size: 34)
                        Text(market.shop.name).font(.app(.headline)).foregroundStyle(Theme.text).lineLimit(1)
                        Text("\(Fmt.number(market.km, decimals: market.km < 10 ? 1 : 0)) KM").font(.mono(10.5, .semibold)).foregroundStyle(Theme.dim)
                    }
                    let status = market.shop.status(at: now)
                    Text(status.text).font(.app(.caption, .semibold))
                        .foregroundStyle(status.open == true ? Theme.aurora : status.open == false ? Theme.danger : Theme.faint)
                    if status.open != true, let open, open.shop.id != market.shop.id {
                        Text(String(localized: "Aperto adesso: \(open.shop.name), \(Fmt.number(open.km, decimals: open.km < 10 ? 1 : 0)) km"))
                            .font(.app(.caption)).foregroundStyle(Theme.dim).lineLimit(1)
                    }
                } else {
                    Text(model.errors[.shops] == nil ? String(localized: "Download in corso") : String(localized: "Non disponibile"))
                        .font(.app(.caption)).foregroundStyle(Theme.faint)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today.shops")
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
                SectionLabel(title: String(localized: "SafeTravel")).padding(.bottom, 8)
                ForEach(news.prefix(4)) { item in
                    if let link = item.link {
                        Link(destination: link) { newsRow(item) }
                    } else {
                        newsRow(item)
                    }
                }
            }
        } else {
            Text("Nessun avviso SafeTravel in questo momento.").font(.app(.subheadline)).foregroundStyle(Theme.dim)
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
                            cell(Fmt.wind(hour.wind), color: hour.wind.map { $0 >= 15 ? Theme.warning : Theme.text } ?? Theme.text)
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
        Text(Fmt.wind(gust))
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
