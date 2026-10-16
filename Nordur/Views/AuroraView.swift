import SwiftUI
import Charts

struct AuroraView: View {
    @Environment(AppModel.self) private var model

    private var zone: TimeZone { model.forecast?.value.timeZone ?? .iceland }
    private var intel: SpaceIntel? { model.space?.value }
    private var kpNeeded: Double { AuroraCalc.kpNeeded(latitude: model.activePlace.coordinate.lat) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(title: "Aurora", subtitle: "NOAA SWPC · NASA CCMC")
                    PlaceHeader(size: 30)
                    NavigationLink { AuroraLiveView() } label: {
                        HStack {
                            Text("MAPPA DELL'OVALE IN TEMPO REALE").font(.mono(11, .semibold)).tracking(0.6)
                            Spacer()
                            Text("→").font(.mono(14, .semibold))
                        }
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .background(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
                tonight
                kpSection
                solarWindSection
                nasaSection
                noaaSection
                links
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refreshGlobal(force: true) }
    }

    // MARK: 01 Tonight

    @ViewBuilder private var tonight: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(index: "01", title: "Prossime 24 ore", trailing: "KP NECESSARIO QUI ≥ \(Fmt.number(kpNeeded, decimals: 1))")
            if let outlook = model.auroraOutlook {
                let score = outlook.best?.score ?? 0
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(score)").font(.metric(84, .bold)).foregroundStyle(score >= 35 ? Theme.aurora : Theme.text)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("/100").font(.mono(11)).foregroundStyle(Theme.dim)
                        Text(outlook.verdict.text.uppercased()).font(.display(22, .semibold)).foregroundStyle(Theme.text)
                        if let best = outlook.best, best.score > 0 {
                            Text("MEGLIO VERSO LE \(Fmt.time(best.date, in: zone))").font(.mono(10)).foregroundStyle(Theme.dim)
                        }
                    }
                }
                if outlook.hasDarkness {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            head("ORA", 44, .leading); head("KP", 50); head("NUVOLE", 64); head("PUNTEGGIO", nil, .leading).padding(.leading, 12)
                        }
                        .padding(.bottom, 6)
                        Rule()
                        ForEach(outlook.darkHours) { hour in
                            HStack(spacing: 0) {
                                Text(Fmt.hour(hour.date, in: zone)).font(.mono(10.5, .medium)).foregroundStyle(Theme.dim).frame(width: 44, alignment: .leading)
                                Text(Fmt.number(hour.kp, decimals: 1)).font(.metric(18, .semibold))
                                    .foregroundStyle((hour.kp ?? 0) >= kpNeeded ? Theme.aurora : Theme.text).frame(width: 50, alignment: .trailing)
                                Text(Fmt.percent(hour.cloudCover)).font(.metric(18)).foregroundStyle((hour.cloudCover ?? 100) > 70 ? Theme.faint : Theme.text)
                                    .frame(width: 64, alignment: .trailing)
                                HStack(spacing: 6) {
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Rectangle().fill(Theme.hairline).frame(height: 1)
                                            Rectangle().fill(Theme.aurora).frame(width: geo.size.width * CGFloat(hour.score) / 100, height: 6)
                                        }
                                        .frame(maxHeight: .infinity)
                                    }
                                    Text("\(hour.score)").font(.metric(16, .semibold)).foregroundStyle(Theme.text).frame(width: 26, alignment: .trailing)
                                }
                                .padding(.leading, 12)
                            }
                            .frame(height: 30)
                            Rule()
                        }
                    }
                } else {
                    Text("Tra metà maggio e inizio agosto in Islanda il cielo non diventa mai abbastanza buio.")
                        .font(.app(.caption)).foregroundStyle(Theme.dim)
                }
                Text("Punteggio = attività geomagnetica (Kp incrociato, ovale OVATION) × cielo sereno, solo nelle ore di buio.")
                    .font(.app(.caption)).foregroundStyle(Theme.dim)
            } else {
                ProgressView().tint(Theme.dim)
            }
        }
    }

    // MARK: 02 Kp cross-check

    @ViewBuilder private var kpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(index: "02", title: "Indice Kp · incrocio fonti", trailing: spreadLabel.text, trailingColor: spreadLabel.color)
            if let intel {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Fmt.number(intel.consensusNow ?? intel.kpObserved?.kp, decimals: 1))
                        .font(.metric(84, .bold))
                        .foregroundStyle(kpColor(intel.consensusNow ?? 0))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("KP ADESSO").font(.mono(10)).foregroundStyle(Theme.dim)
                        Text(kpLabel(intel.consensusNow ?? 0).uppercased()).font(.display(22, .semibold)).foregroundStyle(Theme.text)
                        if let peak = intel.maxBlendNext24h {
                            Text("PICCO 24 H: KP \(Fmt.number(peak.value, decimals: 1)) · \(Fmt.dayTime(peak.date, in: zone).uppercased())")
                                .font(.mono(10)).foregroundStyle(peak.value >= kpNeeded ? Theme.aurora : Theme.dim)
                        }
                    }
                }

                VStack(spacing: 0) {
                    sourceRow("NOAA · stima ogni minuto", "magnetometri a terra", intel.kpNow, time: intel.kpNowTime)
                    sourceRow("NOAA · Kp ufficiale 3 h", "ultimo blocco chiuso", intel.kpObserved?.kp, time: intel.kpObserved?.date)
                    sourceRow("Vento solare · Newell", intel.solarWind?.leadMinutes.map { "anticipo ~\(Int($0)) min · tendenza \(Fmt.number(intel.solarWindTrend, decimals: 1))" } ?? "da L1",
                              intel.solarWindKp, time: intel.solarWind?.latest?.date)
                    sourceRow("NOAA · previsione blocco attuale", "modello SWPC", currentBlock?.noaa, time: currentBlock?.date)
                    if let nasa = nextCME {
                        sourceRow("NASA · CME \(nasa.glancing ? "di striscio" : "diretta")", "arrivo \(nasa.arrivalDate.map { Fmt.dayTime($0, in: zone) } ?? "–") ±7 h",
                                  nasa.expectedKp, time: nil, highlight: true)
                    } else {
                        sourceRow("NASA · CME verso la Terra", intel.donki == nil ? "DONKI non raggiungibile" : "nessuna prevista", nil, time: nil)
                    }
                }
                .overlay(alignment: .top) { Rule() }

                blendChart(intel)

                Text("Kp combinato: per ogni blocco di 3 ore si parte dalla previsione NOAA; nelle prossime 3 ore si fa la media con le misure attuali (stima NOAA a terra ×2, vento solare ×1); se NASA prevede l'arrivo di una CME, il blocco sale al Kp atteso da NASA.")
                    .font(.app(.caption)).foregroundStyle(Theme.dim)
            } else {
                ErrorNote(message: model.errors[.kp])
                ProgressView().tint(Theme.dim)
            }
        }
    }

    private var currentBlock: KpBlendPoint? {
        let now = Date()
        return intel?.blend.first { $0.date <= now && now < $0.date.addingTimeInterval(3 * 3600) }
    }

    private var nextCME: DonkiDigest.Arrival? {
        intel?.donki?.upcoming.filter { $0.expectedKp != nil }.min { ($0.arrivalDate ?? .distantFuture) < ($1.arrivalDate ?? .distantFuture) }
    }

    private var spreadLabel: (text: String, color: Color) {
        guard let spread = intel?.spread else { return ("", Theme.dim) }
        if spread < 1 { return ("FONTI CONCORDI", Theme.dim) }
        if spread < 2 { return ("SCARTO \(Fmt.number(spread, decimals: 1))", Theme.caution) }
        return ("FONTI DISCORDI · \(Fmt.number(spread, decimals: 1))", Theme.warning)
    }

    private func sourceRow(_ title: String, _ detail: String, _ kp: Double?, time: Date?, highlight: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.app(.subheadline, .medium)).foregroundStyle(Theme.text)
                    Text(detail + (time.map { " · \(Fmt.time($0, in: zone))" } ?? "")).font(.mono(9.5)).foregroundStyle(Theme.faint).lineLimit(1)
                }
                Spacer()
                Text(Fmt.number(kp, decimals: 1)).font(.metric(26, .semibold))
                    .foregroundStyle(kp == nil ? Theme.faint : (highlight ? Theme.accent : kpColor(kp ?? 0)))
            }
            .padding(.vertical, 9)
            Rule()
        }
    }

    private func blendChart(_ intel: SpaceIntel) -> some View {
        let now = Date()
        let points = intel.blend.filter { $0.date >= now.addingTimeInterval(-12 * 3600) && $0.date <= now.addingTimeInterval(72 * 3600) }
        return VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(points) { p in
                    BarMark(x: .value("Ora", p.date, unit: .hour), y: .value("Kp", p.value), width: .fixed(9))
                        .foregroundStyle(p.isObserved ? Theme.dim : (p.nasa != nil && p.value == p.nasa ? Theme.accent : kpColor(p.value)))
                    if let noaa = p.noaa, !p.isObserved {
                        PointMark(x: .value("Ora", p.date, unit: .hour), y: .value("NOAA", noaa))
                            .symbol(.circle).symbolSize(14).foregroundStyle(Theme.text)
                    }
                }
                RuleMark(y: .value("Soglia", kpNeeded))
                    .foregroundStyle(Theme.aurora).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("SOGLIA QUI \(Fmt.number(kpNeeded, decimals: 1))").font(.mono(8.5, .semibold)).foregroundStyle(Theme.aurora)
                    }
                RuleMark(x: .value("Adesso", now)).foregroundStyle(Theme.accent).lineStyle(StrokeStyle(lineWidth: 1))
            }
            .chartYScale(domain: 0...9)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.hairline)
                    AxisValueLabel {
                        if let date = value.as(Date.self) { Text(Fmt.axis(date, hour: false).uppercased()).font(.mono(9)).foregroundStyle(Theme.faint) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 3, 5, 7, 9]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.hairline)
                    AxisValueLabel { if let v = value.as(Int.self) { Text("\(v)").font(.mono(9)).foregroundStyle(Theme.faint) } }
                }
            }
            .frame(height: 170)
            .environment(\.locale, Fmt.italian)
            HStack(spacing: 14) {
                legend(Theme.dim, "osservato")
                legend(Theme.text, "combinato")
                legend(Theme.accent, "CME NASA")
                HStack(spacing: 5) { Circle().fill(Theme.text).frame(width: 5, height: 5); Text("NOAA").font(.mono(9)).foregroundStyle(Theme.dim) }
            }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(color).frame(width: 8, height: 8)
            Text(text.uppercased()).font(.mono(9)).foregroundStyle(Theme.dim)
        }
    }

    private func kpColor(_ kp: Double) -> Color {
        if kp >= 7 { return Theme.danger }
        if kp >= 5 { return Theme.warning }
        if kp >= kpNeeded { return Theme.aurora }
        return Theme.text
    }

    private func kpLabel(_ kp: Double) -> String {
        switch kp {
        case 8...: return "Tempesta estrema"
        case 7..<8: return "Tempesta forte"
        case 6..<7: return "Tempesta moderata"
        case 5..<6: return "Tempesta minore"
        case 4..<5: return "Attivo"
        case 3..<4: return "Instabile"
        default: return "Quieto"
        }
    }

    // MARK: 03 Solar wind

    @ViewBuilder private var solarWindSection: some View {
        if let wind = intel?.solarWind, let latest = wind.latest {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(index: "03", title: "Vento solare a L1", trailing: (wind.spacecraft ?? "RTSW").uppercased())
                ReadingGrid(items: [
                    Reading(label: "Bz (GSM)", value: Fmt.number(latest.bz, decimals: 1), unit: "nT",
                            note: latest.bz <= -5 ? "verso sud: favorevole" : (latest.bz < 0 ? "verso sud" : "verso nord"),
                            tint: latest.bz <= -5 ? Theme.aurora : Theme.text, size: 26),
                    Reading(label: "Bt", value: Fmt.number(latest.bt, decimals: 1), unit: "nT", size: 26),
                    Reading(label: "Velocità", value: Fmt.number(latest.speed), unit: "km/s",
                            tint: (latest.speed ?? 0) >= 600 ? Theme.aurora : Theme.text, size: 26),
                    Reading(label: "Densità", value: Fmt.number(latest.density, decimals: 1), unit: "p/cm³", size: 26),
                    Reading(label: "Arrivo a terra", value: wind.leadMinutes.map { "\(Int($0))" } ?? "–", unit: "min", size: 26),
                    Reading(label: "Bz medio 1 h", value: Fmt.number(wind.mean(60) { $0.bz }, decimals: 1), unit: "nT", size: 26),
                ], columns: 3)
                .overlay(alignment: .top) { Rule() }
                .overlay(alignment: .bottom) { Rule() }

                if wind.samples.count > 10 {
                    Chart {
                        ForEach(Array(wind.samples.enumerated()).filter { $0.offset % 2 == 0 }, id: \.offset) { item in
                            LineMark(x: .value("Ora", item.element.date), y: .value("Bz", item.element.bz))
                                .foregroundStyle(Theme.text).lineStyle(StrokeStyle(lineWidth: 1.2))
                        }
                        RuleMark(y: .value("0", 0)).foregroundStyle(Theme.rule.opacity(0.4))
                        RuleMark(y: .value("-5", -5)).foregroundStyle(Theme.aurora).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .hour)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.hairline)
                            AxisValueLabel { if let d = value.as(Date.self) { Text(Fmt.time(d, in: zone)).font(.mono(9)).foregroundStyle(Theme.faint) } }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .trailing) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.hairline)
                            AxisValueLabel { if let v = value.as(Double.self) { Text("\(Int(v))").font(.mono(9)).foregroundStyle(Theme.faint) } }
                        }
                    }
                    .frame(height: 110)
                    Text("BZ ULTIME 3 ORE · SOTTO −5 NT (LINEA VERDE) IL CAMPO SI ACCOPPIA CON QUELLO TERRESTRE")
                        .font(.mono(8.5)).foregroundStyle(Theme.faint)
                }
            }
        }
    }

    // MARK: 04 NASA

    @ViewBuilder private var nasaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(index: "04", title: "NASA DONKI", trailing: intel?.donkiStale == true ? "ULTIMA COPIA SALVATA" : "WSA-ENLIL",
                         trailingColor: intel?.donkiStale == true ? Theme.caution : Theme.dim)
            if let donki = intel?.donki {
                let arrivals = donki.upcoming
                if arrivals.isEmpty {
                    rowText("Nessuna CME diretta verso la Terra nei modelli NASA degli ultimi 10 giorni.")
                } else {
                    ForEach(arrivals) { cme in
                        VStack(spacing: 0) {
                            HStack(alignment: .top, spacing: 12) {
                                Rectangle().fill(cme.glancing ? Theme.caution : Theme.accent).frame(width: 3)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(cme.glancing ? "CME DI STRISCIO" : "CME DIRETTA").font(.mono(9.5, .semibold)).foregroundStyle(Theme.dim)
                                    Text("Arrivo \(cme.arrivalDate.map { Fmt.dayTime($0, in: zone) } ?? "–") ±7 h")
                                        .font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text)
                                    Text([cme.launchDate.map { "partita \(Fmt.dayTime($0, in: zone))" },
                                          cme.speed.map { "\(Int($0)) km/s" },
                                          cme.durationHours.map { "durata ~\(Int($0)) h" }].compactMap { $0 }.joined(separator: " · "))
                                        .font(.app(.caption)).foregroundStyle(Theme.dim)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 0) {
                                    Text(cme.kp.map { "\(Fmt.number($0.min))–\(Fmt.number($0.max))" } ?? "–").font(.metric(24, .semibold)).foregroundStyle(Theme.accent)
                                    Text("KP NASA").font(.mono(8.5)).foregroundStyle(Theme.faint)
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 10)
                            Rule()
                        }
                    }
                }
                let storms = donki.storms.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
                if !storms.isEmpty {
                    Text("TEMPESTE GEOMAGNETICHE · 30 GIORNI").font(.mono(9.5)).foregroundStyle(Theme.faint).padding(.top, 4)
                    ForEach(storms.prefix(5)) { storm in
                        HStack {
                            Text(storm.startDate.map { Fmt.dayTime($0, in: zone) } ?? "–").font(.app(.subheadline)).foregroundStyle(Theme.text)
                            Spacer()
                            Text("KP MAX \(Fmt.number(storm.maxKp))").font(.mono(11, .semibold)).foregroundStyle(kpColor(storm.maxKp ?? 0))
                        }
                        .padding(.vertical, 6)
                        Rule()
                    }
                }
                if !donki.flares.isEmpty {
                    Text("BRILLAMENTI M/X · 3 GIORNI").font(.mono(9.5)).foregroundStyle(Theme.faint).padding(.top, 4)
                    HStack(spacing: 8) {
                        ForEach(donki.flares.prefix(6)) { flare in
                            Text(flare.classType).font(.mono(11, .semibold))
                                .foregroundStyle(flare.classType.hasPrefix("X") ? Theme.onAccent : Theme.text)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(flare.classType.hasPrefix("X") ? Theme.danger : .clear)
                                .overlay(Rectangle().strokeBorder(Theme.hairline))
                        }
                    }
                }
            } else {
                rowText("Il servizio DONKI della NASA (Goddard CCMC) non risponde. Il Kp combinato usa solo le fonti NOAA finché torna disponibile.")
            }
        }
    }

    private func rowText(_ text: String) -> some View {
        Text(text).font(.app(.caption)).foregroundStyle(Theme.dim)
    }

    // MARK: 05 NOAA

    @ViewBuilder private var noaaSection: some View {
        if let intel {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(index: "05", title: "NOAA SWPC")
                let local = model.ovation?.value.horizonProbability(at: model.activePlace.coordinate)
                ReadingGrid(items: [
                    Reading(label: "Scala G oggi", value: "G\(intel.currentScale)", tint: intel.currentScale >= 1 ? Theme.aurora : Theme.text, size: 26),
                    Reading(label: "Potenza emisferica", value: Fmt.number(intel.hemisphericPower), unit: "GW",
                            tint: (intel.hemisphericPower ?? 0) >= 50 ? Theme.aurora : Theme.text, size: 26),
                    Reading(label: "OVATION qui", value: Fmt.number(local), unit: "%", size: 26),
                ], columns: 3)
                .overlay(alignment: .top) { Rule() }
                .overlay(alignment: .bottom) { Rule() }
                let forecasts = intel.scales.filter(\.isForecast)
                if !forecasts.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(Array(forecasts.prefix(3).enumerated()), id: \.offset) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.element.date.map { Fmt.axis($0, hour: false).uppercased() } ?? "–").font(.mono(9)).foregroundStyle(Theme.faint)
                                Text("G\(item.element.level)").font(.metric(22, .semibold))
                                    .foregroundStyle(item.element.level >= 1 ? Theme.aurora : Theme.text)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                ForEach(intel.alerts.prefix(4)) { alert in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.issued.map { Fmt.dayTime($0, in: zone).uppercased() } ?? "").font(.mono(9)).foregroundStyle(Theme.faint)
                        Text(alert.title).font(.app(.caption, .medium)).foregroundStyle(Theme.text)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) { Rule() }
                }
                if let fetched = model.space { FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: "NOAA SWPC · NASA CCMC") }
            }
        }
    }

    private func head(_ text: String, _ width: CGFloat?, _ alignment: Alignment = .trailing) -> some View {
        Text(text).font(.mono(8.5)).foregroundStyle(Theme.faint)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }

    // MARK: Links

    private var links: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(title: "Fonti").padding(.bottom, 6)
            LinkRow(title: "Vedur.is · aurora e nuvole", subtitle: "Mappa ufficiale della copertura nuvolosa", url: "https://en.vedur.is/weather/forecasts/aurora/")
            Rule()
            LinkRow(title: "NOAA SWPC · previsione 30 minuti", subtitle: "Ovale OVATION", url: "https://www.swpc.noaa.gov/products/aurora-30-minute-forecast")
            Rule()
            LinkRow(title: "NOAA SWPC · previsione 3 giorni", subtitle: nil, url: "https://www.swpc.noaa.gov/products/3-day-forecast")
            Rule()
            LinkRow(title: "NASA CCMC · DONKI", subtitle: "CME, tempeste, brillamenti", url: "https://kauai.ccmc.gsfc.nasa.gov/DONKI/")
        }
    }
}
