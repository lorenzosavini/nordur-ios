import SwiftUI
import Charts

struct WeatherView: View {
    @Environment(AppModel.self) private var model
    @State private var showComparison = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    VStack(alignment: .leading, spacing: 16) {
                        ScreenHeader(title: String(localized: "Meteo"), subtitle: String(localized: "Previsioni · 10 giorni"), index: "02") { AppearanceButton() }
                        PlaceHeader(size: 34)
                    }
                    HeroHeader(hero: .weather, eyebrow: model.forecast?.value.official != nil ? String(localized: "vedur.is") : String(localized: "Modello"),
                               title: model.now.map { WeatherCode.describe($0.code, isDay: $0.isDay).text } ?? String(localized: "Previsioni"),
                               height: 170)
                        .padding(.horizontal, -18)
                    AdaptiveColumns(spacing: 30) {
                        if let fetched = model.forecast {
                            let forecast = fetched.value
                            let next48 = forecast.upcomingHours(48)
                            // In order of reliability: what is measured now, then the official
                            // forecast (hours, days), the forecaster's words, the details, the sources.
                            if let observation = model.observation?.value {
                                IMOObservationBlock(observation: observation)
                            }
                            meteogram(next48, forecast: forecast)
                            dailyTable(forecast.days, zone: forecast.timeZone, forecast: forecast)
                            IMOTextCard()
                            if model.stationForecast != nil {
                                DisclosureGroup(isExpanded: $showComparison) {
                                    stationComparison(forecast).padding(.top, 8)
                                } label: {
                                    Text("Confronto ora per ora tra vedur.is e il modello").font(.app(.subheadline, .semibold)).foregroundStyle(Theme.text)
                                }
                                .tint(Theme.text)
                            }
                        } else if let error = model.errors[.forecast] {
                            ErrorNote(message: error)
                        } else {
                            SkeletonBlock(lines: 6)
                        }
                        seaSection
                        airSection
                        if let fetched = model.forecast {
                            sourceBlock(fetched.value, fetched: fetched)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await model.refreshPlace() }
        }
    }

    // MARK: Source

    private func sourceBlock(_ forecast: Forecast, fetched: Fetched<Forecast>) -> some View {
        let primary = forecast.sources.first ?? String(localized: "Open-Meteo")
        return VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title: String(localized: "Fonti"))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Fonte").font(.mono(9.5)).foregroundStyle(Theme.faint).frame(width: 52, alignment: .leading)
                Text(forecast.official != nil ? forecast.sourceLine
                     : primary == "MET Norway" ? (Coverage.meps(Coordinate(lat: forecast.latitude, lon: forecast.longitude)) ? String(localized: "MET Norway · MEPS 2,5 km") : String(localized: "MET Norway · ECMWF")) : primary)
                    .font(.mono(11, .semibold)).foregroundStyle(Theme.text)
            }
            if forecast.official != nil {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("").frame(width: 52)
                    ForecastSourceNote(forecast: forecast)
                }
            } else if model.inIceland {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("").frame(width: 52)
                    Text("Nessuna stazione vedur.is vicina e alla stessa quota di questo luogo: previsione dei modelli.")
                        .font(.app(.caption)).foregroundStyle(Theme.dim)
                }
            }
            if forecast.official == nil, primary == "MET Norway", Coverage.meps(Coordinate(lat: forecast.latitude, lon: forecast.longitude)) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("").frame(width: 52)
                    Text("Modello nordico gestito con vedur.is, lo stesso di yr.no. Dopo \(forecast.primaryUntil.map { Fmt.dayTime($0, in: forecast.timeZone) } ?? String(localized: "60 ore")) e per le raffiche: ECMWF/ICON via Open-Meteo.")
                        .font(.app(.caption)).foregroundStyle(Theme.dim)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("").frame(width: 52)
                FreshnessLabel(date: fetched.date, isStale: fetched.isStale)
            }
            NavigationLink {
                SourcesView()
            } label: {
                HStack(spacing: 4) {
                    Text("Da dove vengono i dati, sezione per sezione")
                    Image(systemName: "chevron.right")
                }
                .font(.app(.caption, .semibold)).foregroundStyle(Theme.aurora)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rule() }
        .overlay(alignment: .bottom) { Rule() }
    }

    // MARK: Meteogram

    private func dayAxis() -> some AxisContent {
        AxisMarks(values: .stride(by: .hour, count: 6)) { value in
            let date = value.as(Date.self) ?? Date()
            let hour = Calendar.current.component(.hour, from: date)
            AxisGridLine(stroke: StrokeStyle(lineWidth: hour == 0 ? 1 : 0.5)).foregroundStyle(hour == 0 ? Theme.rule.opacity(0.5) : Theme.hairline)
            AxisValueLabel {
                Text(hour == 0 ? Fmt.axis(date, hour: false) : String(format: "%02d", hour))
                    .font(.mono(9, hour == 0 ? .semibold : .regular))
                    .foregroundStyle(hour == 0 ? Theme.text : Theme.faint)
            }
        }
    }

    private func yAxis(_ unit: String) -> some AxisContent {
        AxisMarks(position: .trailing) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.hairline)
            AxisValueLabel {
                if let v = value.as(Double.self) { Text("\(Int(v))\(unit)").font(.mono(9)).foregroundStyle(Theme.faint) }
            }
        }
    }

    private func meteogram(_ hours: [HourPoint], forecast: Forecast) -> some View {
        let unit = TempUnit.current
        let temps = hours.compactMap(\.temperature).map(unit.value)
        let low = floor((temps.min() ?? 0) - 1), high = ceil((temps.max() ?? 10) + 1)
        let peak = hours.compactMap(\.gust).max() ?? 0
        let rain = hours.compactMap(\.precipitation).reduce(0, +)
        let freezing = unit.value(0)
        return VStack(alignment: .leading, spacing: 14) {
            SectionLabel(index: "01", title: String(localized: "Prossime 48 ore"))
            originLine(forecast, from: hours.first?.date, to: hours.last?.date)

            chartHeader(String(localized: "Temperatura"), "\(Fmt.temp(hours.compactMap(\.temperature).min())) / \(Fmt.temp(hours.compactMap(\.temperature).max()))")
            Chart {
                ForEach(hours) { hour in
                    if let temp = hour.temperature {
                        LineMark(x: .value(String(localized: "Ora"), hour.date, unit: .hour), y: .value(unit.label, unit.value(temp)))
                            .foregroundStyle(Theme.text)
                            .lineStyle(StrokeStyle(lineWidth: 1.6))
                            .interpolationMethod(.monotone)
                    }
                }
                if low < freezing && high > freezing {
                    RuleMark(y: .value("0", freezing)).foregroundStyle(Theme.accent).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
                RuleMark(x: .value(String(localized: "Adesso"), Date())).foregroundStyle(Theme.accent).lineStyle(StrokeStyle(lineWidth: 1))
            }
            .chartYScale(domain: low...high)
            .chartXAxis { dayAxis() }
            .chartYAxis { yAxis("°") }
            .frame(height: 130)

            chartHeader(String(localized: "Precipitazioni"), Fmt.number(rain, decimals: 1, unit: "Mm in 48 h"))
            Chart {
                ForEach(hours) { hour in
                    BarMark(x: .value(String(localized: "Ora"), hour.date, unit: .hour), y: .value("mm", hour.precipitation ?? 0), width: .ratio(0.7))
                        .foregroundStyle((hour.snowfall ?? 0) > 0 ? Theme.dim : Theme.accent)
                }
            }
            .chartXAxis { dayAxis() }
            .chartYAxis { yAxis("") }
            .frame(height: 64)

            chartHeader(String(localized: "Vento · raffiche"), String(localized: "Max \(Fmt.ms(peak))"), color: Risk.wind(mean: nil, gust: peak) == .ok ? Theme.dim : Risk.wind(mean: nil, gust: peak).color)
            Chart {
                ForEach(hours) { hour in
                    if let gust = hour.gust {
                        LineMark(x: .value(String(localized: "Ora"), hour.date, unit: .hour), y: .value("wind", gust * WindUnit.current.factor), series: .value("s", "raffica"))
                            .foregroundStyle(Theme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
                            .interpolationMethod(.stepCenter)
                    }
                    if let wind = hour.wind {
                        LineMark(x: .value(String(localized: "Ora"), hour.date, unit: .hour), y: .value("wind", wind * WindUnit.current.factor), series: .value("s", "medio"))
                            .foregroundStyle(Theme.text)
                            .lineStyle(StrokeStyle(lineWidth: 1.6))
                            .interpolationMethod(.monotone)
                    }
                }
                RuleMark(y: .value("25", 25 * WindUnit.current.factor))
                    .foregroundStyle(Theme.danger)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .leading) {
                        Text("\(Fmt.ms(25)) · pericolo").font(.mono(8.5, .semibold)).foregroundStyle(Theme.danger)
                    }
            }
            .chartYScale(domain: 0...(max(30, peak + 3) * WindUnit.current.factor))
            .chartXAxis { dayAxis() }
            .chartYAxis { yAxis("") }
            .frame(height: 140)

            // Wind direction strip, every 3 hours.
            HStack(spacing: 0) {
                ForEach(Array(hours.enumerated()).filter { $0.offset % 3 == 0 }, id: \.offset) { item in
                    WindArrow(degrees: item.element.windDirection)
                        .font(.system(size: 9))
                        .foregroundStyle(item.element.windRisk == .ok ? Theme.dim : item.element.windRisk.color)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.trailing, 28)

            HStack(spacing: 16) {
                legend(Theme.text, dashed: false, String(localized: "vento medio"))
                legend(Theme.accent, dashed: true, "raffiche")
                legend(Theme.accent, dashed: false, "adesso")
            }
        }
        .environment(\.locale, Fmt.italian)
    }

    private func chartHeader(_ title: String, _ value: String, color: Color = Theme.dim) -> some View {
        HStack {
            Text(title.loc).font(.mono(9.5, .medium)).foregroundStyle(Theme.faint)
            Spacer()
            Text(value).font(.mono(9.5, .semibold)).foregroundStyle(color)
        }
    }

    private func legend(_ color: Color, dashed: Bool, _ text: String) -> some View {
        HStack(spacing: 6) {
            if dashed {
                HStack(spacing: 2) { ForEach(0..<3, id: \.self) { _ in Rectangle().fill(color).frame(width: 3, height: 1.5) } }
            } else {
                Rectangle().fill(color).frame(width: 14, height: 1.5)
            }
            Text(text.loc).font(.mono(9)).foregroundStyle(Theme.dim)
        }
    }

    // MARK: IMO cross-check

    @ViewBuilder private func stationComparison(_ forecast: Forecast) -> some View {
        if let fetched = model.stationForecast {
            let station = fetched.value
            let now = Date()
            let rows = station.hours.filter { $0.date.addingTimeInterval(3600) > now }.prefix(12)
            // The models' own values (before IMO replaced them in the forecast).
            let modelT: [Int: Double] = forecast.official?.modelTemperature
                ?? Dictionary(forecast.hours.compactMap { h in h.temperature.map { (Int(h.date.timeIntervalSince1970), $0) } }, uniquingKeysWith: { a, _ in a })
            let modelW: [Int: Double] = forecast.official?.modelWind
                ?? Dictionary(forecast.hours.compactMap { h in h.wind.map { (Int(h.date.timeIntervalSince1970), $0) } }, uniquingKeysWith: { a, _ in a })
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(index: "02", title: String(localized: "vedur.is e modello a confronto"), trailing: "\(Int(station.distanceKm)) km")
                VStack(alignment: .leading, spacing: 3) {
                    Text(station.station.name.uppercased()).font(.display(24, .bold)).foregroundStyle(Theme.text)
                    Text("Previsione per stazione di vedur.is\(station.issued.map { String(localized: " · emessa \(Fmt.dayTime($0, in: .iceland))") } ?? "")")
                        .font(.app(.caption)).foregroundStyle(Theme.dim)
                }
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        head(String(localized: "Ora"), 40, .leading)
                        head("vedur.is \(Fmt.tempUnit)", 52)
                        head("MET \(Fmt.tempUnit)", 52)
                        head("vedur.is \(Fmt.windUnit)", 58)
                        head("MET \(Fmt.windUnit)", 58)
                        head(String(localized: "Cielo (vedur.is)"), nil, .leading).padding(.leading, 10)
                    }
                    .padding(.bottom, 6)
                    Rule()
                    ForEach(Array(rows)) { hour in
                        let key = Int(hour.date.timeIntervalSince1970)
                        let metT = modelT[key], metW = modelW[key]
                        let diff = abs((hour.wind ?? 0) - (metW ?? hour.wind ?? 0))
                        HStack(spacing: 0) {
                            Text(Fmt.hour(hour.date, in: .iceland)).font(.mono(10.5, .medium)).foregroundStyle(Theme.dim)
                                .frame(width: 40, alignment: .leading)
                            num(Fmt.degrees(hour.temperature), 52, Theme.text)
                            num(Fmt.degrees(metT), 52, Theme.dim)
                            num(Fmt.wind(hour.wind), 58, (hour.wind ?? 0) >= 15 ? Theme.warning : Theme.text)
                            num(Fmt.wind(metW), 58, diff >= 4 ? Theme.accent : Theme.dim)
                            Text("\(Fmt.compass(hour.degrees)) · \(hour.text)").font(.app(.caption)).foregroundStyle(Theme.dim)
                                .lineLimit(1).minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 10)
                        }
                        .padding(.vertical, 6)
                        Rule()
                    }
                }
                Text("L'app usa la previsione vedur.is. Quando il modello MET differisce di \(Fmt.ms(4)) o più il suo valore è evidenziato: in quel caso considera lo scenario peggiore.")
                    .font(.app(.caption)).foregroundStyle(Theme.dim)
                FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: "vedur.is")
            }
        }
    }

    private func head(_ text: String, _ width: CGFloat?, _ alignment: Alignment = .trailing) -> some View {
        Text(text.loc).font(.mono(8.5)).foregroundStyle(Theme.faint).lineLimit(1)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }

    private func num(_ text: String, _ width: CGFloat, _ color: Color) -> some View {
        Text(text.loc).font(.metric(18, .semibold)).foregroundStyle(color).frame(width: width, alignment: .trailing)
    }

    // MARK: Daily

    /// The badge for a span of time, and where the source switches from vedur.is to the model.
    @ViewBuilder private func originLine(_ forecast: Forecast, from: Date?, to: Date?) -> some View {
        if let from {
            let first = forecast.origin(at: from)
            HStack(spacing: 10) {
                SourceBadge(origin: first, detail: first == .official ? forecast.official?.station.name : nil)
                if first == .official, let until = forecast.official?.until, let to, until < to {
                    Text("→").font(.mono(9)).foregroundStyle(Theme.faint)
                    SourceBadge(origin: .model, detail: String(localized: "dalle \(Fmt.dayTime(until, in: .Iceland))"))
                }
            }
        }
    }

    private func dailyTable(_ days: [DayPoint], zone: TimeZone, forecast: Forecast) -> some View {
        let lows = days.compactMap(\.minTemp), highs = days.compactMap(\.maxTemp)
        let scaleMin = (lows.min() ?? 0) - 1, scaleMax = (highs.max() ?? 10) + 1
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(index: "03", title: String(localized: "10 giorni"), trailing: String(localized: "Min · max · raff · mm"))
            originLine(forecast, from: days.first?.date, to: days.last.map { $0.date.addingTimeInterval(86400) })
            VStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    let info = WeatherCode.describe(day.code)
                    HStack(spacing: 8) {
                        // The day's source at a glance: blue vedur.is, grey model.
                        Capsule().fill(forecast.origin(at: day.date.addingTimeInterval(12 * 3600)).color).frame(width: 3, height: 26)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(index == 0 ? String(localized: "Oggi") : weekday(day.date, zone)).font(.mono(10.5, .semibold))
                                .foregroundStyle(index == 0 ? Theme.accent : Theme.text)
                            Text(dayNumber(day.date, zone)).font(.mono(9)).foregroundStyle(Theme.faint)
                        }
                        .frame(width: 44, alignment: .leading)
                        Image(systemName: info.symbol).symbolRenderingMode(.monochrome).font(.system(size: 14))
                            .foregroundStyle(Theme.text).frame(width: 22)
                        Text(Fmt.degrees(day.minTemp)).font(.metric(19)).foregroundStyle(Theme.dim).frame(width: 26, alignment: .trailing)
                        RangeBar(low: day.minTemp ?? 0, high: day.maxTemp ?? 0, scaleMin: scaleMin, scaleMax: scaleMax)
                        Text(Fmt.degrees(day.maxTemp)).font(.metric(19, .semibold)).foregroundStyle(Theme.text).frame(width: 26, alignment: .leading)
                        gust(day.maxGust).frame(width: 34)
                        Text(Fmt.number(day.precipitation, decimals: (day.precipitation ?? 0) < 10 ? 1 : 0))
                            .font(.metric(16)).foregroundStyle((day.precipitation ?? 0) >= 10 ? Theme.accent : Theme.dim)
                            .frame(width: 32, alignment: .trailing)
                    }
                    .padding(.vertical, 9)
                    .opacity(index > 6 ? 0.6 : 1)
                    Rule()
                }
            }
            .overlay(alignment: .top) { Rule() }
            Text("Oggi: pioggia prevista da adesso a mezzanotte. Oltre 7 giorni la previsione è indicativa.").font(.app(.caption)).foregroundStyle(Theme.dim)
        }
    }

    private func gust(_ value: Double?) -> some View {
        let v = value ?? 0
        return Text(Fmt.number(value))
            .font(.metric(16, .bold))
            .foregroundStyle(v >= 18 ? Theme.onAccent : (v >= 13 ? Theme.caution : Theme.text))
            .padding(.horizontal, 4)
            .background(v >= 25 ? Theme.danger : (v >= 18 ? Theme.warning : .clear))
    }

    private func weekday(_ date: Date, _ zone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Fmt.italian
        f.timeZone = zone
        f.dateFormat = "EEE"
        return f.string(from: date).uppercased().replacingOccurrences(of: ".", with: "")
    }

    private func dayNumber(_ date: Date, _ zone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Fmt.italian
        f.timeZone = zone
        f.dateFormat = "d MMM"
        return f.string(from: date).uppercased()
    }

    // MARK: Sea & air

    @ViewBuilder private var seaSection: some View {
        if let fetched = model.marine, fetched.value.hasData, let c = fetched.value.current {
            let marine = fetched.value
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(index: "04", title: String(localized: "Mare"))
                ReadingGrid(items: [
                    Reading(label: String(localized: "Onde"), value: Fmt.number(c.wave_height, decimals: 1), unit: "m", size: 26),
                    Reading(label: String(localized: "Periodo"), value: Fmt.number(c.wave_period), unit: "s", size: 26),
                    Reading(label: "Da", value: Fmt.compass(c.wave_direction), size: 26),
                    Reading(label: String(localized: "Swell"), value: Fmt.number(c.swell_wave_height, decimals: 1), unit: "m", size: 26),
                    Reading(label: String(localized: "Max 48 h"), value: Fmt.number(marine.maxWaveHeight(next: 48), decimals: 1), unit: "m", size: 26),
                    Reading(label: String(localized: "Acqua"), value: Fmt.degrees(c.sea_surface_temperature), unit: Fmt.tempUnit, size: 26),
                ], columns: 3)
                .overlay(alignment: .top) { Rule() }
                .overlay(alignment: .bottom) { Rule() }
                HStack(spacing: 8) {
                    RiskBadge(risk: marine.beachRisk, text: String(localized: "Spiagge: \(marine.beachRisk.label)"))
                    RiskBadge(risk: marine.seaRisk, text: String(localized: "Barca: \(marine.seaRisk.label)"))
                }
                Text("Reynisfjara e spiagge del sud: onde anomale senza preavviso. Resta lontano dalla battigia.")
                    .font(.app(.caption)).foregroundStyle(Theme.dim)
                FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: String(localized: "Open-Meteo Marine"))
            }
        }
    }

    @ViewBuilder private var airSection: some View {
        if let fetched = model.air, let c = fetched.value.current {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(index: "05", title: String(localized: "Aria e gas vulcanici"))
                ReadingGrid(items: [
                    Reading(label: String(localized: "Indice EU"), value: Fmt.number(c.european_aqi),
                            tint: fetched.value.aqiRisk == .ok ? Theme.text : fetched.value.aqiRisk.color, size: 26),
                    Reading(label: "SO₂", value: Fmt.number(c.sulphur_dioxide), unit: "µg/m³",
                            tint: fetched.value.so2Risk == .ok ? Theme.text : fetched.value.so2Risk.color, size: 26),
                    Reading(label: "PM10", value: Fmt.number(c.pm10), unit: "µg/m³", size: 26),
                ], columns: 3)
                .overlay(alignment: .top) { Rule() }
                .overlay(alignment: .bottom) { Rule() }
                Text("Dispersione del gas vulcanico: vedur.is.").font(.app(.caption)).foregroundStyle(Theme.dim)
                FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: String(localized: "CAMS via Open-Meteo"))
            }
        }
    }
}
