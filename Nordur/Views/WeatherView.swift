import SwiftUI
import Charts

struct WeatherView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ScreenHeader(title: "Meteo", subtitle: "Previsioni a 16 giorni") { AppearanceButton() }
                    PlaceHeader()
                    if let fetched = model.forecast {
                        let forecast = fetched.value
                        let next48 = forecast.upcomingHours(48)
                        temperatureChart(next48, zone: forecast.timeZone)
                        windChart(next48, zone: forecast.timeZone)
                        hourlyList(Array(next48.prefix(24)), zone: forecast.timeZone)
                        dailyList(forecast.days, zone: forecast.timeZone)
                        FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: "Open-Meteo")
                    } else if let error = model.errors[.forecast] {
                        ErrorNote(message: error)
                    } else {
                        ProgressView().padding(40)
                    }
                    seaCard
                    airCard
                }
                .padding()
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await model.refreshPlace() }
        }
    }

    // MARK: Charts

    private func axis() -> some AxisContent {
        AxisMarks(values: .stride(by: .hour, count: 12)) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.hairline)
            AxisValueLabel { if let date = value.as(Date.self) { Text(Fmt.axis(date)).font(.geist(10)).foregroundStyle(Theme.faint) } }
        }
    }

    private func yAxis() -> some AxisContent {
        AxisMarks(position: .trailing) { _ in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.hairline)
            AxisValueLabel().foregroundStyle(Theme.faint)
        }
    }

    private func temperatureChart(_ hours: [HourPoint], zone: TimeZone) -> some View {
        let temps = hours.compactMap(\.temperature)
        let low = (temps.min() ?? 0) - 2, high = (temps.max() ?? 10) + 2
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Temperatura, 48 ore").eyebrow()
                Spacer()
                if let min = temps.min(), let max = temps.max() {
                    Text("\(Fmt.temp(min)) / \(Fmt.temp(max))").font(.metric(13, .semibold)).foregroundStyle(Theme.dim)
                }
            }
            Chart {
                ForEach(hours) { hour in
                    if let temp = hour.temperature {
                        AreaMark(x: .value("Ora", hour.date, unit: .hour), yStart: .value("base", low), yEnd: .value("°C", temp))
                            .foregroundStyle(LinearGradient(colors: [Theme.caution.opacity(0.28), Theme.caution.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Ora", hour.date, unit: .hour), y: .value("°C", temp))
                            .foregroundStyle(Theme.caution)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.catmullRom)
                    }
                }
                if low < 0 && high > 0 {
                    RuleMark(y: .value("0", 0)).foregroundStyle(Theme.accent.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartYScale(domain: low...high)
            .chartXAxis { axis() }
            .chartYAxis { yAxis() }
            .frame(height: 150)
            .environment(\.locale, Fmt.italian)

            Text("Precipitazioni (mm)").eyebrow(Theme.faint)
            Chart {
                ForEach(hours) { hour in
                    BarMark(x: .value("Ora", hour.date, unit: .hour), y: .value("mm", hour.precipitation ?? 0))
                        .foregroundStyle((hour.snowfall ?? 0) > 0 ? Theme.text.opacity(0.8) : Theme.accent)
                        .cornerRadius(1.5)
                }
            }
            .chartXAxis { axis() }
            .chartYAxis { yAxis() }
            .frame(height: 70)
            .environment(\.locale, Fmt.italian)
        }
        .panel()
    }

    private func windChart(_ hours: [HourPoint], zone: TimeZone) -> some View {
        let peak = hours.compactMap(\.gust).max() ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Vento e raffiche, 48 ore").eyebrow()
                Spacer()
                Text("max \(Fmt.ms(peak))").font(.metric(13, .semibold)).foregroundStyle(Risk.wind(mean: nil, gust: peak).color)
            }
            Chart {
                ForEach(hours) { hour in
                    if let gust = hour.gust {
                        AreaMark(x: .value("Ora", hour.date, unit: .hour), y: .value("Raffiche", gust))
                            .foregroundStyle(LinearGradient(colors: [Theme.warning.opacity(0.35), Theme.warning.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                    }
                    if let wind = hour.wind {
                        LineMark(x: .value("Ora", hour.date, unit: .hour), y: .value("Vento", wind))
                            .foregroundStyle(Theme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.monotone)
                    }
                }
                RuleMark(y: .value("25", 25))
                    .foregroundStyle(Theme.danger.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("25 m/s").font(.geist(9, .semibold)).foregroundStyle(Theme.danger)
                    }
            }
            .chartYScale(domain: 0...max(30, peak + 3))
            .chartXAxis { axis() }
            .chartYAxis { yAxis() }
            .frame(height: 160)
            .environment(\.locale, Fmt.italian)
            HStack(spacing: 14) {
                legendDot(Theme.accent, "vento medio")
                legendDot(Theme.warning, "raffiche")
            }
        }
        .panel()
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 12, height: 3)
            Text(text).font(.geist(11)).foregroundStyle(Theme.dim)
        }
    }

    // MARK: Lists

    private func hourlyList(_ hours: [HourPoint], zone: TimeZone) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ora per ora").eyebrow()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                        let info = WeatherCode.describe(hour.code, isDay: hour.isDay)
                        VStack(spacing: 8) {
                            Text(index == 0 ? "Ora" : Fmt.time(hour.date, in: zone)).font(.metric(11, .semibold))
                                .foregroundStyle(index == 0 ? Theme.accent : Theme.dim)
                            Image(systemName: info.symbol).symbolRenderingMode(.hierarchical).font(.geist(18))
                                .foregroundStyle(Theme.text).frame(height: 22)
                            Text(Fmt.temp(hour.temperature)).font(.metric(17, .semibold)).foregroundStyle(Theme.text)
                            WindArrow(degrees: hour.windDirection).font(.geist(10)).foregroundStyle(Theme.dim)
                            Text("\(Int((hour.gust ?? 0).rounded()))").font(.metric(12, .bold)).foregroundStyle(hour.windRisk == .ok ? Theme.dim : hour.windRisk.color)
                            Text(hour.precipitationProbability.map { $0 >= 20 ? "\(Int($0))%" : " " } ?? " ")
                                .font(.metric(10)).foregroundStyle(Theme.accent)
                        }
                        .frame(width: 46)
                        .padding(.vertical, 10)
                        .background(index == 0 ? Theme.raised : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            HStack(spacing: 12) {
                Text("Freccia: direzione del vento").font(.geist(10)).foregroundStyle(Theme.faint)
                Text("Numero: raffica m/s").font(.geist(10)).foregroundStyle(Theme.faint)
            }
        }
        .panel()
    }

    private func dailyList(_ days: [DayPoint], zone: TimeZone) -> some View {
        let lows = days.compactMap(\.minTemp), highs = days.compactMap(\.maxTemp)
        let scaleMin = (lows.min() ?? 0) - 1, scaleMax = (highs.max() ?? 10) + 1
        return VStack(alignment: .leading, spacing: 4) {
            Text("16 giorni").eyebrow().padding(.bottom, 8)
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                let info = WeatherCode.describe(day.code)
                HStack(spacing: 10) {
                    Text(index == 0 ? "Oggi" : Fmt.day(day.date, in: zone))
                        .font(.geist(14, index == 0 ? .semibold : .regular))
                        .foregroundStyle(index > 6 ? Theme.dim : Theme.text)
                        .frame(width: 82, alignment: .leading)
                    Image(systemName: info.symbol).symbolRenderingMode(.hierarchical).foregroundStyle(Theme.text).frame(width: 24)
                    Text(Fmt.temp(day.minTemp)).font(.metric(14)).foregroundStyle(Theme.dim).frame(width: 32, alignment: .trailing)
                    RangeBar(low: day.minTemp ?? 0, high: day.maxTemp ?? 0, scaleMin: scaleMin, scaleMax: scaleMax)
                    Text(Fmt.temp(day.maxTemp)).font(.metric(14, .semibold)).foregroundStyle(Theme.text).frame(width: 32, alignment: .leading)
                    Text("\(Int((day.maxGust ?? 0).rounded()))")
                        .font(.metric(12, .bold))
                        .foregroundStyle(day.windRisk == .ok ? Theme.faint : day.windRisk.color)
                        .frame(width: 24, alignment: .trailing)
                }
                .padding(.vertical, 7)
                if index < days.count - 1 { Divider().overlay(Theme.hairline) }
            }
            Text("Ultima colonna: raffica massima (m/s). Oltre 7 giorni la previsione è indicativa.")
                .font(.geist(10)).foregroundStyle(Theme.faint).padding(.top, 6)
        }
        .panel()
    }

    // MARK: Sea & air

    @ViewBuilder private var seaCard: some View {
        if let fetched = model.marine, fetched.value.hasData, let c = fetched.value.current {
            let marine = fetched.value
            Card(title: "Mare", systemImage: "water.waves", tint: .teal) {
                HStack {
                    Metric(title: "Onde", value: Fmt.number(c.wave_height, decimals: 1, unit: "m"))
                    Metric(title: "Periodo", value: Fmt.number(c.wave_period, decimals: 0, unit: "s"))
                    Metric(title: "Da", value: Fmt.compass(c.wave_direction))
                }
                HStack {
                    Metric(title: "Onda lunga (swell)", value: Fmt.number(c.swell_wave_height, decimals: 1, unit: "m"))
                    Metric(title: "Max 48 h", value: Fmt.number(marine.maxWaveHeight(next: 48), decimals: 1, unit: "m"))
                    Metric(title: "Acqua", value: Fmt.temp(c.sea_surface_temperature))
                }
                HStack {
                    Text("Spiagge").font(.app(.caption))
                    RiskBadge(risk: marine.beachRisk)
                    Spacer()
                    Text("Traghetti/barche").font(.app(.caption))
                    RiskBadge(risk: marine.seaRisk)
                }
                Text("Reynisfjara e spiagge del sud: onde anomale senza preavviso. Resta lontano dalla battigia.")
                    .font(.app(.caption2)).foregroundStyle(.secondary)
                FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: "Open-Meteo Marine")
            }
        }
    }

    @ViewBuilder private var airCard: some View {
        if let fetched = model.air, let c = fetched.value.current {
            Card(title: "Aria e gas vulcanici", systemImage: "aqi.medium", tint: .purple) {
                HStack {
                    Metric(title: "Indice EU", value: Fmt.number(c.european_aqi), tint: fetched.value.aqiRisk.color)
                    Metric(title: "SO₂", value: Fmt.number(c.sulphur_dioxide, unit: "µg/m³"), tint: fetched.value.so2Risk.color)
                    Metric(title: "PM10", value: Fmt.number(c.pm10, unit: "µg/m³"))
                }
                Text("Gas vulcanico: previsioni di dispersione su vedur.is.")
                    .font(.app(.caption2)).foregroundStyle(.secondary)
                FreshnessLabel(date: fetched.date, isStale: fetched.isStale, source: "CAMS via Open-Meteo")
            }
        }
    }
}
